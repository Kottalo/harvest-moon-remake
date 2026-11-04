"""Bake ordinary USA villager schedules, route cells and the packed ANI subset."""
import argparse
import json
import re
import struct
from pathlib import Path

from import_disc import Disc, ROOT

SOURCE = ROOT / "reference/hmbtn-decomp/src"
FARM = SOURCE / "overlay/11_GF_FARM"
ATLAS = ROOT / "game/original_sprites/catalogue.json"
OUTPUT = ROOT / "game/npc/npc_catalogue.json"


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def position(x, y, z, facing, wait=0):
    return [x, -y, -z, facing % 4, wait]


def route(section, row):
    offset = 0x1000 + row * 17 * 12
    cells = list(struct.iter_unpack("<HhHhhh", section[offset:offset + 17 * 12]))
    points, columns = [], {}
    keep_position = bool(cells and cells[0][0] == 7)
    for column, (kind, operand, facing, x, y, z) in enumerate(cells):
        if kind == 0x8000:
            return [points, columns.get(operand, -1), keep_position]
        if kind == 4 or (column and not any(cells[column])):
            break
        point = position(x, y, z, facing, max(0, operand) if kind in (1, 5, 6) else 0)
        if not points or points[-1] != point or point[4]:
            points.append(point)
        columns[column] = len(points) - 1
        if kind in (0, 0xffff):
            break
    return [points, -1, keep_position]


def choose(clauses, active):
    for checks, result in clauses:
        if all((word[8:-1] not in active) if word.startswith("CUE_NOT(") else word in active
               for word in checks):
            return None if result == "CUE_NONE" else int(result, 16)
    raise ValueError(clauses)


def bake(disc):
    locations = load_json(ROOT / "game/world/location_catalog.json")
    areas = {(area["place"], area["location"]): int(id_) for id_, area in locations.items()}
    source_table = (SOURCE / "overlay/common/farm_section_table.h").read_text(encoding="utf-8")
    offsets = [int(word, 16) for word in re.findall(r"0x[\da-fA-F]+", source_table.split("= {", 1)[1])]
    sections = {id_: disc.asset(offsets[id_ * 4], offsets[id_ * 4 + 1] - offsets[id_ * 4])
                for id_ in areas.values()}
    packs = {id_: struct.unpack_from("<h", data, 12)[0] for id_, data in sections.items()}
    cue_data = disc.asset(0x74800, 0xa800)
    cue_source = (FARM / "event/cue_history.c").read_text(encoding="utf-8")
    cue_tables = {int(id_): body for id_, body in re.findall(r"cue_history_item_(\d+)\[\] = \{(.*?)\};", cue_source, re.S)}
    atlas = load_json(ATLAS)
    images, actors, routes = {}, {}, {}

    def take_art(ranges):
        poses = ranges[:5]
        assert len(poses[0]) >= 4 and all(poses), [len(row) for row in poses]
        for seq in poses:
            for frame in seq:
                if frame["image"] is not None:
                    images[frame["image"]] = atlas["images"][frame["image"]]
        return poses

    for name, actor in sorted(atlas["npc"].items(), key=lambda pair: pair[1]["id"]):
        if actor["id"] not in cue_tables:
            continue
        clauses = [(re.findall(r"CUE_NOT\(\w+\)|\w+", raw), result) for raw, result in re.findall(
            r"(?:CUE_IF,(.*?)CUE_THEN,|CUE_ELSE,)\s*(CUE_NONE|0x[\da-fA-F]+)", cue_tables[actor["id"]], re.S)]
        days, variants, variants_by_offset, used_areas = [], [], {}, set()
        for first_year in (True, False):
            for season in range(4):
                for weekday in range(7):
                    active = {str(11+weekday), str(23+season), "18", "EVENT_FLAG_WEATHER_SUNNY"}
                    if first_year:
                        active.add("EVENT_FLAG_FIRST_YEAR")
                    offset = choose(clauses, active)
                    if offset is None:
                        days.append(-1)
                        continue
                    if offset not in variants_by_offset:
                        steps = []
                        for minute, encoded_row, place, location in struct.iter_unpack(
                                "<hHhh", cue_data[offset:offset + 30 * 8]):
                            if (place, location) == (0, 0) or not 0 <= minute < 1440:
                                break
                            area = areas.get((place, location), -1)
                            row = encoded_row & 255
                            stamp = (minute - 360) % 1440
                            if steps and steps[-1][1:] == [area, row]:
                                continue
                            if steps:
                                stamp = max(stamp, steps[-1][0])
                            steps.append([stamp, area, row])
                            if area >= 0:
                                used_areas.add(area)
                                routes.setdefault(area, {})[row] = route(sections[area], row)
                        variants_by_offset[offset] = len(variants)
                        variants.append(steps)
                    days.append(variants_by_offset[offset])
        if not used_areas:
            continue
        source_packs = {int(key): value for key, value in actor["packs"].items() if key.isdigit()
                        and value and len(value[0]) >= 4 and all(value[:5])}
        default = min(source_packs)
        art_by_area = {area: packs[area] for area in sorted(used_areas) if packs[area] in source_packs}
        art = {pack: take_art(source_packs[pack]) for pack in sorted({default, *art_by_area.values()})}
        actors["zack" if name == "unnamed_26" else name] = dict(
            id=actor["id"], days=days, schedules=variants, default_art=default, area_art=art_by_area, art=art)

    # The helper house uses separate spawn positions and colour palettes.
    helpers_source = (FARM / "people/harvest_sprites.c").read_text(encoding="utf-8")
    helper_spots = re.search(r"harvest_helper_spots\[7\] = \{(.*?)\};", helpers_source, re.S)[1]
    helpers = {}
    for number, (name, spot) in enumerate(zip(
            ("chef", "nappy", "timid", "hoggy", "staid", "bold", "aqua"),
            re.findall(r"\{([^}]+)\}", helper_spots), strict=True), start=1):
        ranges = atlas["animals"][f"harvest_sprite_{number}"]["0"]
        helpers[name] = dict(spot=position(*map(int, spot.split(","))), poses=take_art(ranges))
    return dict(actors=actors, routes=routes, helpers=helpers, images=images,
                pages=atlas["pages"], canvas=atlas["canvas"], origin=atlas["origin"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    catalogue = bake(Disc(args.disc))
    output = json.dumps(catalogue, separators=(",", ":")) + "\n"
    if args.check:
        assert OUTPUT.read_text(encoding="utf-8") == output
    else:
        OUTPUT.write_text(output, encoding="utf-8")
    print("NPC_CATALOGUE_OK", len(catalogue["actors"]), "villagers,", len(catalogue["helpers"]),
          "helpers,", sum(map(len, catalogue["routes"].values())), "route rows")


if __name__ == "__main__":
    main()

"""Bake USA item prices, storage rules and shipping-box interaction zones."""
import argparse
import json
import re
import struct
from pathlib import Path

from import_disc import Disc, LAYOUTS, ROOT


SOURCE = ROOT / "reference/hmbtn-decomp/src"


def source_item_ids():
    return {name: int(value, 16) for name, value in re.findall(
        r"(ITEM_\w+)\s*=\s*(0x[\dA-Fa-f]+)", (SOURCE / "include/items.h").read_text())}


def scene_offsets():
    sections = (SOURCE / "overlay/common/farm_section_table.h").read_text()
    return [int(value, 16) for value in re.findall(r"0x[\da-fA-F]+", sections.split("= {", 1)[1])]


def bake(disc, ids, offsets):
    table = (SOURCE / "main/game/farm_tables.c").read_text().split("static ItemInfo item_info", 1)[1].split("};", 1)[0]
    prices = {}
    stowable = []
    pattern = (r"\[(ITEM_\w+)\]\s*=\s*\{[^\n{]+\{[^}]+\},\s*-?\d+,\s*(-?\d+),\s*(-?\d+),"
               r"\s*\{\.word\s*=\s*[^}]+\},\s*\{\.word\s*=\s*(0x[\da-fA-F]+)\}")
    for key, buy, sell, class_flags in re.findall(pattern, table):
        if key not in ids:
            continue
        item = ids[key]
        if int(buy) > 0 or int(sell) > 0:
            prices[str(item)] = [int(buy), int(sell)]
        # player_pending_transition uses item_class_word_negative.
        if int(class_flags, 16) & 0x80000000:
            stowable.append(item)
    assert ids["ITEM_COPPER_ORE"] in stowable and ids["ITEM_BASKET"] not in stowable
    assert prices[str(ids["ITEM_YOUNG_COW"])] == [6000, 0]
    assert prices[str(ids["ITEM_TURNIP"])] == [0, 60]
    world = json.loads((ROOT / "game/world/location_catalog.json").read_text(encoding="utf-8"))
    zones = {34: {}, 37: {}}
    for area in world:
        header = disc.asset(offsets[int(area)*4], 0xbdc)
        for index in range(50):
            offset = 16 + index * 44
            flags, kind = struct.unpack_from("<2H", header, offset)
            if not flags & 0x4000 or kind not in zones:
                continue
            facing = struct.unpack_from("<h", header, offset+8)[0]
            low = struct.unpack_from("<3h", header, offset+14)
            high = struct.unpack_from("<3h", header, offset+20)
            zones[kind].setdefault(area, []).append([facing, low[0]/1000, -high[2]/1000, high[0]/1000, -low[2]/1000])
    assert "112" in zones[34]
    mine_source = (SOURCE / "overlay/11_GF_FARM/field/mine.c").read_text()
    mines = {}
    for area, suffix in [(234, ""), (245, "_mine")]:
        weights = re.search(rf"mine_layer_weights{suffix}\[10\]\[8\] = \{{(.*?)\}};", mine_source, re.S)[1]
        events = re.search(rf"mine_layer_events{suffix}\[8\] = \{{(.*?)\}};", mine_source, re.S)[1]
        mines[str(area)] = {
            "weights": [[int(value) for value in row.split(",")] for row in re.findall(r"\{([^}]+)\}", weights)],
            "events": [0] + [ids[name] for name in re.findall(r"ITEM_\w+", events)],
        }
    return {"prices": prices, "shipping": zones[34], "counters": zones[37], "mines": mines, "stowable": sorted(stowable)}


def fishing_data(disc, ids, offsets):
    water = {}
    for area in [0, 24, 28, 56, 68, 72]:
        start, end = offsets[area*4:area*4+2]
        scene = disc.asset(start, end-start)
        base = 0x200c
        polygons = []
        for obj in range(struct.unpack_from("<I", scene, base-4)[0]):
            vp, _, _, _, pp, count, _ = struct.unpack_from("<7I", scene, base+obj*28)
            pos = base+pp
            for _ in range(count):
                flags, mode = struct.unpack_from("<HH", scene, pos)
                size, vertices, vi, *_ = LAYOUTS[mode & 0xfdff]
                if flags & 0x46 == 2:
                    corners = struct.unpack_from("<"+"H"*vertices, scene, pos+vi)
                    points = [struct.unpack_from("<3h", scene, base+vp+index*8) for index in corners]
                    polygons.extend(value for x, _, z in points for value in (x, -z))
                    if vertices == 3:
                        polygons.extend(polygons[-2:])
                pos += size
        water[str(area)] = polygons
    fishing = (SOURCE / "overlay/11_GF_FARM/field/fishing.c").read_text()
    catches = {}
    for kind in range(1, 5):
        body = re.search(rf"fishing_spot_catches_{kind}\[\d+\] = \{{(.*?)\}};", fishing, re.S)[1]
        fields = [field.strip() for field in body.split(",") if field.strip()]
        catches[str(kind)] = [ids[field] if field in ids else int(field, 0) for field in fields[1:-1]]
    amounts = re.search(r"fishing_bite_amounts\[82\] = \{(.*?)\};", fishing, re.S)[1]
    amounts = [int(value, 16) for value in re.findall(r"0x[\da-fA-F]+", amounts)]
    seasonal = [amounts[offset+1:offset+1+amounts[offset]*2] for offset in (6, 28, 38, 58)]
    return {"water": water, "catches": catches, "seasonal": seasonal}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    disc = Disc(args.disc)
    ids = source_item_ids()
    offsets = scene_offsets()
    for name, extract in [("economy", bake), ("fishing", fishing_data)]:
        data = extract(disc, ids, offsets)
        path = ROOT / f"game/economy/source_{name}.json"
        output = json.dumps(data, separators=(",", ":")) + "\n"
        if args.check:
            assert path.read_text(encoding="utf-8") == output
        else:
            path.write_text(output, encoding="utf-8")
    print("SOURCE_ECONOMY_OK")


if __name__ == "__main__":
    main()

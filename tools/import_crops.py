"""Extract crop rules, field artwork and tool patterns from the USA source."""
import argparse
import json
import re

from PIL import Image

from import_disc import Disc, ROOT, texture_bank, texture_page
from import_original_sprites import FARM, numbers, table


def patterns(source):
    body = source.split("static PictureGrid picture_grids", 1)[1].split("\n};", 1)[0]
    grids = {}
    for index, text in re.findall(r"/\*\s*(\d+)\s*\*/\s*\{\{(.*?)\}\},", body, re.S):
        grid = [numbers(row) for row in re.findall(r"\{([^{}]+)\}", text + "}")]
        assert len(grid) == 13 and all(len(row) == 13 for row in grid)
        transpose = list(map(list, zip(*grid)))
        rotations = [transpose, [row[::-1] for row in grid], transpose[::-1], grid]
        grids[int(index)] = [
            [[x-6, y-6] for _, x, y in sorted(
                (value, x, y) for y, row in enumerate(rotation) for x, value in enumerate(row) if value)]
            for rotation in rotations]
    return grids


def export(disc):
    source = (ROOT / "reference/hmbtn-decomp/src/main/game/farm_tables.c").read_text(encoding="utf-8")
    crop_table = source.split("static FarmCrop crop_table", 1)[1].split("\n};", 1)[0]
    rows = {name: numbers(row) for name, row in re.findall(r"/\* CROP_(\w+) \*/\s*\{([^}]+)", crop_table)}
    seed_rows = re.findall(
        r"\[ITEM_(\w+)_SEEDS\] = \{0x4040, 2, CROP_(\w+), \{[^}]+\}, (\d+),[^\n]+\n[^\n]+, (\d+), 0, 0\}", source)
    seed_rows = seed_rows[:21] # Seasonal event variants share the strawberry crop record.
    assert len(seed_rows) == 21 and len(rows) == 22, (seed_rows, list(rows))
    art = json.loads((ROOT / "game/original_sprites/catalogue.json").read_text(encoding="utf-8"))
    items = {entry["id"]: entry["variants"] for entry in art["items"].values()}
    names = ["芜菁","马铃薯","黄瓜","草莓","卷心菜","番茄","玉米","洋葱","南瓜","菠萝",
             "茄子","胡萝卜","地瓜","菠菜","青椒","月泪草","粉红猫薄荷","奇幻花","玩具花","橙杯果","牧草"]
    seeds, crops = {}, {}

    def picture(frame):
        page, *rect = art["images"][frame["image"]]
        return [art["pages"][page], rect, frame["offset"]]

    for item, ((_, crop, grid, animation), name) in enumerate(zip(seed_rows, names), 34):
        seeds[item] = dict(name=name, animation=int(animation), grid=int(grid), icon=picture(items[item]["sector"][0][0]))
        variants = [(item, crop)] if item != 51 else [(376, "BLUE_MAGIC_RED"), (377, "RED_MAGIC_RED")]
        for plant, key in variants:
            season, mature, regrow, *days, harvest = rows[key]
            frames = []
            if harvest > 0:
                field_id = 86 if harvest == 133 else harvest
                # The outdoor pumpkin pack has broken split pieces in the
                # original conversion. The greenhouse uses the same crop art.
                variant = "4" if harvest in (73, 133) else str(season)
                source_frames = items[field_id][variant]

                frames = [None]
                for stage in range(1, mature + 1):
                    if stage + 2 < len(source_frames):
                        frames.append(picture(source_frames[stage + 2][0]))
                    else:
                        # A few banks lack the terminal field pose. Use the
                        # original harvested picture so ripeness stays visible.
                        frames.append(picture(items[harvest]["sector"][0][0]))
            crops[plant] = dict(season=season, mature=mature, regrow=regrow, days=days[:mature],
                                harvest=harvest, frames=frames)
    produce = {row["harvest"]: picture(items[row["harvest"]]["sector"][0][0])
               for row in crops.values() if row["harvest"] > 0}
    grids = patterns(source)
    player = (FARM / "people/player.c").read_text(encoding="utf-8")
    water_steps = table(player, "tool_charge_steps_b")[:5]
    catalogue = dict(seeds=seeds, crops=crops, produce=produce,
                     sow=grids[25], water=[grids[index] for index in range(20, 25)],
                     cut=[grids[index] for index in range(5)], water_steps=water_steps)
    (ROOT / "game/field/crop_catalog.json").write_text(json.dumps(catalogue, ensure_ascii=False, separators=(",", ":"))+"\n", encoding="utf-8")

    field = (FARM / "field/field.c").read_text(encoding="utf-8")
    body = field.split("cell_looks[30] = {", 1)[1].split("\n};", 1)[0]
    looks = [(numbers(uv), int(clut, 0)) for uv, clut in re.findall(r"\{\{([^}]+)\},\s*(0x[0-9A-F]+)\}", body)]
    source = (ROOT / "reference/hmbtn-decomp/src/overlay/common/farm_section_table.h").read_text(encoding="utf-8")
    offsets = table(source, "section_table")
    ground = Image.new("RGBA", (256, 128))
    for season in range(4):
        start, end = offsets[season*4+1:season*4+3]
        vram, _ = texture_bank(disc.asset(start, end-start))
        for slot, look in enumerate([0,1,2,3,4,5,13,21]):
            uv, clut = looks[29 if season == 3 else look]
            u, v = min(uv[::2]), min(uv[1::2])
            if season == 2 and look >= 5:
                clut = (clut & 0xFFC0) | 0x35
            page = 7 if season == 3 else (29 if look >= 5 else 8)
            tile = texture_page(vram, page, clut).crop((u,v,u+32,v+32))
            assert tile.getbbox(), (season, look)
            ground.paste(tile, (slot*32, season*32))
    ground.save(ROOT / "game/original_sprites/field_ground.png")
    print("CROP_SOURCE_OK", len(seeds), "seed tools,", len(crops), "crop records,", len(produce), "produce")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc")
    export(Disc(parser.parse_args().disc))

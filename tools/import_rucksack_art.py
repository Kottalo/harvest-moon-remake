"""Extract the original backpack's cursor, slot marks and number sprites."""
import argparse
from pathlib import Path

from PIL import Image
from import_disc import Disc, ROOT, compose_animations

ORIGIN = (128, 176)
CELL = (44, 36)
MARGIN_X = 10


def build(disc):
    frames, ranges, _ = compose_animations(
        disc.asset(0x25000, 0x5800), 0x13dc, [10, 11], canvas_size=256)
    # storage_swap.c and item_storage.c use all three range-11 frames.
    sequence = ranges[1] + ranges[0]
    atlas = Image.new("RGBA", (CELL[0] * len(sequence), CELL[1]))
    x, y = ORIGIN
    for index, frame in enumerate(sequence):
        image = frames[frame["tile"]]
        sprite = image.crop((x - MARGIN_X, y, x - MARGIN_X + CELL[0], y + CELL[1]))
        assert sprite.getbbox()
        atlas.paste(sprite, (index * CELL[0], 0))
    return atlas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = ROOT / "game/items/rucksack_marks.png"
    source = build(Disc(args.disc))
    if args.check:
        with Image.open(output) as asset:
            assert asset.size == source.size and asset.convert("RGBA").tobytes() == source.tobytes()
    else:
        source.save(output)
    print("SOURCE_RUCKSACK_ART_OK")


if __name__ == "__main__":
    main()

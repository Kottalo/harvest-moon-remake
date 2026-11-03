"""Extract original USA NPC, farm animal and item pictures into Godot atlases."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess
from tempfile import TemporaryDirectory

from PIL import Image

from import_disc import Disc, ROOT, compose_animations, texture_bank
from pack_textures import NODE, TOOL

FARM = ROOT / "reference/hmbtn-decomp/src/overlay/11_GF_FARM"
CANVAS = 256


def numbers(text):
    return [int(value, 0) for value in re.findall(r"-?0x[\da-fA-F]+|-?\d+", text)]


def table(source, name):
    return numbers(re.search(rf"\b{name}\[\d+\]\s*=\s*\{{([^}}]+)", source)[1])


def toc(source, name, index):
    count, offsets = re.search(rf"\b{name}_{index}\s*=\s*\{{(\d+),\s*\{{([^}}]+)", source).groups()
    count = int(count)
    offsets = numbers(offsets)
    return offsets[:count], offsets[count:]


def names(source, prefix):
    return {int(value, 0): name.lower() for name, value in
            re.findall(rf"\b{prefix}_(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)\s*,", source)}


def read_pack(disc, offsets, index):
    return disc.asset(offsets[index], offsets[index + 1] - offsets[index])


class Library:
    def __init__(self, frames):
        self.frames = frames
        self.images = {}

    def decode(self, block, start, bank, *, decoded=None, palette_y=0):
        data = block[start:]
        ranges, frames = struct.unpack_from("<2I", data, 28)
        assert 0 < frames - ranges <= 2048 and (frames - ranges) % 4 == 0
        pictures, animations, _ = compose_animations(
            data, bank - start, range((frames - ranges) // 4), canvas_size=CANVAS,
            decoded_bank=decoded, palette_y=palette_y)
        for animation in animations:
            for frame in animation:
                picture = pictures[frame.pop("tile")]
                bounds = picture.getbbox()
                if bounds is None:
                    frame["image"] = None
                    continue
                crop = picture.crop(bounds)
                digest = hashlib.sha256(struct.pack("<2H", *crop.size) + crop.tobytes()).hexdigest()
                if digest not in self.images:
                    self.images[digest] = crop.size
                    crop.save(self.frames / f"{digest}.png")
                frame["image"] = digest
                frame["offset"] = [bounds[0] - CANVAS // 2, bounds[1] - (CANVAS // 2 + 48)]
        return animations

    def pack(self, work, destination):
        project = work / "sprites.ftpp"
        project.write_text(json.dumps(dict(
            images=[dict(name=f"{key}.png", path=str(self.frames / f"{key}.png"))
                    for key in self.images], folders=[],
            packOptions=dict(textureName="original_sprites", width=2048, height=2048,
                             padding=4, extrude=4, allowRotation=False, allowTrim=False,
                             detectIdentical=True, exporter="JsonHash", textureFormat="png",
                             packer="MaxRectsPacker", packerMethod="Smart"))), encoding="utf-8")
        packed = work / "packed"
        packed.mkdir()
        subprocess.run([NODE, str(TOOL / "node_modules/free-tex-packer-cli/index.js"),
                        "--project", str(project), "--output", str(packed)], check=True, cwd=ROOT)
        entries = {}
        pages = []
        for metadata in sorted(packed.glob("*.json")):
            png = metadata.with_suffix(".png")
            pages.append(f"res://{(destination / png.name).relative_to(ROOT).as_posix()}")
            atlas = Image.open(png).convert("RGBA")
            for name, frame in json.loads(metadata.read_text(encoding="utf-8"))["frames"].items():
                key = Path(name).stem
                assert not frame["rotated"] and not frame["trimmed"]
                rect = frame["frame"]
                x, y, w, h = (rect[k] for k in ("x", "y", "w", "h"))
                assert (w, h) == self.images[key]
                assert atlas.crop((x, y, x+w, y+h)).tobytes() == Image.open(self.frames / f"{key}.png").tobytes()
                entries[key] = [len(pages)-1, x, y, w, h]
        assert entries.keys() == self.images.keys()
        return pages, entries, packed


def extract(disc, library):
    load = (FARM / "farm_load.c").read_text(encoding="utf-8")
    data = (FARM / "farm_data.c").read_text(encoding="utf-8")
    people = names((FARM / "people/villager.h").read_text(encoding="utf-8"), "CHARACTER")
    item_names = names((ROOT / "reference/hmbtn-decomp/src/include/items.h").read_text(encoding="utf-8"), "ITEM")
    offsets = table(load, "farm_pack_file_offsets")
    npc = {}
    for index in range(len(offsets) - 1):
        pack = read_pack(disc, offsets, index)
        starts, banks = toc(data, "farm_pack_toc", index)
        bank = banks[0]
        decoded = texture_bank(pack[bank:])
        for extra_bank in banks[1:]:
            texture_bank(pack[extra_bank:], decoded[0])
        ids = struct.unpack_from(f"<{len(starts)+1}I", pack)
        assert ids[0] == len(starts)
        for id_, start in zip(ids[1:], starts):
            name = people.get(id_, f"actor_{id_:03d}")
            npc.setdefault(name, dict(id=id_, packs={}))["packs"][index] = library.decode(pack, start, bank, decoded=decoded)

    animals = {}
    offsets = table(load, "farm_slot_file_offsets")
    livestock = ("calf", "cow", "slot_actor_03", "pregnant_cow", "lamb", "sheep",
                 "slot_actor_07", "pregnant_sheep", "shorn_sheep", "harvest_sprite")
    for index in range(2):
        pack = read_pack(disc, offsets, index)
        starts, (bank,) = toc(data, "farm_slot_toc", index)
        decoded = texture_bank(pack[bank:])
        for name, start in zip(livestock, starts):
            if name == "harvest_sprite":
                for helper, palette in enumerate((0, 3, 1, 6, 2, 4, 5), start=1):
                    animals.setdefault(f"harvest_sprite_{helper}", {})[index] = library.decode(
                        pack, start, bank, decoded=decoded, palette_y=palette)
            else:
                animals.setdefault(name, {})[index] = library.decode(pack, start, bank, decoded=decoded)
    pack = disc.asset(0x380B000, 0x5000)
    starts, (bank,) = toc(data, "farm_slot_toc", 6)
    for name, start in zip(("chick", "chicken", "actor_item_157", "actor_item_156", "visitor"), starts):
        animals[name] = {0: library.decode(pack, start, bank)}
    for table_name, variants in (
        ("farm_span_offsets", (("dog", 0x23C8), ("puppy", 0x1420))),
        ("farm_anim8_offsets", (("horse", 2592), ("pony", 2104))),
    ):
        offsets = table(load, table_name)
        for index, (name, bank) in enumerate(variants):
            animals[name] = {0: library.decode(read_pack(disc, offsets, index), 0, bank)}

    wildlife = (
        ("squirrel", "snake", "rabbit", "ladybug", "grasshopper"),
        ("squirrel", "rabbit", "beetle", "stag_beetle", "cicada"),
        ("fox", "squirrel", "rabbit", "cricket", "dragonfly"),
        ("fox", "monkey", "rabbit"),
    )
    offsets = table(load, "farm_season_file_offsets")
    for index, variants in enumerate(wildlife):
        pack = read_pack(disc, offsets, index)
        starts, (bank,) = toc(data, "farm_slot_toc", index + 2)
        assert len(variants) == len(starts)
        decoded = texture_bank(pack[bank:])
        for name, start in zip(variants, starts):
            animals.setdefault(name, {})[index] = library.decode(pack, start, bank, decoded=decoded)

    items = {}
    packed_only = {59, 60, 61, 80}
    for id_ in range(1, 392):
        if id_ in packed_only:
            continue
        block = disc.asset(0x3C19000 + id_*2048, 2048)
        if block[:4] == b"\x0e\0\0\0" and block[0x100] == 13:
            items.setdefault(id_, {})["sector"] = library.decode(block, 0, 0x100)
    offsets = table(load, "farm_item_file_offsets")
    ids = table(data, "place_entries")
    indices = numbers(re.search(r"\bresource_lists\[10\]\s*=\s*\{([^}]+)", data)[1])
    for index, first in enumerate(indices):
        block = read_pack(disc, offsets, index)
        starts, (bank,) = toc(data, "farm_item_toc", index)
        decoded = texture_bank(block[bank:])
        assert ids[first] == len(starts)
        for id_, start in zip(ids[first + 1:], starts):
            if id_ > 0:
                items.setdefault(id_, {})[str(index)] = library.decode(block, start, bank, decoded=decoded)
    assert packed_only <= items.keys()
    return dict(npc=npc, animals=animals, items={
        item_names.get(id_, f"item_{id_:03x}"): dict(id=id_, variants=variants)
        for id_, variants in sorted(items.items())
    }, items_without_picture={
        name: id_ for id_, name in item_names.items() if 0 < id_ < 380 and id_ not in items
    })


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    destination = ROOT / "game/original_sprites"
    staging = TOOL / "frames"
    staging.mkdir(exist_ok=True)
    with TemporaryDirectory(prefix="original-sprites-", dir=staging) as temporary:
        work = Path(temporary)
        frames = work / "frames"
        frames.mkdir()
        library = Library(frames)
        catalogue = extract(Disc(args.disc), library)
        pages, images, packed = library.pack(work, destination)
        catalogue.update(pages=pages, images=images, canvas=CANVAS, origin=[128, 176], source_tick_rate=30)
        output = json.dumps(catalogue, separators=(",", ":")) + "\n"
        if not args.check:
            destination.mkdir(exist_ok=True)
            (destination / "catalogue.json").write_text(output, encoding="utf-8")
        assert (destination / "catalogue.json").read_text(encoding="utf-8") == output
        for page in pages:
            target = ROOT / page[6:]
            pixels = (packed / target.name).read_bytes()
            if not args.check:
                target.write_bytes(pixels)
            assert target.read_bytes() == pixels
    print("ORIGINAL_SPRITES_OK:", {key: len(catalogue[key]) for key in
          ("npc", "animals", "items", "items_without_picture", "images", "pages")})


if __name__ == "__main__":
    main()

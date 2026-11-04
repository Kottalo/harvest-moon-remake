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

from import_disc import Disc, ROOT, compose_animations, model_mesh, texture_bank, texture_page
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
                frame["image"] = self.add_picture(crop)
                frame["offset"] = [bounds[0] - CANVAS // 2, bounds[1] - (CANVAS // 2 + 48)]
        return animations

    def add_picture(self, picture):
        digest = hashlib.sha256(struct.pack("<2H", *picture.size) + picture.tobytes()).hexdigest()
        if digest not in self.images:
            self.images[digest] = picture.size
            picture.save(self.frames / f"{digest}.png")
        return digest

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


def extract_event_actors(disc, library, people, item_names, npc, items):
    source = (FARM / "event/event_script.c").read_text(encoding="utf-8")
    offsets = table(source, "event_script_offsets")
    member = int(re.search(r"#define EVENT_SCRIPT_AFILE (0x[0-9A-Fa-f]+)", source)[1], 0)
    base = disc.archive_toc[member]
    assert offsets[-1] <= disc.archive_toc[member + 1] - base
    for event, (start, end) in enumerate(zip(offsets, offsets[1:])):
        if end == start:
            continue
        block = disc.asset(base + start, end - start)
        _, count, *flags = struct.unpack_from("<26H", block)
        origin = 52 + (count + 1) * 4
        assert 0 <= count <= 24 and origin <= len(block), event
        slots = [
            (flag, origin + struct.unpack_from("<I", block, 52 + index * 4)[0])
            for index, flag in enumerate(flags[:count])
        ]
        actors = [
            (flag, position) for flag, position in slots
            if flag & 0x3C00 and block[position:position + 4] == b"\x0e\0\0\0"
        ]
        if not actors:
            continue
        vram = bytearray(1024 * 512 * 2)
        texture_count = 0
        for flag, position in slots:
            if flag & 0x8000:
                _, textures = texture_bank(block[position:], vram)
                texture_count += textures
        assert texture_count, event
        for index, (flag, position) in enumerate(actors):
            id_ = flag & 0x3FF
            variant = f"event_{event:03d}_{index:02d}"
            animation = library.decode(block, position, 0, decoded=(vram, texture_count))
            if flag & 0x2000 or flag == 0x401:
                if flag == 0x401:
                    id_ = 41
                name = people.get(id_, f"actor_{id_:03d}")
                npc.setdefault(name, dict(id=id_, packs={}))["packs"][variant] = animation
            else:
                items.setdefault(id_, {})[variant] = animation



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
    # These plant IDs are selected by field.c from an art slot, rather than
    # by the shop/rucksack ID alongside that slot.
    plant_slots = {2: {0x178: 17, 0x179: 25}, 4: {0x178: 22, 0x179: 27}}
    for index, first in enumerate(indices):
        block = read_pack(disc, offsets, index)
        starts, (bank,) = toc(data, "farm_item_toc", index)
        decoded = texture_bank(block[bank:])
        assert ids[first] == len(starts)
        for id_, start in zip(ids[first + 1:], starts):
            if id_ > 0:
                items.setdefault(id_, {})[str(index)] = library.decode(block, start, bank, decoded=decoded)
        for id_, slot in plant_slots.get(index, {}).items():
            items.setdefault(id_, {})[f"field_{index}"] = library.decode(
                block, starts[slot], bank, decoded=decoded)
    assert packed_only <= items.keys()
    extract_event_actors(disc, library, people, item_names, npc, items)
    stray = disc.asset(0x7F000, 0x4800)
    animals["stray_dog"] = {0: library.decode(stray, 0, 0x770)}
    assert "gourmet" in npc
    actor_resources = {
        "cat": "actor_043", "visiting_cow": "actor_040", "visiting_sheep": "player",
        "actor_item_17a": "all_villagers", "actor_item_17b": "actor_044",
    }
    for animal, entry in actor_resources.items():
        # Event variants may reuse the same numeric slot for a different actor.
        animals[animal] = {key: value for key, value in npc[entry]["packs"].items()
                           if isinstance(key, int)}
        assert animals[animal], animal
    return dict(npc=npc, animals=animals, items={
        item_names.get(id_, f"item_{id_:03x}"): dict(id=id_, variants=variants)
        for id_, variants in sorted(items.items())
    }, item_actor_links={
        "visitor": ["visitor"], "156": ["actor_item_156"], "157": ["actor_item_157"],
        "stray_dog": ["stray_dog"], "pony": ["pony"], "horse": ["horse"], "calf": ["calf"],
        "young_cow": ["cow"], "cow": ["cow"], "visiting_cow": ["visiting_cow"],
        "lamb": ["lamb"], "sheep": ["sheep"], "visiting_sheep": ["visiting_sheep"],
        "harvest_sprite": [f"harvest_sprite_{index}" for index in range(1, 8)],
        "17a": ["actor_item_17a"], "17b": ["actor_item_17b"],
    }, items_without_picture={
        name: id_ for id_, name in item_names.items() if 0 < id_ < 380 and id_ not in items
    })


def extract_soil_states(disc, library):
    source = (FARM / "field/field.c").read_text(encoding="utf-8")
    body = source.split("cell_looks[30] = {", 1)[1].split("\n};", 1)[0]
    looks = [(numbers(uv), int(clut, 0)) for uv, clut in
             re.findall(r"\{\{([^}]+)\},\s*(0x[0-9A-F]+)\}", body)]
    assert len(looks) == 30
    section_source = (ROOT / "reference/hmbtn-decomp/src/overlay/common/farm_section_table.h").read_text(encoding="utf-8")
    offsets = table(section_source, "section_table")
    states = {}
    names = ("soil", "tilled_soil", "watered_soil", "sown_soil", "watered_sown_soil")
    for season in range(4):
        start, end = offsets[season * 4 + 1:season * 4 + 3]
        vram, _ = texture_bank(disc.asset(start, end - start))
        for index, name in enumerate(names):
            uv, clut = looks[29 if season == 3 else index]
            u, v = uv[::2], uv[1::2]
            rect = (min(u), min(v), max(u) + 1, max(v) + 1)
            tile = texture_page(vram, 7 if season == 3 else 8, clut).crop(rect)
            assert tile.getbbox(), (season, name)
            states.setdefault(name, dict(id=359 + index, seasons={}))["seasons"][season] = dict(
                image=library.add_picture(tile), corners=[[x - rect[0], y - rect[1]] for x, y in zip(u, v)])
    return states


def extract_makers(disc, library, work):
    source = (ROOT / "reference/hmbtn-decomp/src/overlay/common/farm_section_table.h").read_text(encoding="utf-8")
    offsets = table(source, "section_table")
    makers = {}
    # Source TMD objects group by draw packet, so each also contains adjacent wall faces.
    for name, area, object_index, x, z in (
        ("mayonnaise_maker", 120, 15, 1400, 2140),
        ("cheese_maker", 104, 26, -200, 2540),
        ("yarn_maker", 108, 34, 600, 2540),
    ):
        start, textures, end = offsets[area * 4:area * 4 + 3]
        data = disc.asset(start, textures - start)
        vram, _ = texture_bank(disc.asset(textures, end - textures))
        directory = work / name
        (directory / "textures").mkdir(parents=True)
        def machine_primitive(index, points):
            return index == object_index and all(
                abs(px - x) <= 172 and -500 <= py <= 0 and z - 204 <= pz <= z + 172
                for px, py, pz in points)
        surfaces, report = model_mesh(data, vram, directory, primitive_filter=machine_primitive)
        assert report["primitives"] > 60, (name, report)
        for surface in surfaces:
            assert surface["visible"] and surface["blend_mode"] == -1, name
            texture = surface["texture"]
            surface["image"] = library.add_picture(Image.open(directory / texture).convert("RGBA")) if texture else None
            vertices = surface["vertices"]
            for vertex in range(0, len(vertices), 3):
                vertices[vertex] = round(vertices[vertex] - x / 1000, 6)
                vertices[vertex + 2] = round(vertices[vertex + 2] + z / 1000, 6)
        makers[name] = dict(area=area, tmd_object=object_index, primitives=report["primitives"],
                            position=[x / 1000, 0, -z / 1000],
                            surfaces=[{key: surface[key] for key in ("vertices", "colors", "uv", "image")}
                                      for surface in surfaces])
    return makers



def thomas_walk_catalogue(catalogue):
    # Keep the first NPC's runtime catalogue small. The source library is loaded offline.
    packs = catalogue["npc"]["mayor_thomas"]["packs"]
    ranges = (packs[6] if 6 in packs else packs["6"])[:5]
    assert [len(sequence) for sequence in ranges] == [4, 8, 8, 8, 8]
    images = {frame["image"]: catalogue["images"][frame["image"]]
              for sequence in ranges for frame in sequence}
    return dict(ranges=ranges, images=images, canvas=catalogue["canvas"],
                origin=catalogue["origin"], pages=catalogue["pages"])


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
        disc = Disc(args.disc)
        catalogue = extract(disc, library)
        models = extract_makers(disc, library, work)
        catalogue["field_surfaces"] = extract_soil_states(disc, library)
        pages, images, packed = library.pack(work, destination)
        catalogue.update(pages=pages, images=images, canvas=CANVAS, origin=[128, 176], source_tick_rate=30)
        for model in models.values():
            for surface in model["surfaces"]:
                image = surface.pop("image")
                if image:
                    page, *region = images[image]
                    surface["atlas"] = pages[page]
                    surface["region"] = region
        for name in catalogue["item_actor_links"] | catalogue["field_surfaces"]:
            catalogue["items_without_picture"].pop(name, None)
        catalogue["items_without_picture"].pop("mayonnaise_maker")
        catalogue["nonvisual_action_ids"] = catalogue.pop("items_without_picture")
        # These three handlers leave the ANI base unset in farm_actor_load_sprite.
        assert set(catalogue["nonvisual_action_ids"].values()) == {0x153, 0x155, 0x159}
        catalogue["item_models"] = {name: f"res://game/original_sprites/models/{name}.tscn" for name in models}
        output = json.dumps(catalogue, separators=(",", ":")) + "\n"
        model_output = json.dumps(models, separators=(",", ":")) + "\n"
        thomas = ROOT / "game/npc/thomas_walk.json"
        thomas_output = json.dumps(thomas_walk_catalogue(catalogue), separators=(",", ":")) + "\n"
        if not args.check:
            (destination / "models").mkdir(parents=True, exist_ok=True)
            (destination / "catalogue.json").write_text(output, encoding="utf-8")
            (destination / "models/makers.json").write_text(model_output, encoding="utf-8")
            thomas.write_text(thomas_output, encoding="utf-8")
        assert thomas.read_text(encoding="utf-8") == thomas_output
        assert (destination / "models/makers.json").read_text(encoding="utf-8") == model_output
        assert (destination / "catalogue.json").read_text(encoding="utf-8") == output
        for page in pages:
            target = ROOT / page[6:]
            pixels = (packed / target.name).read_bytes()
            if not args.check:
                target.write_bytes(pixels)
            assert target.read_bytes() == pixels
    print("ORIGINAL_SPRITES_OK:", {key: len(catalogue[key]) for key in
          ("npc", "animals", "items", "field_surfaces", "nonvisual_action_ids", "images", "pages")})


if __name__ == "__main__":
    main()

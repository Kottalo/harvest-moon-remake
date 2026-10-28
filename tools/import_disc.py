"""Convert the user's USA disc to native Godot assets. No disc access at runtime.

Layouts are documented in reference/hmbtn-decomp/src/main/{graphics,geometry}
and src/overlay/common/farm_section_table.h. Requires Pillow for PNG writing.
"""
from pathlib import Path
import argparse
from collections import Counter
import hashlib
import json
import re
import struct
from tempfile import TemporaryDirectory

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
WRITTEN_TEXTURES = set()
MOTION_TEXTURES = {}


class Disc:
    def __init__(self, path):
        self.file = open(path, 'rb')
        magic = self.file.read(16)
        self.stride, self.skip = (2352, 24) if magic[:12] == b'\x00' + b'\xff' * 10 + b'\x00' else (2048, 0)
        pvd = self.read(16 * 2048, 2048)
        assert pvd[1:6] == b'CD001', 'Not a supported ISO/Mode2 disc'
        lba = struct.unpack_from('<I', pvd, 158)[0]
        size = struct.unpack_from('<I', pvd, 166)[0]
        directory = self.read(lba * 2048, size)
        pos = 0
        self.archive = None
        while pos < len(directory):
            length = directory[pos]
            if not length:
                pos = (pos // 2048 + 1) * 2048
                continue
            record = directory[pos:pos + length]
            name = record[33:33 + record[32]].decode('ascii', errors='replace')
            if name.split(';')[0] == 'A_FILE.BIN':
                self.archive = struct.unpack_from('<I', record, 2)[0] * 2048
            pos += length
        assert self.archive is not None, 'A_FILE.BIN is missing'

    def read(self, offset, length):
        result = bytearray()
        while length:
            sector, within = divmod(offset, 2048)
            count = min(length, 2048 - within)
            self.file.seek(sector * self.stride + self.skip + within)
            data = self.file.read(count)
            assert len(data) == count, 'Truncated disc'
            result.extend(data)
            offset += count
            length -= count
        return bytes(result)

    def asset(self, offset, length):
        return self.read(self.archive + offset, length)


def expand_rle(data, length):
    result = bytearray()
    pos = 0
    while len(result) < length:
        assert pos < len(data), 'Truncated RLE control'
        count = struct.unpack_from('b', data, pos)[0]
        pos += 1
        if count < 0:
            count = -count
            assert pos + count <= len(data), 'Truncated RLE literal'
            result.extend(data[pos:pos + count])
            pos += count
        else:
            assert pos < len(data), 'Truncated RLE repeat'
            result.extend(bytes([data[pos]]) * max(1, count))
            pos += 1
    assert len(result) == length, 'RLE exceeds image bounds'
    return result


def texture_bank(data):
    assert data[0] == 0x0d, 'Expected image bank'
    vram = bytearray(1024 * 512 * 2)
    count = struct.unpack_from('<H', data, 2)[0]
    pos = 4
    for index in range(count):
        size_flags, x, y, w, h = struct.unpack_from('<I4H', data, pos)
        size, flags = size_flags & 0xffffff, size_flags >> 24
        assert 0 < w <= 1024 and 0 < h <= 512 and x + w <= 1024 and y + h <= 512, (index, x, y, w, h)
        payload = data[pos + 12:pos + 12 + size]
        assert len(payload) == size
        pixels = expand_rle(payload, w * h * 2) if (flags & 12) == 0 or flags & 8 else payload
        assert len(pixels) >= w * h * 2
        if flags & 8:
            for col in range(w):
                for half in range(2):
                    for row in range(h):
                        vram[((y + row) * 1024 + x + col) * 2 + half] = pixels[(col * 2 + half) * h + row]
        else:
            for row in range(h):
                dest = ((y + row) * 1024 + x) * 2
                vram[dest:dest + w * 2] = pixels[row * w * 2:(row + 1) * w * 2]
        pos += 12 + (size + 3 & ~3)
    return vram, count


def rgba(word, semi_transparent=False):
    alpha = 0 if word == 0 else 128 if semi_transparent and word & 0x8000 else 255
    return tuple(((word >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)) + (alpha,)


def texture_page(vram, page, clut, semi_transparent=False):
    x, y, depth = (page & 15) * 64, ((page >> 4) & 1) * 256, (page >> 7) & 3
    assert depth < 3, 'Reserved PS1 texture depth'
    words = memoryview(vram).cast('H')
    cx, cy = (clut & 63) * 16, (clut >> 6) & 511
    palette = [rgba(words[(cy * 1024 + cx + i) % len(words)], semi_transparent) for i in range(16 if depth == 0 else 256)] if depth < 2 else []
    colors = []
    for v in range(256):
        for u in range(256):
            word = words[((y + v) & 511) * 1024 + ((x + (u >> (2 - depth))) & 1023)]
            if depth == 0:
                colors.append(palette[(word >> ((u & 3) * 4)) & 15])
            elif depth == 1:
                colors.append(palette[(word >> ((u & 1) * 8)) & 255])
            else:
                colors.append(rgba(word, semi_transparent))
    image = Image.new('RGBA', (256, 256))
    image.putdata(colors)
    return image


# mode -> (size, vertex count, first vertex index offset, first color offset, textured, gouraud)
LAYOUTS = {
    0x2101: (16, 3, 8, 4, False, False),
    0x3101: (24, 3, 16, 4, False, True),
    0x2901: (16, 4, 8, 4, False, False),
    0x3901: (28, 4, 20, 4, False, True),
    0x2501: (28, 3, 20, 16, True, False),
    0x3501: (36, 3, 28, 16, True, True),
    0x2d01: (32, 4, 24, 20, True, False),
    0x3d01: (44, 4, 36, 20, True, True),
}


def scene_motion(data):
    """FarmModeScript.frames: scene_view.c slot_rect_step and slot_image_step."""
    frames = [struct.unpack_from('<HhH6h', data, 16 + 50 * 44 + i * 18) for i in range(8)]
    result, seen = [], set()
    for index, frame in enumerate(frames):
        identity, duration, following, x, y, sx, sy, w, h = frame
        if identity == 0xffff or identity in seen:
            continue
        seen.add(identity)
        if not identity & 0x8000:
            result.append(dict(dest=[x, y, w, h], source=[sx, sy, w, h], timing=[0, 0, 0, following + 1]))
            continue
        chain, tick, current = [], 0, index
        while True:
            key, duration, following, x, y, sx, sy, w, h = frames[current]
            assert key == identity and duration > 0
            chain.append(dict(dest=[x, y, w, h], source=[sx, sy, w, h], timing=[tick, tick + duration, 0, 0]))
            tick += duration
            current = following
            if current == index:
                break
            assert len(chain) < 8, 'Unsupported non-cyclic image slot'
        copies = [0, 8, 16] if struct.unpack_from('<H', data, 2)[0] == 0x2c and identity & 1 else [0]
        for item in chain:
            item['timing'][2] = tick
            for shift in copies:
                x, y, w, h = item['dest']
                result.append(dict(dest=[x + shift, y, w, h], source=item['source'], timing=item['timing']))
    return result


def texture_motion(vram, page, clut, filename, out, frames, semi):
    if not frames:
        return {}
    destination = out / filename
    if destination in MOTION_TEXTURES:
        return MOTION_TEXTURES[destination]
    px, py, depth = (page & 15) * 64, ((page >> 4) & 1) * 256, (page >> 7) & 3
    factor = 4 >> depth
    selected = [f for f in frames if px <= f['dest'][0] and f['dest'][0] + f['dest'][2] <= px + 256 // factor
                and py <= f['dest'][1] and f['dest'][1] + f['dest'][3] <= py + 256]
    if not selected:
        MOTION_TEXTURES[destination] = {}
        return {}
    words = memoryview(vram).cast('H')
    cx, cy = (clut & 63) * 16, (clut >> 6) & 511
    palette = [rgba(words[cy * 1024 + cx + i], semi) for i in range(16 if depth == 0 else 256)] if depth < 2 else []
    width = max(f['source'][2] * factor for f in selected)
    height = sum(f['source'][3] for f in selected)
    atlas = Image.new('RGBA', (width, height))
    records, row = [], 0
    for frame in selected:
        sx, sy, w, h = frame['source']
        pixels = []
        for v in range(h):
            for u in range(w * factor):
                word = words[((sy + v) & 511) * 1024 + ((sx + u // factor) & 1023)]
                value = palette[(word >> ((u % factor) * (16 // factor))) & ((1 << (16 // factor)) - 1)] if depth < 2 else rgba(word, semi)
                pixels.append(value)
        image = Image.new('RGBA', (w * factor, h))
        image.putdata(pixels)
        atlas.paste(image, (0, row))
        x, y, dw, dh = frame['dest']
        records.append(dict(dest=[(x - px) * factor, y - py, dw * factor, dh], source=[0, row, w * factor, h], timing=frame['timing']))
        row += h
    motion_name = str(Path(filename).with_stem(Path(filename).stem + '_motion')).replace('\\', '/')
    atlas.save(out / motion_name)
    result = dict(texture=motion_name, size=[width, height], records=records)
    MOTION_TEXTURES[destination] = result
    return result


def model_mesh(data, vram, out, offset=0x2000, texture_names=None, animations=()):
    assert struct.unpack_from('<I', data, offset)[0] in (0x41, 0x42)
    base = offset + 12
    objects = struct.unpack_from('<I', data, offset + 8)[0]
    groups, types = {}, Counter()
    if texture_names is None:
        texture_names = {}
    for obj in range(objects):
        vp, nv, _, _, pp, np, _ = struct.unpack_from('<7I', data, base + obj * 28)
        points = [struct.unpack_from('<3h', data, base + vp + i * 8) for i in range(nv)]
        pos = base + pp
        for primitive in range(np):
            header = struct.unpack_from('<I', data, pos)[0]
            key = header >> 16 & 0xfdff
            assert key in LAYOUTS, f'Unsupported TMD mode {key:04x} at {pos:x}'
            size, count, vi, ci, textured, gouraud = LAYOUTS[key]
            packet = data[pos:pos + size]
            assert len(packet) == size
            indices = struct.unpack_from('<' + 'H' * count, packet, vi)
            assert all(i < nv for i in indices), (obj, primitive, indices, nv)
            page = struct.unpack_from('<H', packet, 10)[0] if textured else 0
            clut = struct.unpack_from('<H', packet, 6)[0] if textured else 0
            name = f'p{page:04x}_c{clut:04x}' if textured else 'solid'
            # Additive black changes no framebuffer pixels, but these planes still supply ground.
            colors = [packet[ci + i * 4:ci + i * 4 + 3] for i in range(count if gouraud else 1)]
            visible = not (textured and header & 0x02000000 and (page >> 5) & 3 == 1 and not any(map(any, colors)))
            blend_mode = (page >> 5) & 3 if textured and header & 0x02000000 else -1
            group_key = (name, visible, blend_mode)
            if group_key not in groups:
                if textured and name not in texture_names:
                    texture_names[name] = f'textures/{out.name}_atlas_{len(texture_names) + 1:02d}.png'
                filename = texture_names[name] if textured else ''
                if textured and out / filename not in WRITTEN_TEXTURES:
                    texture_page(vram, page, clut).save(out / filename)
                    WRITTEN_TEXTURES.add(out / filename)
                if blend_mode >= 0:
                    filename = str(Path(filename).with_stem(Path(filename).stem + '_blend')).replace('\\', '/')
                    if out / filename not in WRITTEN_TEXTURES:
                        texture_page(vram, page, clut, True).save(out / filename)
                        WRITTEN_TEXTURES.add(out / filename)
                groups[group_key] = dict(texture=filename, blend_mode=blend_mode, visible=visible, vertices=[], colors=[], uv=[], primitive_flags=[], sort_centers=[])
                if textured:
                    groups[group_key]['motion'] = texture_motion(vram, page, clut, filename, out, animations, blend_mode >= 0)
            group = groups[group_key]
            center = [sum(points[index][axis] for index in indices) / count / 1000 for axis in range(3)]
            center[1], center[2] = -center[1], -center[2]
            # ground.c / farm_settle_on_ground: low header bits govern walkability.
            group['primitive_flags'].extend([header & 0xffff] * (1 if count == 3 else 2))
            for corner in ((0, 1, 2) if count == 3 else (0, 1, 2, 1, 3, 2)):
                x, y, z = points[indices[corner]]
                # PS1 camera looks along +Z with Y down. Godot uses -Z, Y up.
                # Flipping only Y mirrored the entire farm in the previous build.
                group['vertices'].extend((x / 1000, -y / 1000, -z / 1000))
                group['sort_centers'].extend(center)
                color = packet[ci + (corner * 4 if gouraud else 0):][:3]
                # PS1 textured color 128 is neutral; solid colors use the full 255 range.
                divisor = 128 if textured else 255
                group['colors'].extend(min(1, c / divisor) for c in color)
                if textured:
                    u, v = packet[4 + corner * 4:6 + corner * 4]
                    group['uv'].extend(((u + .5) / 256, (v + .5) / 256))
                else:
                    group['uv'].extend((0, 0))
            types[f'{key:04x}'] += 1
            pos += size
    return list(groups.values()), dict(objects=objects, primitives=sum(types.values()), modes=types, materials=len(groups))


def farm_mesh(data, vram, out, json_output=None):
    texture_names = {}
    animations = scene_motion(data)
    surfaces, report = model_mesh(data, vram, out, texture_names=texture_names, animations=animations)
    entries = []
    # FarmModeScript is 0xBDC bytes, ending with 15 FarmZoneModel records of 44 bytes.
    for index in range(15):
        record = 0xbdc - 15 * 44 + index * 44
        flags, name = struct.unpack_from('<II', data, record)
        # scene_populate_objects / scene_assign_slots hide absent and slot 1/2 entries.
        if flags & (0x8000 | 0x1000) or flags & 0x100 and flags & 15 in (1, 2):
            continue
        position = struct.unpack_from('<3h', data, record + 20)
        angle = struct.unpack_from('<3h', data, record + 28)
        parts, info = model_mesh(data, vram, out, 0x2000 + name, texture_names, animations)
        x, y, z = position
        entries.append(dict(index=index, flags=flags, source_position=position,
                            position=[x / 1000, -y / 1000, -z / 1000],
                            angle=[angle[0], -angle[1], -angle[2]], surfaces=parts))
    (json_output or out / 'farm.json').write_text(json.dumps(dict(surfaces=surfaces, entries=entries), separators=(',', ':')))
    report.update(scene_entries=len(entries), coordinate_conversion='(x, -y, -z) / 1000', texture_sources=texture_names)
    return report


def scene_exits(data, count):
    """farm_zone_find: skip dead, marker and event-only trigger zones; id is destination."""
    result = []
    for index in range(50):
        offset = 16 + index * 44
        flags, target = struct.unpack_from('<2H', data, offset)
        low = struct.unpack_from('<3h', data, offset + 14)
        high = struct.unpack_from('<3h', data, offset + 20)
        if flags & 0x6188 or target >= count or low[0] >= high[0] or low[2] >= high[2]:
            continue
        # Farm zones intentionally test X/Z only, including boxes with zero Y thickness.
        entry = struct.unpack_from('<3h', data, offset + 38)
        facing, event = struct.unpack_from('<2h', data, offset + 8)
        # player.c zone handling: HAS_EVENT bypasses FACING/action gating;
        # event 0x2f also bypasses the action button, but still checks facing.
        facing_gated = facing != 999 and flags & 0x1200 == 0x1000
        result.append(dict(index=index, target=target, facing=facing, event=event, source_flags=flags,
                           requires_facing=facing_gated,
                           requires_action=facing_gated and event != 0x2f,
                           min=[low[0] / 1000, -high[2] / 1000],
                           max=[high[0] / 1000, -low[2] / 1000],
                           entry=[entry[0] / 1000, -entry[1] / 1000, -entry[2] / 1000]))
    return result


def import_world(disc, offsets, out):
    count = (len(offsets) - 1) // 4
    # Follow the actual default spring exits, rather than importing seasonal duplicates.
    headers = [disc.asset(offsets[i * 4], 0xbdc) for i in range(count)]
    exits = [scene_exits(header, count) for header in headers]
    connected, pending = {0}, [0]
    while pending:
        for exit in exits[pending.pop()]:
            if exit['target'] not in connected:
                connected.add(exit['target'])
                pending.append(exit['target'])
    names = json.loads((ROOT / 'tools/location_names.json').read_text(encoding='utf-8'))
    intermediate = ROOT / 'tools/generated/locations'
    intermediate.mkdir(parents=True, exist_ok=True)
    (intermediate.parent / '.gdignore').write_text('')
    world, reports = {}, []
    for area in sorted(connected):
        start, texture, event = offsets[area * 4:area * 4 + 3]
        data = disc.asset(start, texture - start)
        slug = names[str(area)]['slug']
        directory = out / slug
        (directory / 'textures').mkdir(parents=True, exist_ok=True)
        vram, blocks = texture_bank(disc.asset(texture, event - texture))
        report = farm_mesh(data, vram, directory, intermediate / f'{slug}.json')
        report.update(area=area, texture_blocks=blocks)
        reports.append(report)
        value, location = struct.unpack_from('<2H', data)
        world[str(area)] = dict(id=area, slug=slug, name=names[str(area)]['name'],
                                place=value, location=location,
                                scene=f'res://game/locations/{slug}/{slug}.scn',
                                source_json=f'res://tools/generated/locations/{slug}.json',
                                texture_base=f'res://game/locations/{slug}/',
                                exits=exits[area], spawn=[0, 0.05, 0])
        print(f"AREA_EXTRACTED {area}: {report['objects']} objects, {len(exits[area])} exits", flush=True)
    # Entry coordinates are stored in the source exit, in the destination's coordinate system.
    for info in world.values():
        for exit in info['exits']:
            if exit['target'] != 0:
                world[str(exit['target'])]['spawn'] = exit['entry']
    assert all(str(exit['target']) in world for info in world.values() for exit in info['exits'])
    (ROOT / 'game/world/location_catalog.json').write_text(json.dumps(world, ensure_ascii=False, indent=2), encoding='utf-8')
    return reports


def compose_animations(data, bank_offset, range_ids, palette_rule=None, canvas_size=128):
    """Compose the original ANI parts with their original palette and frame timing."""
    assert struct.unpack_from('<I', data)[0] == 14
    images, lists, parts, ranges, frames = struct.unpack_from('<5I', data, 16)
    vram, blocks = texture_bank(data[bank_offset:])
    words = memoryview(vram).cast('H')
    rendered, animations, cache = [], [], {}
    for animation in range_ids:
        count, offset = struct.unpack_from('<hH', data, ranges + animation * 4)
        result = []
        for frame in range(count):
            list_id, fx, fy, duration, control = struct.unpack_from('<HhhBB', data, frames + offset + frame * 10)
            canvas = Image.new('RGBA', (canvas_size, canvas_size))
            if list_id <= 0xfffd:
                part_count, part_offset = struct.unpack_from('<hH', data, lists + list_id * 4)
                assert 0 <= part_count < 64
                for part in reversed(range(part_count)):
                    image_id, palette_id, dx, dy, attr, place = struct.unpack_from('<HHhhBB', data, parts + part_offset + part * 12)
                    if palette_rule is not None:
                        palette_id = palette_rule(animation, palette_id, place)
                    key = (image_id, palette_id, attr)
                    if key not in cache:
                        x, y, w, h = struct.unpack_from('<4h', data, images + image_id * 8)
                        cx, cy, _, _ = struct.unpack_from('<4h', data, images + palette_id * 8)
                        depth = attr >> 7
                        width = w * (2 if depth else 4)
                        assert width > 0 and h > 0
                        colors = []
                        for row in range(h):
                            for col in range(width):
                                packed = vram[((y + row) * 1024 + x) * 2 + col] if depth else vram[((y + row) * 1024 + x) * 2 + col // 2]
                                index = packed if depth else (packed >> ((col & 1) * 4)) & 15
                                colors.append(rgba(words[cy * 1024 + cx + index]))
                        image = Image.new('RGBA', (width, h))
                        image.putdata(colors)
                        if attr & 1:
                            image = image.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                        if attr & 2:
                            image = image.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
                        cache[key] = image
                    canvas.alpha_composite(cache[key], (canvas_size//2 + dx + fx, canvas_size//2+48 + dy + fy))
            bounds = canvas.getchannel('A').getbbox()
            result.append(dict(tile=len(rendered), duration=duration, control=control,
                               foot_y=bounds[3] if bounds else 112))
            rendered.append(canvas)
        animations.append(result)
    return rendered, animations, blocks


def player_sprites(data, out):
    rendered, animations, blocks = compose_animations(data, 0xbe08, range(15))
    atlas = Image.new('RGBA', (1024, ((len(rendered) + 7) // 8) * 128))
    for tile, image in enumerate(rendered):
        atlas.paste(image, (tile % 8 * 128, tile // 8 * 128))
    atlas.save(out / 'player_atlas.png')
    (out / 'player_animations.json').write_text(json.dumps(dict(cell=128, columns=8, origin=[64, 112], animations=animations)))
    return dict(ranges=len(animations), frames=len(rendered), texture_blocks=blocks)


def self_check():
    script = bytearray(0xbdc)
    for index in range(8):
        struct.pack_into('<H', script, 2216 + index * 18, 0xffff)
    struct.pack_into('<HhH6h', script, 2216, 0, 1, 8, 320, 44, 328, 44, 8, 31)
    assert scene_motion(script) == [dict(dest=[320, 44, 8, 31], source=[328, 44, 8, 31], timing=[0, 0, 0, 9])]
    struct.pack_into('<HhH6h', script, 2216, 0x8000, 2, 1, 0, 0, 300, 0, 1, 4)
    struct.pack_into('<HhH6h', script, 2234, 0x8000, 3, 0, 0, 0, 300, 4, 1, 4)
    frames = scene_motion(script)
    assert [entry['timing'] for entry in frames] == [[0, 2, 5, 0], [2, 5, 5, 0]]
    with TemporaryDirectory() as temporary:
        directory = Path(temporary)
        (directory / 'textures').mkdir()
        vram = bytearray(1024 * 512 * 2)
        struct.pack_into('<H', vram, 300 * 2, 0x1f)
        motion = texture_motion(vram, 0x100, 0, 'textures/check.png', directory, frames, False)
        assert motion['size'] == [1, 8] and Image.open(directory / motion['texture']).getpixel((0, 0)) == (255, 0, 0, 255)
    struct.pack_into('<H', script, 2, 0x2c)
    struct.pack_into('<H', script, 2216, 0x8001)
    struct.pack_into('<H', script, 2234, 0x8001)
    repeated = scene_motion(script)
    assert [entry['dest'][0] for entry in repeated] == [0, 8, 16, 0, 8, 16]
    zone_data = bytearray(0xbdc)
    for flags, event, facing, expected in [(0x9200, 28, 1, False), (0x9000, 37, 1, True), (0x9000, 47, 1, False), (0x9000, 37, 999, False)]:
        struct.pack_into('<2H', zone_data, 16, flags, 1)
        struct.pack_into('<2h', zone_data, 24, facing, event)
        struct.pack_into('<3h', zone_data, 30, -100, 0, -100)
        struct.pack_into('<3h', zone_data, 36, 100, 0, 100)
        assert scene_exits(zone_data, 2)[0]['requires_action'] == expected
    model = bytearray(12 + 28 + 24 + 32)
    struct.pack_into('<3I', model, 0, 0x41, 0, 1)
    struct.pack_into('<7I', model, 12, 28, 3, 0, 0, 52, 2, 0)
    for index, point in enumerate([(0, 0, 0), (100, 0, 0), (0, 0, 100)]):
        struct.pack_into('<3h', model, 40 + index * 8, *point)
    for index, flags in enumerate([0, 0x80]):
        struct.pack_into('<I3B x 3H 2x', model, 64 + index * 16, 0x21010000 | flags, 128, 128, 128, 0, 1, 2)
    surfaces, _ = model_mesh(model, bytearray(), ROOT, offset=0)
    assert surfaces[0]['primitive_flags'] == [0, 0x80]
    assert len(surfaces[0]['vertices']) == len(surfaces[0]['primitive_flags']) * 9
    # Only neutral additive black is invisible; preserve its geometry for collision.
    textured = bytearray(model[:64]) + bytearray(28)
    struct.pack_into('<7I', textured, 12, 28, 3, 0, 0, 52, 1, 0)
    struct.pack_into('<3H', textured, 84, 0, 1, 2)
    with TemporaryDirectory() as temporary:
        for index, (command, page, color, visible) in enumerate([
                (0x27010000, 0x20, 0, False), (0x27010000, 0, 0, True),
                (0x25010000, 0x20, 0, True), (0x27010000, 0x20, 128, True)]):
            directory = Path(temporary) / str(index)
            (directory / 'textures').mkdir(parents=True)
            struct.pack_into('<I', textured, 64, command)
            struct.pack_into('<H', textured, 74, page)
            textured[80:83] = bytes([color] * 3)
            result, _ = model_mesh(textured, bytearray(1024 * 512 * 2), directory, offset=0)
            assert result[0]['visible'] == visible
            assert result[0]['primitive_flags'] == [0] and len(result[0]['vertices']) == 9
            assert all(abs(actual - expected) < 1e-9 for actual, expected in zip(result[0]['sort_centers'], [1 / 30, 0, -1 / 30] * 3))
    assert expand_rle(b'\xfdABC\x03Z', 6) == b'ABCZZZ'
    assert expand_rle(b'\x00Q', 1) == b'Q'
    try:
        expand_rle(b'\xfcAB', 4)
    except AssertionError:
        pass
    else:
        raise AssertionError('Truncation not rejected')
    for flags in (4, 0, 8):
        pixels = bytes([1, 2, 3, 4, 5, 6, 7, 8])
        payload = pixels if flags == 4 else b'\xf8' + pixels
        pack = struct.pack('<BBH I4H', 13, 0, 1, len(payload) | flags << 24, 10, 20, 2, 2) + payload
        vram, count = texture_bank(pack)
        actual = vram[(20 * 1024 + 10) * 2:(20 * 1024 + 10) * 2 + 4] + vram[(21 * 1024 + 10) * 2:(21 * 1024 + 10) * 2 + 4]
        assert actual == (pixels if flags != 8 else bytes([1, 3, 5, 7, 2, 4, 6, 8]))
        assert count == 1
    assert rgba(0) == (0, 0, 0, 0) and rgba(0x7fff) == (255, 255, 255, 255)
    assert rgba(0, True)[3] == 0 and rgba(0x8000, True)[3] == 128 and rgba(0x7fff, True)[3] == 255
    print('RLE, raw/column image banks, palettes, source ground flags, primitive sort centers and neutral additive-black drawing checked')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('disc', nargs='?', type=Path)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    self_check()
    if args.check and not args.disc:
        return
    assert args.disc and args.disc.is_file(), 'Supply your USA .bin or .iso'
    disc = Disc(args.disc)
    table = (ROOT / 'reference/hmbtn-decomp/src/overlay/common/farm_section_table.h').read_text()
    offsets = [int(v, 16) for v in re.findall(r'0x[0-9a-fA-F]+', table.split('= {', 1)[1])]
    out = ROOT / 'game/locations'
    areas = import_world(disc, offsets, out)
    report = dict(areas=areas, area_count=len(areas))
    player = disc.asset(0x2a800, 0x49000)
    report['player'] = player_sprites(player, ROOT / 'game/player')
    report.update(source='https://github.com/coalslav/hmbtn-decomp',
                  disc_sha256=hashlib.file_digest(open(args.disc, 'rb'), 'sha256').hexdigest(),
                  note='Default spring areas connected by source exits. Original assets extracted locally. Native Godot runtime does not read the disc.')
    (ROOT / 'tools/generated/source_manifest.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

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

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


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


def rgba(word):
    return tuple(((word >> shift) & 31) * 255 // 31 for shift in (0, 5, 10)) + (0 if word == 0 else 255,)


def texture_page(vram, page, clut):
    x, y, depth = (page & 15) * 64, ((page >> 4) & 1) * 256, (page >> 7) & 3
    assert depth < 3, 'Reserved PS1 texture depth'
    words = memoryview(vram).cast('H')
    cx, cy = (clut & 63) * 16, (clut >> 6) & 511
    colors = []
    for v in range(256):
        for u in range(256):
            word = words[((y + v) & 511) * 1024 + ((x + (u >> (2 - depth))) & 1023)]
            if depth == 0:
                word = words[(cy * 1024 + cx + ((word >> ((u & 3) * 4)) & 15)) % len(words)]
            elif depth == 1:
                word = words[(cy * 1024 + cx + ((word >> ((u & 1) * 8)) & 255)) % len(words)]
            colors.append(rgba(word))
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


def farm_mesh(data, vram, out):
    assert struct.unpack_from('<I', data, 0x2000)[0] == 0x42
    base = 0x200c
    objects = struct.unpack_from('<I', data, 0x2008)[0]
    groups, types = {}, Counter()
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
            if name not in groups:
                filename = f'textures/{name}.png' if textured else ''
                if textured:
                    texture_page(vram, page, clut).save(out / filename)
                groups[name] = dict(texture=filename, vertices=[], colors=[], uv=[])
            group = groups[name]
            for corner in ((0, 1, 2) if count == 3 else (0, 1, 2, 1, 3, 2)):
                x, y, z = points[indices[corner]]
                group['vertices'].extend((x / 1000, -y / 1000, z / 1000))
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
    (out / 'farm.json').write_text(json.dumps(dict(surfaces=list(groups.values())), separators=(',', ':')))
    return dict(objects=objects, primitives=sum(types.values()), modes=types, materials=len(groups))


def player_sprites(data, out):
    """Compose the original ANI parts with their original palette and frame timing."""
    assert struct.unpack_from('<I', data)[0] == 14
    images, lists, parts, ranges, frames = struct.unpack_from('<5I', data, 16)
    vram, blocks = texture_bank(data[0xbe08:])
    words = memoryview(vram).cast('H')
    rendered, animations, cache = [], [], {}
    # First 15 source ranges cover idle, walking, running and common movement poses.
    for animation in range(15):
        count, offset = struct.unpack_from('<hH', data, ranges + animation * 4)
        result = []
        for frame in range(count):
            list_id, fx, fy, duration, control = struct.unpack_from('<HhhBB', data, frames + offset + frame * 10)
            canvas = Image.new('RGBA', (128, 128))
            if list_id <= 0xfffd:
                part_count, part_offset = struct.unpack_from('<hH', data, lists + list_id * 4)
                assert 0 <= part_count < 64
                for part in reversed(range(part_count)):
                    image_id, palette_id, dx, dy, attr, place = struct.unpack_from('<HHhhBB', data, parts + part_offset + part * 12)
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
                    canvas.alpha_composite(cache[key], (64 + dx + fx, 112 + dy + fy))
            result.append(dict(tile=len(rendered), duration=duration, control=control))
            rendered.append(canvas)
        animations.append(result)
    atlas = Image.new('RGBA', (1024, ((len(rendered) + 7) // 8) * 128))
    for tile, image in enumerate(rendered):
        atlas.paste(image, (tile % 8 * 128, tile // 8 * 128))
    atlas.save(out / 'player.png')
    (out / 'player.json').write_text(json.dumps(dict(cell=128, columns=8, origin=[64, 112], animations=animations)))
    return dict(ranges=len(animations), frames=len(rendered), texture_blocks=blocks)


def self_check():
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
    print('RLE, raw/column image banks and palette checks passed')


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
    start, texture, event = offsets[:3]
    out = ROOT / 'assets/original'
    (out / 'textures').mkdir(parents=True, exist_ok=True)
    bank, count = texture_bank(disc.asset(texture, event - texture))
    report = farm_mesh(disc.asset(start, texture - start), bank, out)
    player = disc.asset(0x2a800, 0x49000)
    report['player'] = player_sprites(player, out)
    report.update(texture_blocks=count, source='https://github.com/coalslav/hmbtn-decomp',
                  disc_sha256=hashlib.file_digest(open(args.disc, 'rb'), 'sha256').hexdigest(),
                  note='Farm section 0. Original assets extracted locally. Native Godot runtime does not read the disc.')
    (out / 'manifest.json').write_text(json.dumps(report, indent=2))
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()

"""Extract original item effects, supermarket display sprites and SPU sounds offline."""
import argparse
import json
import re
import struct
import wave
from pathlib import Path

from PIL import Image

from import_disc import Disc, ROOT, compose_animations

FARM = ROOT / 'reference/hmbtn-decomp/src/overlay/11_GF_FARM'
SOUNDS = {
    'confirm': 0, 'cancel': 1, 'refuse': 2, 'menu': 3, 'cursor': 5,
    'jump': 6, 'show_item': 7, 'stow': 8, 'put_down': 9, 'step': 0x48,
    'sow': 14, 'ship': 19, 'refill': 21, 'door': 76,
    **{f'tool_{tool}_{grade}': base + grade for tool, base in
       [('sickle', 29), ('hoe', 34), ('axe', 39), ('hammer', 44), ('water', 49)]
       for grade in range(5)},
}


def draw_frames(disc, pack_id, slot, ranges):
    data = (FARM / 'farm_data.c').read_text()
    start = (FARM / 'farm_load.c').read_text().split('farm_item_file_offsets[11] = {', 1)[1].split('}', 1)[0]
    packs = [int(x, 16) for x in re.findall(r'0x[0-9a-fA-F]+', start)]
    toc = re.search(rf'farm_item_toc_{pack_id} = \{{\d+, \{{(.*?)\}}\}};', data, re.S)[1]
    offsets = [int(x) for x in re.findall(r'\d+', toc)]
    pack = disc.asset(packs[pack_id], packs[pack_id + 1] - packs[pack_id])
    return compose_animations(pack[offsets[slot]:], offsets[-1] - offsets[slot], ranges)[0]


def atlas(destination, groups):
    frames = [frame for group in groups.values() for frame in group]
    image = Image.new('RGBA', (1024, ((len(frames) + 7) // 8) * 128))
    for index, frame in enumerate(frames):
        image.paste(frame, (index % 8 * 128, index // 8 * 128))
    image.save(destination.with_suffix('.png'))
    offset = 0
    result = {}
    for name, group in groups.items():
        result[name] = [offset, len(group)]
        offset += len(group)
    return result


def sound_data(disc, effect):
    sound = (ROOT / 'reference/hmbtn-decomp/src/main/sound/sound.c').read_text()
    definitions = sound.split('sound_defs[78] = {', 1)[1].split('};', 1)[0]
    bank, _, program, tone, note, fine, volume = [
        int(x) for x in re.findall(r'\d+', re.findall(r'\{([^{}]+)\}', definitions)[effect])]
    header_start, sample_start = [(0, 4096), (24576, 34816), (251904, 258048)][bank]
    archive = disc.archive_toc[9]
    header = disc.asset(archive + header_start, sample_start - header_start)
    assert header[:4] == b'pBAV'
    programs = struct.unpack_from('<H', header, 18)[0]
    # The VAB tone block is compact. A populated program's index is its rank.
    rank = sum(header[32 + index * 16] > 0 for index in range(program))
    tone_offset = 32 + 128 * 16 + (rank * 16 + tone) * 32
    center, shift = struct.unpack_from('<2B', header, tone_offset + 4)
    sample = struct.unpack_from('<H', header, tone_offset + 22)[0]
    sizes = struct.unpack_from('<256H', header, 32 + 128 * 16 + programs * 512)
    assert 0 < sample < len(sizes) and sizes[sample] > 0
    encoded = disc.asset(archive + sample_start + 8 * sum(sizes[:sample]), sizes[sample] * 8)
    rate = round(44100 * 2 ** ((note - center + (fine - shift) / 128) / 12))
    return encoded, rate, volume


def decode_adpcm(data, volume):
    filters = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]
    previous = older = 0
    pcm = bytearray()
    for offset in range(0, len(data) - 15, 16):
        control, flags = data[offset:offset + 2]
        shift = control & 15
        a, b = filters[control >> 4]
        for pair in data[offset + 2:offset + 16]:
            for nibble in (pair & 15, pair >> 4):
                signed = (nibble ^ 8) - 8
                value = (signed << 12 >> shift) + ((a * previous + b * older + 32) >> 6)
                value = max(-32768, min(32767, value))
                pcm.extend(struct.pack('<h', value * volume // 127))
                older, previous = previous, value
        if flags & 1:
            break
    return pcm


def main(path):
    disc = Disc(path)
    effects = ROOT / 'game/items/debris_effects'
    frames = {}
    for season in range(4):
        for item, slot in [(58, 0), (62, 4), (64, 6)]:
            if item == 64 and season == 3:
                continue  # The source removes weeds in winter; art slot 6 is reused.
            action = 3 if item == 64 and season == 2 else 1
            frames[f'{item}_{season}'] = draw_frames(disc, season, slot, [action])
            assert frames[f'{item}_{season}']
    effects.with_suffix('.json').write_text(json.dumps(atlas(effects, frames)) + '\n')

    display = ROOT / 'game/locations/supermarket/merchandise'
    groups = {str(i): draw_frames(disc, 8, i, [0])[:1] for i in [7,8,9,10,12,13,14,15,16,17,24,25,26,27]}
    art = atlas(display, groups)
    tables = (ROOT / 'reference/hmbtn-decomp/src/main/game/farm_tables.c').read_text()
    # Keys are the actual purchase item IDs, or the seasonal seed choices on each stand.
    shelves = {
        112: [15, 34,35,36,54], 113: [16, 39,40,41,54], 114: [17, 44,45,46,54],
        115: [8, 109,110], 116: [27, 33], 117: [24, 100], 118: [10], 119: [7, 132],
        120: [12, 165], 121: [13, 166], 122: [14, 167], 123: [26, 153], 124: [25, 154],
    }
    rows = []
    for index, (sprite, *items) in shelves.items():
        raw = re.search(rf'/\* {index} \*/ \{{30, [^\n]+?\{{([^}}]+)\}}', tables)[1]
        x, y, z, _ = map(int, raw.split(','))
        rows.append(dict(position=[x/1000, -y/1000, -z/1000], tile=art[str(sprite)][0], items=items))
    display.with_suffix('.json').write_text(json.dumps(rows, indent=2) + '\n')

    sounds = ROOT / 'game/audio'
    sounds.mkdir(exist_ok=True)
    for name, effect in SOUNDS.items():
        data, rate, volume = sound_data(disc, effect)
        pcm = decode_adpcm(data, volume)
        assert any(pcm), name
        with wave.open(str(sounds / f'{name}.wav'), 'wb') as output:
            output.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
            output.writeframes(pcm)
    print(f'INTERACTION_ASSETS_OK: {sum(map(len, frames.values()))} effect frames, {len(rows)} shelf positions, {len(SOUNDS)} sound cues')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('disc', type=Path)
    main(parser.parse_args().disc)

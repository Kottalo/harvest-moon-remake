"""Consolidate identical PNGs with compatible import profiles, offline only."""
import argparse
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / 'tools/texture_dedup_manifest.json'

def read_manifest():
    return json.loads(MANIFEST.read_text(encoding='utf-8')) if MANIFEST.exists() else {'aliases': {}, 'motion': {}}

def canonical_path(path):
    """Resolve a source path for import/check tools, without any runtime loader."""
    path = Path(path)
    relative = 'res://' + path.resolve().relative_to(ROOT).as_posix()
    return ROOT / read_manifest()['aliases'].get(relative, relative)[6:]

def pixels(path):
    with Image.open(path) as image:
        rgba = image.convert('RGBA')
        return [*rgba.size, hashlib.sha256(rgba.tobytes()).hexdigest()]

def profile(path):
    sidecar = Path(str(path)+'.import')
    return sidecar.read_text(encoding='utf-8').split('[params]', 1)[1].strip() if sidecar.exists() else None

def plan():
    groups = defaultdict(list)
    for base in ['game', 'assets']:
        for path in sorted((ROOT/base).rglob('*.png')):
            groups[tuple(pixels(path))].append(path)
    aliases, hashes, motion, retained = {}, {}, {}, []
    for group in groups.values():
        if len(group)<2: continue
        profiles = {profile(path) for path in group}
        if None in profiles or len(profiles)!=1:
            retained.append([path.relative_to(ROOT).as_posix() for path in group])
            continue
        group.sort(key=lambda path: (not path.is_relative_to(ROOT/'game'), path.as_posix()))
        target = 'res://'+group[0].relative_to(ROOT).as_posix()
        hashes[target] = pixels(group[0])
        for duplicate in group[1:]:
            aliases['res://'+duplicate.relative_to(ROOT).as_posix()] = target
        if group[0].stem.endswith('_motion'):
            for path in group: motion[path.stem] = target
    scenes = []
    for base in ['game', 'scenes']:
        for path in sorted((ROOT/base).rglob('*.scn')):
            if not path.name.endswith('.texture_tmp.scn'):
                scenes.append('res://'+path.relative_to(ROOT).as_posix())
    data = dict(aliases=aliases, pixels=hashes, motion=motion, scenes=scenes, retained_import_variants=retained)
    MANIFEST.write_text(json.dumps(data, indent=2)+'\n', encoding='utf-8')
    print(f'TEXTURE_PLAN_OK: {len(aliases)} duplicates, {len(scenes)} native scenes, {len(retained)} distinct import-profile pairs')

def apply_text():
    data = read_manifest()
    # JSON catalogs use native canonical paths; generated source provenance stays untouched.
    for base in ['game', 'assets', 'scenes', 'scripts']:
        for path in (ROOT/base).rglob('*'):
            if path.suffix not in {'.json', '.tscn', '.tres', '.gd'}: continue
            text = path.read_text(encoding='utf-8')
            updated = text
            for old, new in data['aliases'].items(): updated = updated.replace(old, new)
            if text!=updated: path.write_text(updated, encoding='utf-8')
    # These atlases previously used uncompressed embedded ImageTextures. Keep that
    # pixel format when sharing their existing imported Texture2D across scenes.
    for target in set(data['motion'].values()):
        sidecar = ROOT/(target[6:]+'.import')
        text = sidecar.read_text(encoding='utf-8')
        assert 'compress/mode=0' in text and 'mipmaps/generate=false' in text, target
        text = text.replace('detect_3d/compress_to=1','detect_3d/compress_to=0')
        sidecar.write_text(text.replace('process/fix_alpha_border=true','process/fix_alpha_border=false'), encoding='utf-8')

def finish():
    data = read_manifest()
    # Never delete a source until every native/text owner has been redirected.
    for base in ['game', 'assets', 'scenes', 'scripts']:
        for path in (ROOT/base).rglob('*'):
            if path.suffix not in {'.scn', '.json', '.tscn', '.tres', '.gd'}: continue
            content = path.read_bytes()
            assert not any(old.encode() in content for old in data['aliases']), f'Stale texture owner: {path}'
    for old, new in data['aliases'].items():
        source, target = ROOT/old[6:], ROOT/new[6:]
        assert pixels(target)==data['pixels'][new], target
        if source.exists():
            assert pixels(source)==pixels(target), source
            if profile(source) is not None:
                a, b = profile(source), profile(target)
                if source.stem in data['motion']:
                    a, b = (s.replace('detect_3d/compress_to=1','detect_3d/compress_to=0').replace('process/fix_alpha_border=true','process/fix_alpha_border=false') for s in [a,b])
                assert a==b, f'Import profiles diverged: {source}'
    # Validate the entire set before removing any alias, so a later mismatch
    # cannot leave a partly consolidated asset tree.
    for old in data['aliases']:
        source = ROOT/old[6:]
        for removed in [source, Path(str(source)+'.import')]:
            assert removed.resolve().is_relative_to(ROOT)
            removed.unlink(missing_ok=True)
    check()

def check():
    data = read_manifest()
    for target, expected in data['pixels'].items(): assert pixels(ROOT/target[6:])==expected, target
    for old in data['aliases']:
        assert not (ROOT/old[6:]).exists() and not (ROOT/(old[6:]+'.import')).exists(), old
    seen = {}
    for base in ['game', 'assets']:
        for path in (ROOT/base).rglob('*.png'):
            key = (tuple(pixels(path)), profile(path))
            assert key not in seen, f'Compatible duplicate remains: {seen.get(key)} / {path}'
            seen[key] = path
    print(f'TEXTURE_DEDUP_OK: {len(data["aliases"])} duplicate PNG/import pairs share canonical resources; pixels retained; distinct import profiles preserved')

if __name__=='__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['plan','prepare','finish','apply','check'])
    mode = parser.parse_args().mode
    if mode=='plan': plan()
    elif mode=='prepare': apply_text()
    elif mode=='finish': finish()
    elif mode=='apply': apply_text(); finish()
    else: check()

"""Enforce directory ownership and semantic names without a framework."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
world = json.loads((ROOT / 'game/world/location_catalog.json').read_text(encoding='utf-8'))
slugs = {info['slug'] for info in world.values()}
assert len(slugs) == len(world), 'Location folders must have unique semantic names'
for info in world.values():
    slug = info['slug']
    assert re.fullmatch(r'[a-z][a-z0-9_]*', slug), slug
    assert not re.fullmatch(r'area_?\d+', slug), 'Raw area ids are provenance, not directory names'
    assert info['scene'] == f'res://game/locations/{slug}/{slug}.scn'
    assert (ROOT / info['scene'][6:]).is_file(), info['scene']
    for path in (ROOT / 'game/locations' / slug / 'textures').glob('*.png'):
        assert path.stem.startswith(slug + '_atlas_'), path
    assert all(str(exit['target']) in world for exit in info['exits']), slug
for path in (ROOT / 'game').rglob('*'):
    if not path.is_file():
        continue
    relative = path.relative_to(ROOT / 'game')
    assert relative.parts[0] in {'player', 'camera', 'world', 'locations'}, relative
    assert path.suffix.lower() not in {'.bin', '.cue', '.iso', '.py'}, relative
    if path.suffix not in {'.gd', '.tscn'}:
        continue
    text = path.read_text(encoding='utf-8')
    assert 'res://tools/' not in text and 'res://reference/' not in text, relative
    for ref in re.findall(r'res://[^"\s]+', text):
        assert (ROOT / ref[6:]).is_file(), (relative, ref)
    if relative.parts[0] in {'player', 'camera'}:
        assert 'res://game/world/' not in text and 'res://game/locations/' not in text, relative
assert (ROOT / 'tools/generated/.gdignore').is_file()
print(f'STRUCTURE_CHECK_OK: {len(world)} named location folders; player/camera/world boundaries and resource references valid')

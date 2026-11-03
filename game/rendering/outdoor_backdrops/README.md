# Outdoor visual continuation

The user explicitly chose fixed camera zoom plus new background continuity on 2026-11-03.
Fourteen named materials cover fifteen outdoor areas; town square and beach share `coast`.
Indoor maps never enable this background.

`outdoor_backdrop.gd` keeps one opaque camera-space quad behind the native scene,
with two pixels of overscan for viewport/MSAA edges. It has no collision, navigation,
walkability or query geometry. Camera limits use only the original Location, so the
background cannot change framing, exits or gameplay proportions. `stretch/aspect=expand`
removes fixed-aspect window bars. The ordinary day/night canvas tint affects both.

The shader continues the nearest original map patch in the original camera plane.
Its UV transform, bounded mirrored tile and vertex tint come from native source
triangles. Four adjacent field samples blend continuously; atlas addressing never
crosses into unrelated packed pictures. Transparent foliage pixels reveal sampled
continuation rather than the clear colour. Far background can visibly repeat source
detail: this is procedural scenery continuation, not newly authored buildings or terrain.
The original map, assets, water shader and physical world remain authoritative.

Each map uses four 64x64 RGBAF lookup textures (256 KiB uploaded), references existing
packed atlases and adds one opaque draw. It does no nearest-triangle search per frame.
The compressed binary `.res` fields belong in Git LFS. They are shader data, not new
pictures to send through the image texture packer.

Offline regeneration, with local Python/NumPy and portable Godot:

```
python tools/build_outdoor_backdrops.py
python tools/build_outdoor_backdrops.py --check
godot --headless --path . --script tools/verify_outdoor_backdrop.gd
```

The exporter reads native scenes (including clipped coast and expanded summit
backdrops), never the ROM. Temporary geometry/float fields remain behind
`tools/generated/.gdignore`; runtime only loads this named material catalogue.
Regenerate after changing native map geometry/UVs/atlas bindings. `--gpu` on the
verifier additionally performs rendered-pixel checks in an isolated GPU process.
Do not call force_draw/editor test callbacks or disturb the user's running game.

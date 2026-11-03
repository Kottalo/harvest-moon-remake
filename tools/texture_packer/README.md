# Free Texture Packer pipeline

Free Texture Packer CLI 0.3.0 is pinned in package.json/package-lock.json.
Install its offline build dependency with `npm ci` in this directory.
Node.js, Python with Pillow and Godot are build tools, not runtime dependencies.

- `source/`: original PNGs, original import profiles and ANI frame tables, tracked in Git/LFS.
- `frames/`: generated, separate PNG inputs. Examples: `player/normal/tile_000.png` and
  `player/actions/base/range_000/frame_000.png`. Not tracked; regenerate from source/.
- `projects/`: generated .ftpp projects passed to the actual CLI. Not tracked.
- `atlas_manifest.json`: source hashes, packing rectangles and native resource mapping.

This entire directory has `.gdignore`. Source pictures, separate frames, npm modules and
packer metadata are never imported or exported by Godot. Runtime atlases and native
AtlasTexture .tres resources live beside their owning game/location assets.

From the project root:

1. `python tools/pack_textures.py build` cuts the original ANI sheets into frames and
   invokes the CLI, generating atlases, frame catalogues and AtlasTexture resources.
2. Refresh assets through the running editor's Godot AI filesystem scan. If no editor
   is open, `godot --headless --editor --import --quit` can import them.
3. `godot --headless --script tools/pack_native_textures.gd` updates native scene bindings.
4. `godot --headless --script tools/verify_atlases.gd` verifies all native scenes.
5. `python tools/pack_textures.py finish` verifies pixels/frame tables and removes old
   imported standalone PNGs. Originals remain in source/.

`Import-Assets.ps1` includes these stages when extracting the original disc again.
Repacking from source/ does not require a ROM. `build` regenerates frames/; source/
holds the recoverable source material. No TinyPNG or other image-upload service is used.

Packing uses the CLI's MaxRectsPacker/Smart layout, 2048 maximum pages, no resizing, rotation or automatic trimming, plus
4-pixel padding and extrusion. Compatible import profiles remain grouped separately;
raw motion buffers stay uncompressed without mipmaps or alpha-border processing.
Map texture pages and VRAM-copy buffers keep their internal layout; source UVs and
animation records are preserved through explicit shader atlas regions.

Action crops retain each original 256-pixel canvas margin and timing. Equal crop
pixels may share a rectangle while keeping different margins; the runtime frame cache
therefore includes the margin in its key. Normal frames retain their 128-pixel canvas.

Checks: `pack_textures.py check`, `pack_textures.py check-imports` (fresh imported-cache hashes), `verify_atlases.gd`, `verify_packed_frames.gd`, existing
runtime/actions/grounding/hoe/mine/tool-switch checks. No GPU screenshot acceptance is
claimed for this migration; see CHECKPOINT.md for the editor recovery incident.

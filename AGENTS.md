# Project instructions

## Directory contract

- `game/player/`: player scene, input, movement, ANI playback and shared player assets only. No world/map loading dependencies.
- `game/camera/`: camera projection and follow/overview behavior only. Preserve the original yaw/FOV; the user requested two successive 20% distance increases on 2026-10-28 (distance scale 1.44).
- `game/world/`: world entry scene, location catalog, navigation/exits and simple navigation prompts. Do not put player animation, camera math, shops, crops or NPC behavior here.
- `game/locations/<semantic_name>/`: one original place per folder, its native scene and texture atlases. Use names such as `farmhouse`, `library`, `clinic`; raw source area numbers belong in metadata, never the primary directory name.
- `tools/`: offline conversion and runnable checks. `tools/generated/` contains ignored, regenerable conversion intermediates, not runtime code.
- `reference/` is read-only source reference; `addons/` is third-party code; `verification/` is evidence, not gameplay.
- The old `scenes/farm.tscn`, `scenes/original_farm.scn`, `scripts/farm.gd` and farm texture aliases are retained for the user's existing editor tabs. The old script only redirects to `game/world/world.tscn`. Add no new logic to these compatibility paths. Do not rename/close the user's open scene tabs as part of cleanup.
- Use snake_case filenames/folders and PascalCase Godot nodes. Place assets beside the location/player that owns them; do not create generic `misc`, `utils` or `manager` dumps.
- After moving/adding runtime files run `python tools/check_structure.py` as well as the relevant runtime checks. Update this contract when a real new subsystem is added.
- Keep the editor open while working. Use godot-ai MCP asset scans for new files; do not launch a second headless editor against the same project's editor layout while the user is using it.

- This is a native Godot remake in progress, not the existing PS1 recomp build. Keep the sibling `Source` and `Game` projects intact unless the user requests changes there.
- Use the user's `coalslav/hmbtn-decomp` checkout in `reference/hmbtn-decomp` as the primary behavioral/format reference. Read PORTING.md for the verified formats and current scope. Do not claim the whole game is ported.
- Use godot-ai MCP for live editor state, project runs, input, screenshots and error inspection. Select the session whose project path is this directory. Plugin/server are both 4.3.1. Authentication uses `godot-ai attach` over stdio; do not replace it with an unauthenticated HTTP URL. Limit screenshots to longest edge 800 to stay under the transport event budget.
- Runtime assets are native `.scn`, PNG and JSON. Disc reads belong only in the offline importer. Never add a ROM reader, PS1 interpreter or recomp dependency to the Godot runtime.
- Preserve the corrected coordinate transform `(x,-y,-z)/1000`. Up/Down/Left/Right must project NE/SW/NW/SE with exactly four directions. Default camera uses the original H=1000 on 320x240 perspective (vertical FOV ~13.68555 degrees); orthographic overview is only a debug view. Do not reintroduce screen-axis movement or an estimated camera zoom. Bake all visible FarmZoneModel records at their source positions.
- Godot 4.7.2 portable executables are at `../Tools/Godot`; use the compatibility renderer on this machine.
- For runtime/physics changes, run `--headless --path . --script tools/verify_runtime.gd`. For importer changes, run its `--check`, re-extract, bake and run the native check using Import-Assets.ps1. Do not repeat conversion when only runtime code changed.
- The user authorized a private GitHub checkpoint with project assets stored in Git LFS. Keep it private; never upload the disc/ROM or make game assets public.
- The user requests every completed update be committed and pushed after verification. Check that local LFS assets are hydrated; a clean Git status alone is insufficient.

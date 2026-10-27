# Project instructions

- This is a native Godot remake in progress, not the existing PS1 recomp build. Keep the sibling `Source` and `Game` projects intact unless the user requests changes there.
- Use the user's `coalslav/hmbtn-decomp` checkout in `reference/hmbtn-decomp` as the primary behavioral/format reference. Read PORTING.md for the verified formats and current scope. Do not claim the whole game is ported.
- Use godot-ai MCP for live editor state, project runs, input, screenshots and error inspection. Select the session whose project path is this directory. Plugin/server are both 4.3.1. Authentication uses `godot-ai attach` over stdio; do not replace it with an unauthenticated HTTP URL. Limit screenshots to longest edge 800 to stay under the transport event budget.
- Runtime assets are native `.scn`, PNG and JSON. Disc reads belong only in the offline importer. Never add a ROM reader, PS1 interpreter or recomp dependency to the Godot runtime.
- Preserve the corrected coordinate transform `(x,-y,-z)/1000`. Up/Down/Left/Right must project NE/SW/NW/SE with exactly four directions. Default camera uses the original H=1000 on 320x240 perspective (vertical FOV ~13.68555 degrees); orthographic overview is only a debug view. Do not reintroduce screen-axis movement or an estimated camera zoom. Bake all visible FarmZoneModel records at their source positions.
- Godot 4.7.2 portable executables are at `../Tools/Godot`; use the compatibility renderer on this machine.
- For runtime/physics changes, run `--headless --path . --script tools/verify_runtime.gd`. For importer changes, run its `--check`, re-extract, bake and run the native check using Import-Assets.ps1. Do not repeat conversion when only runtime code changed.
- Extracted assets stay local; do not publish the user's disc or game assets.

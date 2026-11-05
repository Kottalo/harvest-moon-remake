# Verification and editor workflow

## Headless checks

```powershell
python tools/check.py --list
python tools/check.py
python tools/check.py smoke world npc
```

The default runs structure, LFS hydration and one runtime smoke test. Named groups select existing scripts, run sequentially, and report completion markers and durations. Add `--godot <path>` if the portable engine is elsewhere, and point to the engine executable itself on Windows so a timeout can stop the exact test process. The 120 Hz cases use matching fixed frame timing. `--timeout <seconds>` bounds each check.

If the Windows `python` alias points to the Store, use the installed Python executable. On this workstation the Codex runtime has one at `$env:USERPROFILE/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe`.

Run `python tools/test_check.py` after editing the runner or structure checker. The grouped checks cover runtime behavior. Shader output, asset provenance and live frame pacing have their own checks in the scoped rules.

## Project constraints

- Do not call RenderingServer.force_draw from editor test callbacks or force asynchronous GPU checks through synchronous MCP test methods: a trial hung the editor and required user-approved recovery. The failed temporary GPU test/runner were removed. Do not repeat it, stop the editor without approval, or claim GPU acceptance from headless tests. Use ordinary isolated-process GPU checks when the platform supports them; preserve the user's editor/game/focus.
- Use snake_case filenames/folders and PascalCase Godot nodes. Place assets beside the location/player that owns them; do not create generic `misc`, `utils` or `manager` dumps.
- After moving/adding runtime files run `python tools/check_structure.py` as well as the relevant runtime checks. Update this contract when a real new subsystem is added.
- Action checks are `tools/verify_actions.gd` and `tools/import_player_actions.py --check`. GPU action/alignment/transition checks run through `tools/run_render_check.py --log <absolute-path>`: its Godot process belongs to an isolated Windows desktop that is never switched to, so it cannot steal the user's focus. Use the Godot AI MCP for editor scans/state while keeping the user's game untouched.
- Keep the editor open while working. Use godot-ai MCP asset scans for new files; do not launch a second headless editor against the same project's editor layout while the user is using it.
- This is a native Godot remake in progress, not the existing PS1 recomp build. Keep the sibling `Source` and `Game` projects intact unless the user requests changes there.
- Use the user's `coalslav/hmbtn-decomp` checkout in `reference/hmbtn-decomp` as the primary behavioral/format reference. Read PORTING.md for the verified formats and current scope. Do not claim the whole game is ported.
- For live editor state, use the matching Godot AI MCP session over authenticated `godot-ai attach` stdio. Keep the server version aligned with the installed addon version in `addons/godot_ai/plugin.cfg`. Use `Open-Editor.cmd` for the installed local Python override when available. Limit MCP screenshots to an 800 px longest edge.
- Godot 4.7.2 portable executables are at `../Tools/Godot`; use the compatibility renderer on this machine.
- For runtime/physics changes, run `--headless --path . --script tools/verify_runtime.gd`. For importer changes, run its `--check`, re-extract, bake and run the native check using Import-Assets.ps1. Do not repeat conversion when only runtime code changed.
- The user authorized a private GitHub checkpoint with project assets stored in Git LFS. Keep it private; never upload the disc/ROM or make game assets public.
- The user requests every completed update be committed and pushed after verification. Check that local LFS assets are hydrated; a clean Git status alone is insufficient.
- Do not steal focus or inject input into the user's running game. Use background/headless checks and isolated offscreen review; do not launch, restart or foreground the game for testing while the user is working.

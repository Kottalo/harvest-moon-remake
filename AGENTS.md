# Project instructions

Harvest Moon BTN is a native Godot remake. Open `project.godot` through `Open-Editor.cmd`. The runtime entry is `game/world/world.tscn`. Use the original decompilation in `reference/hmbtn-decomp/` for source behavior and formats.

## Find the owner

Start in the named runtime folder. Read its linked rules for implementation and regression details before touching that subsystem. Read additional rows only when the change crosses those boundaries.

| Task | Runtime owner | Rules | Headless check group |
| --- | --- | --- | --- |
| Camera, framing, occlusion at map edges | `game/camera/` | [Camera](docs/engineering/camera.md) | `camera` |
| Input, player actions, motion, hops, shadows | `game/player/`, `game/characters/` | [Player](docs/engineering/player.md) | `player` |
| Soil, crops, mines, loose items and prefabs | `game/field/`, `game/items/` | [Field](docs/engineering/field.md) | `field` |
| Locations, doors, signs, transitions, world history | `game/world/`, `game/locations/` | [World](docs/engineering/world.md) | `world` |
| NPC schedules, pathfinding, personas and dialogue | `game/npc/` | [NPCs](docs/engineering/npc.md), [world history](docs/engineering/world.md) for journal changes | `npc` |
| Clock, bedtime and time debug panel | `game/time/` | [Time](docs/engineering/time.md) | `time` |
| Shaders, atlases and conversion | `game/rendering/`, `game/original_sprites/`, `tools/` | [Assets](docs/engineering/assets.md) | Use its importer and GPU checks |

Use `rg --files game/<owner>` to find runtime sources. Search top-level verification scripts in `tools/` with `rg --files tools -g 'verify_*.gd' -g '!tools/texture_packer/**'`. Use [PORTING.md](PORTING.md) and [CHECKPOINT.md](CHECKPOINT.md) when investigating prior changes or source provenance.

## Verify and deliver

- Reproduce bugs through the gameplay entry point and fix them in the owning module. Add a focused regression when the existing checks miss the failure.
- Use `python tools/check.py --list` to find the available groups. Run `python tools/check.py smoke <group>` for a runtime change. For example, `python tools/check.py smoke npc`. Every run checks the directory boundaries and Git LFS hydration first. For individual checks and render or importer work, follow the [verification workflow](docs/engineering/workflow.md) and the scoped rules.
- Use headless verification or the isolated GPU runner. Keep the live editor open and leave the user's game and input alone. Use the authenticated Godot AI MCP when a live editor operation is required.
- Keep generated files, ROMs and source tooling out of the runtime. Treat `reference/` as read-only and `addons/` as third-party. Keep the compatibility scene paths used by existing editor tabs.
- Commit verified changes and push them to the private GitHub repository. Stage only files belonging to the task.

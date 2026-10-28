# Checkpoint — 2026-10-28

Entry scene: `game/world/world.tscn`. Open `project.godot` in Godot 4.7.2 (compatibility renderer); local desktop launchers use the adjacent `../Tools/Godot` installation.

Implemented: 43 original spring locations, 94 source exits, ground collision, original four-direction input (up NE / down SW / left NW / right SE), original camera distances/projection, original player ANI idle/walk/run. Walk over road exits; press E or Enter at doors. Tab toggles a map overview.

Runtime ownership: `game/player` handles player input/movement/animation; `game/camera` handles projection/follow; `game/world` handles location transitions; `game/locations/<name>` owns each place's scene and named atlases. Offline conversion/checks live under `tools`. Source area ids remain in metadata, not folder names.

Checks passed after the split: `tools/check_structure.py`, `tools/import_disc.py --check`, `tools/verify_runtime.gd`, `tools/verify_world.gd`. All 43 entry floors and all 94 exits passed. Logs are in `verification/`.

Pending: NPCs, dialogues/events, shop hours/story access rules, crops/tools/inventory, animals, full saves/audio, alternate seasons and deeper mine generation. Current locations provide native geometry/navigation, not the full original game simulation.

The user's editor remains open; they are adjusting its orthographic viewing angle themselves. Do not close/restart the editor or change the approved runtime camera while continuing work. Use godot-ai MCP scans for assets.

The old `scenes/original_farm.scn` and farm texture aliases remain for existing editor tabs. `scripts/farm.gd` is only a compatibility redirect; new systems belong under `game/`. Binary assets use Git LFS. ROMs, tool caches, credentials, Godot binaries and generated conversion JSON are excluded. The source reference is pinned as a Git submodule.

The user authorized a private GitHub checkpoint including project assets. Keep the repository private and never upload ROM images. CodeGraph has not been configured; Ponytail and godot-ai MCP have been used.
# 2026-10-28 素材恢复与镜头更新

- LFS 历史迁移后本地残留了指针文本，导致编辑器贴图加载失败；已通过 `git lfs checkout` 恢复全部 1,525 个文件，并在运行中的编辑器重新导入 56 张旧贴图。
- `tools/check_structure.py` 现在拒绝未展开的 LFS 指针；已验证真实素材通过、指针样本失败。
- 按用户最新要求，在上次基础上再拉远 20%，游戏镜头距离为原版的 1.44 倍：水平 12.96、高差 6.48，保留原版 yaw/FOV 和四向移动。旧记录中的 9.0/4.5 是原版基准。
- 原生运行检查、旧农场场景和全部 55 张旧农场贴图加载检查均通过；验证日志见 `verification/lfs-camera-fix.txt`。
- 后续每次更新验证后提交并 push，仓库保持私有，二进制素材继续使用 LFS。


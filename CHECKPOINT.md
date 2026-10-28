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
- 人物缩放已改为固定世界尺寸，移除镜头的屏幕尺寸补偿；基准 pixel_size=0.009827848，来自原版相机到人物锚点的深度/1000。距离、FOV、正交视图下人物与场景保持相对比例，检查见 `verification/player-world-scale.txt`。

## 2026-10-28 楼梯与障碍碰撞

下方记录是第一版通用跨阶方案，已由本文件最后的原版地面/换层修正取代，不能作为完整上下楼成功的依据。

- 在 `game/player/player.gd` 增加受限跨阶：最大单级 0.12，抬升/前进全身扫掠、可落脚表面与头顶空间检查；从台阶真实表面取高度，避免胶囊圆角误判。人物和地图尺寸未改。
- `floor_snap_length=0.12`，下楼继续贴地。保留原生 `move_and_slide`，高障碍和薄墙继续阻挡。
- 验证镇南街区两处原始楼梯、医院和旅馆楼梯的步行/跑步上下行；60/120 Hz 下检测高障碍、薄墙和低天花板。日志：`verification/collision-60.txt`、`verification/collision-120.txt`。
- 移动、镜头、人物比例和全地图出入口回归记录：`verification/stairs-runtime.txt`、`verification/stairs-world.txt`。

## 2026-10-28 按原版修正楼梯与换层

- 直接核对 `ground.c:ground_primitive_under/ground_height_at`、`farm_probe.c:farm_settle_on_ground` 和 `player.c:player_update_position/player_slide_on_bump` 及区域切换分支。保留原面片 flags，原生场景分别烘焙 0xC080 地面和 0xE080 通行表面；显示模型中带 0x8000 的台阶装饰不再干扰原版隐藏斜坡。独立场景物件保留实体碰撞，地面边界阻止进入无效区域。
- 使用原版 200 单位高度容差；前探基准 48 单位并覆盖 Godot 胶囊半径；只检查实际抬升所需净空。地面射线在精确三角形接缝失效时，尝试 1 个原版单位的偏移以匹配原版整数边界判定。
- 修正旧提取器把 0x1000 一律译为按 E 的错误；加入 source_flags/event/requires_facing，按 0x1200 组合及 event 0x2f 判定自动/确认换层。剧情、营业时间等完整事件系统仍未移植。
- `verification/source-stair-transitions.txt` 记录使用物理方向键实际走过 16 条室内连接：13 自动、3 按确认。`source-collision-60.txt` / `source-collision-120.txt` 扩大到楼梯边线、接缝、旋转方向、医院/牧场隐藏斜坡、160 单位台阶、低净空、高障碍、薄墙、禁行表面与原版房间边界。
- 当前回归：`verification/source-ground-runtime.txt`、`verification/source-ground-world.txt`。运行时仍只读取 Godot 原生资源，不读取 ROM。

## 2026-10-28 立即下楼回归修复

- 已实际复现旧版失败：医院 188→192 后立即反向，0.6 秒全局冷却忽略了下楼触发区，人物进入楼梯洞却停在 192。旧实机测试等待了 45 个物理帧，漏掉此用法。
- 删除全局换图冷却；只对跨场景按住的确认键要求先释放，自动出口始终接受判定。审计全部 94 个原版到达坐标：没有坐标落在自动返回区内，仅一处落在需确认的返回区内。
- `verify_stair_transitions.gd` 现在每次换层后，从真实到达位置立刻按反方向返回，不等待、不传送、不修改过渡状态。16 条连接均通过立即返回测试；新测试在修复前首先复现牧场卧室下楼失败。
- 运行中物理方向键实测路线：188→192→188→192→188，折返等待 0 帧。证据：`verification/immediate-stair-live.json`、`verification/immediate-stair-returns.txt`。

## 2026-10-28 全部楼梯改为连续斜坡

- 按用户要求删除角色主动抬升、向上/前方跨阶扫掠等专门逻辑。角色 Y 只由 Godot 原生碰撞移动、重力和 floor snap 决定；地面查询只限制无效通行区域。
- 审计当前 43 个地点，为 17 个地点设置 19 段连续楼梯坡道和 1 处平整落脚平台，保留楼梯原始外观。原版分段隐藏坡面也合并为整片，包含室外镇南街区、广场、海滩、温泉及室内楼梯。各地点的 `walkable_ramps.json` 是定义，场景中的 `WalkableRamps/<语义名称>` 是原生碰撞资源。
- 烘焙器使用 Godot 几何裁切移除坡道范围内的旧台阶/坡面碰撞，保留周围平台；`tools/bake_assets.gd -- --check` 检查裁切面积，`-- --ramps-only` 只更新有坡道定义的地点。
- 覆盖与验证记录：`verification/ramp-coverage.json`、`all-ramps-60.txt`、`all-ramps-120.txt`、`all-ramps-transitions.txt`、`all-ramps-world.txt`。每段坡面均采样宽度和长度，保留立即折返、身体净空、高障碍及薄墙检查。


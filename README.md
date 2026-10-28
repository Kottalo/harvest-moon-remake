# Harvest Moon Remake

《牧场物语：回归自然》的 Godot 原生移植工程，当前 checkpoint 见 [CHECKPOINT.md](CHECKPOINT.md)。

现有 43 个原版春季地点、94 条原始连接，支持移动、跑步、碰撞、原版镜头和主角动画。海滩与广场的双向连接已无缝化，两侧模型常驻；其余 92 个分区出口沿用原版坐标，门口按 E 或 Enter 进出，Tab 查看当前地点全景。方向键：上东北、下西南、左西北、右东南。

这是场景与移动阶段的移植，NPC、对话、剧情、营业时间、种植、物品、动物、音频和完整存档尚未实现。

2026-10-28：按用户要求，游戏镜头连续两次拉远 20%，现为原版距离的 1.44 倍，保留原版观察角度与透视参数。

人物使用固定世界尺寸的 3D billboard，按原版镜头基准校准。镜头距离、FOV 或正交缩放变化时，人物与场景一起缩放，不再固定人物的屏幕像素大小。

所有可通行楼梯使用连续斜坡碰撞，外观仍是原版楼梯；角色通过 Godot 原生移动与贴地跟随坡面，不再主动跨级抬升。各地点的 `walkable_ramps.json` 定义坡道与平台，烘焙后位于场景的 `WalkableRamps` 节点下。换层遵循原版区域事件规则：自动入口直接走入，需要确认的入口按 E。坡道及障碍回归：`godot --headless --path . --script tools/verify_collision.gd`（追加 `-- --120hz` 验证 120 Hz）；完整上下楼流程检查为 `tools/verify_stair_transitions.gd`。

人物所有动画帧共用固定画布锚点，保留原版 ANI 的动作偏移；锚点跟随附近的可见路面高度，连续斜坡负责身体通行，避免坡面与原始台阶外观存在高度差时穿地。动画对位、路面高度与道路往返回归：`tools/verify_player_grounding.gd`。

角色整张精灵按脚底对应的位置判断遮挡，场景模型保留正常的 3D 深度和背面剔除，避免墙切开角色、台阶之间错误穿插。原始 STP 位区分透明、混合及不透明像素，瀑布和蒸汽使用对应的半透明混合；纯黑加法通行面只保留碰撞。场景和人物使用 Linear，抗锯齿为 4× MSAA。GPU 检查：在 Godot AI `game_eval` 中执行 `return await load("res://tools/verify_render_order.gd").new().run(get_tree().current_scene)`。

游戏渲染目标为 60 FPS，物理更新为 60 Hz；角色速度和动作时长仍按原版。水面/瀑布/蒸汽使用原始场景表和离线 motion atlas，通过 shader 平滑滚动、换帧交融及轻微 UV 波纹呈现动态，未变形模型。GPU 动画检查：`return await load("res://tools/verify_water.gd").new().run(get_tree().current_scene)`。室外地图延伸方案已按用户要求取消，保留原始边界。山顶仅扩大原有星空与远山背景，覆盖背景边缘，不改变可行走地形。

海滩与广场通行回归：`godot --headless --path . --script tools/verify_coast.gd`（追加 `-- --120hz`）。重新烘焙任一连接地点或全部场景时，烘焙器会同时更新两侧裁切资源。

换层后可立即折返；确认键按住跨场景时，需要松开再按才触发下一次确认。

## 运行

使用 Godot 4.7.2 打开 `project.godot`，主场景为 `game/world/world.tscn`。兼容性渲染器适用于当前电脑。桌面环境也可以运行 `Play-Godot.cmd` / `Open-Editor.cmd`，它们使用相邻的 `../Tools/Godot` 便携版。

二进制场景、贴图及媒体使用 Git LFS。克隆时运行：

```sh
git lfs install
git clone --recurse-submodules https://github.com/Kottalo/harvest-moon-remake.git
git -C harvest-moon-remake lfs pull
```

如果 Godot 大量提示 PNG/场景加载失败，先运行 `python tools/check_structure.py`。它会检查是否残留 LFS 指针；在工程目录执行 `git lfs pull` 和 `git lfs checkout` 恢复真实素材，再让编辑器重新扫描、导入。迁移 LFS 历史后也应执行此检查，不能只以 `git status` 干净判断素材可用。

## 目录

- `game/player/`：角色场景、输入、移动、动画、共享角色素材。
- `game/camera/`：原版镜头投影、跟随和检查全景。
- `game/world/`：主场景、地点目录、出入口切换。
- `game/locations/<名称>/`：每个地点的原生场景、贴图图集和材质；例如 `farmhouse`、`library`、`clinic`。
- `tools/`：离线提取、转换及检查；`tools/generated/` 是可重新生成的中间文件，不提交。
- `reference/hmbtn-decomp/`：原版反编译源码，固定版本的只读 Git submodule。
- `addons/`：第三方 Godot AI MCP 插件。
- `verification/`：检查记录。

`AGENTS.md` 定义目录职责和模块边界，`python tools/check_structure.py` 检查归属、命名和资源引用。旧 `scenes/`、`scripts/farm.gd` 与农场素材别名保留给现有编辑器标签页，运行入口已迁移到 `game/`，旧脚本只做跳转。

运行时只使用 Godot 场景、PNG 和 JSON，不读取 ROM 或执行 PS1 指令。重新转换素材才需要本机 USA 镜像、Python/Pillow 和参考源码；入口是 `Import-Assets.ps1`。当前使用 Godot AI MCP 4.3.1，编辑器保持打开时通过 MCP 刷新素材。

这个私有 checkpoint 包含用户授权保存的项目素材，不包含 ROM；不要改为公开仓库。历史实现记录见 `PORTING.md`，当前目录及进度以本文件和 `CHECKPOINT.md` 为准。

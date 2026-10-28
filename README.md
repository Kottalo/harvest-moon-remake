# Harvest Moon Remake

《牧场物语：回归自然》的 Godot 原生移植工程，当前 checkpoint 见 [CHECKPOINT.md](CHECKPOINT.md)。

现有 43 个原版春季地点、94 个出入口，支持移动、跑步、碰撞、原版镜头和主角动画。沿道路进入边缘自动换区，门口按 E 或 Enter 进出，Tab 查看当前地点全景。方向键：上东北、下西南、左西北、右东南。

这是场景与移动阶段的移植，NPC、对话、剧情、营业时间、种植、物品、动物、音频和完整存档尚未实现。

2026-10-28：按用户要求，游戏镜头连续两次拉远 20%，现为原版距离的 1.44 倍，保留原版观察角度与透视参数。

人物使用固定世界尺寸的 3D billboard，按原版镜头基准校准。镜头距离、FOV 或正交缩放变化时，人物与场景一起缩放，不再固定人物的屏幕像素大小。

地面与楼梯按原版面片标志区分可行走表面和显示模型，使用原版高度容差并检查身体净空。换层遵循原版区域事件规则：自动入口直接走入，需要确认的入口按 E。楼梯及障碍回归：`godot --headless --path . --script tools/verify_collision.gd`（追加 `-- --120hz` 验证 120 Hz）；完整上下楼流程检查为 `tools/verify_stair_transitions.gd`。

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

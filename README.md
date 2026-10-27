# Harvest Moon BTN · Godot 原生移植工程

工程实际位于桌面 `HarvestMoonBTN\GodotRemake`。

- 双击 `Play-Godot.cmd`：运行当前初版。
- 双击 `Open-Editor.cmd`：打开 Godot 编辑器，启用 Godot AI MCP。
- WASD / 方向键移动，Shift 跑步，Tab 切换跟随与全景。

目前已导入原版农场模型、贴图和主角动画，可行走、跑步并与地面、墙体碰撞。**这是移植初版，尚不是完整游戏**：种植、物品、NPC、对话、剧情、室内、存档、音频和季节变化尚未接入；部分动态场景物件也还没有恢复。当前碰撞由场景网格生成，尚未逐项移植原游戏的碰撞与出入口规则。

运行加载 Godot 原生场景和 PNG，不读取 `.bin` / `.cue`，不使用 PS1 CPU 解释器。只有重新提取素材时，`Import-Assets.ps1` 需要原版 USA 光盘镜像；保留的旧 Windows 版有自己的镜像依赖。

Godot 4.7.2 位于相邻的 `Tools\Godot`，采用兼容性渲染器。Godot AI 插件及 Python 服务端版本均为 4.3.1；已加入 Codex MCP 设置，且实际通过认证连接完成启动、输入操作与截图。连接需保持 Godot 编辑器打开。已有对话若未刷新工具列表，可在下次重新打开对话时载入配置。

源码参考为你提供的 [coalslav/hmbtn-decomp](https://github.com/coalslav/hmbtn-decomp)，完整本地副本在 `reference/hmbtn-decomp`。转换过程和验证记录见 `PORTING.md`。素材从本机镜像提取，未上传。

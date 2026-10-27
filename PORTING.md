# 实现与验证记录

## 固定来源

- 游戏反编译：`https://github.com/coalslav/hmbtn-decomp`，提交 `a2dd23e4554154bb34a4c8a09d1a74b4039028dc`。
- Godot AI：`https://github.com/hi-godot/godot-ai`，4.3.1，插件副本提交 `a799acfa49cd9510738b7976355aae85cf7577b9`，Python 端由 uv 安装 `godot-ai==4.3.1`。
- Godot：4.7.2 stable，官方 Windows x64 便携版。
- 本地 USA 镜像 SHA256：`41f81532a5fd70d6f79e7b5750513c35eee732d5e31ba144a1db7e90d84d97de`。

## 已实现的转换链

`tools/import_disc.py` → 原版素材 PNG / JSON → `tools/bake_assets.gd` → Godot 原生 `scenes/original_farm.scn`。

运行脚本 `scripts/farm.gd` 只负责原生输入、CharacterBody3D、动画与镜头，运行时不会解析原始 PS1 模型、光盘或指令。

| 数据 | 源码参考 | 当前转换结果 |
|---|---|---|
| A_FILE.BIN 与农场分段 | `src/main/cd/afile.c`、`src/overlay/common/farm_section_table.h` | ISO/Mode2 扇区读取，农场 section 0 |
| 农场模型 | `src/main/geometry/model.c/.h` | 294 个对象、4246 个原始面，烘焙为 51 个材质分组 |
| 贴图与调色板 | `src/main/graphics/texture_pack.c/.h` | 166 个农场数据块，支持 raw、行 RLE、列 RLE、4/8/16 位纹理 |
| 主角动画 | `src/main/graphics/anim.c/.h`、`src/overlay/27_GF_TITLE/title.c` | A_FILE 偏移 0x2A800，图像库偏移 0xBE08；277 个数据块，前 15 组 / 90 帧 |
| 站立、走、跑映射 | `src/overlay/11_GF_FARM/people/player.c` | 站立组 0 按朝向；走 1+朝向；跑 6+朝向；保留帧控制与半刻时长规则 |
| 镜头方向 | `src/overlay/11_GF_FARM/world/scene_view.c` | yaw -512，眼点高度 4500、距离 9000 的方向；Godot 使用正交投影 |

TMD 使用本游戏定长 primitive 布局，不能把头部前两个字节当作标准 TMD packet 长度。转换器对未知模式、越界索引、纹理边界及截断数据报错。

## 检查

1. `python tools/import_disc.py --check`：RLE、原始/列图像库、颜色与截断检查。
2. `godot --headless --path . --script tools/verify_runtime.gd`：实际场景、输入与物理集成检查。60 个物理帧分别行走 2.6000、斜走 2.6000、跑步 4.7999 世界单位；落地且真实网格墙体阻挡角色。
3. 另建只含 `assets`、`scripts`、`scenes`、检查脚本的隔离目录；没有 ROM、反编译仓库、转换器和 MCP 插件。重新导入后相同运行检查通过。
4. Godot AI MCP 通过认证 stdio attach：编辑器状态、启动活性、真实 InputMap 操作序列、游戏画面截图。MCP 输入 60 帧移动距离 2.6000，地面状态为 true；运行快照为 60 FPS。此为单场景采样，非整机性能保证。

高分辨率截图可能超过 MCP 的 1 MiB 单事件限制，验证截图使用最长边 800 像素。未提高服务器限制。

## 继续移植的依赖顺序

先恢复地图分段切换、出入口和动态场景物件，再根据原仓库接入时间、物品/工具、耕作和作物生命周期；随后接入 NPC 日程、对话/事件、动物、室内、音频与完整存档。每项应对照旧 Windows 原生重编译版验证行为。当前工程没有声称这些系统已经移植。

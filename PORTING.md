# 实现与验证记录

## 固定来源

- 游戏反编译：`https://github.com/coalslav/hmbtn-decomp`，提交 `a2dd23e4554154bb34a4c8a09d1a74b4039028dc`。
- Godot AI：`https://github.com/hi-godot/godot-ai`，4.3.1，插件副本提交 `a799acfa49cd9510738b7976355aae85cf7577b9`，Python 端由 uv 安装 `godot-ai==4.3.1`。
- Godot：4.7.2 stable，官方 Windows x64 便携版。
- 本地 USA 镜像 SHA256：`41f81532a5fd70d6f79e7b5750513c35eee732d5e31ba144a1db7e90d84d97de`。

## 2026-10-29 地面物件 offset 的来源

`field_draw_grid` 用 `(col*400-4050,-100,1250-row*400)` 投影，等于逻辑格心 `(col*400-4200,0,1400-row*400)` 加 `(150,-100,-150)`；`estate_draw_records` 对独立记录使用相同绘制偏移。图片来自 `farm_item_toc_0` 槽 0／4／6 的 range 0，不能换成 `0x3C19000+item*2048` 的手持 ANI：图案相同但部件偏移不同（树枝横纵差 2 像素，石头／杂草纵向差 1 像素）。地面批次以独立材质参数恢复原版投影点，碰撞中心不跟着画面偏移移动。

田地占格由 `field_world_to_cell` 的 `/399` 决定，和 400 单位美术格心有随行列累积的偏差；最后一格的碰撞中心比美术格心在 Godot X/Z 分别少 0.0445／0.0245。原版 `farm_record_hit_test` 对独立物件采用 `position±ItemInfo.halfWidth/halfDepth`，石头／树枝／杂草均为 100／100。用户要求的连续自由落点采用这一独立记录规则，保留初始田地占格。Godot 玩家胶囊及高 0.4 的防攀爬屏障仍是原生物理适配，不等同于 PS1 的二维点探测。

可运行 `tools/import_player_actions.py <disc> --items-only` 只刷新物件原生资源，`--check` 校验导出表与动画画布；`tools/verify_item_offsets_gpu.gd` 验证 18 个实际 GPU 场景，`tools/verify_item_collision.gd` 验证源区间、独立半宽、四向运动与自由放置。ROM 仅供离线提取，不在运行时读取。

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
| 镜头与坐标 | `src/overlay/11_GF_FARM/world/scene_view.c`、`src/main/geometry/model.c` | yaw -512，PS1 眼点约 (6363,-4500,-6363)，H=1000、320×240；Godot 坐标 (x,-y,-z)/1000，垂直视角约 13.68555°，4:3 画幅 |
| 场景物件 | `src/overlay/11_GF_FARM/world/scene.c/.h` | 读取 FarmModeScript 末尾 15 条 44 字节记录，按 absent/hidden/slot 标志装入 8 个可见物件，保留原始位置与角度 |

TMD 使用本游戏定长 primitive 布局，不能把头部前两个字节当作标准 TMD packet 长度。转换器对未知模式、越界索引、纹理边界及截断数据报错。

## 检查

1. `python tools/import_disc.py --check`：RLE、原始/列图像库、颜色与截断检查。
2. `godot --headless --path . --script tools/verify_runtime.gd`：实际场景、输入与物理集成检查。验证上下左右的屏幕位移符号为东北、西南、西北、东南及对应四种姿态；Godot 透视投影与独立实现的原版 camera_build_view/GTE 公式误差小于 0.05 原始像素；检查原始场景物件位置。60 个物理帧行走 1.2301、组合方向行走 1.2301、跑步 2.1902 世界单位；速度取自 player.c 中 41/73 单位每 30 Hz 帧。落地且真实网格墙体阻挡角色。
3. 另建只含 `assets`、`scripts`、`scenes`、检查脚本的隔离目录；没有 ROM、反编译仓库、转换器和 MCP 插件。重新导入后相同运行检查通过。
4. Godot AI MCP 通过认证 stdio attach：编辑器状态、启动活性、真实 InputMap 操作序列、游戏画面截图。校正后重新启动，确认 fov=13.685546875、透视投影、逻辑画面 960×720、物件 0 位置 (-4.78,0,-4.28)，编辑器错误日志为空。早期 verification 中的 2.6000 移动距离记录属于校正前版本，不代表当前原版速度。

## 2026-10-28 还原校正

早期只反转了 Y 轴，并把输入旋转成屏幕正方向，造成地图左右镜像和方向错误；正交 size=12 也是未经原版投影计算的近似。现已统一使用 (x,-y,-z)/1000，方向键沿原始世界轴走；组合键按 player_dpad_facing 的四向选择规则处理。默认镜头恢复透视，Tab 全景仅用于检查地图。

主角原本由 player_draw 投影 (x+150,y-100,z-150) 后以固定屏幕像素绘制；现在同步恢复这个锚点，并按相机深度调整 billboard 的 pixel_size，避免镜头校正后角色比例错误。

8 个场景物件单独保存在 ZoneModel_00…07 节点中，位置与旋转来自文件；没有为修正画面而手动调换建筑。还没有完整恢复它们的动态交互。

高分辨率截图可能超过 MCP 的 1 MiB 单事件限制，验证截图使用最长边 800 像素。未提高服务器限制。

## 继续移植的依赖顺序

先恢复地图分段切换、出入口和动态场景物件，再根据原仓库接入时间、物品/工具、耕作和作物生命周期；随后接入 NPC 日程、对话/事件、动物、室内、音频与完整存档。每项应对照旧 Windows 原生重编译版验证行为。当前工程没有声称这些系统已经移植。

镜头偏移现在由原始水平距离 9000、高度差 4500、yaw -512 计算，移除了手填的旋转后 X/Z 近似值。MCP 已读取运行中镜头：水平距离 9.0、高度 4.5、直线距离 10.0623064、透视视角 13.685546875°；启动及编辑器错误日志为空。

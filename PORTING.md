# 实现与验证记录

## 2026-11-03 阻挡接触与跳跃通道

落地且实际速度为零时，镜头保持碰撞 safe_margin 四倍范围内的稳定渲染焦点，避免毫米级碰撞恢复变成地面物件的亚像素抖动。真正移动、大位移和直接换图会立即恢复跟随；固定观察角度不再逐帧从世界坐标差值重算。玩家物理、正常插值和物件位置保持原样。

跑跳按前进方向的一层检查：胶囊可以跨过同排左右并列的合法低物件，后面的第二排、侧面实体墙、天花板和缺失落点仍拒绝。仅对完整弧线/落点均已验证的那一排暂时增加例外，按 RID 统一清理，覆盖物件中途被删除的情况。verify_blocked_camera.gd / verify_running_hop.gd 的 60/120 Hz 检查及既有碰撞回归记录于 verification/blocked-camera-*、hop-rows-*、contact-*。

## 2026-11-03 原生图集管线

Free Texture Packer CLI 已接入完整离线导入。原 1633 张游戏/兼容 PNG 放在 tools/texture_packer/source；动作 spritesheet 按原帧表拆开，原 margin 保存在目录清单里，再打包为运行图集。texture_packer/.gdignore 排除原图、独立帧、npm 模块与构建项目；游戏只使用输出图集、AtlasTexture、JSON 和原生场景，不扫描或读取源目录。

当前为 88 张图集、8012 个输入条目，其中 6212 条动作帧、两份普通/兼容角色图各 96 个格子。相同 crop 可以复用图集区域，但源 margin 不同，运行帧缓存必须同时区分 margin。地图页和水流缓冲保留原 UV 空间，材质通过 atlas region 采样；角色/影子/手持物由 Sprite3D 处理区域，批量地面物件单独变换 UV。农场/矿洞 shader 的图像输入也使用区域采样，动态状态纹理继续独立。

重复构建字节一致；源像素、46 场景结构、全部 6212 帧实际绘制数据及已有运行/动作/锄地/换工具检查通过。GPU 画面对比未验收，编辑器强制绘制试验及用户恢复过程见 CHECKPOINT.md。操作步骤和边界见 tools/texture_packer/README.md。

## 2026-11-03 贴图去重

相同 RGBA 像素且导入配置相同的 PNG 现在共享一份既有资源。`tools/texture_dedup_manifest.json` 记录 100 个旧路径到保留路径的映射；47 个运行资源和 53 个旧农场别名删除，共减少 5,054,357 字节源 PNG。旧农场场景仍可打开，53 个别名引用改指向现有农场贴图；另外 3 组源图相同但导入设置不同的版本保留。

`Import-Assets.ps1` 在原始素材提取后执行 `python tools/texture_dedup.py apply`，随后刷新并烘焙。烘焙和矿洞素材校验使用同一离线映射，不要求修改原始转换中间数据，不增加运行时依赖。7 组农场/Yodel motion atlas 改用共享导入 Texture2D，保持未压缩、无 mipmaps、无 alpha-border fix、无自动 3D 压缩，匹配先前内嵌 ImageTexture。每个材质的 STP/混合模式、动画表、shader 和 UV 独立保留；去重并不代表合并材质或减少 draw calls。

`texture_dedup.py check` 验证保留像素与已删除别名，`tools/verify_texture_dedup.gd` 核对 46 个原生场景的迁移前指纹、外部依赖和实际共享 Resource。指纹包含几何、UV、变换、碰撞、shader 源参数及普通材质配置，排除被替换的纹理资源身份与 Godot 自动生成节点名的进程编号；数组顺序仍区分各节点。基线/汇总及运行日志保存在 `verification/texture-dedup-*`，原图完整 RGBA 哈希在离线清单中。

## 2026-11-03 F1 天色调试

F1 面板在游戏暂停时提供自动/清晨/白天/傍晚/夜晚预览，复用既有减色 shader 和源色值；不改游戏日期、时钟或自然插值。手动预览可覆盖室内限制，隐藏保留选择，自动恢复地图原规则。面板独立持有 SceneTree 暂停，不改玩家操作锁，并处理下拉弹窗 F1 与退出清理。原生 headless 输入/布局/选择信号及昼夜、睡眠、运行回归通过；本机隔离 GPU 初始化失败，本轮未做截图验收，具体限制见 CHECKPOINT.md。

## 2026-10-30 出门安全关闭

到达地图后，门保持打开，直到带原偏移的真实玩家胶囊离开两片门板的完整转动界限，再消耗正常保持时间并关闭；重新进入范围时暂停关闭。只对尚未安全的到达点做短暂向外行走，保留原生碰撞/地面探测，遇挡墙按时交还控制并保持开门，不瞬移穿墙。窄室内门同时识别胶囊和可行走地面探测边界，保留站定 E 返回和立即楼梯往返；用户要求的此项原生物理适配不改变原版入门退让/转回动作。验证与范围见 CHECKPOINT.md 最新条目。

## 2026-10-30 原版录像校对与脚底微调

用户录像明确表现先转身退让门板，再转回进入，最后淡出。此前 10+20 两段全部向前的实现已更正：`player_walk_start` 保存朝向后，`facing_buttons` 表映射到相反方向，`player_dpad_facing` 再更新面向；第二阶段重复反转。按真实 countdown 判零顺序为 11/21 个源 tick，后退 0.451、净前进 0.410，七条实际 E 路线/取消/60/120 Hz/GPU 与楼梯立即返回通过。旧条目中要求全程前进 1.23 的结论不再适用。

按用户截图将身体统一下移四个素材像素至 offset (0,49)，手持图跟随同一 Y 基准，影子和物理不动。狗屋只去掉被不透明木纹覆盖的两个共面灰背板三角形，避免原版画家排序几何在原生深度缓冲中互相争抢；木纹门楣面积、屋顶、铭牌和原位置保留。详细限制和实测记录见 CHECKPOINT.md 最新条目。

## 2026-10-30 落脚对齐基准

用户要求以耕土格心对齐影子，再让人物脚底共用该点。影子保留原图，但可见中心通过 offset (-1,47.5) 对准逻辑落脚点；移除图片绘制时的手部投影偏移，保留原深度锚点。人物和携物沿用固定 (0,53) ANI 原点，不按每帧轮廓重排、不吸附移动或调整物理胶囊。四个实际耕土格/四朝向 GPU 可见中心误差小于 0.01 像素；坡道、跳跃与原生运动检查通过，详见 CHECKPOINT.md 最新条目。

## 2026-10-30 影子、矿洞地面与门口通行

影子由 `player_draw` → `farm_draw_cursor` 的共享 UI range 24/frame 0 离线导出；保留画布原点和半透明混合，贴地并在身体后方排序，跳跃时留在地面。矿洞参考 `mine_dig`/`mine_retexture_cell`，在原有地面材质上更新单格状态纹理，保留原版 CLUT、UV 和 100 格的朝向；源室外矿洞入口清除访问状态。当前仅含挖掘地面效果，未实现随机掉落和下层生成。

开门按 AUTO_WALK/NO_INPUT 的原意，在已确认的门过渡中跳过普通阻挡，保留源地面落脚与 10+20 tick 行走，再淡出。玩家碰撞掩码暂存并在换图/取消时恢复；门口判定恢复严格脚点，窄室内门只在原生胶囊实际受阻时补偿与原版点探测的尺寸差。六条真实 E 路线完整移动约 1.23，60/120 Hz、取消恢复、16 条楼梯立即往返通过。海岸首阶的四个共面重复三角形改为海滩单独持有，碰撞和镜头不变。来源、限制与验证数据见 CHECKPOINT.md 最新条目及 verification/shadow-mine-*.txt。

## 2026-10-29 跑跳、换工具与正交投影

默认投影按用户要求改为正交，相同深度方向上的世界尺寸不再近大远小；保留原角度与既有中心取景比例。关闭默认碰撞显示。跑跳参考 player_slide_on_bump / farm_probe_steps 的单阻碍格＋下一格空闲规则，使用 range 10/28 原姿势与 -80/+16/30 Hz 的 11 tick 弧线；完整胶囊先验证弧线和落点，只临时忽略被跨越的那一个小物件，以适配用户保留的 0.4 整格屏障，落地/换图清理。Q 参考 player_check_tool_slots 的 0x47 姿势与 10 tick 展示，图片来自 per-item ANI，保持 mark_screen_offsets 组 0/方向 0 和身体前层。新增 35 个语义工具图通过 import_player_actions.py --tool-icons-only 离线提取；工具、携物与原有动画图未替换。原生物理/实际 Q 与方向键在 60/120 Hz 验证，GPU 图和记录见 CHECKPOINT.md 最新条目。

## 固定来源

2026-10-29 锄地接入：`tools/import_farm_field.py` 校验并导出 `field.c` 的 cell_looks／column_mirror_table、`farm_tables.c` 锄头 picture_grids 与 `player.c` 的 tool_charge_steps_a。真实挥锄结束触发原版逐格结果：1／2／3／4／6 格，失败即终止后续格子，已有湿土不被锄干。耕地使用 page 8 / CLUT 0x3E95，湿土保留使用 CLUT 0x3E5F；shader 用原版 31 texel 角点跨度重算目标格 UV，替换原地面颜色，几何和碰撞不变。离线检查涵盖全部 1125 个田地四边形及镜像；GPU 中真实 Space 操作产生的耕地与独立原版四边形参考的 9 个采样像素一致。土壤在本次运行内跨区保留，不代表完整作物／挖矿／存档系统已接入。

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

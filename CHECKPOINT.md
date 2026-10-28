# Checkpoint — 2026-10-28

## 2026-10-29 原版物件图片与阻挡 offset 校正

- 查证两个实际差异：此前地面用了手持物的 ANI（石头／杂草低 1 像素，树枝横纵偏 2 像素）；自由放置后仍分配整格 399×399 阻挡，混用了原版田地与独立物件的规则。
- `import_player_actions.py --items-only <disc>` 从 `farm_data.c` 的物件包 0、槽 0/4/6 提取地面 range 0，保留原始 ANI 部件偏移；新增 `*_ground.png`，手持 PNG 不变。从 `farm_tables.c` 导出独立记录半宽／半深 100/100，从 `estate.c` 导出绘制偏移 (+150,-100,-150)。运行时只读原生 PNG／JSON。
- 地面材质单独启用 Godot (0.15,0.1,0.15) 绘制锚点，碰撞和逻辑点不移动；共享 shader 的玩家／手持材质默认偏移为零。初始田地物件继续按 399 单位区间阻挡，保留美术 400 单位间距导致的偏差；自由落点采用原版独立记录的 200×200 范围，仍用连续坐标。高度 0.4 的防攀爬屏障及玩家胶囊为原生适配，未声称是原版 3D 物理形状。
- 源数据检查逐像素比较原版地面 ANI；GPU 在三种物件、三个农场位置、1x／1.44x 距离共 18 个场景对照原版画布与裁剪批次。碰撞检查增加 15 个角落／内部原始占格偏移及三个独立记录的实际中心／尺寸，保留最近落点、50% 门槛、四向后退和无物品丢失检查。
- 验证通过：以上实际 MultiMesh GPU 对照、60／120 Hz 各 72 次接近与拿放／后退回归、GPU 的 E 键交互及 24 次增量放置、260 动作组合、门／转场、原生运行与结构／LFS 实体文件检查；证据为 `verification/source-item-offsets-*.txt`。仅新增三张通过 LFS 跟踪的地面 PNG 及其 Godot 导入描述，没有提交 ROM，也未启动用户游戏。

## 2026-10-29 前方放置检测区与连续落点

- 按用户建议，增加跟随四个朝向的前方互动检测区：中心距角色 0.4，宽深各 0.8，约两个田地格宽；8×8 子格做原生碰撞查询，估算可用比例，默认达到 50% 才尝试放置。检测尺寸、采样和比例均为命名常量，仅交互／释放时查询。
- 用户追加要求不再 round 到下一格：先精确使用前方实际坐标，只有遇障碍才以 0.025 间隔在检测区内按最近距离搜索。新记录带 `free_position`，图片和碰撞盒都用连续坐标；导入的初始物件仍保留原版占格偏移。格子编号只记账，不再决定新物品位置。
- 若最近落点仅与角色重叠，先验证后方碰撞扫掠及中点／终点可行走地面，最多退 0.2；真实动作释放时以 `move_and_collide` 小退后创建物件。后方不安全会选其他落点；复查或移动失败继续持有。全物件尺寸、墙壁路径与地面检查仍有效，碎小空隙不能强行放入；放置保持增量更新。
- 检查加入四个方向的石头／树枝、玩家排除、50% 可放、37.5% 拒绝、碎小窄缝、跨格边 1 mm 不跳格、实际碰撞随连续位置、真实放下动画的小退，以及后方障碍／无地面的安全替代落点。GPU 动作检查改为验证连续落点及记账，保留 24 次增量放置回归。
- 以上检查与原有 72 次碰撞接近在 60／120 Hz 均通过；独立桌面 GPU 的 E 键放置、260 动作组合、24 次增量循环、门／转场通过，原生运行及资源结构检查通过。证据见 `verification/continuous-placement-*.txt`。未操作用户运行中的游戏。

## 2026-10-29 放置自动选择最近空位

- 上一版只检查前方固定格；角色贴近格边时，空格的阻挡范围与胶囊相交便直接拒绝。按用户新要求，改为在前方目标的 3×3 邻接范围内选择距离原目标最近的有效前方落点，保留角色站位，避开脚下。
- 候选点同时检查实际活动物件、原生碰撞盒、通向落点的障碍，以及可行走支撑地面；一单位的查询间隙允许相邻占格边缘接触。尚未导入的原版大石等布局占位没有实体，不再凭隐藏的 field cell 值阻止放置。释放动画结束时重新检查；真的没有落点则继续持有，不销毁物品。
- 拿起／清除时立即关闭对应碰撞层，再等待节点释放，避免同帧放置查询碰到已移除的物件。放置仍只增量添加一件物品。
- 新增四朝向、石头／树枝的贴边落点回归，验证最近格、角色不移动、真实障碍旁可放、不能穿墙、必须有地面、忽略不可见布局占位，以及释放前被占用时物品不会丢失。
- 验证通过：60／120 Hz 各 72 次实际碰撞接近及自动落点回归；独立桌面的 GPU 动作检查包含实际 E 键拿起／放下、24 次增量循环、空批次恢复和原有门／转场；原生运行检查通过。记录见 `verification/nearest-placement-*.txt`。

## 2026-10-29 地面散落物阻挡

- 对照 `farm_tables.c` 与 `farm_probe.c`：石头、树枝、杂草分别使用规则 3、6、2，三者都为 TILE_RULE_BLOCKED。旧实现遗漏杂草碰撞，石头／树枝仅有中心 0.16×0.16、0.12 高的小盒，允许从占格边缘穿过。
- 现在按 `field_world_to_cell` 的 399 单位真实格界生成阻挡，保留 400 单位原画位置；共享 0.399×0.4×0.399 BoxShape，独立碰撞体跟随对应记录。竖直屏障适配原版二维占格测试，避免胶囊把物件当台阶。只改散落物阻挡，连续楼梯斜坡与玩家尺寸保持原样。
- 拿起／工具清除同步释放占格和碰撞，放回时恢复；放置目标若与角色胶囊重叠则保留手持物，避免卡进刚放下的石头。继续使用上一轮增量更新，不重建其他物件。
- 专项检查覆盖三类物品的四方向／中线及两侧／走跑，60/120 Hz 各 72 次实体接近；同时检查邻接空格能通过、清除无残留、放回恢复、禁止脚下放置。原生速度／镜头校准改在空旷农场前院进行，避免把正确阻挡误认为移动速度变慢。
- 修正碰撞测试的物理计时：每个 physics tick 后再等 process frame，在 120 Hz 下会把一次等待变成两个物理 tick，走过测试平台后误报上不去。现在先等待规定的物理 tick，再等最终绘制帧；真实控制器未改。423 个物件全部具有阻挡后，后台 960×720／4× MSAA 农场采样仍为 69 次绘制调用，P95 帧间隔约 12.8ms。
- 专项阻挡与通用楼梯／障碍回归均在 60/120 Hz 通过；16 条房间楼梯立即折返、GPU 拿放／增量更新和原生运行也通过。记录见 `verification/field-obstructions-*.txt`。

## 2026-10-29 放下物品不再重建整片散落物

- 根因是 `release_item` 放置完成后调用 `set_area(current_area)`，导致全部物件／碰撞／批次被删除重建，连其他投掷物也会清空。改为只加入这一条物件记录和碰撞，区域重建仅用于真正换地图。
- MultiMesh 入场时按田地格数预留容量，以 `visible_instance_count` 只绘制连续的有效实例。拿起时用最后一个实例填补空位并更新它的槽号，放下时写入末尾，不重新分配 GPU 缓冲。静止物件批次关闭物理插值，避免复用槽位时从旧物件的位置滑动过来；其他物件及其碰撞节点保持身份和位置。
- 回归覆盖实体 E 拿起／放回及阻挡、24 次连续拿放、石头类型清空后再添加、其他投掷物保留、全部批次身份／容量不变。后台 GPU 检查读取真实实例坐标，原生运行和批次／原精灵逐像素画面对照继续验证；证据为 `verification/incremental-items-*.txt`。

## 2026-10-28 卡顿优化、昼夜和睡眠

- 在同一 Intel UHD 620、960×720、4× MSAA、独立后台桌面上，对 Git `288aef8` 和新实现使用相同采样脚本：各地点预热 1.5 秒，采样 2.5 秒，关闭 VSync／帧率上限以测余量。农场绘制调用 269→69，中位帧间隔 14.836→9.454ms，P95 19.205→12.224ms。六地点完整数据见 `verification/performance-day-cycle.json`；这是静止采样，不承诺每条路线／每一帧都固定 60 FPS，加载时间不作为冷盘测速。
- 农场 423 个散落物按石头、树枝、杂草分为三个裁切 MultiMesh，保留原画布位置、UV、深度及独立阻挡；拾取／放回同步批次和源格子。真实 GPU 对照原 Sprite3D：边界一致，320×320 画面只有 1 个像素差异。HUD 降到 10 Hz 更新，中文和 ASCII 使用同一系统字体，减少大量字体／纹理切换。相邻地点使用 Godot 原生线程预载，缓存仅保留当前及邻接地图。物理插值开启，镜头读取插值位置并在地图／重生跳转后清除历史。
- 修正上一轮对 PS1 `addPrim` 链表先后顺序的误解：先插入的物品会晚于身体显示，因此抱物四方向均在身体前；拾取／释放的下／右在前、左／上在后。真实玩家动作参数的 12 种 GPU 遮挡组合全部通过，并继续保留与建筑的正常深度测试。
- `clock.c` 的 one_minute=30，30 Hz 下累计 15 tick 才走一分钟，即 0.5 秒／分钟；HUD 按原版十分钟显示。源 place_entries 决定室内／矿洞暂停，全景、菜单和过渡暂停时钟。原版四时段为 05–07／07–15／15–17／其余，减法色值为 (20,0,0)/(0,0,0)/(5,30,40)/(80,70,45)，切换持续 256 个 30 Hz tick；HUD 不受世界色调影响。
- 自宅原始 ZONE_PICK_MENU 范围为 x=-1.6..-1.2、z=0.3..0.7，面向左。床边 E 打开睡眠／继续活动菜单，Esc 取消，E／Enter 确定。离线导出 PLAYER_MODE_GO_TO_BED 的独立 ANI，按原版 18 tick 上床轨迹及 +40 单位落点高度移至床上，保留身体弧线但不让镜头随身体上下跳；随后原生淡出、跨天、回到源自宅晨间坐标 (-0.09,0,-0.541)，06:00 淡入。
- 每季 30 天、四季、星期和 98 的内部年份上限；日期在 06:00 更替，午夜只回卷时钟。正常熬夜到 06:00 也回家跨天，并防止重复增加日期。本阶段不假装实现体力／疲劳、作物／动物日更、季节场景美术或完整存档；交互记录仍在会话内保留。
- 30/60/120 FPS 时钟一致性、原始地点暂停、四时段 GPU 色值、睡眠物理按键／取消／18 tick 轨迹／春30到夏1／冬30到次年春1均通过。原生运行、物品交互、43 场景／92 出口、60 Hz 碰撞、16 条楼梯立即折返、60/120 Hz 海滩连接、角色贴地及既有水流／遮挡 GPU 检查通过。全过程未启动／重启／注入按键到用户的游戏。

## 2026-10-28 原版动作、门板及地点过渡

- 离线读取基础角色的 177 个 ANI range，保留原始帧时长、0x80 跳转与 0xFF 结束控制。五种农具分别使用 72/92/112/132/152 起始组，四向各五级；每级蓄力 20 个 30 Hz tick，释放后按实际蓄力等级选组并从 level+1 帧挥动，满蓄力后 61 tick 转原版过度蓄力姿态。工具材质及蓄力光效按 `player_draw_body` 的调色板替换规则离线生成。
- 独立读取 milker/clippers/brush/bell、钓鱼、补水、药剂及播种动作包。钓竿包含甩竿、等待和收竿姿态。本次范围为动作播放与基础交互；商店解锁、升级进度、作物／动物／钓鱼收益系统尚未接入。
- 部分工具、水流特效超出原 128 画布。新动作保留 256 共同画布，原点 (128,176)，打包 AtlasTexture margins 后仍使用同一个 (0,53) 固定锚点和原 pixel_size。离线展开检查验证原 90 帧逐像素相同；真实 GPU 渲染的原版站立与打包站立边界完全相同，未逐帧归一化脚底。
- 手持物沿用 `mark_screen_offsets` 的朝向／姿态偏移与原版绘制先后。使用视空间距离偏移处理前后关系，避免 reverse-Z 下把“在身后”错误变成“在身前”；真实 GPU 的重叠像素与手持纹理绑定均有检查。原有角色遮挡和已确认的水流 GPU 回归继续通过。
- 农场散落物来自 `title_layout0_cells`，423 个石头、树枝、杂草支持拾取、抱持移动和释放；基础镰刀／斧头／锤子命中相应物件时更新会话内记录。石头、树枝带实体阻挡，杂草不挡路。
- 石头／树枝按 `player_use_held_item` 的目标位 0x10 与 `player_selection_to_result` 规则放回农场空格，先取前方 400 单位点，再按原始 399 单位格转换定位；占用格不放置，杂草及场外丢弃。拿起、放回、清除同步更新源 field cell 与阻挡，放回测试要求最终只有一个物件。
- 根据源 zone 的 modelIndex 识别 22 处可转动门板，沿原模型铰链转动；原始角度上限 0x420、角速度每 tick 增 8、开启 16 tick、保持 11 tick、关闭 16 tick，有双门时反向转动。进入时播放原版走入姿态。
- `farm_main.c` 的换图采用 `fade_start_blend(20)`：旧帧冻结，30 Hz 每步减 12/255，清黑后换地图；`fade_start_in(10,0,2)` 在 60 Hz 显示时钟下淡入。输入只在过渡期间锁定，没有恢复旧的到达后冷却；海滩—广场不触发此过渡。
- `verify_actions.gd` 覆盖 260 个工具／等级／方向／蓄力组合、实际 E 拾取与抱持、门板与双门、60/120 FPS 过渡时钟；原生移动、43 个地点／92 个普通出口、16 条楼梯立即折返继续检查。GPU 检查放在独立 Windows desktop，始终保持用户 input desktop 为 Default，不抢焦点。

2026-10-28：用户否决了程序化 3D 主角初版。已撤回模型、F3 切换及配套文件，恢复原版精灵；Blender 安装保留，试作可从 Git 历史恢复。今后测试使用后台或离屏方式，不抢焦点、不向用户正在使用的游戏注入按键。

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

## 2026-10-28 镇南街区道路接坡

- 用户截图位置实际坐标为 (1.205002, 0.800812, 5.26998)，属于上层道路的接坡，上一轮重复台阶清单漏掉了它。四向全身扫掠没有命中阻挡物；向 -Z 的地面法线是 (0, 0.6, -0.8)，53.13° 超过旧 45° 上限，导致地面通行查询主动清零速度。
- 增加命名坡面 `UpperRoadConnection`，连接 z=3.94/y=0.08 与 z=5.2/y=0.8，宽 x=0.8…1.6。整坡约 29.745°，替换该范围的碎接坡。角色可行走坡度调整为 60°，覆盖同类原版合法接坡，垂直障碍仍不可通行。
- 回归增加截图的准确站位和坡道两侧，以及复现 53.13° 原版坡度的独立实体斜坡。修复前原地按上 100 帧完全不动；修复后实际下降到低处地面并保持着地。证据见 `verification/road-connection-diagnostic.json` 与 `road-connection-60.txt` / `road-connection-120.txt`。

## 2026-10-28 可见脚底与地形高度对齐

- 上一轮直线道路碰撞坡在 z=4.8 处低于原始可见路面约 0.109，原来的精灵水平偏移也把显示位置移出了身体接地点，造成角色埋地。保留连续坡面通行；人物在着地时仅调整精灵显示高度，贴合接地点上下 0.2 范围内的朝上可见表面，缺失时使用胶囊与支撑平面的间隙补偿。身体仍完全由原生移动和吸附控制。
- 移除手部投影用途的 XZ 偏移，离线导入每个 ANI 帧的透明像素脚底边界 `foot_y`，统一站立、行走、跑步及四朝向的落脚点。90 帧资源重新从本地素材导入，PNG 和 JSON 与工程逐字节一致；人物世界尺寸和镜头设置保持不变。
- `tools/verify_player_grounding.gd` 检查报告路段的 8 个静态位置和 3 条通行路线的连续下坡/上坡，以及四朝向动画脚底锚点。脚底对可见表面高度误差最大约 0.00000003。运行画面已核对；60/120 Hz 碰撞、原生运行、16 条楼梯连接的立即折返回归通过。记录见 `verification/player-grounding*.txt`。

## 2026-10-28 修正动画帧对位

- 上一轮逐帧使用透明边界 `foot_y` 重新设置 Sprite3D.offset，破坏了 ANI 共用画布的基准；例如从站立切换到第一帧走路时，offset.y 从 53 变成 50，人为挪动整个人物。抬脚和身体起伏本来已通过原始 frame/part dx/dy 烘焙在图集中，不应再次归一化。
- 全部帧恢复共用场景里固定的 (0,53) 画布锚点，保留素材本身的动作偏移；`foot_y` 只保留为离线诊断数据。路面高度补偿仍只根据地形调整精灵位置，与动画帧无关。镜头、世界尺寸和碰撞未更改。
- 扩大同一检查至全部 68 个站立/走路/跑步帧及四朝向：旧实现会明确失败，新实现通过；道路三条路线的下坡/返回和原生运行检查通过。Godot AI 已核对跑步第 51 图块在报告路段的运行画面。新记录为 `verification/animation-alignment*.txt`；上一节所称“各帧脚底对齐”由本节的固定画布基准取代。

## 2026-10-28 模型显示和角色前后遮挡

- 医院楼梯的黑坡是源文件带半透明命令、加法模式、全零顶点色的通行面，原版绘制结果不改变背景。转换器将这类面标为不可见，烘焙时保留全部物理/通行三角形；不再把它们作为黑色实体显示。新增转换自检区分加法黑、其他混合黑、非混合黑和有颜色的加法面。
- 原版 `model.c` 剔除背面；旧转换器强制双面显示，导致医院盆栽背面和医院楼上门板背面参与绘制。恢复原始正面，已对照三张报告画面核对医院楼梯/盆栽及楼上木门。
- 用户指出需要类似 YSort 的按角色位置判断前后。现在使用原始面片中心和 `0x8000/0x4000` 深度偏移，并按 `player_draw` 的脚底相对手部点为整张角色计算统一深度，保持实际深度测试。身体、帽子不会再按 billboard 各像素与门板交叉裁切；动画对位和世界尺寸保持不变。
- 新增独立 GPU 检查：墙前采样为蓝帽、墙后采样为红墙，记录于 `verification/render-order-gpu.json`。医院门口新增走路/跑步物理回归：角色均在门外停止，按 E 能进入医院，无需放大碰撞胶囊掩盖显示问题。
- 43 个场景重新提取/烘焙；运行、43 个入口/94 个出口、68 帧固定锚点、道路往返、60/120 Hz 碰撞及 16 条楼梯立即折返检查通过。记录为 `verification/render-order-*.txt`，实际画面为 `render_order_clinic.png` 与 `render_order_clinic_upstairs.png`。完整 PS1 非零颜色半透明混合效果仍未全面复刻，本次处理的是已确认的纯黑加法无效绘制。

## 2026-10-28 海滩与广场无缝连接、渲染和水面更新

- 海滩入口坡面原来从 x=-6.6/y=-0.4 开始，漏了最低台阶及沙地连接；现接到 x=-6.4/y=-0.56。烘焙裁切还修复了与端面共面的旧立面被重复保留的问题。台阶外观仍保留，通行使用连续坡面。
- 撤销场景面片固定平均深度：那会使台阶和地面互相错误遮挡，造成视觉变形。场景恢复连续几何深度，人物仍保留整张精灵的脚底相对深度基准。GPU 交叉面测试同时验证两侧遮挡关系。
- 海滩与广场使用同一 `coast.tscn`，海滩偏移 (12.4,0,0.8)，共享平台 x=5。裁去两张地图各自的重复预览，只保留一套楼梯。跨界仅更新区域名，不替换模型、角色坐标或镜头；其余 92 个原始分区出口保留。三条路线的走/跑、立即往返、模型身份及镜头/地面连续性均在 60/120 Hz 验证。
- 透明材质保留命令混合位、纹理页混合模式和调色板 STP 位。分别绘制不透明像素与平均/加法/减法/四分之一加法像素，透明部分不写深度；瀑布、蒸汽的黑色外壳消除。GPU 验证加法黑不改变背景、混合 STP 黑正确变暗、不透明像素保持不透明。
- 对照 `scene_view.c:slot_rect_step/slot_image_step` 导出原始 VRAM-copy 表：温泉滚动为每 9 个 30 Hz 帧下移 2 行，31 行图像滚到 30 后回零；海浪主循环为 16/12/8/12 帧，细浪保留三条复制带。源图像即使在当前纹理页外也离线解码进 motion atlas，再作为原生 ImageTexture 烘焙。用户觉得原始跳帧僵硬后，改为平滑滚动、海浪帧交融及轻微世界坐标 UV 扰动，保留源循环时长，不移动模型顶点；用户已确认此版水流正确。GPU 检查验证中间帧变化及循环复位。当前使用 renderer TIME，完整暂停系统接入时再绑定暂停时钟。
- 画质为 Linear 和 4× MSAA。镜头按用户最终选择保留 1.44 倍距离。渲染目标 60 FPS、物理 60 Hz，运行采样 60 FPS；源动作时长和 1.23/2.19 世界单位每秒速度保持不变。速度检查按实际物理 tick 计时，避免渲染/导入负载造成误判。
- 用户取消了室外地图延伸：辅助地形代码和全部 ExteriorTerrain 节点均撤回，恢复原版外边界。保留已授权的海滩与广场无缝连接。
- 山顶星空及远山是独立的背景网格，原始宽度在拉远镜头后会露边。仅在原镜头平面内扩大：星空 3 倍，远山横向 3 倍、向下 2 倍，固定地平线锚点与观察深度，不改前景地形、人物和物理碰撞。包括用户截图位置在内的五个观察位置，两侧上部 65% 边缘均无背景清屏色采样。证据：`verification/summit-background.json`、`summit_background.png`。


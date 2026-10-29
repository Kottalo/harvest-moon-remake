# 地面物件 prefab 对位

双击 `stone.tscn`（石头）、`branch.tscn`（树枝）或 `weeds.tscn`（杂草），进入 3D 编辑器。

1. 选 `GroundSprite`，用移动工具调整图片位置；也可在 Inspector 调整 `Offset`（图片像素偏移）、`Pixel Size` 或 X/Y `Scale`。图片保持 Billboard，自动朝向镜头；不要旋转图片节点或移动 prefab 根节点。
2. 选根节点，在 `Preview Mode` 选择 `Initial field item`（初始物件）或 `Freely placed item`（自由放下）。每次只显示一个橙色方块。方块是世界空间的真实 3D 范围，不会朝向镜头。
3. 展开 `Obstruction`，按模式选择 `FieldFootprint` 或 `LooseFootprint`。拖动／旋转这个节点，或展开 `Shape → Size` 改宽、高、深。橙色方块自动跟随，游戏碰撞与放置检测读取相同数据。按最新要求，两种模式默认都是 0.4×0.4 的耕土格大小，中心和可见格心一致，取消原版 399/400 格距的位置差。
4. 按 Ctrl+S 保存 `.tscn`。下次重新运行游戏时应用给同类物件；无需修改 JSON，也不会重建整张地图。预览方块只在编辑器显示。

这三个 prefab 是手工对位的权威来源，素材导入脚本不会覆盖它们。导出器中的原版数据保留作参考。不要为了通过原版默认参数回归而重置用户保存的图片／碰撞调整。

放下时，物件根坐标会选择最近的可用耕土格心（格距 0.4）。GroundSprite 的图片偏移与 LooseFootprint 的碰撞偏移继续使用你保存的数值；吸附格心不会重置它们。Preview Mode 中现有的 Freely placed item 名称表示使用独立物件碰撞盒。

2026-10-29：按用户要求，树枝 GroundSprite 的 Offset 单独校正为 (1,43.05)，使其可见图案居中；石头和草的图片设置不变。FieldFootprint / LooseFootprint 均为 Vector3(0.4,0.4,0.4)，底部贴地。仍可通过这些 prefab 手工调整。

调试线框：石头为亮粉色、树枝为黄色、草为荧光绿，关闭 Debug Fill 以免半透明色块遮住物品。FieldFootprint 和 LooseFootprint 的 Debug Color / Debug Fill 会原样应用到游戏里的真实碰撞体；这些显示属性不改变碰撞大小和位置。

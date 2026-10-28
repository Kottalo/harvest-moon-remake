# 地面物件 prefab 对位

双击 `stone.tscn`（石头）、`branch.tscn`（树枝）或 `weeds.tscn`（杂草），进入 3D 编辑器。

1. 选 `GroundSprite`，用移动工具调整图片位置；也可在 Inspector 调整 `Offset`（图片像素偏移）、`Pixel Size` 或 X/Y `Scale`。图片保持 Billboard，自动朝向镜头；不要旋转图片节点或移动 prefab 根节点。
2. 选根节点，在 `Preview Mode` 选择 `Initial field item`（初始物件）或 `Freely placed item`（自由放下）。每次只显示一个橙色方块。方块是世界空间的真实 3D 范围，不会朝向镜头。
3. 展开 `Obstruction`，按模式选择 `FieldFootprint` 或 `LooseFootprint`。拖动／旋转这个节点，或展开 `Shape → Size` 改宽、高、深。橙色方块自动跟随，游戏碰撞与放置检测读取相同数据。初始物件额外保留原版 399/400 格距造成的微小位置差。
4. 按 Ctrl+S 保存 `.tscn`。下次重新运行游戏时应用给同类物件；无需修改 JSON，也不会重建整张地图。预览方块只在编辑器显示。

这三个 prefab 是手工对位的权威来源，素材导入脚本不会覆盖它们。导出器中的原版数据保留作参考。不要为了通过原版默认参数回归而重置用户保存的图片／碰撞调整。

extends CanvasLayer
## PS1 storage_swap.c positions and D-pad links, including marked-slot mode.
const Frame := preload("res://game/rendering/source_window.gd")
const SOURCE_SIZE := Vector2(320,240)
const SPOTS := [
	[57,36,[9,9,9,9,9,9,2,4,4,1,1,1,0,0,5,0,0,5,2,4,4,1,1,1]],
	[141,20,[10,10,14,10,10,5,0,0,0,2,2,2,1,1,5,1,1,5,0,0,0,2,2,2]],
	[175,20,[11,11,15,11,11,6,1,1,1,0,3,3,2,2,6,2,2,6,1,1,1,0,3,3]],
	[209,20,[0,12,16,0,12,7,0,2,2,0,4,4,0,3,7,0,3,7,0,2,2,0,4,4]],
	[243,20,[0,13,17,0,13,8,0,3,3,0,0,0,0,4,8,0,4,8,0,3,3,0,0,0]],
	[141,54,[0,0,1,0,0,10,0,0,0,0,0,6,0,0,1,0,0,1,0,0,0,0,0,6]],
	[175,54,[0,0,2,0,0,11,0,0,5,0,0,7,0,0,2,0,0,2,0,0,5,0,0,7]],
	[209,54,[0,0,3,0,0,12,0,0,6,0,0,8,0,0,3,0,0,3,0,0,6,0,0,8]],
	[243,54,[0,0,4,0,0,13,0,0,7,0,0,0,0,0,4,0,0,4,0,0,7,0,0,0]],
	[57,110,[0,0,0,0,0,0,11,13,13,10,10,10,9,9,14,9,9,14,11,13,13,10,10,10]],
	[141,94,[1,1,5,1,1,14,9,9,9,11,11,11,10,10,14,10,10,14,9,9,9,11,11,11]],
	[175,94,[2,2,6,2,2,15,10,10,10,9,12,12,11,11,15,11,11,15,10,10,10,9,12,12]],
	[209,94,[0,3,7,0,3,16,0,11,11,0,13,13,0,12,16,0,12,16,0,11,11,0,13,13]],
	[243,94,[0,4,8,0,4,17,0,12,12,9,9,9,0,13,17,0,13,17,0,12,12,9,9,9]],
	[141,128,[0,0,10,0,0,1,0,0,9,0,0,15,0,0,10,0,0,10,0,0,9,0,0,15]],
	[175,128,[0,0,11,0,0,2,0,0,14,0,0,16,0,0,11,0,0,11,0,0,14,0,0,16]],
	[209,128,[0,0,12,0,0,3,0,0,15,0,0,17,0,0,12,0,0,12,0,0,15,0,0,17]],
	[243,128,[0,0,13,0,0,4,0,0,16,0,0,9,0,0,13,0,0,13,0,0,16,0,0,9]],
]

const MARKS_PATH := "res://game/items/rucksack_marks.png"
const TILE := Vector2(44,36)
const SLOT_SIZE := Vector2(32,32)
# Range 11's ring is 34×34. The hand's visible pixels sit left of its anchor.
const SELECTION_OFFSET := Vector2(-1,-1)
const CURSOR_OFFSET := Vector2(20.5,24)
const HELP := "方向键：移动光标\nZ：选择／交换\nC：查看物品\nX：取消／关闭"

var economy
var actions
var panel: ColorRect
var frame: Control
var art: Control
var equip_label: Label
var carry_label: Label
var detail: Label
var marks: Texture2D
var icons: Array[Texture2D] = []
var icon_cache := {}
var cursor := 0
var marked := -1
var explaining := false
var hud_visible := false
var clock_visible := false

func setup(owner_economy, font: Font) -> void:
	economy = owner_economy
	actions = economy.world.player.actions
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = ColorRect.new()
	panel.color = Color(0,0,0,0.5)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame = Control.new()
	frame.size = SOURCE_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(frame)
	for rect: Rect2 in [Rect2(25,16,96,74),Rect2(121,16,174,74),Rect2(25,90,96,74),
			Rect2(121,90,174,74),Rect2(26,164,267,62)]:
		var box := Frame.new()
		box.source_pixel = 1.0
		box.position = rect.position
		box.size = rect.size
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(box)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_art)
	frame.add_child(art)
	equip_label = _label("装备",font)
	carry_label = _label("持有",font)
	detail = _label(HELP,font)
	panel.hide()
	panel.resized.connect(_layout)
	set_process_input(false)
	_layout()
	# Resolve the marks and starting loadout while the world is still starting.
	marks = load(MARKS_PATH) if ResourceLoader.exists(MARKS_PATH) else ImageTexture.create_from_image(Image.load_from_file(MARKS_PATH))
	icons.resize(SPOTS.size())
	_refresh()

func _layout() -> void:
	var amount := minf(panel.size.x/SOURCE_SIZE.x,panel.size.y/SOURCE_SIZE.y)
	frame.scale = Vector2.ONE*amount
	frame.position = ((panel.size-SOURCE_SIZE*amount)*0.5).floor()
	_place_text(equip_label,Vector2(29,19),11,amount)
	_place_text(carry_label,Vector2(29,93),11,amount)
	_place_text(detail,Vector2(30,167),10,amount)
	detail.add_theme_constant_override("line_spacing",roundi(-2*amount))

func _place_text(label: Label, point: Vector2, source_font_size: int, amount: float) -> void:
	# Rasterize the font at the destination size, independently of the pixel-art layer.
	label.position = (frame.position+point*amount).round()
	label.add_theme_font_size_override("font_size",maxi(1,roundi(source_font_size*amount)))

func _label(value: String, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font",font)
	label.add_theme_color_override("font_color",Color("#202020"))
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label

func open() -> void:
	if get_tree().paused or actions.busy() or actions.player.input_locked or not actions.player.is_on_floor():
		return
	marked = -1
	cursor = 0
	explaining = false
	detail.text = HELP
	hud_visible = economy.world.hud.visible
	clock_visible = economy.world.day_cycle.clock_label.visible
	economy.world.hud.hide()
	economy.world.day_cycle.clock_label.hide()
	panel.show()
	get_tree().paused = true
	set_process_input(true)
	_refresh()

func _slot_visible(index: int) -> bool:
	return index in [0,9] or ((index-1)%9)<economy.rucksack.capacity

func _slot_origin(index: int) -> Vector2:
	return Vector2(SPOTS[index][0],SPOTS[index][1])

func _refresh() -> void:
	for index in SPOTS.size():
		if _slot_visible(index):
			icons[index] = _icon(_item(index),index<9)
	art.queue_redraw()

func _draw_art() -> void:
	if marks==null:
		return
	for index in SPOTS.size():
		if not _slot_visible(index):
			continue
		var point := _slot_origin(index)
		_draw_mark(2,point)
		var icon := icons[index]
		if icon!=null:
			art.draw_texture(icon,point+(SLOT_SIZE-icon.get_size())*0.5)
		var item := _item(index)
		if actions.seed_catalogue.has(str(item)):
			var number: int = clampi(economy.count(item),0,99)
			_draw_mark(13,point+Vector2(2,22))
			if number>=10:
				_draw_mark(3+number/10,point+Vector2(12,22))
			_draw_mark(3+number%10,point+Vector2(22,22))
	if marked>=0:
		_draw_mark(0,_slot_origin(marked)+SELECTION_OFFSET)
	_draw_mark(1,_slot_origin(cursor)+CURSOR_OFFSET)

func _draw_mark(index: int, point: Vector2) -> void:
	art.draw_texture_rect_region(marks,Rect2(point-Vector2(10,0),TILE),Rect2(Vector2(index*TILE.x,0),TILE))

func _name(item: int, tool_row: bool) -> String:
	if item==0:
		return "空"
	if tool_row and item in actions.TOOL_IDS and item!=34:
		var name: String = actions.TOOL_NAMES[actions.TOOL_IDS.find(item)]
		if item<=25:
			name += " · "+actions.LEVEL_NAMES[int(economy.levels.get(item,0))]
		return name
	return economy.item_name(item)

func _icon(item: int, tool_row: bool) -> Texture2D:
	if item==0:
		return null
	var level: int = economy.levels.get(item,0)
	var source_id := item+level
	if icon_cache.has(source_id):
		return icon_cache[source_id]
	var picture: Texture2D = actions.source_item_picture(source_id)
	if picture==null:
		if tool_row:
			picture = actions.tool_picture(34,item) if actions.seed_catalogue.has(str(item)) else actions.tool_picture(item,-1,level)
		else:
			picture = actions.item_picture(item)
	var icon: Texture2D = actions.menu_icon(picture)
	icon_cache[source_id] = icon
	return icon

func _explain() -> void:
	var item := _item(cursor)
	if item==0:
		return
	var lines := PackedStringArray([_name(item,cursor<9)])
	if actions.seed_catalogue.has(str(item)):
		lines.append("种子数量：%d" % economy.count(item))
	elif cursor<9 and item in economy.TOOL_BASES:
		lines.append("熟练度：%d" % int(economy.experience.get(item,0)))
	elif cursor>=9 and economy.sell_price(item)>0:
		lines.append("出货价格：%d G" % economy.sell_price(item))
	lines.append("X：返回")
	detail.text = "\n".join(lines)
	explaining = true


func _item(index: int) -> int:
	if index==0:
		return economy.rucksack.active_tool(actions)
	if index==9:
		return actions.carried_id
	return economy.rucksack.tools[index-1] if index<9 else economy.rucksack.items[index-10]

func _put(index: int, item: int) -> void:
	if index==0:
		actions.set_bag_tool(item)
	elif index==9:
		actions.carried_id = item
		actions.update_held(false)
	elif index<9:
		economy.rucksack.tools[index-1] = item
	else:
		economy.rucksack.items[index-10] = item

func _confirm(index: int) -> void:
	if marked<0:
		marked = index
	else:
		var target := index
		if target==marked:
			target = 0 if index<9 else 9
		if (target<9)!=(marked<9):
			return
		var first := _item(marked)
		var second := _item(target)
		_put(marked,second)
		_put(target,first)
		marked = -1
	_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT and not explaining:
		var point := art.get_local_mouse_position()
		for index in SPOTS.size():
			if _slot_visible(index) and Rect2(_slot_origin(index),SLOT_SIZE).has_point(point):
				cursor = index
				_confirm(index)
				get_viewport().set_input_as_handled()
				break
	if not event is InputEventKey or not event.pressed:
		return
	var direction := [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT].find(event.physical_keycode)
	if direction>=0:
		if not explaining:
			var level := [2,4,8].find(economy.rucksack.capacity)
			cursor = SPOTS[cursor][2][level+direction*3+(12 if marked>=0 else 0)]
			art.queue_redraw()
	elif event.echo:
		return
	elif event.is_action_pressed("backpack"):
		_close()
	elif event.is_action_pressed("ui_cancel"):
		if explaining:
			explaining = false
			detail.text = HELP
		elif marked>=0:
			marked = -1
			art.queue_redraw()
		else:
			_close()
	elif event.is_action_pressed("ui_accept"):
		if not explaining:
			_confirm(cursor)
	elif event.is_action_pressed("use_tool"):
		_explain()
	elif event.physical_keycode!=KEY_F1:
		return
	get_viewport().set_input_as_handled()

func _close() -> void:
	panel.hide()
	_restore_world()
	set_process_input(false)

func _restore_world() -> void:
	economy.world.hud.visible = hud_visible
	economy.world.day_cycle.clock_label.visible = clock_visible
	get_tree().paused = false

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible and is_instance_valid(economy.world.hud):
		_restore_world()

extends CanvasLayer
## Wooden toolbox skin. Directional links still follow PS1 storage_swap.c.
const TOOLBOX_SIZE := ToolboxStyle.FRAME_SIZE
const SLOT_SIZE := ToolboxStyle.SLOT_SIZE
const SLOT_PITCH := ToolboxStyle.SLOT_PITCH
const ToolboxStyle := preload("res://game/items/toolbox_style.gd")
const SLOT_LINKS := [
	[9,9,9,9,9,9,2,4,4,1,1,1,0,0,5,0,0,5,2,4,4,1,1,1],
	[10,10,14,10,10,5,0,0,0,2,2,2,1,1,5,1,1,5,0,0,0,2,2,2],
	[11,11,15,11,11,6,1,1,1,0,3,3,2,2,6,2,2,6,1,1,1,0,3,3],
	[0,12,16,0,12,7,0,2,2,0,4,4,0,3,7,0,3,7,0,2,2,0,4,4],
	[0,13,17,0,13,8,0,3,3,0,0,0,0,4,8,0,4,8,0,3,3,0,0,0],
	[0,0,1,0,0,10,0,0,0,0,0,6,0,0,1,0,0,1,0,0,0,0,0,6],
	[0,0,2,0,0,11,0,0,5,0,0,7,0,0,2,0,0,2,0,0,5,0,0,7],
	[0,0,3,0,0,12,0,0,6,0,0,8,0,0,3,0,0,3,0,0,6,0,0,8],
	[0,0,4,0,0,13,0,0,7,0,0,0,0,0,4,0,0,4,0,0,7,0,0,0],
	[0,0,0,0,0,0,11,13,13,10,10,10,9,9,14,9,9,14,11,13,13,10,10,10],
	[1,1,5,1,1,14,9,9,9,11,11,11,10,10,14,10,10,14,9,9,9,11,11,11],
	[2,2,6,2,2,15,10,10,10,9,12,12,11,11,15,11,11,15,10,10,10,9,12,12],
	[0,3,7,0,3,16,0,11,11,0,13,13,0,12,16,0,12,16,0,11,11,0,13,13],
	[0,4,8,0,4,17,0,12,12,9,9,9,0,13,17,0,13,17,0,12,12,9,9,9],
	[0,0,10,0,0,1,0,0,9,0,0,15,0,0,10,0,0,10,0,0,9,0,0,15],
	[0,0,11,0,0,2,0,0,14,0,0,16,0,0,11,0,0,11,0,0,14,0,0,16],
	[0,0,12,0,0,3,0,0,15,0,0,17,0,0,12,0,0,12,0,0,15,0,0,17],
	[0,0,13,0,0,4,0,0,16,0,0,9,0,0,13,0,0,13,0,0,16,0,0,9],
]

var economy
var actions
var panel: ColorRect
var frame: Control
var art: Control
var capacity_label: Label
var equipped_label: Label
var carried_label: Label
var detail: Label
var brass_pin: Texture2D
var labels: Array[Dictionary] = []
var seed_labels: Array[Label] = []
var styles := {}
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
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(frame)
	art = Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.draw.connect(_draw_art)
	frame.add_child(art)
	styles = ToolboxStyle.materials()
	brass_pin = ToolboxStyle.brass_pin()

	var regular := ToolboxStyle.font(font)
	var strong := ToolboxStyle.font(font,700)
	_add_label("农场工具箱",Vector2(41,30),21,ToolboxStyle.HEADING,strong)
	capacity_label = _add_label("",Vector2(355,38),11,Color("#422a20"),strong)
	for caption in [["手持工具",Vector2(37,90)],["手持物品",Vector2(37,179)],
			["工具",Vector2(195,90)],["物品",Vector2(195,179)]]:
		_add_label(caption[0],caption[1],12,Color("#f5d3a3"),strong)
	equipped_label = _add_label("",Vector2(99,126),11,ToolboxStyle.INK,regular)
	carried_label = _add_label("",Vector2(99,214),11,ToolboxStyle.MUTED_INK,regular)
	detail = _add_label("",Vector2(39,282),10,ToolboxStyle.INK,regular)
	for label in [equipped_label,carried_label,detail]:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in 9:
		var label := ToolboxStyle.quantity_label(strong)
		panel.add_child(label)
		seed_labels.append(label)

	panel.hide()
	panel.resized.connect(_layout)
	set_process_input(false)
	icons.resize(SLOT_LINKS.size())
	_layout()
	_refresh()

func _extra_row() -> int:
	return SLOT_PITCH if economy.rucksack.capacity==8 else 0

func _layout() -> void:
	var extra := _extra_row()
	frame.size = TOOLBOX_SIZE+Vector2(0,2*extra)
	var amount := minf(panel.size.x*0.92/frame.size.x,panel.size.y*0.90/frame.size.y)
	frame.scale = Vector2.ONE*amount
	frame.position = ((panel.size-frame.size*amount)*0.5).floor()
	for entry in labels:
		var point: Vector2 = entry.point
		if point.y>=277:
			point.y += 2*extra
		elif point.y>=179:
			point.y += extra
		_place_text(entry.label,point,entry.size,amount)
	equipped_label.size.x = roundi(64*amount)
	carried_label.size.x = equipped_label.size.x
	detail.size.x = roundi(394*amount)
	for index in seed_labels.size():
		var label := seed_labels[index]
		_place_text(label,_slot_origin(index)+ToolboxStyle.QUANTITY_ORIGIN,ToolboxStyle.QUANTITY_FONT_SIZE,amount)
		label.size.x = roundi((SLOT_SIZE.x-2.0*ToolboxStyle.QUANTITY_ORIGIN.x)*amount)
	art.queue_redraw()

func _place_text(label: Label, point: Vector2, font_size: int, amount: float) -> void:
	# Draw text at its final size, outside the scaled pixel-art layer.
	label.position = (frame.position+point*amount).round()
	label.add_theme_font_size_override("font_size",maxi(1,roundi(font_size*amount)))

func _make_label(value: String, ink: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_override("font",font)
	label.add_theme_color_override("font_color",ink)
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return label

func _add_label(value: String, point: Vector2, size: int, ink: Color, font: Font) -> Label:
	var label := _make_label(value,ink,font)
	labels.append({"label":label,"point":point,"size":size})
	return label

func open() -> void:
	if get_tree().paused or actions.busy() or actions.player.input_locked or not actions.player.is_on_floor():
		return
	marked = -1
	cursor = 0
	_hide_detail()
	hud_visible = economy.world.hud.visible
	clock_visible = economy.world.day_cycle.clock_label.visible
	economy.world.hud.hide()
	economy.world.day_cycle.clock_label.hide()
	if frame.size.y!=TOOLBOX_SIZE.y+2*_extra_row():
		_layout()
	panel.show()
	economy.world.sound.cue("menu")
	get_tree().paused = true
	set_process_input(true)
	_refresh()

func _slot_visible(index: int) -> bool:
	return index in [0,9] or ((index-1)%9)<economy.rucksack.capacity

func _slot_origin(index: int) -> Vector2:
	var item_row := index>=9
	var start_y := 199+_extra_row() if item_row else 111
	if index in [0,9]:
		return Vector2(37,start_y)
	var slot := index-10 if item_row else index-1
	return Vector2(195+(slot%ToolboxStyle.SLOT_COLUMNS)*SLOT_PITCH,start_y+(slot/ToolboxStyle.SLOT_COLUMNS as int)*SLOT_PITCH)

func _refresh() -> void:
	capacity_label.text = "背包  %d 格" % economy.rucksack.capacity
	equipped_label.text = _name(_item(0),true).get_slice(" · ",0)
	carried_label.text = _name(_item(9),false)
	for index in SLOT_LINKS.size():
		if _slot_visible(index):
			icons[index] = _icon(_item(index),index<9)
	for index in seed_labels.size():
		var label := seed_labels[index]
		var item := _item(index)
		label.visible = _slot_visible(index) and actions.seed_catalogue.has(str(item))
		if label.visible:
			label.text = "×%d" % economy.count(item)
	art.queue_redraw()

func _draw_art() -> void:
	var extra := _extra_row()
	var tall := 2*extra
	_draw_box("shell",Rect2(Vector2.ZERO,frame.size))
	_draw_box("rim",Rect2(1,1,470,333+tall))
	_draw_box("wood",Rect2(12,12,448,309+tall))
	_draw_box("header",Rect2(22,23,428,49))
	_draw_box("badge",Rect2(343,34,89,25))
	if brass_pin!=null:
		for point in [Vector2(26,28),Vector2(441,28),Vector2(26,307+tall),Vector2(441,307+tall)]:
			art.draw_texture(brass_pin,point)
	_draw_box("tray",Rect2(25,82,146,184+tall))
	_draw_box("tray",Rect2(178,82,269,184+tall))
	if explaining:
		_draw_box("help",Rect2(25,277+tall,422,28))
	for index in SLOT_LINKS.size():
		if not _slot_visible(index):
			continue
		var point := _slot_origin(index)
		var icon := icons[index]
		_draw_box("filled" if icon!=null else "empty",Rect2(point,SLOT_SIZE))
		if icon!=null:
			var picture := ToolboxStyle.icon_rect(icon)
			picture.position += point
			art.draw_texture_rect(icon,picture,false)
		if index==marked:
			_draw_box("marked",Rect2(point,SLOT_SIZE).grow(-4))
		if index==cursor:
			_draw_box("focus",Rect2(point,SLOT_SIZE))

func _draw_box(id: String, bounds: Rect2) -> void:
	art.draw_style_box(styles[id],bounds)

func _hide_detail() -> void:
	explaining = false
	detail.hide()
	art.queue_redraw()


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
	detail.text = "   ·   ".join(lines)
	detail.show()
	explaining = true
	art.queue_redraw()


func _item(index: int) -> int:
	if index<9:
		return economy.rucksack.tool_at(actions,index)
	return actions.carried_id if index==9 else economy.rucksack.items[index-10]

func _put(index: int, item: int) -> void:
	if index<9:
		economy.rucksack.put_tool(actions,index,item)
	elif index==9:
		actions.carried_id = item
		actions.update_held(false)
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
		for index in SLOT_LINKS.size():
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
			var previous := cursor
			cursor = SLOT_LINKS[cursor][level+direction*3+(12 if marked>=0 else 0)]
			if cursor!=previous:
				economy.world.sound.cue("cursor")
			art.queue_redraw()
	elif event.echo:
		return
	elif event.is_action_pressed("backpack"):
		_close()
	elif event.is_action_pressed("ui_cancel"):
		if explaining:
			_hide_detail()
		elif marked>=0:
			marked = -1
			art.queue_redraw()
		else:
			_close()
	elif event.is_action_pressed("ui_accept"):
		if not explaining:
			economy.world.sound.cue("confirm")
			_confirm(cursor)
	elif event.is_action_pressed("use_tool"):
		_explain()
	elif event.physical_keycode!=KEY_F1:
		return
	get_viewport().set_input_as_handled()

func _close() -> void:
	economy.world.sound.cue("cancel")
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

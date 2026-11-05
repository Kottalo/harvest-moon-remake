extends CanvasLayer
## Wooden toolbox skin. Directional links still follow PS1 storage_swap.c.
const TOOLBOX_SIZE := Vector2(472,335)
const SLOT_SIZE := Vector2(52,52)
const SLOT_PITCH := 62
const BRASS_PIN := "res://game/items/toolbox_brass_pin.svg"
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

const HELP_KEYS := [
	["↑↓←→","移动",39,50], ["Z","交换",129,18],
	["C","查看",185,18], ["X","关闭",243,18],
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
var help_labels: Array[Label] = []
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
	_setup_styles()
	brass_pin = _load_brass_pin()

	var regular := SystemFont.new()
	var families := PackedStringArray(["Noto Sans SC"])
	if font is SystemFont:
		families.append_array(font.font_names)
	regular.font_names = families
	var strong := regular.duplicate() as SystemFont
	strong.font_weight = 700
	_add_label("农场工具箱",Vector2(41,30),21,Color("#fff1ce"),strong)
	capacity_label = _add_label("",Vector2(355,38),11,Color("#422a20"),strong)
	for caption in [["手持工具",Vector2(37,90)],["手持物品",Vector2(37,179)],
			["工具",Vector2(195,90)],["物品",Vector2(195,179)]]:
		_add_label(caption[0],caption[1],12,Color("#f5d3a3"),strong)
	equipped_label = _add_label("",Vector2(99,126),11,Color("#fff0d7"),regular)
	carried_label = _add_label("",Vector2(99,214),11,Color("#eac7a1"),regular)
	for key in HELP_KEYS:
		help_labels.append(_add_label(key[0],Vector2(key[2]+5,282),10,Color("#352419"),strong))
		help_labels.append(_add_label(key[1],Vector2(key[2]+key[3]+5,282),10,Color("#fff0d7"),regular))
	detail = _add_label("",Vector2(39,282),10,Color("#fff0d7"),regular)
	for label in [equipped_label,carried_label,detail]:
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for index in 9:
		seed_labels.append(_make_label("",Color("#3d291f"),strong))

	panel.hide()
	panel.resized.connect(_layout)
	set_process_input(false)
	icons.resize(SLOT_LINKS.size())
	_layout()
	_refresh()

func _load_brass_pin() -> Texture2D:
	if ResourceLoader.exists(BRASS_PIN):
		return load(BRASS_PIN)
	var pin := Image.new()
	if pin.load_svg_from_buffer(FileAccess.get_file_as_bytes(BRASS_PIN))==OK:
		return ImageTexture.create_from_image(pin)
	return null

func _setup_styles() -> void:
	_style("shell",Color("#38251b"),12)
	_style("rim",Color.TRANSPARENT,12,Color("#c18550"),2)
	_style("wood",Color("#9b603b"),8,Color("#75462d"),1)
	_style("header",Color("#67402a"),6,Color("#d39760"),1)
	_style("badge",Color("#d6a66a"),4,Color("#69462f"),1)
	_style("tray",Color("#4c3024"),6,Color("#c99565"),1)
	_style("filled",Color("#b78357"),5,Color("#d19d68"),1)
	_style("empty",Color("#80543a"),5,Color("#ac7955"),1)
	_style("focus",Color.TRANSPARENT,5,Color("#ffe1a2"),2)
	_style("marked",Color.TRANSPARENT,4,Color("#ecac64"),2)
	_style("help",Color("#68412b"),4)
	_style("key",Color("#d4a471"),4)

func _style(id: String, fill: Color, radius: int, edge := Color.TRANSPARENT, width := 0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_corner_radius_all(radius)
	style.set_border_width_all(width)
	styles[id] = style

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
		_place_text(label,_slot_origin(index)+Vector2(18,37),10,amount)
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
	_show_help()
	hud_visible = economy.world.hud.visible
	clock_visible = economy.world.day_cycle.clock_label.visible
	economy.world.hud.hide()
	economy.world.day_cycle.clock_label.hide()
	if frame.size.y!=TOOLBOX_SIZE.y+2*_extra_row():
		_layout()
	panel.show()
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
	return Vector2(195+(slot%4)*SLOT_PITCH,start_y+(slot/4 as int)*SLOT_PITCH)

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
	_draw_box("help",Rect2(25,277+tall,422,28))
	if not explaining:
		for key in HELP_KEYS:
			_draw_box("key",Rect2(key[2],282+tall,key[3],16))
	for index in SLOT_LINKS.size():
		if not _slot_visible(index):
			continue
		var point := _slot_origin(index)
		var icon := icons[index]
		_draw_box("filled" if icon!=null else "empty",Rect2(point,SLOT_SIZE))
		if icon!=null:
			var picture_size := icon.get_size()*1.25
			art.draw_texture_rect(icon,Rect2(point+(SLOT_SIZE-picture_size)*0.5,picture_size),false)
		if index==marked:
			_draw_box("marked",Rect2(point,SLOT_SIZE).grow(-4))
		if index==cursor:
			_draw_box("focus",Rect2(point,SLOT_SIZE))

func _draw_box(id: String, bounds: Rect2) -> void:
	art.draw_style_box(styles[id],bounds)

func _show_help() -> void:
	explaining = false
	detail.hide()
	for label in help_labels:
		label.show()
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
	lines.append("X 返回")
	detail.text = "   ·   ".join(lines)
	detail.show()
	for label in help_labels:
		label.hide()
	explaining = true
	art.queue_redraw()


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
			cursor = SLOT_LINKS[cursor][level+direction*3+(12 if marked>=0 else 0)]
			art.queue_redraw()
	elif event.echo:
		return
	elif event.is_action_pressed("backpack"):
		_close()
	elif event.is_action_pressed("ui_cancel"):
		if explaining:
			_show_help()
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

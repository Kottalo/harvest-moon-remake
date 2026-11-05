extends CanvasLayer
## PS1 storage_swap.c positions and D-pad links, including marked-slot mode.
const Frame := preload("res://game/rendering/source_window.gd")
const SCALE := 2.6
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

var economy
var actions
var panel: ColorRect
var frame: Control
var detail: Label
var buttons: Array[Button] = []
var cursor := 0
var marked := -1

func setup(owner_economy, font: Font) -> void:
	economy = owner_economy
	actions = economy.world.player.actions
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = ColorRect.new()
	panel.color = Color(0,0,0,0.55)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame = Control.new()
	frame.custom_minimum_size = Vector2(270,186)*SCALE
	center.add_child(frame)
	for rect: Rect2 in [Rect2(0,0,96,74),Rect2(96,0,174,74),Rect2(0,74,96,74),Rect2(96,74,174,74)]:
		var box := Frame.new()
		box.position = rect.position*SCALE
		box.size = rect.size*SCALE
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(box)
	for caption in [["手持工具",Vector2(7,3)],["背包工具",Vector2(101,3)],["手持物品",Vector2(7,77)],["背包物品",Vector2(101,77)]]:
		_label(caption[0],caption[1],font,16)
	for index in SPOTS.size():
		var cell := Button.new()
		cell.position = Vector2(SPOTS[index][0]-25,SPOTS[index][1]-11)*SCALE
		cell.size = Vector2(29,28)*SCALE
		cell.add_theme_font_override("font",font)
		cell.add_theme_constant_override("icon_max_width",46)
		cell.expand_icon = true
		cell.focus_entered.connect(_focus.bind(index))
		cell.pressed.connect(_confirm.bind(index))
		frame.add_child(cell)
		buttons.append(cell)
	detail = _label("",Vector2(1,151),font,19)
	_label("方向键选择 · Z 标记／交换 · X 取消 · 空格关闭",Vector2(1,168),font,16)
	for label in [detail,frame.get_child(frame.get_child_count()-1)]:
		label.add_theme_color_override("font_color",Color.WHITE)
	panel.hide()
	set_process_input(false)

func _label(value: String, point: Vector2, font: Font, text_size: int) -> Label:
	var label := Label.new()
	label.position = point*SCALE
	label.text = value
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",text_size)
	label.add_theme_color_override("font_color",Color("#223344"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(label)
	return label

func open() -> void:
	if get_tree().paused or actions.busy() or actions.player.input_locked or not actions.player.is_on_floor():
		return
	marked = -1
	cursor = 0
	panel.show()
	get_tree().paused = true
	set_process_input(true)
	_refresh()
	buttons[0].grab_focus()

func _refresh() -> void:
	var capacity: int = economy.rucksack.capacity
	for index in buttons.size():
		var cell := buttons[index]
		cell.visible = index in [0,9] or ((index-1)%9)<capacity
		if not cell.visible:
			continue
		var item := _item(index)
		cell.icon = _icon(item,index<9)
		cell.text = ""
		if index==marked:
			cell.text = "✓"
		elif item==0:
			cell.text = "—"
		elif actions.seed_catalogue.has(str(item)):
			cell.text = str(economy.count(item))
		elif cell.icon==null:
			cell.text = str(item)
		cell.tooltip_text = _name(item,index<9)
	_focus(cursor)

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
	var picture: Texture2D
	if tool_row:
		picture = actions.tool_picture(34,item) if actions.seed_catalogue.has(str(item)) else actions.tool_picture(item,-1,int(economy.levels.get(item,0)))
	else:
		picture = actions.item_picture(item)
	return actions.menu_icon(picture)

func _focus(index: int) -> void:
	cursor = index
	detail.text = "%s    背包每排 %d 格" % [_name(_item(index),index<9),economy.rucksack.capacity]

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
	if not event is InputEventKey or not event.pressed:
		return
	var direction := [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT].find(event.physical_keycode)
	if direction>=0:
		var capacity: int = economy.rucksack.capacity
		var level := [2,4,8].find(capacity)
		var next: int = SPOTS[cursor][2][level+direction*3+(12 if marked>=0 else 0)]
		buttons[next].grab_focus()
		get_viewport().set_input_as_handled()
	elif not event.echo and event.is_action_pressed("backpack"):
		_close()
		get_viewport().set_input_as_handled()
	elif not event.echo and event.is_action_pressed("ui_cancel"):
		if marked>=0:
			marked = -1
			_refresh()
		else:
			_close()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode==KEY_F1:
		get_viewport().set_input_as_handled()

func _close() -> void:
	panel.hide()
	get_tree().paused = false
	set_process_input(false)

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible:
		get_tree().paused = false

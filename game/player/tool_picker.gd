extends CanvasLayer
## Farmhouse tool storage, using the source mark-and-swap interaction.
const ToolboxStyle := preload("res://game/items/toolbox_style.gd")
# scene_camera_transition turns the lid 0x20 per farm tick, up to 0x280.
const LID_ANGLE := -0x280 * TAU / 4096.0
const LID_TIME := 20.0 / 30.0
const Rucksack := preload("res://game/items/rucksack.gd")
const PAGE_COUNT := Rucksack.TOOLBOX_PAGES
const PAGE_SIZE := Rucksack.TOOLBOX_PAGE_SIZE
const CURSOR_KEYS := [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]
# item_storage.c item_markers: up/down/left/right, each for 2/4/8 bag slots.
const CURSOR_LINKS := [
	[13,13,13,9,9,5,2,4,4,1,1,1],
	[13,13,13,9,9,5,0,0,0,2,2,2],
	[14,14,14,10,10,6,1,1,1,0,3,3],
	[0,15,15,0,11,7,0,2,2,0,4,4],
	[0,16,16,0,12,8,0,3,3,0,0,0],
	[0,0,1,0,0,9,0,0,0,0,0,6],
	[0,0,2,0,0,10,0,0,5,0,0,7],
	[0,0,3,0,0,11,0,0,6,0,0,8],
	[0,0,4,0,0,12,0,0,7,0,0,0],
	[1,1,5,13,13,13,12,12,12,10,10,10],
	[2,2,6,14,14,14,9,9,9,11,11,11],
	[2,3,7,15,15,15,10,10,10,12,12,12],
	[2,4,8,16,16,16,11,11,11,9,9,9],
	[9,9,9,1,1,1,16,16,16,14,14,14],
	[10,10,10,2,2,2,13,13,13,15,15,15],
	[11,11,11,2,3,3,14,14,14,16,16,16],
	[12,12,12,2,4,4,15,15,15,13,13,13],
]

var actions
var rucksack: Rucksack
var sound: Callable
var page_label: Label
var held_slot: Button
var bag_slots: Array[Button] = []
var seed_count: Callable
var storage_slots: Array[Button] = []
var marked: Button
var marker: Panel
var opened_tool := 0
var gameplay_hud: Label
var clock_label: Label
var panel: ColorRect
var shell: PanelContainer
var tabs: TabContainer
var title: Label
var tooltip: PanelContainer
var tooltip_label: Label
var tooltip_slot: Button
var styles: Dictionary
var strong_font: Font
var hud_visible := false
var clock_visible := false
var owns_pause := false
var lid: Node3D


func setup(player_actions, font: Font, available_seeds: Callable,
		hud: Label, clock: Label, bag, play_sound: Callable) -> void:
	actions = player_actions
	rucksack = bag
	sound = play_sound
	seed_count = available_seeds
	gameplay_hud = hud
	clock_label = clock
	styles = ToolboxStyle.materials()
	strong_font = ToolboxStyle.font(font,700)
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

	panel = ColorRect.new()
	panel.color = Color(0,0,0,0.55)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell = _wood_panel(panel,"工具箱外框",styles.shell,12)
	shell.custom_minimum_size = ToolboxStyle.FRAME_SIZE
	panel.resized.connect(_layout)
	shell.minimum_size_changed.connect(_layout)
	var shell_style := shell.get_theme_stylebox("panel") as StyleBoxFlat
	shell_style.border_color = styles.rim.border_color
	shell_style.set_border_width_all(2)
	var wood := _wood_panel(shell,"木质内框",styles.wood,13)
	wood.theme = Theme.new()
	wood.theme.default_font = ToolboxStyle.font(font)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",10)
	wood.add_child(rows)

	var header := _wood_panel(rows,"标题木板",styles.header,12)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation",12)
	header.add_child(heading)
	var brass := ToolboxStyle.brass_pin()
	_add_pin(heading,brass)
	title = _label(heading,"工具箱",25,ToolboxStyle.HEADING)
	title.add_theme_font_override("font",strong_font)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.name = "CloseButton"
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(32,28)
	_style_button(close,styles.key)
	close.pressed.connect(_close)
	heading.add_child(close)
	_add_pin(heading,brass)

	# item_status_draw: the held tool and rucksack are above the four-by-two storage page.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",10)
	rows.add_child(top)
	var equipped := _tray(top,"手持工具")
	equipped.custom_minimum_size.x = 114
	held_slot = _slot(equipped,0)
	var bag_tools := _tray(top,"背包工具")
	bag_tools.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bag_grid := _grid()
	bag_tools.add_child(bag_grid)
	for index in PAGE_SIZE:
		bag_slots.append(_slot(bag_grid,index+1))
	var storage := _tray(rows,"箱内工具")
	var shelf := HBoxContainer.new()
	# Match the start of the rucksack grid above the storage grid.
	shelf.add_theme_constant_override("separation",28)
	storage.add_child(shelf)
	var pager := HBoxContainer.new()
	pager.custom_minimum_size.x = 114
	pager.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	shelf.add_child(pager)
	_page_button(pager,"‹",-1)
	page_label = _label(pager,"",14,ToolboxStyle.INK)
	_page_button(pager,"›",1)
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	shelf.add_child(tabs)

	tooltip = _wood_panel(panel,"物品提示",styles.badge,8)
	tooltip.theme = wood.theme
	tooltip.z_index = 1
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_label = _label(tooltip,"",14,ToolboxStyle.DARK_INK)
	tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.hide()

	marker = Panel.new()
	marker.name = "MarkedSlot"
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_theme_stylebox_override("panel",styles.marked)
	panel.add_child(marker)
	marker.hide()

	panel.hide()
	set_process_input(false)


func _layout() -> void:
	var bounds := shell.get_combined_minimum_size()
	var zoom := minf(panel.size.x*0.92/bounds.x,panel.size.y*0.90/bounds.y)
	if zoom<=0:
		return
	shell.size = bounds
	shell.scale = Vector2.ONE*zoom
	shell.position = ((panel.size-bounds*zoom)*0.5).floor()


func _tray(parent: Control, caption: String) -> VBoxContainer:
	var tray := _wood_panel(parent,caption,styles.tray,9)
	var content := VBoxContainer.new()
	tray.add_child(content)
	_label(content,caption,14,ToolboxStyle.HEADING)
	return content


func _page_button(parent: Control, glyph: String, step: int) -> void:
	var button := Button.new()
	button.text = glyph
	button.custom_minimum_size = Vector2(23,26)
	button.focus_mode = Control.FOCUS_NONE
	_style_button(button,styles.key)
	button.pressed.connect(_change_page.bind(step))
	parent.add_child(button)


func _change_page(step: int) -> void:
	var slot := _cursor_index()
	_set_page(tabs.current_tab+step)
	_focus_slot_index(slot)
	if slot<Rucksack.TOOLBOX_FIRST_SLOT:
		sound.call("cursor")


func _set_page(page: int) -> void:
	tabs.current_tab = posmod(page,PAGE_COUNT)
	_update_page_label()


func _update_page_label() -> void:
	page_label.text = "%d / %d" % [tabs.current_tab+1,PAGE_COUNT]


func _padded(style: StyleBoxFlat, padding: int) -> StyleBoxFlat:
	var box := style.duplicate() as StyleBoxFlat
	box.set_content_margin_all(padding)
	return box


func _wood_panel(parent: Control, label: String, style: StyleBoxFlat, padding: int) -> PanelContainer:
	var node := PanelContainer.new()
	node.name = label
	node.add_theme_stylebox_override("panel",_padded(style,padding))
	parent.add_child(node)
	return node


func _label(parent: Control, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	parent.add_child(label)
	return label


func _add_pin(parent: Control, texture: Texture2D) -> void:
	var pin := TextureRect.new()
	pin.texture = texture
	pin.custom_minimum_size = Vector2(7,7)
	pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(pin)


func _style_button(button: Button, normal: StyleBoxFlat) -> void:
	button.add_theme_stylebox_override("normal",normal)
	button.add_theme_stylebox_override("hover",styles.badge)
	button.add_theme_stylebox_override("pressed",styles.badge)
	button.add_theme_stylebox_override("focus",styles.focus)
	button.add_theme_stylebox_override("disabled",styles.empty)
	button.add_theme_color_override("font_color",ToolboxStyle.DARK_INK)
	button.add_theme_color_override("font_focus_color",ToolboxStyle.DARK_INK)
	button.add_theme_color_override("font_hover_color",ToolboxStyle.DARK_INK)
	button.add_theme_color_override("font_pressed_color",ToolboxStyle.DARK_INK)
	button.add_theme_color_override("font_disabled_color",ToolboxStyle.MUTED_INK)


func open(toolbox_lid: Node3D = null) -> void:
	if get_tree().paused or not actions.can_select_tool():
		return
	if storage_slots.is_empty():
		for page in PAGE_COUNT:
			var grid := _grid()
			tabs.add_child(grid)
			for slot in PAGE_SIZE:
				storage_slots.append(_slot(grid,Rucksack.TOOLBOX_FIRST_SLOT+page*PAGE_SIZE+slot))
	rucksack.sync_toolbox(actions,seed_count)
	_refresh_slots()
	opened_tool = rucksack.active_tool(actions)
	tabs.current_tab = 0
	_update_page_label()
	hud_visible = gameplay_hud.visible
	clock_visible = clock_label.visible
	gameplay_hud.hide()
	clock_label.hide()
	get_tree().paused = true
	owns_pause = true
	set_process_input(true)
	lid = toolbox_lid
	if is_instance_valid(lid):
		await _move_lid(LID_ANGLE)
		if not is_instance_valid(lid):
			_restore_world()
			return
	panel.show()
	_layout()
	sound.call("menu")
	held_slot.grab_focus()


func _move_lid(angle: float) -> void:
	var motion := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	motion.tween_property(lid,"rotation:z",angle,LID_TIME)
	await motion.finished


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = ToolboxStyle.SLOT_COLUMNS
	var spacing := ToolboxStyle.SLOT_PITCH-int(ToolboxStyle.SLOT_SIZE.x)
	grid.add_theme_constant_override("h_separation",spacing)
	grid.add_theme_constant_override("v_separation",spacing)
	return grid


func _slot(parent: Container, index: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = ToolboxStyle.SLOT_SIZE
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(button,_padded(styles.filled,3))
	var picture := TextureRect.new()
	picture.name = "Icon"
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(picture)
	var quantity := ToolboxStyle.quantity_label(strong_font)
	button.add_child(quantity)
	quantity.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	quantity.offset_left = ToolboxStyle.QUANTITY_ORIGIN.x
	quantity.offset_top = ToolboxStyle.QUANTITY_ORIGIN.y - ToolboxStyle.SLOT_SIZE.y
	quantity.offset_right = -3
	quantity.offset_bottom = -2
	button.set_meta("slot",index)
	button.mouse_entered.connect(_show_tooltip.bind(button))
	button.mouse_exited.connect(_hide_tooltip.bind(button))
	button.focus_entered.connect(_focus_slot.bind(button))
	button.focus_exited.connect(_hide_tooltip.bind(button))
	button.pressed.connect(_select.bind(button))
	parent.add_child(button)
	return button


func _refresh_slots() -> void:
	_set_slot(held_slot,rucksack.active_tool(actions))
	for index in bag_slots.size():
		var button := bag_slots[index]
		button.visible = index<rucksack.capacity
		_set_slot(button,rucksack.tools[index] if button.visible else 0)
	for index in storage_slots.size():
		_set_slot(storage_slots[index],rucksack.toolbox[index])


func _set_slot(button: Button, item: int) -> void:
	var seed: Dictionary = actions.seed_catalogue.get(str(item),{})
	button.set_meta("item",item)
	button.disabled = item!=0 and seed.is_empty() and not actions.owns_tool(item)
	button.add_theme_stylebox_override("normal",styles.empty if item==0 else styles.filled)
	# A child label overlays the slot without changing the button's minimum size.
	var quantity := button.get_node("Quantity") as Label
	quantity.text = "" if seed.is_empty() else "×%d" % seed_count.call(item)
	var tool_name: String = actions.TOOL_NAMES[actions.TOOL_IDS.find(item)] if item!=0 and seed.is_empty() else seed.get("name","")
	button.set_meta("item_name",tool_name)
	var picture := button.get_node("Icon") as TextureRect
	picture.texture = null if item==0 else actions.menu_icon(actions.tool_picture(item) if seed.is_empty() else actions.tool_picture(34,item))
	if picture.texture != null:
		var rect := ToolboxStyle.icon_rect(picture.texture)
		picture.position = rect.position
		picture.size = rect.size
	picture.modulate.a = 0.46 if button.disabled else 1.0


func _focus_slot(slot: Button) -> void:
	if panel.visible:
		_show_tooltip(slot)
		sound.call("cursor")


func _show_tooltip(slot: Button) -> void:
	var item_name: String = slot.get_meta("item_name","")
	if item_name.is_empty():
		return
	tooltip_slot = slot
	_place_tooltip.call_deferred(slot,item_name)


func _place_tooltip(slot: Button, item_name: String) -> void:
	if tooltip_slot != slot or not slot.is_visible_in_tree():
		return
	tooltip_label.text = item_name
	var tip_size := tooltip.get_combined_minimum_size()
	tooltip.size = tip_size
	var rect := slot.get_global_rect()
	var x := clampf(rect.get_center().x - tip_size.x / 2.0,0.0,maxf(0.0,panel.size.x - tip_size.x))
	tooltip.position = Vector2(x,maxf(0.0,rect.position.y - tip_size.y - 4.0))
	tooltip.show()


func _hide_tooltip(slot: Button) -> void:
	if tooltip_slot == slot:
		tooltip_slot = null
		tooltip.hide()


func _select(slot: Button) -> void:
	if slot.disabled:
		return
	if marked==null:
		marked = slot
		marker.reparent(slot,false)
		marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		marker.show()
	else:
		var from := int(marked.get_meta("slot"))
		var to := 0 if marked==slot else int(slot.get_meta("slot"))
		if from==to or (to==0 and held_slot.disabled):
			return
		var item := rucksack.tool_at(actions,from)
		var other := rucksack.tool_at(actions,to)
		rucksack.put_tool(actions,from,other)
		rucksack.put_tool(actions,to,item)
		_clear_mark()
		_refresh_slots()
		_hide_tooltip(tooltip_slot)
		_show_tooltip(slot)
	sound.call("confirm")


func _clear_mark() -> void:
	marked = null
	marker.hide()


func _cursor_index() -> int:
	var focus := get_viewport().gui_get_focus_owner()
	var slot := int(focus.get_meta("slot",0)) if focus!=null else 0
	if slot>=Rucksack.TOOLBOX_FIRST_SLOT:
		return Rucksack.TOOLBOX_FIRST_SLOT+(slot-Rucksack.TOOLBOX_FIRST_SLOT)%PAGE_SIZE
	return slot


func _focus_slot_index(slot: int) -> void:
	if slot==0:
		held_slot.grab_focus()
	elif slot<Rucksack.TOOLBOX_FIRST_SLOT:
		bag_slots[slot-1].grab_focus()
	else:
		storage_slots[tabs.current_tab*PAGE_SIZE+slot-Rucksack.TOOLBOX_FIRST_SLOT].grab_focus()


func _move_cursor(direction: int) -> void:
	var slot := _cursor_index()
	var level := [2,4,8].find(rucksack.capacity)
	if direction==2 and slot in [9,13]:
		_set_page(tabs.current_tab-1)
	elif direction==3 and slot in [12,16]:
		_set_page(tabs.current_tab+1)
	_focus_slot_index(CURSOR_LINKS[slot][direction*3+level])


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	if not panel.visible:
		get_viewport().set_input_as_handled()
		return
	var direction := CURSOR_KEYS.find(event.physical_keycode)
	if direction>=0:
		get_viewport().set_input_as_handled()
		_move_cursor(direction)
		return
	match event.physical_keycode:
		KEY_X, KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if event.echo:
				return
			if marked!=null:
				_clear_mark()
				sound.call("cancel")
			else:
				_close()
		KEY_I:
			get_viewport().set_input_as_handled()
			if not event.echo:
				_close()
		KEY_TAB:
			get_viewport().set_input_as_handled()
			if not event.echo:
				_change_page(-1 if event.shift_pressed else 1)
		KEY_F1:
			get_viewport().set_input_as_handled()


func _close() -> void:
	if panel.visible:
		sound.call("cancel")
		_clear_mark()
		_hide_tooltip(tooltip_slot)
		panel.hide()
		if is_instance_valid(lid):
			await _move_lid(0.0)
		_restore_world()
		var equipped := rucksack.active_tool(actions)
		if equipped!=0 and equipped!=opened_tool:
			actions.select_tool(actions.equipped,equipped if actions.equipped==34 else -1)


func _restore_world() -> void:
	owns_pause = false
	set_process_input(false)
	if is_instance_valid(lid):
		lid.rotation.z = 0.0
	lid = null
	if is_instance_valid(gameplay_hud):
		gameplay_hud.visible = hud_visible
	if is_instance_valid(clock_label):
		clock_label.visible = clock_visible
	get_tree().paused = false


func _exit_tree() -> void:
	if owns_pause:
		_restore_world()

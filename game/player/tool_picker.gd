extends CanvasLayer
## Farmhouse tool and seed selection. PlayerActions owns equipment and the show animation.
const ToolboxStyle := preload("res://game/items/toolbox_style.gd")

var actions
var seed_count: Callable
var choose_tool: Callable
var gameplay_hud: Label
var clock_label: Label
var panel: ColorRect
var tabs: TabContainer
var title: Label
var equipment: Label
var entries: Dictionary = {}
var styles: Dictionary
var hud_visible := false
var clock_visible := false


func setup(player_actions, font: Font, available_seeds: Callable, select_tool: Callable,
		hud: Label, clock: Label) -> void:
	actions = player_actions
	seed_count = available_seeds
	choose_tool = select_tool
	gameplay_hud = hud
	clock_label = clock
	styles = ToolboxStyle.materials()
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS

	panel = ColorRect.new()
	panel.color = Color(0,0,0,0.55)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var shell := _wood_panel(center,"工具箱外框",styles.shell,12)
	shell.custom_minimum_size.x = 740
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
	title.add_theme_font_override("font",ToolboxStyle.font(font,700))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tag := _wood_panel(heading,"装备铭牌",styles.badge,8)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	equipment = _label(tag,"",14,ToolboxStyle.DARK_INK)
	_add_pin(heading,brass)

	tabs = TabContainer.new()
	tabs.add_theme_stylebox_override("panel",_padded(styles.tray,12))
	tabs.add_theme_stylebox_override("tab_selected",_padded(styles.badge,8))
	tabs.add_theme_stylebox_override("tab_unselected",_padded(styles.header,8))
	tabs.add_theme_stylebox_override("tab_hovered",_padded(styles.wood,8))
	tabs.add_theme_stylebox_override("tab_focus",styles.focus)
	tabs.add_theme_color_override("font_selected_color",ToolboxStyle.DARK_INK)
	tabs.add_theme_color_override("font_unselected_color",ToolboxStyle.INK)
	tabs.add_theme_color_override("font_hovered_color",ToolboxStyle.HEADING)
	tabs.add_theme_constant_override("h_separation",5)
	rows.add_child(tabs)

	var footer := _wood_panel(rows,"操作说明",styles.help,7)
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation",8)
	footer.add_child(keys)
	for shortcut in [["↑↓←→","选择"],["Z","装备"],["Tab","换页"]]:
		_label(_wood_panel(keys,"键帽",styles.key,4),shortcut[0],11,ToolboxStyle.DARK_INK)
		var instruction := _label(keys,shortcut[1],12,ToolboxStyle.INK)
		instruction.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keys.add_child(spacer)
	var close := Button.new()
	close.text = "X  关闭"
	close.custom_minimum_size = Vector2(88,25)
	_style_button(close,styles.key)
	close.pressed.connect(_close)
	keys.add_child(close)

	panel.hide()
	set_process_input(false)


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
	button.add_theme_color_override("icon_disabled_color",Color(1,1,1,0.46))


func open() -> void:
	if get_tree().paused or not actions.can_select_tool():
		return
	if entries.is_empty():
		var tools := _add_tab("工具")
		for index in actions.TOOL_IDS.size():
			var tool: int = actions.TOOL_IDS[index]
			if tool != 34:
				_add_entry(tools,actions.TOOL_NAMES[index],tool)
		var seeds := _add_tab("种子")
		for key: String in actions.seed_catalogue:
			_add_entry(seeds,actions.seed_catalogue[key].name,34,int(key))
	for tool: int in actions.TOOL_IDS:
		if tool != 34:
			var button: Button = entries[tool]
			button.icon = actions.menu_icon(actions.tool_picture(tool))
			button.disabled = not actions.owns_tool(tool)
	for key: String in actions.seed_catalogue:
		var seed := int(key)
		entries[seed].text = "%s × %d" % [actions.seed_catalogue[key].name,seed_count.call(seed)]
	equipment.text = "已装备  " + actions.tool_name()
	var using_seeds: bool = actions.equipped == 34
	tabs.current_tab = 1 if using_seeds else 0
	hud_visible = gameplay_hud.visible
	clock_visible = clock_label.visible
	gameplay_hud.hide()
	clock_label.hide()
	panel.show()
	get_tree().paused = true
	set_process_input(true)
	_focus_tab(actions.selected_seed if using_seeds else actions.equipped)


func _add_tab(label: String) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = label
	grid.columns = 5
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	tabs.add_child(grid)
	return grid


func _add_entry(grid: GridContainer, label: String, tool: int, seed := -1) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(120,62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.add_theme_constant_override("icon_max_width",30)
	button.add_theme_font_size_override("font_size",13)
	_style_button(button,_padded(styles.filled,5))
	if seed != -1:
		button.icon = actions.menu_icon(actions.tool_picture(tool,seed))
	button.pressed.connect(_select.bind(tool,seed))
	grid.add_child(button)
	entries[seed if seed != -1 else tool] = button


func _select(tool: int, seed: int) -> void:
	_close()
	choose_tool.call(seed if seed!=-1 else tool)


func _focus_tab(preferred := 0) -> void:
	var grid := tabs.get_current_tab_control()
	var button: Button = entries.get(preferred)
	if button!=null and button.get_parent()==grid and not button.disabled:
		button.grab_focus()
		return
	for entry: Button in grid.get_children():
		if not entry.disabled:
			entry.grab_focus()
			return


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_I, KEY_X, KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close()
			KEY_TAB:
				get_viewport().set_input_as_handled()
				tabs.current_tab = 1 - tabs.current_tab
				_focus_tab()
			KEY_F1:
				get_viewport().set_input_as_handled()


func _close() -> void:
	if panel.visible:
		panel.hide()
		_restore_world()
		set_process_input(false)


func _restore_world() -> void:
	if is_instance_valid(gameplay_hud):
		gameplay_hud.visible = hud_visible
	if is_instance_valid(clock_label):
		clock_label.visible = clock_visible
	get_tree().paused = false


func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible:
		_restore_world()

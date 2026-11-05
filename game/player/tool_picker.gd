extends CanvasLayer
## Tool and seed selection. PlayerActions owns equipment and the show animation.
var actions
var seed_count: Callable
var choose_tool: Callable
var panel: ColorRect
var tabs: TabContainer
var title: Label
var entries: Dictionary = {}


func setup(player_actions, font: Font, available_seeds: Callable, select_tool: Callable) -> void:
	actions = player_actions
	seed_count = available_seeds
	choose_tool = select_tool
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = ColorRect.new()
	panel.color = Color(0.04,0.06,0.05,0.7)
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	panel.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.custom_minimum_size.x = 700
	frame.add_theme_font_override("font",font)
	frame.add_theme_font_size_override("font_size",18)
	center.add_child(frame)
	var margin := MarginContainer.new()
	for edge in ["top","bottom","left","right"]:
		margin.add_theme_constant_override("margin_" + edge,18)
	frame.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	margin.add_child(rows)
	title = Label.new()
	title.add_theme_font_size_override("font_size",22)
	rows.add_child(title)
	tabs = TabContainer.new()
	rows.add_child(tabs)
	var hint := Label.new()
	hint.text = "点击图标装备 · Tab 换页 · 方向键选择，Z 确认 · I / X 关闭"
	rows.add_child(hint)
	var close := Button.new()
	close.text = "返回游戏"
	close.pressed.connect(_close)
	rows.add_child(close)
	panel.hide()
	set_process_input(false)


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
			entries[tool].icon = actions.menu_icon(actions.tool_picture(tool))
			entries[tool].disabled = not actions.owns_tool(tool)
	for key: String in actions.seed_catalogue:
		var seed := int(key)
		entries[seed].text = "%s × %d" % [actions.seed_catalogue[key].name,seed_count.call(seed)]
	title.text = "工具箱 · 已装备 " + actions.tool_name()
	var using_seeds: bool = actions.equipped == 34
	tabs.current_tab = 1 if using_seeds else 0
	panel.show()
	get_tree().paused = true
	set_process_input(true)
	var focused: int = actions.selected_seed if using_seeds else actions.equipped
	entries.get(focused,entries[1]).grab_focus()


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
	button.custom_minimum_size = Vector2(120,48)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_constant_override("icon_max_width",28)
	if seed != -1:
		button.icon = actions.menu_icon(actions.tool_picture(tool,seed))
	button.pressed.connect(_select.bind(tool,seed))
	grid.add_child(button)
	entries[seed if seed != -1 else tool] = button


func _select(tool: int, seed: int) -> void:
	_close()
	choose_tool.call(seed if seed!=-1 else tool)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_I, KEY_X, KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close()
			KEY_TAB:
				get_viewport().set_input_as_handled()
				tabs.current_tab = 1 - tabs.current_tab
				tabs.get_current_tab_control().get_child(0).grab_focus()
			KEY_F1:
				get_viewport().set_input_as_handled()


func _close() -> void:
	if panel.visible:
		panel.hide()
		get_tree().paused = false
		set_process_input(false)


func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible:
		get_tree().paused = false

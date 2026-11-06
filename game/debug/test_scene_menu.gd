extends CanvasLayer
## Hosts playable fixtures in a separate 3D world while gameplay is suspended.
const SCENES := [
	["NPC 走动与避障","res://game/debug/npc_walk_test.tscn"],
	["独立工具箱","res://game/debug/toolbox_test.tscn"],
]

var world
var container: SubViewportContainer
var viewport: SubViewport
var menu: ColorRect
var rows: VBoxContainer
var first_button: Button
var return_button: Button
var fixture: Node
var gameplay_mode: ProcessMode
var was_paused := false


func setup(owner_world, font: Font) -> void:
	world = owner_world
	name = "DebugScenes"
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	container = SubViewportContainer.new()
	container.stretch = true
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = world.get_viewport().msaa_3d
	container.add_child(viewport)
	container.hide()

	menu = ColorRect.new()
	menu.color = Color(0.06,0.09,0.09,0.90)
	add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 320
	panel.theme = Theme.new()
	panel.theme.default_font = font
	panel.theme.default_font_size = 18
	center.add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,18)
	panel.add_child(margin)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation",10)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "测试场景"
	title.add_theme_font_size_override("font_size",24)
	rows.add_child(title)
	for entry: Array in SCENES:
		var button := _button(entry[0],_start.bind(entry[1]))
		if first_button==null:
			first_button = button
	return_button = _button("返回当前游戏",_return_to_game)
	_button("关闭面板（F2）",_close)
	menu.hide()


func _button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 38
	button.pressed.connect(callback)
	rows.add_child(button)
	return button


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F2:
			if menu.visible:
				_close()
			elif fixture!=null or (not get_tree().paused and not world.day_cycle.debug_panel.panel.visible
					and not world.transitioning and not world.day_cycle.sleeping):
				was_paused = get_tree().paused
				get_tree().paused = true
				viewport.gui_disable_input = true
				return_button.visible = fixture!=null
				menu.show()
				first_button.grab_focus()
			get_viewport().set_input_as_handled()
		KEY_X, KEY_ESCAPE:
			if menu.visible:
				_close()
				get_viewport().set_input_as_handled()
		KEY_F1:
			if menu.visible or fixture!=null:
				get_viewport().set_input_as_handled()


func _close() -> void:
	menu.hide()
	viewport.gui_disable_input = false
	get_tree().paused = was_paused


func _start(scene_path: String) -> void:
	var scene := load(scene_path) as PackedScene
	if scene==null:
		return
	if fixture==null:
		gameplay_mode = world.process_mode
		world.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		_remove_fixture()
	menu.hide()
	viewport.gui_disable_input = false
	get_tree().paused = false
	container.show()
	fixture = scene.instantiate()
	fixture.process_mode = Node.PROCESS_MODE_PAUSABLE
	viewport.add_child(fixture)


func _remove_fixture() -> void:
	viewport.remove_child(fixture)
	fixture.queue_free()
	fixture = null


func _return_to_game() -> void:
	_remove_fixture()
	container.hide()
	world.process_mode = gameplay_mode
	was_paused = false
	_close()

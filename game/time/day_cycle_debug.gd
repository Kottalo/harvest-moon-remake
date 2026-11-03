extends CanvasLayer
## F1 colour preview; separate from calendar/time and existing input locks.
var clock
var panel: PanelContainer
var selector: OptionButton
var close_button: Button
var was_paused := false

func setup(owner_clock) -> void:
	clock = owner_clock
	name = "DayCycleDebug"
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 110
	panel = PanelContainer.new()
	panel.position = Vector2(20,64)
	panel.custom_minimum_size = Vector2(360,0)
	panel.add_theme_font_override("font",clock.clock_label.get_theme_font("font"))
	panel.add_theme_font_size_override("font_size",18)
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+edge,14)
	panel.add_child(margin)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation",12)
	margin.add_child(rows)
	var title := Label.new()
	title.text = "调试面板 · 游戏已暂停"
	rows.add_child(title)
	var caption := Label.new()
	caption.text = "天色预览"
	rows.add_child(caption)
	selector = OptionButton.new()
	selector.custom_minimum_size.y = 38
	for text in ["跟随游戏时间","清晨","白天","傍晚","夜晚"]:
		selector.add_item(text)
	selector.select(clock.debug_period+1)
	selector.item_selected.connect(func(index: int): clock.set_debug_period(index-1))
	selector.get_popup().window_input.connect(_input)
	rows.add_child(selector)
	var hint := Label.new()
	hint.text = "仅预览天色，不修改游戏时间。\n关闭后保留预览；选第一项恢复自动。"
	hint.add_theme_font_size_override("font_size",15)
	rows.add_child(hint)
	close_button = Button.new()
	close_button.text = "继续游戏（F1）"
	close_button.focus_mode = Control.FOCUS_NONE # Keyboard closing uses F1, never a gameplay accept key.
	close_button.pressed.connect(func(): set_open(false))
	rows.add_child(close_button)
	panel.hide()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F1:
		set_open(not panel.visible)
		get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	if panel.visible==open: return
	if open:
		was_paused = get_tree().paused
		get_tree().paused = true
		selector.select(clock.debug_period+1)
	else:
		selector.get_popup().hide()
		get_tree().paused = was_paused
	panel.visible = open
	if open: selector.grab_focus()
	else: selector.release_focus()

func _exit_tree() -> void:
	if is_instance_valid(panel) and panel.visible:
		get_tree().paused = was_paused

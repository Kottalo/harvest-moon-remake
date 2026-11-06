extends CanvasLayer
## F1 colour preview and optional frame-pacing capture.
var clock
var panel: PanelContainer
var selector: OptionButton
var close_button: Button
var rows: VBoxContainer
var map_button: Button
var map_view
var live_tracking := false
var player_was_processing := false
var was_paused := false
var usage_label: Label
var timing_button: Button
var timing_until := 0
var previous_frame := 0
var frame_times := PackedFloat32Array()
var late_frames := 0
var worst_frame := {}

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
	rows = VBoxContainer.new()
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
	set_process(false)
	if OS.is_debug_build():
		timing_button = Button.new()
		timing_button.text = "采样画面卡顿（30 秒）"
		timing_button.pressed.connect(_start_timing)
		rows.add_child(timing_button)
		usage_label = Label.new()
		usage_label.add_theme_font_size_override("font_size",15)
		rows.add_child(usage_label)
		map_button = Button.new()
		map_button.text = "地图与角色追踪"
		map_button.pressed.connect(_open_map.bind(margin))
		rows.add_child(map_button)
	close_button = Button.new()
	close_button.text = "继续游戏（F1）"
	close_button.focus_mode = Control.FOCUS_NONE # Keyboard closing uses F1, never a gameplay accept key.
	close_button.pressed.connect(func(): set_open(false))
	rows.add_child(close_button)
	panel.hide()

func _open_map(margin: MarginContainer) -> void:
	if map_view==null:
		map_view = load("res://game/npc/npc_map_debug.gd").new()
		margin.add_child(map_view)
		map_view.setup(clock.world,clock.clock_label.get_theme_font("font"))
		map_view.back_requested.connect(_close_map)
		map_view.live_requested.connect(_set_live_tracking)
		for dropdown: OptionButton in [map_view.area_choice,map_view.actor_choice]:
			dropdown.get_popup().window_input.connect(_input)
	rows.hide()
	map_view.open(not was_paused and not clock.world.transitioning and not clock.world.player.actions.busy())
	panel.reset_size()
	map_view.area_choice.grab_focus()


func _close_map() -> void:
	if map_view==null or not map_view.visible:
		return
	_set_live_tracking(false)
	map_view.area_choice.get_popup().hide()
	map_view.actor_choice.get_popup().hide()
	map_view.hide()
	rows.show()
	panel.reset_size()


func _set_live_tracking(enabled: bool) -> void:
	if live_tracking==enabled:
		return
	var player = clock.world.player
	if enabled:
		player_was_processing = player.is_physics_processing()
		player.set_physics_process(false)
	else:
		player.set_physics_process(player_was_processing)
	live_tracking = enabled
	get_tree().paused = not enabled
	map_view.set_live(enabled)


func _start_timing() -> void:
	frame_times.clear()
	late_frames = 0
	worst_frame.clear()
	previous_frame = 0
	timing_until = Time.get_ticks_usec() + 30_000_000
	timing_button.text = "正在采样…"
	timing_button.disabled = true
	set_open(false)
	set_process(true)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if previous_frame > 0 and not get_tree().paused:
		var interval := (now - previous_frame) / 1000.0
		frame_times.append(interval)
		if interval > 25.0:
			late_frames += 1
		if interval > worst_frame.get("ms",0.0):
			worst_frame = {
				"ms":interval,"area":clock.world.current_area,
				"map_prefetch":not clock.world.location_loader.requested.is_empty(),
				"cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
				"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
			}
	previous_frame = 0 if get_tree().paused else now
	if now < timing_until:
		return
	set_process(false)
	timing_button.disabled = false
	timing_button.text = "采样画面卡顿（30 秒）"
	if frame_times.is_empty():
		return
	frame_times.sort()
	var p95 := frame_times[int(frame_times.size()*0.95)]
	var report := {
		"frames":frame_times.size(),"p95_ms":p95,"late_frames":late_frames,"worst":worst_frame,
		"fps_cap":Engine.max_fps,"refresh_hz":DisplayServer.screen_get_refresh_rate(),
		"vsync":DisplayServer.window_get_vsync_mode(),
		"embedded":Engine.is_embedded_in_editor(),
		"render_scale":clock.world.get_viewport().scaling_3d_scale,
	}
	var file := FileAccess.open("user://camera-pacing-last.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report,"\t"))
		file.close()
	print("CAMERA_PACING: ",JSON.stringify(report))
	timing_button.text = "重新采样 · p95 %.1f ms · %d 帧超时" % [p95,late_frames]

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
		_close_map()
		selector.get_popup().hide()
		get_tree().paused = was_paused
	panel.visible = open
	if open:
		refresh_usage()
		selector.grab_focus()
	else:
		selector.release_focus()

func _exit_tree() -> void:
	if live_tracking and is_instance_valid(clock.world.player):
		clock.world.player.set_physics_process(player_was_processing)
	if is_instance_valid(panel) and panel.visible:
		get_tree().paused = was_paused

func refresh_usage() -> void:
	if usage_label!=null and panel.visible:
		usage_label.text = clock.world.npcs.dialogue.client.usage_summary()

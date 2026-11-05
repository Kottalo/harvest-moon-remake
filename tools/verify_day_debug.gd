extends SceneTree
## Native F1/OptionButton input on an isolated viewport; no user game access.
var viewport: SubViewport
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for tick in count: await process_frame
func require_ok(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func key(code: int,pressed := true,echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	event.echo = echo
	var popup: PopupMenu = world.day_cycle.debug_panel.selector.get_popup()
	if popup.visible: popup.window_input.emit(event)
	else: viewport.push_input(event,true)
func tap(code: int) -> void:
	key(code)
	key(code,false)
	await frames(2)
func picture() -> Image:
	for frame in 3: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.gui_embed_subwindows = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	await frames(8)
	var clock = world.day_cycle
	var debug = clock.debug_panel
	if not require_ok(not debug.panel.visible and not paused and clock.debug_period==-1,"Debug panel must start hidden and automatic"): return
	await tap(KEY_F1)
	if not require_ok(debug.panel.visible and paused,"Physical F1 did not show/pause the panel"): return
	await frames(3)
	if not require_ok(viewport.get_visible_rect().encloses(debug.panel.get_global_rect()) and debug.panel.get_global_rect().encloses(debug.close_button.get_global_rect()) and debug.selector.item_count==5,"Native debug panel layout clipped controls or omitted choices"): return
	key(KEY_F1,true,true)
	if not require_ok(debug.panel.visible,"Key repeat toggled the panel again"): return
	key(KEY_F1,false)
	var minute: int = clock.minute
	var day: int = clock.day
	var position: Vector3 = world.player.position
	Input.action_press("move_right")
	Input.action_press("use_tool")
	await frames(35)
	Input.action_release("move_right")
	Input.action_release("use_tool")
	if not require_ok(clock.minute==minute and clock.day==day and world.player.position==position and not world.player.actions.busy(),"Panel allowed game time/movement/tool input to advance"): return
	var day_picture: Image
	var night_picture: Image
	# Activate the native popup's index_pressed path; headless windows have no OS focus.
	for index in [1,2,3,4,0]:
		debug.selector.grab_focus()
		await tap(KEY_Z)
		if not require_ok(debug.selector.get_popup().visible,"Native time selector did not open"): return
		debug.selector.get_popup().index_pressed.emit(index)
		debug.selector.get_popup().hide()
		await frames(2)
		if not require_ok(debug.selector.selected==index and clock.debug_period==index-1,"Native dropdown did not apply the selected sky: "+str([index,debug.selector.selected,clock.debug_period])): return
		var expected: Vector3 = clock._period_rgb(index-1) if index>0 else clock.tint_rgb
		var actual: Vector3 = clock.tint.material.get_shader_parameter("subtract_rgb")
		if not require_ok(actual.is_equal_approx(expected/255.0) and clock.minute==minute and clock.day==day,"Preview changed the clock or applied the wrong source tint"): return
		if DisplayServer.get_name()!="headless" and index in [2,4]:
			var shot := await picture()
			shot.save_png("res://verification/debug_day_panel.png" if index==2 else "res://verification/debug_night_panel.png")
			if index==2: day_picture = shot
			else: night_picture = shot
	if day_picture!=null:
		var brighter := 0
		for point in [Vector2i(620,430),Vector2i(660,450),Vector2i(690,480)]:
			if day_picture.get_pixelv(point).get_luminance()>night_picture.get_pixelv(point).get_luminance()+0.05: brighter += 1
		if not require_ok(brighter==3,"Actual GPU scene did not darken under the night preview"): return
		print("DAY_DEBUG_GPU_OK: three real scene samples darken; panel remains above the colour filter")
	# F1 must also work while the native dropdown owns keyboard focus.
	await tap(KEY_Z)
	key(KEY_F1)
	key(KEY_F1,false)
	await frames(2)
	if not require_ok(not debug.panel.visible and not debug.selector.get_popup().visible and not paused,"F1 did not close an active popup and resume the game"): return
	await tap(KEY_F1)
	debug.selector.select(4)
	debug.selector.item_selected.emit(4)
	debug.close_button.pressed.emit()
	await frames(2)
	if not require_ok(not debug.panel.visible and not paused and clock.debug_period==3,"Close button failed to retain the preview/resume"): return
	world._change_area(80,Vector3(0,0.05,0))
	if not require_ok(clock.tint.visible and clock.debug_period==3,"Manual preview was lost on an indoor scene change"): return
	clock.set_debug_period(-1)
	if not require_ok(not clock.tint.visible,"Automatic mode failed to restore original indoor tint rules"): return
	world.player.input_locked = true
	await tap(KEY_F1)
	await tap(KEY_F1)
	if not require_ok(world.player.input_locked,"Closing debug panel cleared another system's input lock"): return
	world.player.input_locked = false
	paused = true
	await tap(KEY_F1)
	await tap(KEY_F1)
	if not require_ok(paused,"Debug panel cleared a pre-existing tree pause"): return
	paused = false
	await tap(KEY_F1)
	viewport.free()
	if not require_ok(not paused,"Removing an open panel left the tree paused"): return
	print("DAY_DEBUG_CHECK_OK: viewport F1/repeat, popup input signal, native index_pressed selection/layout, frozen game/input, no date/time edit, retained preview, automatic indoor rules, lock/pause preservation and cleanup")
	quit()

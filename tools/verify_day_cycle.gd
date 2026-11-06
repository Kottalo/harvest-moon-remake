extends SceneTree
## Real clock, input, bed menu and full sleep transition; no user save/game access.
var failed := false
var bed_arc_height := 0.0
var bed_arrival := Vector3.ZERO
var saw_sleeping_fade := false
var saw_folded_blanket := false
var saw_tucked_blanket := false

func _initialize() -> void:
	_run.call_deferred()

func _require(ok: bool, message: String) -> bool:
	if not ok:
		failed = true
		push_error(message)
		quit(1)
	return ok

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _wait_wake(world) -> bool:
	for i in 480:
		await _frames(1)
		if world.player.actions.cinematic:
			bed_arc_height = maxf(bed_arc_height,world.player.position.y)
			var blanket: MeshInstance3D = world.get_node("Location/ZoneModel_01/Geometry")
			if world.player.actions.range_id==1 and is_equal_approx(blanket.get_blend_shape_value(0),1.0):
				saw_folded_blanket = true
			if world.player.actions.range_id == 2:
				bed_arrival = world.player.position
				if is_equal_approx(blanket.get_blend_shape_value(1),1.0):
					saw_tucked_blanket = true
		if world.transition_effect.phase=="sleep_out" and world.player.actions.state=="bed_hold":
			saw_sleeping_fade = true
		if not world.transitioning and not world.day_cycle.sleeping:
			return true
	return false

func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world._change_area(0,Vector3.ZERO)
	var clock = world.day_cycle
	for hz in [30,60,120]:
		clock.minute = 360
		clock.elapsed = 0
		for i in hz*2-1: clock.advance(1.0/hz)
		if not _require(clock.minute==360,"Clock ticked before 2 seconds"): return
		clock.advance(1.0/hz)
		if not _require(clock.minute==361,"Clock must advance one minute in 2 seconds at every FPS"): return
	clock.elapsed = 0.0
	clock.advance(0.75)
	world._change_area(80,Vector3(-0.8,0.05,0.5))
	var before: int = clock.minute
	clock.advance(1.0)
	if not _require(clock.minute==before,"Indoor clock ticked early after crossing the door"): return
	clock.advance(0.25)
	if not _require(clock.minute==before+1,"Outdoor and indoor seconds must count toward the same minute"): return
	clock.advance(2.0)
	if not _require(clock.minute==before+2,"Indoor clock must advance at one minute per 2 seconds"): return
	before = clock.minute
	world._change_area(0,Vector3.ZERO)
	world.overview = true
	clock.advance(2)
	world.overview = false
	if not _require(clock.minute==before+1,"Overview must allow the clock to advance"): return
	clock.menu_open = true
	clock.advance(2)
	clock.menu_open = false
	if not _require(clock.minute==before+2,"The sleep prompt must allow the clock to advance"): return
	clock.sleeping = true
	clock.advance(30)
	clock.sleeping = false
	if not _require(clock.minute==before+2,"The sleep transition must pause the clock"): return
	for test in [[300,0],[420,1],[900,2],[1020,3]]:
		clock.minute = test[0]
		clock.period = clock.time_period()
		clock.tint_rgb = clock._period_rgb(clock.period)
		clock.tint_from = clock.tint_rgb
		clock.tint_to = clock.tint_rgb
		clock.refresh()
		if not _require(clock.period==test[1],"Source dawn/day/dusk/night periods changed"): return
	clock.minute = 899
	clock.period = 1
	clock.tint_rgb = Vector3.ZERO
	clock.tint_from = Vector3.ZERO
	clock.tint_to = Vector3.ZERO
	clock.elapsed = 0
	clock.advance(2.0)
	clock.advance(128.0/30.0)
	if not _require(clock.tint_rgb.distance_to(Vector3(2.5,15,20))<0.001,"Original tint must interpolate over 256 ticks"): return
	print("CLOCK_OK: 2 s/min at 30/60/120 FPS; continuous indoor/outdoor time; menu/overview keep time; source four periods and 256-tick subtractive tint")
	world._change_area(80,Vector3(-0.98,0.03,0.5))
	world.player.facing = 1
	await _frames(8)
	if not _require(clock.nearby_bed(),"Original bedside interaction zone is unreachable"): return
	world.player.actions.carried_id = 58
	if not _require(not clock.nearby_bed(),"Bed interaction must reject carried items"): return
	world.player.actions.carried_id = 0
	_key(KEY_Z,true)
	await _frames(2)
	_key(KEY_Z,false)
	if not _require(clock.menu_open and world.player.input_locked,"Physical E did not open the bed menu"): return
	_key(KEY_X,true)
	await _frames(2)
	_key(KEY_X,false)
	if not _require(not clock.menu_open and not world.player.input_locked,"Cancelling sleep must restore control"): return
	clock.day = 29
	clock.season = 0
	clock.weekday = 6
	clock.minute = 1430
	clock.elapsed = 0
	_key(KEY_Z,true)
	await _frames(2)
	_key(KEY_Z,false)
	await _frames(1)
	_key(KEY_Z,true)
	await _frames(2)
	_key(KEY_Z,false)
	if not _require(world.transitioning and clock.sleeping,"Confirming sleep did not start the real transition"): return
	if not _require(await _wait_wake(world),"Sleep animation/fade sequence did not finish"): return
	if not _require(saw_folded_blanket and saw_tucked_blanket,"Blanket failed to fold before the jump and settle over the sleeping pose"): return
	if not _require(saw_sleeping_fade,"Sleeping pose was not held through the live fade"): return
	if not _require(bed_arc_height>0.45 and Vector2(bed_arrival.x,bed_arrival.z).distance_to(Vector2(-1.35,0.96))<0.001,"Original 18-tick bedtime arc did not reach the bed"): return
	if not _require(clock.minute==360 and clock.day==0 and clock.season==1 and clock.weekday==0 and world.current_area==80,"Sleep did not cross midnight/season and wake at 06:00"): return
	await _frames(5)
	if not _require(world.player.is_on_floor() and not world.player.input_locked,"Morning player was not grounded/unlocked"): return
	print("SLEEP_OK: physical Z menu, X cancel, Z sleep; original ANI, blanket morphs, 18-tick bed arc and live fade; spring 30 -> summer 1, 06:00, farmhouse spawn grounded")
	world._change_area(180,Vector3.ZERO)
	clock.day = 29
	clock.season = 3
	clock.year = 0
	clock.weekday = 6
	clock.minute = 359
	clock.elapsed = 0
	var position: Vector3 = world.player.global_position
	world.npcs.dialogue.show_notice("测试","跨日时保持这个窗口打开。")
	clock.advance(4.25)
	if not _require(paused and clock.minute==361 and not clock.sleeping and not world.transitioning,
			"Dawn paused the clock or started a transition while the notice was open"): return
	world.npcs.dialogue.close()
	clock.advance(0.0)
	if not _require(clock.year==1 and clock.season==0 and clock.day==0 and clock.weekday==0 and clock.minute==361
			and is_equal_approx(clock.elapsed,0.25) and world.current_area==180 and world.player.global_position==position,
			"Dawn moved the player or advanced the day twice"): return
	print("OVERNIGHT_OK: dawn advances the calendar in place, including through a modal")
	world.free()
	print("DAY_CYCLE_CHECK_OK")
	quit()

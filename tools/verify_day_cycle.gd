extends SceneTree
## Real clock, input, bed menu and full sleep transition; no user save/game access.
var failed := false
var bed_arc_height := 0.0
var bed_arrival := Vector3.ZERO

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
			if world.player.actions.range_id == 2:
				bed_arrival = world.player.position
		if not world.transitioning and not world.day_cycle.sleeping:
			return true
	return false

func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var clock = world.day_cycle
	for hz in [30,60,120]:
		clock.minute = 360
		clock.elapsed = 0
		for i in hz*5: clock.advance(1.0/hz,false)
		if not _require(clock.minute==370,"Clock must advance 10 minutes in 5 seconds at every FPS"): return
	world._change_area(80,Vector3(-0.8,0.05,0.5))
	var before: int = clock.minute
	clock.advance(120,false)
	if not _require(clock.minute==before,"Source indoor place must pause the clock"): return
	world._change_area(0,Vector3.ZERO)
	clock.advance(30,true)
	clock.menu_open = true
	clock.advance(30,false)
	clock.menu_open = false
	clock.sleeping = true
	clock.advance(30,false)
	clock.sleeping = false
	if not _require(clock.minute==before,"Overview, menus and sleep must pause the clock"): return
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
	clock.advance(0.5,false)
	clock.advance(128.0/30.0,false)
	if not _require(clock.tint_rgb.distance_to(Vector3(2.5,15,20))<0.001,"Original tint must interpolate over 256 ticks"): return
	print("CLOCK_OK: 0.5 s/min at 30/60/120 FPS; indoor/menu/overview pause; source four periods and 256-tick subtractive tint")
	world._change_area(80,Vector3(-0.98,0.03,0.5))
	world.player.facing = 1
	await _frames(8)
	if not _require(clock.nearby_bed(),"Original bedside interaction zone is unreachable"): return
	world.player.actions.carried_id = 58
	if not _require(not clock.nearby_bed(),"Bed interaction must reject carried items"): return
	world.player.actions.carried_id = 0
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	if not _require(clock.menu_open and world.player.input_locked,"Physical E did not open the bed menu"): return
	_key(KEY_ESCAPE,true)
	await _frames(2)
	_key(KEY_ESCAPE,false)
	if not _require(not clock.menu_open and not world.player.input_locked,"Cancelling sleep must restore control"): return
	clock.day = 29
	clock.season = 0
	clock.weekday = 6
	clock.minute = 1430
	clock.elapsed = 0
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	await _frames(1)
	_key(KEY_ENTER,true)
	await _frames(2)
	_key(KEY_ENTER,false)
	if not _require(world.transitioning and clock.sleeping,"Confirming sleep did not start the real transition"): return
	if not _require(await _wait_wake(world),"Sleep animation/fade sequence did not finish"): return
	if not _require(bed_arc_height>0.45 and Vector2(bed_arrival.x,bed_arrival.z).distance_to(Vector2(-1.35,0.96))<0.001,"Original 18-tick bedtime arc did not reach the bed"): return
	if not _require(clock.minute==360 and clock.day==0 and clock.season==1 and clock.weekday==0 and world.current_area==80,"Sleep did not cross midnight/season and wake at 06:00"): return
	await _frames(5)
	if not _require(world.player.is_on_floor() and not world.player.input_locked,"Morning player was not grounded/unlocked"): return
	print("SLEEP_OK: physical E menu, Esc cancel, Enter sleep; original ANI and 18-tick bed arc; spring 30 -> summer 1, 06:00, farmhouse spawn grounded")
	world._change_area(0,Vector3.ZERO)
	clock.day = 29
	clock.season = 3
	clock.year = 0
	clock.minute = 359
	clock.elapsed = 0
	clock.advance(0.5,false)
	if not _require(await _wait_wake(world),"Natural 06:00 rollover failed"): return
	if not _require(clock.year==1 and clock.season==0 and clock.day==0 and clock.minute==360 and world.current_area==80,"Natural overnight/year rollover advanced the day twice"): return
	print("OVERNIGHT_OK: natural 06:00 returns home; winter 30 -> year 2 spring 1 exactly once")
	world.free()
	print("DAY_CYCLE_CHECK_OK")
	quit()

extends SceneTree

func _initialize() -> void:
	run.call_deferred()


func require_ok(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func at_door(world, area: int, event_id: int, minute: int, weekday: int, season := 0, day := 1) -> Dictionary:
	var clock = world.day_cycle
	clock.minute = minute
	clock.weekday = weekday
	clock.season = season
	clock.day = day
	var exit: Dictionary
	for candidate: Dictionary in world.world[str(area)].exits:
		if int(candidate.event)==event_id:
			exit = candidate
			break
	var centre := Vector3((exit.min[0]+exit.max[0])*0.5,0,(exit.min[1]+exit.max[1])*0.5)
	world._change_area(area,centre)
	world.player.facing = int(exit.facing)
	return exit


func enter_key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func press_enter() -> void:
	enter_key(true)
	for tick in 2:
		await physics_frame
	enter_key(false)
	await physics_frame


func run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	# Monday's initial-affection hours, Tuesday's absence, and a source calendar date.
	for case in [[40,25,539,1,0,1,true],[40,25,540,1,0,1,false],
			[40,25,1079,1,0,1,false],[40,25,1080,1,0,1,true],
			[40,25,660,2,0,2,true],[40,25,660,1,0,7,true],
			[40,27,540,3,0,2,true],[40,27,660,3,0,2,false],
			[36,21,660,1,0,1,true],[36,21,660,2,0,2,false],
			[44,33,540,1,0,1,false],[44,33,1080,1,0,1,true],
			[44,31,660,1,2,2,true],[44,31,1140,1,2,2,false],
			[48,34,660,1,0,0,true],[48,34,1140,1,0,0,false],
			[48,34,600,1,2,4,true],[48,34,660,1,2,4,false],
			[180,26,660,1,0,1,true]]:
		at_door(world,case[0],case[1],case[2],case[3],case[4],case[5])
		world._check_exits(0.0)
		if not require_ok(not world.nearby_exit.is_empty() and world.nearby_exit_locked==case[6],
				"Door lock did not match the source rule: "+str(case)):
			return

	var exit := at_door(world,40,25,539,1)
	world.set_physics_process(true)
	await press_enter()
	world._refresh_hud()
	if not require_ok(not world.transitioning and world.doors.doors.is_empty()
			and world.hud.text.contains("门锁着"),"Locked supermarket accepted E or failed to show refusal"):
		return
	# Change the clock while standing at the same door.
	world.day_cycle.minute = 540
	await press_enter()
	if not require_ok(world.transitioning and not world.nearby_exit_locked,
			"Reaching opening time did not enable the same door"):
		return
	for tick in 250:
		await physics_frame
		if world.current_area==int(exit.target) and not world.transitioning:
			break
	if not require_ok(world.current_area==int(exit.target),"Unlocked entrance did not use the door transition"):
		return
	# A public entrance lock must never trap a player already inside.
	world.day_cycle.minute = 1200
	world.npcs.update(0.0)
	for reverse: Dictionary in world.world["180"].exits:
		if int(reverse.target)==40:
			world.player.position = Vector3((reverse.min[0]+reverse.max[0])*0.5,0,(reverse.min[1]+reverse.max[1])*0.5)
			world.player.facing = int(reverse.facing) if int(reverse.facing)<4 else 0
			world.awaiting_interact_release = false
			world._check_exits(0.0)
			break
	if not require_ok(world.transitioning and not world.nearby_exit_locked,"Shop locked the player in after hours"):
		return
	for tick in 250:
		await physics_frame
		if world.current_area==40 and not world.transitioning:
			break
	if not require_ok(world.current_area==40 and not world.transitioning,"After-hours exit never completed"):
		return
	world.free()
	print("DOOR_ACCESS_OK: source times, resident days off, date exceptions, private rooms, E refusal and after-hours exit")
	quit()

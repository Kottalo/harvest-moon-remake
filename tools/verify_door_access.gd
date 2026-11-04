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


func enter_key(pressed: bool, code := KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func press_enter(code := KEY_E) -> void:
	enter_key(true,code)
	for tick in 2:
		await physics_frame
	enter_key(false,code)
	await physics_frame


func run_to_stop(world, exit: Dictionary, distance := 0.42) -> float:
	var stop: StaticBody3D = world.get_node("Location/DoorStop_%02d" % int(exit.index))
	var inward: Vector3 = stop.get_meta("inward")
	var approach := stop.global_position-inward*distance
	await physics_frame
	var ray := PhysicsRayQueryParameters3D.create(approach+Vector3.UP,approach-Vector3.UP,2)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return INF
	world.player.global_position = hit.position+Vector3.UP*0.01
	world.player.velocity = Vector3.ZERO
	world.player.reset_physics_interpolation()
	var direction: String = ["move_down","move_left","move_up","move_right"][int(exit.facing)]
	Input.action_press(direction)
	Input.action_press("run")
	for tick in 55:
		await physics_frame
	Input.action_release(direction)
	Input.action_release("run")
	var capsule: CollisionShape3D = world.player.get_node("CollisionShape3D")
	return (stop.global_position-capsule.global_position).dot(inward)


func run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var dialogue = world.npcs.dialogue
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

	# Reproduce the reported locked library entrance with actual running input.
	var library_exit := at_door(world,36,21,570,1)
	var distance := await run_to_stop(world,library_exit)
	world.set_physics_process(true)
	await press_enter()
	if not require_ok(world.current_area==36 and world.nearby_exit_locked and not world.transitioning
			and dialogue.notice_open and dialogue.reply.text.contains("无人接待")
			and distance>=world.player.footprint.radius and distance<0.13,
			"Player ran through the locked library stop or could not reach its prompt: "+str(distance)):
		return

	var exit := at_door(world,40,25,539,1)
	world.set_physics_process(false)
	if not require_ok(await run_to_stop(world,exit)<0.13,"Shop doorway could not be reached"):
		return
	world.day_cycle.elapsed = 0.0
	world.set_physics_process(true)
	await press_enter()
	world._refresh_hud()
	if not require_ok(not world.transitioning and world.doors.doors.is_empty()
			and world.hud.text.contains("门锁着") and dialogue.notice_open and not dialogue.entry.visible
			and dialogue.reply.text.contains("开放时间"),"Locked supermarket accepted E or failed to show refusal"):
		return
	await press_enter()
	if not require_ok(not dialogue.overlay.visible and not paused and not world.transitioning,
			"Closing a locked-door notice triggered another interaction"):
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
	world.set_physics_process(false)
	var ranch_exit := at_door(world,24,6,660,0)
	if not require_ok(await run_to_stop(world,ranch_exit,0.85)<0.13,
			"Yodel Ranch's porch steps prevented reaching the closed door"):
		return
	world.set_physics_process(true)
	await press_enter()
	if not require_ok(world.transitioning and not world.nearby_exit_locked,"E did not open the reachable Yodel Ranch door"):
		return
	for tick in 250:
		await physics_frame
		if not world.transitioning:
			break
	if not require_ok(world.current_area==128 and not world.transitioning,"Yodel Ranch entry did not finish"):
		return
	# Read the actual shop sign from its source probe zone, with physical E.
	world._change_area(40,Vector3(-2.049,0,-0.175))
	world.player.facing = 1
	await physics_frame
	await press_enter()
	if not require_ok(not dialogue.overlay.visible,"The shop sign opened when facing away"):
		return
	world.player.facing = 3
	world._refresh_hud()
	if not require_ok(world.hud.text.contains("E 查看 杂货店"),"Nearby sign did not show its interaction hint"):
		return
	await press_enter()
	if not require_ok(dialogue.notice_open and paused and dialogue.title.text=="杂货店"
			and dialogue.reply.text.contains("周二和周日休息") and dialogue.npc_id.is_empty(),
			"Physical E did not show the sign's local text"):
		return
	await press_enter(KEY_ESCAPE)
	if not require_ok(not dialogue.overlay.visible and not paused,"Escape did not dismiss the notice"):
		return
	world._change_area(92,Vector3(-0.976,0,0.2))
	world.player.facing = 1
	await physics_frame
	await press_enter()
	if not require_ok(dialogue.notice_open and dialogue.title.text=="马厩告示"
			and dialogue.reply.text.contains("刷毛"),"An indoor object did not use its own source notice"):
		return
	await press_enter(KEY_ENTER)
	if not require_ok(not dialogue.overlay.visible and not paused,"Enter did not dismiss the indoor notice"):
		return
	world.free()
	print("DOOR_ACCESS_OK: source locks, actual entry and exit, E refusal, outdoor signs and indoor notices")
	quit()

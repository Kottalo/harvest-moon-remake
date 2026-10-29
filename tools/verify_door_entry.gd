extends SceneTree
## Source-timed physical E entry through actual imported single and double doors.
const DIRECTIONS := [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)]

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for tick in count: await physics_frame
	await process_frame

func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _require(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _run() -> void:
	Engine.max_fps = 0
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	for route in [[0,0],[0,3],[40,1]]:
		var area: int = route[0]
		var exit: Dictionary
		for candidate in world.world[str(area)].exits:
			if int(candidate.index)==route[1]: exit = candidate
		var direction: Vector3 = DIRECTIONS[int(exit.facing)]
		var centre := Vector3((exit.min[0]+exit.max[0])*0.5,0,(exit.min[1]+exit.max[1])*0.5)
		var start := centre-direction*0.35
		world._change_area(area,start+Vector3.UP)
		await _frames(2)
		var ray := PhysicsRayQueryParameters3D.create(start+Vector3.UP*2,start-Vector3.UP*2,2)
		var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
		if not _require(not floor_hit.is_empty(),"Door approach has no ground"): return
		world.player.position = floor_hit.position+Vector3.UP*0.01
		world.player.velocity = Vector3.ZERO
		world.player.facing = int(exit.facing)
		world.player.reset_physics_interpolation()
		await _frames(8)
		var before: Vector3 = world.player.position
		var began := Engine.get_physics_frames()
		_key(true)
		await _frames(2)
		_key(false)
		if not _require(world.transitioning,"Physical E did not begin the door passage"): return
		var second_stage := false
		var captured := false
		for tick in Engine.physics_ticks_per_second*2:
			if world.transition_effect.phase=="out": break
			if float(Engine.get_physics_frames()-began)/Engine.physics_ticks_per_second>0.55 and world.player.scripted_walk_time>0:
				second_stage = true
			if DisplayServer.get_name()!="headless" and route==[0,0] and second_stage and not captured:
				for frame in 2: await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("res://verification/door_opening.png")
				captured = true
			await _frames(1)
		var seconds := float(Engine.get_physics_frames()-began)/Engine.physics_ticks_per_second
		var distance: float = (world.player.position-before).dot(direction)
		if not _require(world.transition_effect.phase=="out" and seconds>=0.95 and seconds<1.2 and second_stage and distance>0.08,"Source 10+20 tick door passage was skipped or blocked: "+str([route,seconds,distance,second_stage])): return
		print("DOOR_ENTRY_OK: ",route," source 10+20 ticks before fade; elapsed=",seconds," movement=",distance)
		for tick in Engine.physics_ticks_per_second*3:
			if not world.transitioning: break
			await _frames(1)
		if not _require(world.current_area==int(exit.target) and not world.player.input_locked,"Door passage did not arrive and release input"): return
	world.queue_free()
	await process_frame
	print("DOOR_ENTRY_CHECK_OK: ",Engine.physics_ticks_per_second," Hz; farmhouse, mirrored barn doors and clinic via actual E")
	quit()

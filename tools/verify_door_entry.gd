extends SceneTree
## Source-timed physical E entry through actual imported single and double doors.
const DIRECTIONS := [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)]

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for tick in count: await physics_frame
	await process_frame

func _key(pressed: bool, code := KEY_E) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
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
	for route in [[0,0],[0,3],[40,1],[180,0],[204,0],[168,0],[44,0]]:
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
		# E from the former forward-probe range must not open the door early.
		_key(true)
		await _frames(2)
		_key(false)
		await _frames(2)
		if not _require(not world.transitioning,"Door opened before actual feet entered its source zone"): return
		var direction_key: int = [KEY_DOWN,KEY_LEFT,KEY_UP,KEY_RIGHT][int(exit.facing)]
		_key(true,direction_key)
		await _frames(ceili(0.7*Engine.physics_ticks_per_second))
		_key(false,direction_key)
		await _frames(2)
		var before: Vector3 = world.player.position
		var began := Engine.get_physics_frames()
		_key(true)
		await _frames(2)
		_key(false)
		if not _require(world.transitioning,"Physical E did not begin the door passage"): return
		var second_stage := false
		var back_step := false
		var minimum_distance := 0.0
		var captured := false
		var sequence: Image
		var sequence_frame := 0
		if DisplayServer.get_name()!="headless" and route==[44,0]: sequence = Image.create(800,600,false,Image.FORMAT_RGB8)
		for tick in Engine.physics_ticks_per_second*2:
			if world.transition_effect.phase=="out": break
			var travelled: float = (world.player.position-before).dot(direction)
			minimum_distance = minf(minimum_distance,travelled)
			if travelled < -0.2 and world.player.facing==posmod(int(exit.facing)+2,4): back_step = true
			if back_step and world.player.facing==int(exit.facing) and world.player.scripted_walk_time>0: second_stage = true
			if DisplayServer.get_name()!="headless" and route==[0,0] and second_stage and not captured:
				for frame in 2: await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("res://verification/door_opening.png")
				captured = true
			if sequence!=null and sequence_frame<4 and float(Engine.get_physics_frames()-began)/Engine.physics_ticks_per_second>=[0.2,0.36,0.7,1.0][sequence_frame]:
				await RenderingServer.frame_post_draw
				var sample: Image = viewport.get_texture().get_image()
				sample.resize(400,300,Image.INTERPOLATE_LANCZOS)
				sample.convert(Image.FORMAT_RGB8)
				sequence.blit_rect(sample,Rect2i(0,0,400,300),Vector2i(sequence_frame%2*400,sequence_frame/2 as int*300))
				sequence_frame += 1
			await _frames(1)
		var seconds := float(Engine.get_physics_frames()-began)/Engine.physics_ticks_per_second
		var distance: float = (world.player.position-before).dot(direction)
		for index in world.player.get_slide_collision_count():
			var collision: KinematicCollision3D = world.player.get_slide_collision(index)
			print("PASSAGE_CONTACT: ",collision.get_collider().get_path()," normal=",collision.get_normal())
		if not _require(world.transition_effect.phase=="out" and seconds>=1.03 and seconds<1.25 and back_step and second_stage and minimum_distance<-0.40 and minimum_distance>-.49 and absf(distance-0.41)<0.035 and absf(world.player.position.y-before.y)<0.21,"Source turn/back-step/return-entry sequence was skipped or blocked: "+str([route,seconds,distance,minimum_distance,second_stage])): return
		print("DOOR_ENTRY_OK: ",route," source 10+20 countdowns including tick 0; elapsed=",seconds," back step=",minimum_distance," net entry=",distance)
		if sequence!=null:
			if not _require(sequence_frame==4,"Church entry sequence frames missing"): return
			sequence.save_png("res://verification/door_sequence.png")
		for tick in Engine.physics_ticks_per_second*3:
			if not world.transitioning: break
			await _frames(1)
		if not _require(world.current_area==int(exit.target) and not world.player.input_locked and world.player.get_collision_exceptions().is_empty() and not world.player.door_passage and world.player.collision_mask==3,"Door passage did not arrive and release input"): return
	# A scene change/cancel must also restore the exact normal collision mask.
	world._change_area(0,Vector3(-4.65,0.05,-4.03))
	world.player.facing = 1
	await _frames(8)
	_key(true)
	await _frames(2)
	_key(false)
	if not _require(world.transitioning and world.player.door_passage and world.player.collision_mask==0,"Cancellation fixture did not enter a confirmed source passage"): return
	world._change_area(80,Vector3(1.377,0,0.842))
	await _frames(3)
	if not _require(not world.transitioning and not world.player.input_locked and not world.player.door_passage and world.player.collision_mask==3 and world.player.scripted_walk_time==0,"Cancelling a doorway passage left ghost collision/input state"): return
	print("DOOR_CANCEL_OK: normal collision mask/input restored and old coroutine cancelled")
	world.queue_free()
	await process_frame
	print("DOOR_ENTRY_CHECK_OK: ",Engine.physics_ticks_per_second," Hz; seven exterior/interior single/twin doors via actual E, turn away/back-step/turn back/enter/fade and cancellation")
	quit()

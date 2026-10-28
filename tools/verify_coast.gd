extends SceneTree
## Walk/run across the coast seam and reverse immediately without model or camera swaps.
var world: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _travel(target: float, key: int, running: bool) -> bool:
	var identity: int = world.get_node("Location").get_instance_id()
	var square_mesh: RID = world.get_node("Location/TownSquare/Geometry").mesh.get_rid()
	var beach_mesh: RID = world.get_node("Location/Beach/Geometry").mesh.get_rid()
	var speed: float = world.player.RUN_SPEED if running else world.player.WALK_SPEED
	_key(key, true)
	_key(KEY_SHIFT, running)
	for tick in Engine.physics_ticks_per_second * 4:
		var previous: Vector3 = world.player.position
		var camera_before: Vector3 = world.camera.position
		var physics_before := Engine.get_physics_frames()
		await _frames(1)
		var point: Vector3 = world.player.position
		var movement := point - previous
		if not _require(world.get_node("Location").get_instance_id() == identity and world.get_node("Location/TownSquare/Geometry").mesh.get_rid() == square_mesh and world.get_node("Location/Beach/Geometry").mesh.get_rid() == beach_mesh, "Coast crossing replaced the scene or either mesh"):
			return false
		var camera_step: float = (world.camera.position - camera_before).length()
		var offset_error: float = (world.camera.position - point - world.camera.eye_offset).length()
		var ticks := maxi(Engine.get_physics_frames() - physics_before, 1)
		var frame_limit := speed / Engine.physics_ticks_per_second * (ticks + 1) * 1.6 + 0.004
		# process_frame is emitted before the camera's _process. At 120 Hz / 60 FPS,
		# its next render can also include the previous sample's pending physics ticks.
		var camera_limit := frame_limit * 2.0 + 0.005
		if not _require(absf(movement.x) <= frame_limit and absf(movement.y) <= frame_limit and camera_step <= camera_limit and offset_error <= frame_limit and world.player.is_on_floor(), "Coast crossing teleported, lost the floor, or jumped the camera: " + str([previous, point, world.player.is_on_floor(), camera_step, offset_error])):
			return false
		if (key == KEY_LEFT and point.x <= target) or (key == KEY_RIGHT and point.x >= target):
			_key(key, false)
			_key(KEY_SHIFT, false)
			return true
	push_error("Could not traverse the entire beach staircase")
	quit(1)
	return false

func _run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	for side in [-1.1, -0.8, -0.5]:
		for running in [false, true]:
			world._change_area(56, Vector3(-6.28, -0.54, side))
			await _frames(20)
			var square: AABB = world.get_node("Location/TownSquare/Geometry").mesh.get_aabb()
			var beach: AABB = world.get_node("Location/Beach/Geometry").mesh.get_aabb()
			if not _require(square.end.x <= 5.00001 and beach.position.x >= -7.40001, "Duplicated source preview geometry crosses the shared landing"):
				return
			if not await _travel(4.3, KEY_LEFT, running):
				return
			if not _require(world.current_area == 52, "Did not enter the square region"):
				return
			# No waiting, teleporting or exit-state reset between the two directions.
			if not await _travel(6.12, KEY_RIGHT, running):
				return
			if not _require(world.current_area == 56, "Did not return to the beach region"):
				return
			print("COAST_ROUTE_OK: side=", side, " running=", running, " position=", world.player.position)
	print("COAST_CHECK_OK: ", Engine.physics_ticks_per_second, " Hz; three lanes walk/run; immediate return; same scene/meshes, continuous player/camera/floor")
	world.queue_free()
	await process_frame
	quit()

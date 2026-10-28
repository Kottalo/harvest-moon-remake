extends SceneTree
## Exercise the real controller against imported stairs and synthetic collision hazards.

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _box(parent: Node3D, location: Vector3, size: Vector3, walkable: bool = false) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 11 if walkable else 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = location
	body.add_child(shape)
	parent.add_child(body)

func _walk(player: CharacterBody3D, position: Vector3, action: String, frames: int, running: bool = false) -> Vector3:
	player.position = position
	player.velocity = Vector3.ZERO
	await _frames(12)
	Input.action_press(action)
	if running:
		Input.action_press("run")
	await _frames(frames)
	Input.action_release(action)
	Input.action_release("run")
	await _frames(4)
	return player.position

func _run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	await _frames(5)
	for sample in [
		[32, Vector3(1.233451, 0.02, 2.614479), Vector3(0.3, 0.22, 2.614479), 0.18],
		[32, Vector3(1.0, 0.02, 2.55), Vector3(0.3, 0.22, 2.55), 0.18],
		[32, Vector3(1.0, 0.02, 3.05), Vector3(0.3, 0.22, 3.05), 0.18],
		[32, Vector3(1.0, 0.02, 2.8), Vector3(0.3, 0.22, 2.8), 0.18],
		[32, Vector3(1.0, 0.02, -0.8), Vector3(0.3, 0.22, -0.8), 0.18],
		[188, Vector3(0.15, 0.02, -1.6), Vector3(-1.1, 0.76, -1.6), 0.7],
		[188, Vector3(0.15, 0.02, -1.8), Vector3(-1.1, 0.76, -1.8), 0.7],
		[188, Vector3(0.15, 0.02, -1.52), Vector3(-1.1, 0.76, -1.52), 0.7],
		[204, Vector3(1.3, 0.02, 3.6), Vector3(-0.5, 0.82, 3.6), 0.7],
		[128, Vector3(-1.28, 0.02, -0.5), Vector3(-1.28, 0.72, 0.65), 0.65],
		[152, Vector3(0.5, 0.02, 0.8), Vector3(1.9, 0.74, 0.8), 0.68],
	]:
		for running in [false, true]:
			world._change_area(sample[0], sample[1])
			var speed: float = world.player.RUN_SPEED if running else world.player.WALK_SPEED
			var path: Vector3 = sample[2] - sample[1]
			var actions: Array = (["move_left", "move_right"] if path.x < 0 else ["move_right", "move_left"]) if absf(path.x) > absf(path.z) else (["move_up", "move_down"] if path.z < 0 else ["move_down", "move_up"])
			var frames := roundi((Vector2(path.x, path.z).length() / speed + 0.2) * Engine.physics_ticks_per_second)
			var top: Vector3 = await _walk(world.player, sample[1], actions[0], frames, running)
			print("STAIR_SAMPLE ", sample[0], " running=", running, " end=", top)
			var progress: float = Vector2(top.x - sample[1].x, top.z - sample[1].z).dot(Vector2(path.x, path.z).normalized())
			if not _require(top.y > sample[3] and progress > Vector2(path.x, path.z).length() - 0.12, "Imported staircase ascent failed: " + str(sample[0])):
				return
			var bottom: Vector3 = await _walk(world.player, sample[2], actions[1], frames, running)
			if not _require(bottom.y < 0.1 and world.player.is_on_floor(), "Imported staircase descent failed: " + str([sample[0], bottom])):
				return
	world._change_area(188, Vector3(0.8, 0.02, 0))
	var room_wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 0), "move_right", Engine.physics_ticks_per_second * 2, true)
	if not _require(room_wall.x < 2.01 and world.player.is_on_floor(), "Player crossed the original room ground boundary"):
		return
	var location: Node3D = world.get_node("Location")
	world.remove_child(location)
	location.free()
	var fixtures := Node3D.new()
	world.add_child(fixtures)
	_box(fixtures, Vector3(0, -0.1, 0), Vector3(8, 0.2, 8), true)
	_box(fixtures, Vector3(0, 0.3, 0), Vector3(0.2, 0.6, 1))
	_box(fixtures, Vector3(0, 0.3, -2), Vector3(0.02, 0.6, 1))
	_box(fixtures, Vector3(0, 0.04, 2), Vector3(0.5, 0.08, 1), true)
	_box(fixtures, Vector3(0, 0.31, 2), Vector3(1, 0.08, 1))
	_box(fixtures, Vector3(0, 0.08, -3), Vector3(0.5, 0.16, 0.6), true)
	_box(fixtures, Vector3(0, 0.08, 1), Vector3(0.5, 0.16, 0.6))
	_box(fixtures, Vector3(0, 0.02, 3), Vector3(0.5, 0.04, 0.6), true)
	_box(fixtures, Vector3(0, 0.34, 3), Vector3(1, 0.04, 0.6))
	await _frames(3)
	for running in [false, true]:
		var wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 0), "move_left", 90, running)
		if not _require(wall.x > 0.15 and wall.y < 0.01, "Player climbed or crossed a tall obstacle"):
			return
		var thin_wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, -2), "move_left", 90, running)
		if not _require(thin_wall.x > 0.065 and thin_wall.y < 0.01, "Player tunneled through a thin obstacle"):
			return
		var ceiling: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 2), "move_left", 90, running)
		if not _require(ceiling.x > 0.3 and ceiling.y < 0.02, "Player stepped through a low ceiling"):
			return
		var speed: float = world.player.RUN_SPEED if running else world.player.WALK_SPEED
		var frames := roundi(0.8 / speed * Engine.physics_ticks_per_second)
		var high_tread: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, -3), "move_left", frames, running)
		if not _require(absf(high_tread.x) < 0.15 and high_tread.y > 0.15, "Original 200-unit tolerance did not accept a 160-unit tread"):
			return
		var blocked_face: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 1), "move_left", frames, running)
		if not _require(blocked_face.x > 0.3 and blocked_face.y < 0.02, "Controller climbed a face excluded from original walkable ground"):
			return
		var tight_clearance: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 3), "move_left", frames, running)
		if not _require(absf(tight_clearance.x) < 0.15 and tight_clearance.y > 0.03, "Valid low-ceiling step was blocked by maximum-height sweep"):
			return
	print("COLLISION_CHECK_OK: ", Engine.physics_ticks_per_second, " Hz; walk/run up/down imported stairs; tall/thin obstacles and low ceilings block player")
	world.queue_free()
	await process_frame
	quit()

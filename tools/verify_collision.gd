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

func _ramp(parent: Node3D, z: float, height: float, run: float = 0.5) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 11
	body.position.z = z
	var shape := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for side in [-0.3, 0.3]:
		points.append(Vector3(0.25, height, side))
		points.append(Vector3(0.25 + run, 0, side))
		points.append(Vector3(0.25, -0.05, side))
		points.append(Vector3(0.25 + run, -0.05, side))
	wedge.points = points
	shape.shape = wedge
	body.add_child(shape)
	parent.add_child(body)

func _run() -> void:
	Engine.max_fps = 0 # Let isolated 120 Hz physics checks advance independently of the game's render cap.
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	await _frames(5)
	var ramp_count := 0
	for area in world.world:
		var info: Dictionary = world.world[area]
		var definition_path: String = info.texture_base + "walkable_ramps.json"
		if not FileAccess.file_exists(definition_path):
			continue
		world._change_area(int(area), Vector3.ZERO)
		await _frames(2)
		for ramp in JSON.parse_string(FileAccess.get_file_as_string(definition_path)):
			for along in [0.1, 0.3, 0.5, 0.7, 0.9]:
				for across in [0.25, 0.5, 0.75]:
					var coordinate := lerpf(ramp["from"][0], ramp.to[0], along)
					var side := lerpf(ramp.cross[0], ramp.cross[1], across)
					var height := lerpf(ramp["from"][1], ramp.to[1], along)
					var point := Vector3(coordinate, height, side) if ramp.axis == "x" else Vector3(side, height, coordinate)
					point = world.area_to_world(int(area), point)
					var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.3, point - Vector3.UP * 0.3, 2)
					var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
					if hit.is_empty():
						query.from.z += 0.0001
						query.to.z += 0.0001
						hit = world.get_world_3d().direct_space_state.intersect_ray(query)
					if not _require(not hit.is_empty() and absf(hit.position.y - height) < 0.003, "Ramp has a hole or overlapping stair collision: " + str([area, ramp.name, point, hit])):
						return
			ramp_count += 1
	print("RAMP_SURFACES_OK: ", ramp_count, " named ramp/landing surfaces sampled across their width and length")
	for sample in [
		[32, Vector3(1.205002, 0.09, 3.98), Vector3(1.205002, 0.800812, 5.26998), 0.75],
		[32, Vector3(0.9, 0.09, 3.98), Vector3(0.9, 0.81, 5.27), 0.75],
		[32, Vector3(1.5, 0.09, 3.98), Vector3(1.5, 0.81, 5.27), 0.75],
		[32, Vector3(-2.23, -0.15, -2.6), Vector3(-1.45, 0.21, -2.6), 0.18],
		[52, Vector3(5.94, -0.45, 0), Vector3(5.08, -0.02, 0), -0.08],
		[56, Vector3(-6.66, -0.35, -0.8), Vector3(-7.3, -0.02, -0.8), -0.08],
		[56, Vector3(-6.28, -0.54, -0.8), Vector3(-7.5, 0.02, -0.8), -0.03],
		[56, Vector3(-6.28, -0.54, -1.1), Vector3(-7.5, 0.02, -1.1), -0.03],
		[56, Vector3(-6.28, -0.54, -0.5), Vector3(-7.5, 0.02, -0.5), -0.03],
		[72, Vector3(-5.24, 1.46, -8.2), Vector3(-5.82, 1.88, -8.2), 1.8],
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
			var start: Vector3 = world.area_to_world(sample[0], sample[1])
			var finish: Vector3 = world.area_to_world(sample[0], sample[2])
			var speed: float = world.player.RUN_SPEED if running else world.player.WALK_SPEED
			var path: Vector3 = sample[2] - sample[1]
			var actions: Array = (["move_left", "move_right"] if path.x < 0 else ["move_right", "move_left"]) if absf(path.x) > absf(path.z) else (["move_up", "move_down"] if path.z < 0 else ["move_down", "move_up"])
			var frames := roundi((path.length() / speed * 1.4 + 0.2) * Engine.physics_ticks_per_second)
			var top: Vector3 = await _walk(world.player, start, actions[0], frames, running)
			print("STAIR_SAMPLE ", sample[0], " running=", running, " end=", top)
			var progress: float = Vector2(top.x - start.x, top.z - start.z).dot(Vector2(path.x, path.z).normalized())
			if not _require(top.y > sample[3] and progress > Vector2(path.x, path.z).length() - 0.12, "Imported staircase ascent failed: " + str(sample[0])):
				return
			var bottom: Vector3 = await _walk(world.player, finish, actions[1], frames, running)
			if not _require(bottom.y < sample[1].y + 0.12 and world.player.is_on_floor(), "Imported staircase descent failed: " + str([sample[0], bottom])):
				return
	world._change_area(188, Vector3(0.8, 0.02, 0))
	var room_wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 0), "move_right", Engine.physics_ticks_per_second * 2, true)
	if not _require(room_wall.x < 2.01 and world.player.is_on_floor(), "Player crossed the original room ground boundary"):
		return
	# Reported hospital door: walking stops outside; the action key still opens the exit.
	for running in [false, true]:
		world._change_area(40, Vector3(2.4, 0.05, -0.28))
		var doorstep: Vector3 = await _walk(world.player, Vector3(2.4, 0.05, -0.28), "move_up", Engine.physics_ticks_per_second, running)
		if not _require(doorstep.z > -0.74 and doorstep.z < -0.6, "Player crossed the closed hospital door: " + str(doorstep)):
			return
		world.set_physics_process(true)
		Input.action_press("interact")
		await _frames(3)
		Input.action_release("interact")
		for frame in Engine.physics_ticks_per_second*3:
			await _frames(1)
			if not world.transitioning:
				break
		world.set_physics_process(false)
		if not _require(world.current_area == 188, "Hospital collision blocked its action exit"):
			return
		print("HOSPITAL_DOOR_OK running=", running, " stop=", doorstep, "; E entered clinic")
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
	_ramp(fixtures, 2, 0.08)
	_ramp(fixtures, -3, 0.16)
	_ramp(fixtures, 3, 0.04)
	_box(fixtures, Vector3(0, 0.08, -1), Vector3(0.5, 0.16, 0.6), true)
	_ramp(fixtures, -1, 0.16, 0.12) # Same 53.13-degree grade as the reported road joint.
	await _frames(3)
	for running in [false, true]:
		var wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 0), "move_left", 90, running)
		if not _require(wall.x > 0.15 and wall.y < 0.01, "Player climbed or crossed a tall obstacle"):
			return
		var thin_wall: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, -2), "move_left", 90, running)
		if not _require(thin_wall.x > 0.065 and thin_wall.y < 0.01, "Player tunneled through a thin obstacle"):
			return
		var ceiling: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 2), "move_left", 90, running)
		if not _require(ceiling.x > 0.3, "Player crossed a ramp without sufficient headroom"):
			return
		var speed: float = world.player.RUN_SPEED if running else world.player.WALK_SPEED
		var frames := roundi(0.8 / speed * Engine.physics_ticks_per_second)
		var high_tread: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, -3), "move_left", frames, running)
		if not _require(absf(high_tread.x) < 0.25 and high_tread.y > 0.15, "Player did not follow the ramp onto the raised landing"):
			return
		var steep_grade: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, -1), "move_left", frames, running)
		# Finish on the landing rather than requiring one exact uphill travel time.
		if steep_grade.x >= 0.25:
			Input.action_press("move_left")
			if running:
				Input.action_press("run")
			for tick in 60:
				await _frames(1)
				if world.player.position.x < 0.2:
					break
			Input.action_release("move_left")
			Input.action_release("run")
			await _frames(4)
			steep_grade = world.player.position
		print("STEEP_GRADE_SAMPLE running=", running, " end=", steep_grade)
		if not _require(steep_grade.x < 0.25 and steep_grade.y > 0.15, "Source walkable 53-degree ramp was classified as a wall"):
			return
		var blocked_face: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 1), "move_left", frames, running)
		if not _require(blocked_face.x > 0.3 and blocked_face.y < 0.02, "Controller climbed a face excluded from original walkable ground"):
			return
		var tight_clearance: Vector3 = await _walk(world.player, Vector3(0.8, 0.02, 3), "move_left", frames, running)
		if not _require(absf(tight_clearance.x) < 0.25 and tight_clearance.y > 0.03, "Valid low-ceiling ramp was blocked"):
			return
	print("COLLISION_CHECK_OK: ", Engine.physics_ticks_per_second, " Hz; walk/run up/down imported stairs; tall/thin obstacles and low ceilings block player")
	world.queue_free()
	await process_frame
	quit()

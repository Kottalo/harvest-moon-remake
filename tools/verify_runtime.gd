extends SceneTree
## Native integration check: imported scene + real input + real physics.
## godot --headless --path . --script tools/verify_runtime.gd

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

func _run() -> void:
	var farm = load("res://game/world/world.tscn").instantiate()
	root.add_child(farm)
	await _frames(90)
	if not _require(farm.player.is_on_floor(), "Player did not land on the imported farm"):
		return
	var start: Vector3 = farm.player.position
	var camera_delta: Vector3 = farm.camera.position - start
	if not _require(absf(Vector2(camera_delta.x, camera_delta.z).length() - 10.8) < 0.00001 and absf(camera_delta.y - 5.4) < 0.00001 and absf(camera_delta.length() - sqrt(145.8)) < 0.00001, "User's 20% farther camera distance was not applied"):
		return
	# User-visible regression: the four keys project NE, SW, NW, SE, with four facings.
	var directions := ["move_up", "move_down", "move_left", "move_right"]
	var screen_signs := [Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, 1)]
	var facings := [2, 0, 1, 3]
	for i in 4:
		farm.player.position = start
		farm.player.velocity = Vector3.ZERO
		Input.action_press(directions[i])
		await _frames(30)
		Input.action_release(directions[i])
		var delta: Vector3 = farm.player.position - start
		var projected := Vector2(farm.camera.basis.x.dot(delta), -farm.camera.basis.y.dot(delta))
		if not _require(projected.x * screen_signs[i].x > 0 and projected.y * screen_signs[i].y > 0 and farm.player.facing == facings[i], "Wrong screen direction or pose: " + directions[i] + str(projected)):
			return
	# Original camera_build_view + GTE H=1000 equations, at the user's 1.2x distance.
	farm.player.position = start
	farm._update_camera()
	var eye := Vector3(6363, -4500, -6363) * 1.2
	var forward := (-eye).normalized()
	var side := Vector3(forward.z, 0, -forward.x).normalized()
	var down := forward.cross(side).normalized()
	var size: Vector2 = root.get_visible_rect().size
	for point in [Vector3.ZERO, Vector3(400, 0, 0), Vector3(0, 0, 400), Vector3(150, -100, -150)]:
		var relative: Vector3 = point - eye
		var depth := forward.dot(relative)
		var expected := Vector2(160 + 1000 * side.dot(relative) / depth, 120 + 1000 * down.dot(relative) / depth)
		var actual: Vector2 = farm.camera.unproject_position(start + Vector3(point.x, -point.y, -point.z) / 1000.0)
		actual /= size / Vector2(320, 240)
		if not _require(actual.distance_to(expected) < 0.05, "Original projection mismatch: " + str([actual, expected, size])):
			return
	var entry0: Node3D = farm.get_node("Location/ZoneModel_00")
	var entry1: Node3D = farm.get_node("Location/ZoneModel_01")
	if not _require(entry0.position.is_equal_approx(Vector3(-4.78, 0, -4.28)) and entry1.position.is_equal_approx(Vector3(1.53, 0.04, -3.18)), "Original scene-object placement changed"):
		return
	var distances := []
	for mode in [0, 1, 2]:
		farm.player.position = start
		farm.player.velocity = Vector3.ZERO
		await _frames(3)
		Input.action_press("move_right")
		if mode == 1:
			Input.action_press("move_down")
		if mode == 2:
			Input.action_press("run")
		await _frames(60)
		Input.action_release("move_right")
		Input.action_release("move_down")
		Input.action_release("run")
		var distance: float = farm.player.position.distance_to(start)
		distances.append(distance)
		var expected := 2.19 if mode == 2 else 1.23
		if not _require(absf(distance - expected) < 0.2, "Incorrect input movement: " + str(distances)):
			return
		if not _require(farm.player.is_on_floor(), "Player left the floor while walking"):
			return
	# Find a real vertical farm wall/fence, then move the actual player capsule into it.
	farm.set_physics_process(false)
	var space: PhysicsDirectSpaceState3D = farm.get_world_3d().direct_space_state
	var wall := {}
	for i in 16:
		var angle := float(i) * TAU / 16.0
		var query := PhysicsRayQueryParameters3D.create(Vector3(0, 0.4, 0), Vector3(cos(angle) * 30, 0.4, sin(angle) * 30))
		query.exclude = [farm.player.get_rid()]
		var hit := space.intersect_ray(query)
		if not hit.is_empty() and absf(hit.normal.y) < 0.1:
			wall = hit
			break
	if not _require(not wall.is_empty(), "No imported wall was found"):
		return
	var normal: Vector3 = wall.normal
	farm.player.position = wall.position + normal * 0.7 - Vector3(0, 0.4, 0)
	var collision = farm.player.move_and_collide(-normal * 1.4)
	if not _require(collision != null, "Player passed through imported wall"):
		return
	print("NATIVE_CHECK_OK: 20% farther camera with original perspective/angle, four diagonal screen directions/facings, scene object positions, walk/run=", distances, "; imported wall blocks player")
	farm.queue_free()
	await process_frame
	quit()

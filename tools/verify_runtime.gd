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
	var farm = load("res://scenes/farm.tscn").instantiate()
	root.add_child(farm)
	await _frames(90)
	if not _require(farm.player.is_on_floor(), "Player did not land on the imported farm"):
		return
	var start: Vector3 = farm.player.position
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
		var expected := 4.8 if mode == 2 else 2.6
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
	print("NATIVE_CHECK_OK: landed, walk/diagonal/run distances=", distances, "; imported wall blocks player")
	farm.queue_free()
	await process_frame
	quit()

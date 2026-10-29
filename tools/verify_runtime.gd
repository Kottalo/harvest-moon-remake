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
	# Calibrate on the clear farmyard; field weeds/stones intentionally block paths.
	farm.player.position = Vector3(0,0.05,-2.0)
	farm.player.velocity = Vector3.ZERO
	farm.player.reset_physics_interpolation()
	await _frames(12)
	var start: Vector3 = farm.player.position
	var camera_delta: Vector3 = farm.camera.position - start
	if not _require(absf(Vector2(camera_delta.x, camera_delta.z).length() - 12.96) < 0.00001 and absf(camera_delta.y - 6.48) < 0.00001 and absf(camera_delta.length() - sqrt(209.952)) < 0.00001, "User's 1.44x camera distance was not applied"):
		return
	# Character/world scale stays fixed for distance and orthographic zoom.
	var sprite: Sprite3D = farm.player.get_node("Sprite3D")
	var sprite_size := sprite.get_aabb().size
	var original_offset: Vector3 = farm.camera.eye_offset
	for mode in 4:
		farm.camera.reset_gameplay()
		farm.camera.eye_offset = original_offset * (2.0 if mode == 1 else 1.0)
		farm.overview = mode == 3
		if mode == 2:
			farm.camera.size *= 1.2
		if farm.overview:
			farm._set_overview()
		farm._update_camera()
		var center := sprite.global_position
		var up: Vector3 = farm.camera.global_basis.y
		var unit_pixels: float = farm.camera.unproject_position(center + up * 0.5).distance_to(farm.camera.unproject_position(center - up * 0.5))
		var sprite_pixels: float = farm.camera.unproject_position(center + up * sprite.get_aabb().size.y * 0.5).distance_to(farm.camera.unproject_position(center - up * sprite.get_aabb().size.y * 0.5))
		if not _require(sprite.get_aabb().size.is_equal_approx(sprite_size) and absf(sprite_pixels / unit_pixels - sprite_size.y) < 0.0001, "Player/world proportion changed with camera mode " + str(mode)):
			return
	farm.overview = false
	farm.camera.eye_offset = original_offset
	farm.camera.reset_gameplay()
	farm._update_camera()
	print("PLAYER_SCALE_OK: fixed world dimensions; distance and orthographic zoom preserve player/world ratio")
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
	# Orthographic gameplay: equal world lengths project equally at every depth.
	farm.player.position = start
	farm._update_camera()
	if not _require(farm.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(farm.camera.size,sqrt(209.952)*0.24),"Gameplay camera must stay orthographic at the previous centre-plane framing"): return
	var size: Vector2 = root.get_visible_rect().size
	for depth in [-3.0,0.0,3.0]:
		var centre: Vector3 = start+farm.camera.global_basis.z*depth
		var a: Vector2 = farm.camera.unproject_position(centre-farm.camera.global_basis.x*0.5)
		var b: Vector2 = farm.camera.unproject_position(centre+farm.camera.global_basis.x*0.5)
		if not _require(absf(a.distance_to(b)-size.y/farm.camera.size)<0.001,"Orthographic camera has perspective size changes"): return
	var entry0: Node3D = farm.get_node("Location/ZoneModel_00")
	var entry1: Node3D = farm.get_node("Location/ZoneModel_01")
	if not _require(entry0.position.is_equal_approx(Vector3(-4.78, 0, -4.28)) and entry1.position.is_equal_approx(Vector3(1.53, 0.04, -3.18)), "Original scene-object placement changed"):
		return
	var distances := []
	for mode in [0, 1, 2]:
		farm.player.position = start
		farm.player.velocity = Vector3.ZERO
		await _frames(3)
		var first_tick := Engine.get_physics_frames()
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
		# A loaded editor can advance several physics ticks per rendered frame.
		var seconds := float(Engine.get_physics_frames() - first_tick) / Engine.physics_ticks_per_second
		var measured_speed := distance / seconds
		distances.append(measured_speed)
		var expected := 2.19 if mode == 2 else 1.23
		if not _require(absf(measured_speed - expected) < 0.03, "Incorrect input speed: " + str(distances)):
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
		query.collision_mask = 1 # Solid positioned objects, not the render-only terrain reference.
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
	print("NATIVE_CHECK_OK: orthographic camera with existing angle/framing, four diagonal screen directions/facings, scene object positions, walk/run speeds=", distances, "; imported wall blocks player")
	farm.queue_free()
	await process_frame
	quit()

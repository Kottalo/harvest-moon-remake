extends SceneTree
## Verify every converted scene and every original exit, using the actual runtime transition.

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame

func _run() -> void:
	var farm = load("res://game/world/world.tscn").instantiate()
	root.add_child(farm)
	farm.set_physics_process(false)
	farm.player.set_physics_process(false)
	var checked := 0
	var landed := 0
	var missing_floors := []
	for area in farm.world:
		var info: Dictionary = farm.world[area]
		var spawn := Vector3(info.spawn[0], info.spawn[1], info.spawn[2])
		farm._change_area(int(area), spawn)
		# Exercise the actual player on each destination floor without triggering another exit.
		farm.player.set_physics_process(true)
		await _frames(30)
		if farm.player.is_on_floor():
			landed += 1
		else:
			var ray := PhysicsRayQueryParameters3D.create(farm.player.position + Vector3(0, 0.1, 0), farm.player.position - Vector3(0, 1.0, 0))
			ray.exclude = [farm.player.get_rid()]
			var hit: Dictionary = farm.get_world_3d().direct_space_state.intersect_ray(ray)
			print("FLOOR_DIAGNOSTIC ", area, ": ", farm.player.position, " velocity=", farm.player.velocity, " ray=", hit)
			missing_floors.append(area)
		farm.player.set_physics_process(false)
		for exit in info.exits:
			if int(area) in [52, 56] and int(exit.target) in [52, 56]:
				continue # This connection now uses continuous world coordinates, checked separately.
			farm._change_area(int(area), spawn)
			farm.player.position = Vector3((exit.min[0] + exit.max[0]) * 0.5, spawn.y, (exit.min[1] + exit.max[1]) * 0.5)
			farm.player.facing = int(exit.facing) if int(exit.facing) in [0, 1, 2, 3] else 0
			Input.action_press("interact")
			farm._check_exits(0.0)
			Input.action_release("interact")
			for frame in 180:
				await _frames(1)
				if not farm.transitioning:
					break
			if farm.current_area != int(exit.target):
				push_error("Exit did not reach destination: " + str([area, exit.index, exit.target, farm.current_area]))
				quit(1)
				return
			var expected := Vector3(exit.entry[0], exit.entry[1] + 0.015, exit.entry[2])
			if farm.player.position.distance_to(expected) > 0.01:
				push_error("Exit did not preserve original entry coordinates")
				quit(1)
				return
			checked += 1
	if not missing_floors.is_empty():
		push_error("Entry floors not reached: " + str(missing_floors))
		quit(1)
		return
	print("WORLD_CHECK_OK: ", landed, " scenes with walkable entry floors; ", checked, " non-coast source exits reached their destinations at original coordinates; coast crossing checked separately")
	farm.queue_free()
	await process_frame
	quit()

extends SceneTree
## Compare visible foot anchors against the actual rendered road, not only collision heights.

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	var maximum_error := 0.0
	for z in [4.05, 4.25, 4.45, 4.65, 4.8, 5.0, 5.18, 5.3]:
		world._change_area(32, Vector3(1.205002, 1.0, z))
		await _frames(30)
		var player: CharacterBody3D = world.player
		var sprite: Sprite3D = player.get_node("Sprite3D")
		var point := player.position
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.3, point - Vector3.UP * 0.3, 4)
		var visible: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if visible.is_empty():
			push_error("Missing visible road surface")
			quit(1)
			return
		var error: float = absf(sprite.global_position.y - visible.position.y)
		maximum_error = maxf(maximum_error, error)
		print("VISIBLE_FOOT_SAMPLE ", point, " ground=", visible.position.y, " foot=", sprite.global_position.y, " error=", error)
		if not player.is_on_floor() or error > 0.025 or absf(sprite.position.x) > 0.00001 or absf(sprite.position.z) > 0.00001:
			push_error("Visible feet do not match the rendered road")
			quit(1)
			return
		for facing in 4:
			player.facing = facing
			for motion in [Vector2.ZERO, [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][facing]]:
				for running in [false, true]:
					for frame in 20:
						player._update_animation(motion, running, 1.0 / 30.0)
						var current: Dictionary = player.animation_data.animations[player.animation][player.animation_frame]
						assert(absf(sprite.offset.y + 64 - current.foot_y) < 0.00001, "Frame foot anchor shifted")
	for x in [0.9, 1.205002, 1.5]:
		world._change_area(32, Vector3(x, 0.81, 5.27))
		await _frames(20)
		for action in ["move_up", "move_down"]:
			Input.action_press(action)
			for tick in 180:
				await _frames(1)
				var player: CharacterBody3D = world.player
				var point := player.position
				var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.2, point - Vector3.UP * 0.2, 4)
				var visible: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
				if player.is_on_floor() and not visible.is_empty() and visible.normal.y >= cos(player.floor_max_angle):
					var error: float = absf(player.sprite.global_position.y - visible.position.y)
					maximum_error = maxf(maximum_error, error)
					if error > 0.025:
						push_error("Moving feet left the visible road: " + str([point, error]))
						quit(1)
						return
				if (action == "move_up" and point.z < 3.9) or (action == "move_down" and point.z > 5.27):
					break
			Input.action_release(action)
		print("VISIBLE_ROAD_RETURN ", x, " end=", world.player.position)
		if world.player.position.y < 0.79 or not world.player.is_on_floor():
			push_error("Grounding fix blocked the road return")
			quit(1)
			return
	print("PLAYER_GROUNDING_OK: stationary and moving rendered ground/foot max error=", maximum_error, "; idle/walk/run foot anchors remain at the support point; three road lanes down/up")
	world.queue_free()
	await process_frame
	quit()

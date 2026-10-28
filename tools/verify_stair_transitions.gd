extends SceneTree
## Walk actual room-to-room exits with physical key events; check automatic versus action-gated routes.
const DIRECTIONS := [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
const KEYS := [KEY_DOWN, KEY_LEFT, KEY_UP, KEY_RIGHT]

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

func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	var automatic := 0
	var manual := 0
	for area in world.world:
		if int(area) < 80:
			continue
		for exit in world.world[area].exits:
			if int(exit.target) < 80:
				continue
			var facing := int(exit.facing)
			assert(facing in [0, 1, 2, 3])
			var center := Vector3((exit.min[0] + exit.max[0]) * 0.5, 0, (exit.min[1] + exit.max[1]) * 0.5)
			var start: Vector3 = center - DIRECTIONS[facing] * 0.45
			world._change_area(int(area), start + Vector3.UP)
			await _frames(2)
			var query := PhysicsRayQueryParameters3D.create(start + Vector3.UP * 2, start - Vector3.UP * 2, 2)
			var floor_hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if floor_hit.is_empty():
				query.from.x += 0.001
				query.to.x += 0.001
				floor_hit = world.get_world_3d().direct_space_state.intersect_ray(query)
			if floor_hit.is_empty():
				push_error("Missing original approach floor: " + str([area, exit.index, start]))
				quit(1)
				return
			world.player.position = floor_hit.position + Vector3.UP * 0.01
			world.player.velocity = Vector3.ZERO
			world.transition_cooldown = 0
			await _frames(10)
			_key(KEYS[facing], true)
			var used_action := false
			for frame in 180:
				await _frames(1)
				if world.current_area != int(area):
					break
				if exit.requires_action and not used_action and not world.nearby_exit.is_empty() and int(world.nearby_exit.index) == int(exit.index):
					_key(KEY_E, true)
					await _frames(1)
					_key(KEY_E, false)
					used_action = true
			_key(KEYS[facing], false)
			_key(KEY_E, false)
			if world.current_area != int(exit.target) or used_action != bool(exit.requires_action):
				push_error("Real stair transition failed: " + str([area, exit.target, world.current_area, world.player.position, used_action, exit.requires_action]))
				quit(1)
				return
			if used_action:
				manual += 1
			else:
				automatic += 1
			print("STAIR_ROUTE_OK: ", area, " -> ", exit.target, " action=", used_action)
	assert(automatic > 0 and manual > 0)
	print("STAIR_TRANSITIONS_OK: ", automatic, " automatic and ", manual, " action-gated room transitions via physical keys")
	world.queue_free()
	await process_frame
	quit()

extends SceneTree
## Walk actual room-to-room exits with physical key events; check automatic versus action-gated routes.
const DIRECTIONS := [Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(1, 0, 0)]
const KEYS := [KEY_DOWN, KEY_LEFT, KEY_UP, KEY_RIGHT]
const DoorAccess := preload("res://game/world/door_access.gd")

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

func _locked(world, exit: Dictionary) -> bool:
	var clock = world.day_cycle
	return not DoorAccess.refusal(int(exit.event),clock.minute,clock.season,clock.day,clock.weekday,
		world.npcs.scheduled_areas).is_empty()

func _walk_exit(world, area: int, exit: Dictionary, locked: bool) -> bool:
	var movement: int = KEYS[int(exit.facing)]
	var pressed := false
	_key(movement,true)
	for frame in 180:
		await _frames(1)
		if world.current_area!=area or world.npcs.dialogue.notice_open:
			break
		if (exit.requires_action or locked) and not pressed and world.nearby_exit.get("index",-1)==exit.index:
			_key(KEY_Z,true)
			await _frames(1)
			_key(KEY_Z,false)
			pressed = true
	_key(movement,false)
	if locked:
		var refused: bool = world.current_area==area and world.nearby_exit_locked and world.npcs.dialogue.notice_open
		world.npcs.dialogue.close()
		return refused
	return world.current_area==int(exit.target) and pressed==bool(exit.requires_action)

func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	var automatic := 0
	var manual := 0
	var refusals := 0
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
			world.day_cycle.day = 2
			world.day_cycle.weekday = 2
			world.day_cycle.minute = 660
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
			await _frames(10)
			var locked := _locked(world,exit)
			if not await _walk_exit(world,int(area),exit,locked):
				push_error("Real stair transition failed: " + str([area,exit.target,world.current_area,world.player.position,locked]))
				quit(1)
				return
			if locked:
				refusals += 1
				continue
			if exit.requires_action:
				manual += 1
			else:
				automatic += 1
			print("STAIR_ROUTE_OK: ", area, " -> ", exit.target, " action=",exit.requires_action)
			# Reverse immediately from the real arrival position: no teleport, wait or state reset.
			var reverse := {}
			for candidate in world.world[str(int(exit.target))].exits:
				if int(candidate.target) == int(area):
					reverse = candidate
					break
			assert(not reverse.is_empty())
			var reverse_locked := _locked(world,reverse)
			if not await _walk_exit(world,int(exit.target),reverse,reverse_locked):
				push_error("Immediate stair return failed: " + str([exit.target,area,world.current_area,world.player.position,reverse_locked]))
				quit(1)
				return
			if reverse_locked:
				refusals += 1
			print("STAIR_RETURN_OK: ",exit.target," -> ",area," immediate=true locked=",reverse_locked)
	assert(automatic > 0 and manual > 0 and refusals > 0)
	print("STAIR_TRANSITIONS_OK: ",automatic," automatic, ",manual," action-gated, ",refusals," locked attempts; immediate returns use real keys")
	world.queue_free()
	await process_frame
	quit()

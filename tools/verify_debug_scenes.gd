extends SceneTree
## Playable F2 fixtures share real mechanics and leave the suspended world intact.

const Grid := preload("res://game/npc/manhattan_grid.gd")


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func _frames(count: int) -> void:
	for i in count:
		await physics_frame
		await process_frame


func _press(key: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = key
		event.keycode = key
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(1)


func _run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	await _frames(8)
	var menu = world.get_node("DebugScenes")
	var minute: int = world.day_cycle.minute
	var position: Vector3 = world.player.position
	var bag: Array = world.economy.rucksack.tools.duplicate()
	await _press(KEY_F2)
	if not _check(menu.menu.visible and paused,"F2 did not open the test menu"): return
	await _press(KEY_F2)
	if not _check(not menu.menu.visible and not paused,"F2 did not close the test menu"): return

	await _press(KEY_F2)
	await _press(KEY_Z)
	var arena = menu.fixture
	if not _check(is_instance_valid(arena) and arena.name=="NpcWalkTest" and not paused
			and world.process_mode==Node.PROCESS_MODE_DISABLED and arena.get_world_3d()!=world.get_world_3d(),
			"NPC scene was not isolated from gameplay"): return
	for tick in 120:
		await _frames(1)
		if arena.npc.walking:
			break
	if not _check(arena.npc.walking and arena.npc.ground_shadow.visible,
			"The real villager did not start walking in the fixture"): return
	var start := Grid.cell_at(arena.get_node("Start").position)
	var goal := Grid.cell_at(arena.get_node("Goal").position)
	var cells: Array[Vector2i] = arena.npc.grid.path(start,goal)
	var directions := {}
	for i in range(1,cells.size()):
		var step := cells[i]-cells[i-1]
		if not _check(step.abs().x+step.abs().y==1,"The open path skipped an adjacent cell"): return
		directions[step] = true
	var distance := (goal-start).abs()
	if not _check(cells.size()==distance.x+distance.y+1 and directions.size()==2
			and cells[distance.x]==Vector2i(goal.x,start.y),"Open diagonal endpoints did not get a single-turn Manhattan route"): return
	await _press(KEY_B)
	if not _check(arena.obstacle.visible and arena.obstacle.collision_layer==1,
			"B did not enable the arena obstacle through the game window"): return
	for tick in 500:
		await _frames(1)
		if arena.npc.waypoint==0:
			break
	if not _check(arena.npc.waypoint==0 and arena.npc.position.distance_to(arena.get_node("Goal").position)<0.2,
			"Thomas did not walk around the inserted wall to the marker"): return

	await _press(KEY_F2)
	menu.rows.get_child(2).pressed.emit()
	await _frames(6)
	var toolbox = menu.fixture
	if not _check(not is_instance_valid(arena) and toolbox.name=="ToolboxTest" and toolbox.picker.panel.visible
			and toolbox.picker.entries.size()==35 and paused,"Switching fixtures did not open the real toolbox"): return
	await _press(KEY_F2)
	if not _check(menu.menu.visible and paused,"F2 could not open over the paused toolbox"): return
	await _press(KEY_F2)
	if not _check(not menu.menu.visible and toolbox.picker.panel.visible and paused,
			"Closing F2 did not preserve the toolbox pause"): return
	await _press(KEY_X)
	if not _check(not toolbox.picker.panel.visible and not paused,"X was not routed to the toolbox viewport"): return
	await _press(KEY_I)
	if not _check(toolbox.picker.panel.visible and paused,"I did not reopen the standalone toolbox"): return
	toolbox.picker.entries[21].pressed.emit()
	await _frames(30)
	if not _check(toolbox.player.actions.equipped==21 and not toolbox.player.actions.busy()
			and world.economy.rucksack.tools==bag,"Toolbox selection did not stay in the fixture"): return
	await _press(KEY_I)
	await _press(KEY_F2)
	menu.return_button.pressed.emit()
	await _frames(1)
	if not _check(not is_instance_valid(toolbox) and menu.fixture==null and not paused
			and world.process_mode==Node.PROCESS_MODE_INHERIT and world.player.position.is_equal_approx(position)
			and world.day_cycle.minute==minute and world.economy.rucksack.tools==bag,
			"Returning did not restore the existing game and resume its process state"): return
	print("DEBUG_SCENES_OK: F2 and keyboard navigation, separate NPC world, wall toggle and detour, standalone toolbox, preserved game session")
	quit()

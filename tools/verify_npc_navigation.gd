extends SceneTree
## Exercises the real farm NPC and its collision-backed graph, without a game window.
const Grid := preload("res://game/npc/manhattan_grid.gd")

func _initialize() -> void:
	_run.call_deferred()


func _require(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func _run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	if not _verify_fewest_turns():
		return
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world._change_area(0,Vector3(0,0.035,0))
	var start := Vector2i(18,0)
	var goal := Vector2i(12,0)
	var npc = load("res://game/npc/villager.tscn").instantiate()
	npc.world = world
	npc.art = world.npcs.library
	npc.poses = npc.art.catalogue.actors.mayor_thomas.art["6"]
	npc.speed = 0.82
	var from := Grid.center_of(start)
	var to := Grid.center_of(goal)
	npc.set_itinerary([[Vector3(from.x,0,from.y),0,0.0],[Vector3(to.x,0,to.y),0,0.0]],-1)
	world.get_node("Location").add_child(npc)
	for column in range(-1,3):
		for row in range(-1,3):
			var soil := Grid.SOIL_EDGE + Vector2(column,row)*Grid.SOIL_SIZE
			for x in 2:
				for y in 2:
					var point := soil + Vector2(x+0.5,y+0.5)*Grid.CELL_SIZE
					var expected := Vector2i(column*2+x,row*2+y)
					if not _require(Grid.cell_at(Vector3(point.x,0,point.y)) == expected
							and Grid.center_of(expected).is_equal_approx(point),"Soil grid is misaligned"):
						return
	for tick in 100:
		await physics_frame
		if not npc.path.is_empty():
			break
	if not _require(npc.placed and npc.sprite.visible and npc.sprite.texture != null,"Thomas did not appear with the source sprite"):
		return
	var path: Array[Vector2i] = npc.grid.path(start,goal)
	if not _require(path.size() == (goal-start).abs().x + 3 and path[0] == start and path[-1] == goal,
			"Expected a route around the original debris: "+str(path)):
		return
	for i in range(1,path.size()):
		var difference := (path[i]-path[i-1]).abs()
		if not _require(difference.x + difference.y == 1,"A* used a non-cardinal step"):
			return
	if not _require(npc.path==path,"NPC did not follow each adjacent grid centre: "+str(npc.path)):
		return
	if not _require(npc.grid.path(start,Vector2i(14,0)).is_empty(),"Initial debris remained reachable"):
		return
	var screen: Vector2 = world.camera.unproject_position(npc.global_position + Vector3.UP*0.15)
	if not _require(root.get_visible_rect().has_point(screen),"The demo NPC is outside the starting camera: "+str(screen)):
		return
	# A thin wall can block an edge even when both cell centres fit the capsule.
	var a: Vector2i = path[1]
	var b: Vector2i = path[2]
	var a_point: Vector3 = npc.grid.positions[a]
	var b_point: Vector3 = npc.grid.positions[b]
	var thin := Vector3(0.02,0.5,0.16) if a.x != b.x else Vector3(0.16,0.5,0.02)
	var wall := _obstacle(world,(a_point + b_point)*0.5,thin)
	var probe := Grid.new()
	probe.begin(world.get_world_3d().direct_space_state,npc.grid.region,npc,npc.footprint.shape,
		npc.footprint.position.y,0.0)
	probe.build_step(1000)
	if not _require(probe.positions.has(a) and probe.positions.has(b) and probe.path(a,b).size()!=2,
			"The grid should not cross a thin wall"):
		return
	wall.free()
	# Place a new solid object across an already-planned route.
	var blocked: Vector2i = npc.path[0] if npc.path[0]!=start else npc.path[1]
	var point: Vector3 = npc.grid.positions[blocked]
	var blocker := _obstacle(world,point,Vector3(0.18,0.5,0.18))
	var replanned := false
	var frames := {}
	for tick in 9 * Engine.physics_ticks_per_second:
		var previous: Vector3 = npc.global_position
		await physics_frame
		var motion: Vector3 = npc.global_position-previous
		if not _require(minf(absf(motion.x),absf(motion.z))<=0.00001 and motion.length()<Grid.CELL_SIZE,
				"NPC moved diagonally or skipped a cell: "+str(motion)):
			return
		if not replanned and not npc.grid.positions.has(blocked):
			if not _require(npc.wait<=0.0 and (npc.building or not npc.path.is_empty()),
					"NPC delayed replanning after the first collision"):
				return
			replanned = true
		if npc.walking:
			frames[npc.sprite.texture] = true
		if npc.last_cell == goal and npc.waypoint == 2:
			break
	if not _require(replanned and npc.last_cell == goal and frames.size() > 4,
			"NPC did not replan and finish walking around the new obstacle"):
		return
	blocker.free()
	if not await _verify_shadow_clearance(world.player,npc):
		return
	world._change_area(176,Vector3.ZERO)
	if not _require(not is_instance_valid(npc) and world.npcs.active.has("mayor_thomas"),
			"Old actor survived a map change or Thomas did not load at home"):
		return
	var thomas = world.npcs.active["mayor_thomas"]
	world._change_area(0,Vector3.ZERO)
	if not _require(not is_instance_valid(thomas) and not world.npcs.active.has("mayor_thomas"),
			"Thomas was in two areas at the same time"):
		return
	print("NPC_NAVIGATION_OK: 0.2 m grid aligned 2x2 per soil tile; cardinal A*, fewest turns among shortest paths, adjacent-only movement, immediate replanning, walking animation, mutual shadow clearance and location lifecycle")
	quit()


func _verify_fewest_turns() -> bool:
	var start := Vector2i.ZERO
	var goal := Vector2i(8,6)
	var grid := Grid.new()
	grid.region = Rect2i(start,goal+Vector2i.ONE)
	for y in range(goal.y+1):
		for x in range(goal.x+1):
			var cell := Vector2i(x,y)
			# Both one-turn paths are blocked. A shortest route with two
			# turns exists, but native A* takes three on this fixture.
			if cell in [Vector2i(goal.x,0),Vector2i(0,goal.y)]:
				continue
			grid.positions[cell] = Vector3.ZERO
			grid.graph.add_point(grid._id(cell),Vector2(cell))
			for direction in [Vector2i.LEFT,Vector2i.UP]:
				if grid.positions.has(cell+direction):
					grid.graph.connect_points(grid._id(cell),grid._id(cell+direction))
	var route := grid.path(start,goal)
	if not _require(route.size()==goal.x+goal.y+1 and route[0]==start and route[-1]==goal,
			"Fewer turns changed the minimum route length or endpoint"):
		return false
	var turns := 0
	var previous := route[1]-route[0]
	for index in range(1,route.size()):
		var step := route[index]-route[index-1]
		if not _require(step.abs().x+step.abs().y==1
				and grid.graph.are_points_connected(grid._id(route[index-1]),grid._id(route[index])),
				"Turn preference stepped outside the four-connected graph"):
			return false
		turns += int(step!=previous)
		previous = step
	return _require(turns==2,"Shortest obstacle detour made unnecessary turns: "+str(route))


func _verify_shadow_clearance(player: CharacterBody3D, npc: CharacterBody3D) -> bool:
	var player_shadow = player.get_node("GroundShadow")
	var npc_shadow = npc.get_node("GroundShadow")
	if not _require(player_shadow.visible and npc_shadow.visible and player_shadow.texture == npc_shadow.texture
			and player_shadow.material_override != npc_shadow.material_override,"Characters did not share the source ground shadow correctly"):
		return false
	var from: Vector3 = npc.grid._ground(Vector2(-1.9,-2.5))
	var to: Vector3 = npc.grid._ground(Vector2(-1.2,-2.5))
	if not _require(from.is_finite() and to.is_finite(),"Shadow clearance fixture needs open farm ground"):
		return false
	npc.set_physics_process(false)
	player.global_position = from + Vector3.UP*0.001
	npc.global_position = to
	player.reset_physics_interpolation()
	npc.reset_physics_interpolation()
	var spacing: float = player_shadow.footprint_radius() + npc_shadow.footprint_radius() + player_shadow.CONTACT_GAP
	for tick in 5:
		await physics_frame
	Input.action_press("move_right")
	for tick in Engine.physics_ticks_per_second:
		await physics_frame
	Input.action_release("move_right")
	var gap := npc.global_position.x - player.global_position.x
	if not _require(absf(gap-spacing)<0.001 and player_shadow.global_position.distance_to(player.global_position)<0.002,
			"Player did not stop at Thomas's shadow: "+str(gap)):
		return false
	Input.action_press("move_left")
	for tick in Engine.physics_ticks_per_second/2:
		await physics_frame
	Input.action_release("move_left")
	if not _require(player.global_position.x < from.x,"Player could not leave shadow contact"):
		return false
	player.set_physics_process(false)
	player.global_position = from
	var destination := Vector2i(100,100)
	npc.grid.positions[destination] = from
	npc.itinerary = [[from,0,0.0]]
	npc.waypoint = 0
	npc.path.assign([destination])
	npc.building = false
	npc.wait = 0.0
	npc.set_physics_process(true)
	for tick in Engine.physics_ticks_per_second:
		await physics_frame
	gap = npc.global_position.x - player.global_position.x
	if not _require(absf(gap-spacing)<0.001 and npc_shadow.global_position.is_equal_approx(npc.global_position),
			"Thomas did not stop at the player's shadow: "+str(gap)):
		return false
	for tick in 3*Engine.physics_ticks_per_second:
		await physics_frame
	if not _require(npc.waypoint==0,"Thomas discarded his destination while the player blocked it"):
		return false
	var blocked_at := npc.global_position
	player.global_position += Vector3.BACK*2
	for tick in 5*Engine.physics_ticks_per_second:
		await physics_frame
		if npc.waypoint==1:
			break
	return _require(npc.waypoint==1 and npc.global_position.distance_to(from)<=Grid.CELL_SIZE*sqrt(2.0)+0.002
			and npc.global_position.distance_to(blocked_at)>0.15,
			"Thomas did not resume his route: "+str([npc.global_position,from,npc.waypoint]))


func _obstacle(parent: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	blocker.add_child(shape)
	parent.add_child(blocker)
	blocker.global_position = point + Vector3.UP*size.y*0.5
	blocker.force_update_transform()
	return blocker

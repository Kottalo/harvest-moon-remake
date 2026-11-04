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
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	var npc = world.get_node("Location/Thomas")
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
		if npc.active:
			break
	if not _require(npc.active and npc.sprite.visible and npc.sprite.texture != null,"Thomas did not appear with the source sprite"):
		return
	var start: Vector2i = npc.patrol[0]
	var goal: Vector2i = npc.patrol[1]
	var path: Array[Vector2i] = npc.grid.path(start,goal)
	if not _require(path.size() == (goal-start).abs().x + 3 and path[0] == start and path[-1] == goal,
			"Expected a route around the original debris: "+str(path)):
		return
	for i in range(1,path.size()):
		var difference := (path[i]-path[i-1]).abs()
		if not _require(difference.x + difference.y == 1,"A* used a non-cardinal step"):
			return
	if not _require(npc.grid.path(start,Vector2i(14,0)).is_empty(),"Initial debris remained reachable"):
		return
	var screen: Vector2 = world.camera.unproject_position(npc.global_position + Vector3.UP*0.15)
	if not _require(root.get_visible_rect().has_point(screen),"The demo NPC is outside the starting camera: "+str(screen)):
		return
	# A thin wall can block an edge even when both cell centres fit the capsule.
	var a: Vector2i = path[1]
	var b: Vector2i = path[2]
	var from: Vector3 = npc.grid.positions[a]
	var to: Vector3 = npc.grid.positions[b]
	var thin := Vector3(0.02,0.5,0.16) if a.x != b.x else Vector3(0.16,0.5,0.02)
	var wall := _obstacle(world,(from + to)*0.5,thin)
	var probe := Grid.new()
	probe.begin(world.get_world_3d().direct_space_state,npc.search_region,npc,npc.footprint.shape,
		npc.footprint.position.y,0.0)
	probe.build_step(1000)
	if not _require(probe.positions.has(a) and probe.positions.has(b) and probe.path(a,b).size() != 2,
			"Thin wall should break the connection between two otherwise open cells"):
		return
	wall.free()
	# Place a new solid object across an already-planned route.
	var blocked: Vector2i = path[2]
	var point: Vector3 = npc.grid.positions[blocked]
	var blocker := _obstacle(world,point,Vector3(0.18,0.5,0.18))
	var replanned := false
	var frames := {}
	for tick in 9 * Engine.physics_ticks_per_second:
		await physics_frame
		if not npc.grid.positions.has(blocked) and not npc.building:
			replanned = true
		if npc.walking:
			frames[npc.sprite.texture] = true
		if npc.cell == goal and npc.goal_index == 2:
			break
	if not _require(replanned and npc.cell == goal and frames.size() > 4,
			"NPC did not replan and finish walking around the new obstacle"):
		return
	blocker.free()
	world._change_area(80,Vector3.ZERO)
	if not _require(not is_instance_valid(npc) and world.get_node_or_null("Location/Thomas") == null,
			"Farm NPC leaked into an interior"):
		return
	world._change_area(0,Vector3.ZERO)
	if not _require(world.get_node_or_null("Location/Thomas") != null,
			"Farm NPC did not return on the next visit"):
		return
	print("NPC_NAVIGATION_OK: 0.2 m grid aligned 2x2 per soil tile; cardinal A*, native debris detour, dynamic replan, walking animation and location lifecycle")
	quit()


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

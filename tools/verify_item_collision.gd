extends SceneTree
## Real player physics against native field items; no active game/editor interaction.
const DIRECTIONS := [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)]
const ACTIONS := ["move_down","move_left","move_up","move_right"]
var player
var items
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _walk(point: Vector3, facing: int, running: bool, seconds := 0.3) -> Vector3:
	player.position = point+Vector3.UP*0.001
	player.reset_physics_interpolation()
	player.velocity = Vector3.ZERO
	player.facing = facing
	await _frames(2)
	Input.action_press(ACTIONS[facing])
	if running: Input.action_press("run")
	await _frames(ceili(seconds*Engine.physics_ticks_per_second))
	Input.action_release(ACTIONS[facing])
	Input.action_release("run")
	await _frames(2)
	return player.position

func _run() -> void:
	Engine.max_fps = 0
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	var arena := Node3D.new()
	root.add_child(arena)
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 11
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(6,0.1,6)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.05
	floor_body.add_child(floor_shape)
	arena.add_child(floor_body)
	player = load("res://game/player/player.tscn").instantiate()
	arena.add_child(player)
	items = load("res://game/items/loose_items.gd").new()
	arena.add_child(items)
	items.world = {"player":player,"transitioning":false}
	items.catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	items.field_cells.resize(1125)
	items.field_cells.fill(0x167)
	items.records[0] = []
	items.set_area(0)
	var cell := 4*45+11
	var centre := Vector3(0.1885,0,0.1955) # Source cell's 399-unit bounds, not its 400-unit art position.
	for id in [58,62,64]:
		var record := {"id":id,"position":Vector3(0.2,0,0.2),"active":true,"cell":cell}
		items.records[0].append(record)
		items.field_cells[cell] = id
		items._add_record(record)
		await _frames(2)
		for facing in 4:
			var direction: Vector3 = DIRECTIONS[facing]
			var side := Vector3(-direction.z,0,direction.x)
			for offset in [-0.14,0.0,0.14]:
				for running in [false,true]:
					var stop := await _walk(centre-direction*0.5+side*offset,facing,running)
					var reach := (stop-centre).dot(direction)
					if not _require(reach <= -0.258 and reach > -0.275 and stop.y<0.015,"Field item can be crossed/climbed or has an oversized blocker: "+str([id,facing,offset,running,stop,reach])): return
					checks += 1
		# An adjacent empty cell must remain traversable.
		var lane := await _walk(centre+Vector3(0.399,0,-0.5),0,true,0.5)
		if not _require(lane.z>centre.z+0.45,"An item's blocker spills into an adjacent empty cell"): return
		# Use the real item/tool signal path's target selection and removal.
		await _walk(centre-Vector3(0,0,0.5),0,false)
		items.use_tool({58:16,62:11,64:1}[id],0)
		await _frames(2)
		if not _require(not record.active and int(items.field_cells[cell])==0x167,"Clearing an item did not clear its field occupancy"): return
		var cleared := await _walk(centre-Vector3(0,0,0.3),0,true,0.3)
		if not _require(cleared.z>centre.z+0.3 and cleared.y<0.015,"Cleared item left an invisible obstruction"): return
		if id in [58,62]:
			player.position = centre-Vector3(0,-0.001,0.23)
			player.facing = 0
			if not _require(items._placement(id).get("blocked",false),"Placement would create a blocker inside the player's capsule"): return
			player.position = centre-Vector3(0,-0.001,0.31)
			var clear: Dictionary = items._placement(id)
			if not _require(not clear.is_empty() and not clear.get("blocked",false),"A safely reachable empty cell rejects placement"): return
			items.placement = {"cell":cell,"position":record.position}
			items.release_item(id,false)
			await _frames(2)
			var restored := await _walk(centre-Vector3(0,0,0.5),0,true)
			if not _require(restored.z<centre.z-0.258,"Putting the item down did not restore its blocking cell"): return
			items._remove(items.batches[id].records.back())
			await _frames(2)
		print("FIELD_ITEM_OK: ",id," four sides, centre/edges, walk/run, empty neighbour, tool clears obstruction, placement restores")
	print("ITEM_COLLISION_CHECK_OK: ",Engine.physics_ticks_per_second," Hz; ",checks," physical approaches; stone/branch/weeds match blocked source cells")
	arena.queue_free()
	await process_frame
	quit()

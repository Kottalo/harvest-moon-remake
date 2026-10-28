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
	if not _source_offsets(): return
	if not await _authored_prefab(arena): return
	if not await _placement_probe(arena): return
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
			var assisted: Dictionary = items._placement(id)
			if not _require(not assisted.get("blocked",false) and assisted.position.distance_to(player.position+Vector3(0,-0.001,0.4))<0.002,"Cell-edge placement snapped away from the exact forward target"): return
			player.position = centre-Vector3(0,-0.001,0.31)
			var clear: Dictionary = items._placement(id)
			if not _require(not clear.is_empty() and not clear.get("blocked",false),"A safely reachable empty cell rejects placement"): return
			items.placement = {"cell":cell,"position":record.position}
			items.release_item(id,false)
			await _frames(2)
			var dropped: Vector3 = items.batches[id].records.back().position
			var restored := await _walk(centre-Vector3(0,0,0.5),0,true)
			# Native swept contact can conservatively stop up to one run tick early.
			# Exact shape size/centre is checked independently in _source_offsets().
			var gap := dropped.z-restored.z
			if not _require(gap>=0.159 and gap<=0.162+player.RUN_SPEED/Engine.physics_ticks_per_second,"Placed item obstruction does not use the source 100-unit half extent at its actual position: "+str([id,restored,dropped,gap])): return
			items._remove(items.batches[id].records.back())
			await _frames(2)
		print("FIELD_ITEM_OK: ",id," four sides, centre/edges, walk/run, empty neighbour, tool clears obstruction", "; placement restores" if id in [58,62] else "")
	if not await _assisted_placement(arena,floor_body): return
	if not await _placement_retreat(arena,floor_body): return
	print("ITEM_COLLISION_CHECK_OK: ",Engine.physics_ticks_per_second," Hz; ",checks," physical approaches; stone/branch/weeds match blocked source cells")
	arena.queue_free()
	await process_frame
	quit()

func _source_offsets() -> bool:
	for id in [58,62,64]:
		for cell in [0,44,4*45+11,24*45,1124]:
			var column: int = cell%45
			var row: int = cell/45
			var art := Vector3((column*400-4200)/1000.0,0,(row*400-1400)/1000.0)
			var node: Node3D = items._spawn(id,art,true)
			var collision: CollisionShape3D = node.get_node("Obstruction").get_child(0)
			# Independent field_world_to_cell interval, not the runtime _cell_bounds helper.
			var expected := Vector3((column*399-4400+199.5)/1000.0,0.2,(row*399-1600+199.5)/1000.0)
			if not _require(collision.global_position.distance_to(expected)<0.00001 and collision.shape.size.is_equal_approx(Vector3(0.399,0.4,0.399)),"Imported collision offset differs from source 399-unit bounds: "+str([id,cell,collision.global_position,expected])): return false
			node.get_node("Obstruction").collision_layer = 0
			node.queue_free()
		var point := Vector3(0.237,0,0.183)
		var loose: Node3D = items._spawn(id,point,true,false)
		var shape: CollisionShape3D = loose.get_node("Obstruction").get_child(0)
		if not _require(shape.global_position.distance_to(point+Vector3.UP*0.2)<0.00001 and shape.shape.size.is_equal_approx(Vector3(0.2,0.4,0.2)),"Free item offset/extent differs from source farm_record_hit_test + ItemInfo(100,100)"): return false
		loose.get_node("Obstruction").collision_layer = 0
		loose.queue_free()
	print("SOURCE_ITEM_COLLISION_OFFSETS_OK: stone/branch/weeds; 15 source-grid corner/interior boxes incl. 44.5mm X and 24.5mm Z art offsets; free records use centred 100-unit half-width/depth")
	return true

func _probe_blocker(arena: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = point
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	arena.add_child(body)
	return body

func _authored_prefab(arena: Node3D) -> bool:
	var original: PackedScene = items.prefab_scenes[58]
	var prefab: Node3D = original.instantiate()
	var field: CollisionShape3D = prefab.get_node("Obstruction/FieldFootprint")
	var loose: CollisionShape3D = prefab.get_node("Obstruction/LooseFootprint")
	field.shape = field.shape.duplicate()
	field.shape.size = Vector3(0.31,0.36,0.34)
	field.position = Vector3(0.03,0.18,-0.04)
	field.rotation.y = 0.3
	loose.shape = loose.shape.duplicate()
	loose.shape.size = Vector3(0.18,0.3,0.24)
	loose.position = Vector3(0.045,0.15,-0.025)
	loose.rotation.y = 0.25
	var edited := PackedScene.new()
	if not _require(edited.pack(prefab)==OK,"Cannot pack authored item prefab"): return false
	items.prefab_scenes[58] = edited
	items.prefab_definitions.erase(58)
	var point := Vector3(0.2,0,0.2)
	for free_position in [false,true]:
		var expected := loose if free_position else field
		var node: Node3D = items._spawn(58,point,true,not free_position)
		var collision: CollisionShape3D = node.get_node("Obstruction").get_child(0)
		var shift := Vector3.ZERO if free_position else Vector3(-0.0115,0,-0.0045)
		if not _require(collision.global_position.distance_to(point+expected.position+shift)<0.00001 and collision.basis.is_equal_approx(expected.basis) and collision.shape.size.is_equal_approx(expected.shape.size),"Manual prefab box position/rotation/size did not reach the actual runtime collider"): return false
		node.get_node("Obstruction").collision_layer = 0
		node.queue_free()
	player.set_physics_process(false)
	player.position = point-Vector3(0,-0.001,0.4)
	player.facing = 0
	var obstacle := _probe_blocker(arena,point+Vector3(0.11,0.15,0),Vector3(0.01,0.3,0.01))
	await _frames(2)
	var target: Dictionary = items._placement(58)
	if not _require(not target.get("blocked",false) and target.position.distance_to(point)>0.001,"Placement queries ignored the authored collider offset/rotation"): return false
	obstacle.collision_layer = 0
	obstacle.queue_free()
	player.set_physics_process(true)
	items.prefab_scenes[58] = original
	items.prefab_definitions.erase(58)
	prefab.free()
	await _frames(2)
	print("AUTHORED_ITEM_PREFAB_OK: saved prefab edits control field/loose box position, rotation and size; placement uses the same authored footprint")
	return true

func _placement_probe(arena: Node3D) -> bool:
	var centre := Vector3(0.1885,0,0.1955)
	player.set_physics_process(false)
	for facing in 4:
		var direction: Vector3 = DIRECTIONS[facing]
		var side := Vector3(-direction.z,0,direction.x)
		player.position = centre-direction*0.4+Vector3.UP*0.001
		player.facing = facing
		await _frames(2)
		var clear: Dictionary = items._placement(58)
		if not _require(not clear.get("blocked",false) and clear.free_ratio==1.0,"Empty forward detector counts the player as an obstacle"): return false
		for width in [0.4,0.5]:
			var size := Vector3(width,0.4,0.8) if facing%2==0 else Vector3(0.8,0.4,width)
			# Leave the capsule clear of the near edge; every probe row still overlaps.
			var obstacle := _probe_blocker(arena,centre+direction*0.08+side*(-0.4+width*0.5)+Vector3.UP*0.2,size)
			await _frames(2)
			for item in [58,62]:
				var target: Dictionary = items._placement(item)
				var expected := 0.5 if width==0.4 else 0.375
				if not _require(is_equal_approx(target.free_ratio,expected) and target.get("blocked",false)==(expected<0.5),"Forward free-area threshold failed: "+str([facing,item,width,target])): return false
			obstacle.collision_layer = 0
			obstacle.queue_free()
			await _frames(2)
	# Crossing a source grid boundary by 1 mm must move the drop by 1 mm, not a cell.
	for facing in 4:
		for offset in [-0.0005,0.0005]:
			var exact := Vector3(12*0.399-4.4+offset,0,0.1955)
			player.position = exact-DIRECTIONS[facing]*0.4+Vector3.UP*0.001
			player.facing = facing
			var target: Dictionary = items._placement(58)
			if not _require(not target.get("blocked",false) and target.position.distance_to(exact)<0.0001,"Grid-boundary motion rounded the continuous drop point"): return false
	player.position = centre-Vector3(0,0,0.4)+Vector3.UP*0.001
	player.facing = 0
	var strips := []
	for offset in [-0.35,-0.15,0.05,0.25]:
		strips.append(_probe_blocker(arena,centre+Vector3(offset,0.2,0.08),Vector3(0.02,0.4,0.8)))
	await _frames(2)
	var fragmented: Dictionary = items._placement(58)
	if not _require(fragmented.free_ratio>=0.5 and fragmented.get("blocked",false),"Disconnected free slivers did not require a complete landing footprint: "+str(fragmented)): return false
	for obstacle in strips:
		obstacle.collision_layer = 0
		obstacle.queue_free()
	await _frames(2)
	player.set_physics_process(true)
	print("PLACEMENT_PROBE_OK: four facings, stone/branch, clear player exclusion, 50% allowed, 37.5% blocked, fragmented gaps rejected")
	return true

func _assisted_placement(arena: Node3D, floor_body: StaticBody3D) -> bool:
	var centre := Vector3(0.1885,0,0.1955)
	var cell := 4*45+11
	for id in [58,62]:
		for facing in 4:
			player.position = centre-DIRECTIONS[facing]*0.23+Vector3.UP*0.001
			player.velocity = Vector3.ZERO
			player.facing = facing
			await _frames(2)
			var before: Vector3 = player.position
			var target: Dictionary = items._placement(id)
			var expected: Vector3 = before+DIRECTIONS[facing]*0.4
			expected.y = 0
			if not _require(not target.get("blocked",false) and target.position.distance_to(expected)<0.001,"Near-edge placement snapped away from the exact nearest target: "+str([id,facing,target,expected])): return false
			items.placement = target
			items.release_item(id,false)
			await _frames(2)
			var placed: Dictionary = items.batches[id].records.back()
			var shape: CollisionShape3D = placed.node.get_node("Obstruction").get_child(0)
			if not _require(placed.position.distance_to(expected)<0.001 and shape.global_position.distance_to(placed.position+Vector3.UP*0.2)<0.001 and player.position.distance_to(before)<0.002,"Assisted placement moved the player, snapped the item or left its collider on the field grid"): return false
			items._remove(placed)
			await _frames(2)
	# An actual collider must be detected even when the field metadata says soil.
	player.position = centre-Vector3(0,-0.001,0.55)
	player.facing = 0
	var obstacle: Node3D = items._spawn(58,Vector3(0.2,0,0.2),true)
	await _frames(2)
	var beside: Dictionary = items._placement(58)
	if not _require(not beside.get("blocked",false) and maxf(absf(beside.position.x-0.1885),absf(beside.position.z-0.1955))>=0.298,"Placement ignored a real obstacle or failed to find the clear space beside it"): return false
	obstacle.get_node("Obstruction").collision_layer = 0
	obstacle.queue_free()
	await _frames(2)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4,0.6,0.04)
	shape.shape = box
	wall.position = player.position+Vector3(0,0.3,0.15)
	wall.add_child(shape)
	arena.add_child(wall)
	await _frames(2)
	player.actions.carried_id = 58
	items.interact()
	if not _require(items.placement.get("blocked",false) and player.actions.carried_id==58 and not player.actions.busy(),"A solid wall allowed placement through it or lost the carried stone"): return false
	wall.collision_layer = 0
	wall.queue_free()
	floor_body.collision_layer = 0
	await _frames(2)
	if not _require(items._placement(58).get("blocked",false),"Placement accepted a location with no support floor"): return false
	floor_body.collision_layer = 11
	player.position = centre-Vector3(0,-0.001,0.31)
	player.velocity = Vector3.ZERO
	await _frames(2)
	items.field_cells.fill(59) # Source-layout boulders not instantiated in this remake.
	if not _require(not items._placement(58).get("blocked",false),"Invisible source-layout placeholders block otherwise empty ground"): return false
	items.field_cells.fill(0x167)
	items.placement = items._placement(58)
	if not _require(not items.placement.get("blocked",false),"Clear ground was rejected after removing the obstacle"): return false
	for y in range(3,6):
		for x in range(10,13):
			var record := {"id":58,"cell":y*45+x,"position":Vector3(x*0.4-4.2,0,y*0.4-1.4),"active":true}
			items.records[0].append(record)
			items._add_record(record) # Other occupants arrive before release completes.
	player.actions.carried_id = 0
	items.release_item(58,false)
	if not _require(player.actions.carried_id==58 and items.batches[58].records.size()==9,"Release did not revalidate occupancy or lost the item"): return false
	for record in items.batches[58].records.duplicate(): items._remove(record)
	items.field_cells.fill(0x167)
	player.actions.carried_id = 0
	print("ASSISTED_PLACEMENT_OK: four facings, exact unsnapped stone/branch targets and colliders, player stays put on clear ground, real obstacles, wall, support floor, no invisible-placeholder blocks, release revalidation and no item loss")
	return true

func _placement_retreat(arena: Node3D, floor_body: StaticBody3D) -> bool:
	var centre := Vector3(0.1885,0,0.1955)
	player.actions.item_released.connect(items.release_item)
	for facing in 4:
		var direction: Vector3 = DIRECTIONS[facing]
		player.position = centre-direction*0.4+Vector3.UP*0.001
		player.velocity = Vector3.ZERO
		player.facing = facing
		await _frames(2)
		var wall_size := Vector3(4,0.4,0.04) if facing%2==0 else Vector3(0.04,0.4,4)
		var wall := _probe_blocker(arena,centre-direction*0.14+Vector3.UP*0.2,wall_size)
		await _frames(2)
		var before: Vector3 = player.position
		var target: Dictionary = items._placement(58)
		if not _require(not target.get("blocked",false) and target.backstep>0 and target.backstep<0.05 and target.position.distance_to(centre)<0.276,"Nearest continuous landing did not allow a small safe retreat: "+str([facing,target])): return false
		player.actions.carried_id = 58
		items.interact()
		if not _require(player.actions.busy(),"Assisted retreat did not start the actual drop animation"): return false
		await _frames(ceili(1.2*Engine.physics_ticks_per_second))
		var record: Dictionary = items.batches[58].records.back()
		var retreat: Vector3 = player.position-before
		if not _require(player.actions.carried_id==0 and not player.actions.busy() and absf(retreat.dot(direction)+target.backstep)<0.002 and record.position.distance_to(target.position)<0.001,"Actual drop animation did not keep the closest point and move the player safely backward"): return false
		items._remove(record)
		await _frames(2)
		player.position = before
		player.velocity = Vector3.ZERO
		var rear_size := Vector3(4,0.4,0.04) if facing%2==0 else Vector3(0.04,0.4,4)
		var rear := _probe_blocker(arena,before-direction*0.085+Vector3.UP*0.2,rear_size)
		await _frames(2)
		var beside: Dictionary = items._placement(58)
		if not _require(not beside.get("blocked",false) and beside.backstep==0 and beside.position.distance_to(centre)>target.position.distance_to(centre),"Blocked retreat did not choose a safe alternative instead of pushing through the rear wall"): return false
		rear.collision_layer = 0
		rear.queue_free()
		floor_body.collision_layer = 3 # Placement floor remains; backstep walkability is absent.
		await _frames(2)
		var unsupported: Dictionary = items._placement(58)
		if not _require(not unsupported.get("blocked",false) and unsupported.backstep==0,"Retreat accepted unsupported ground"): return false
		floor_body.collision_layer = 11
		wall.collision_layer = 0
		wall.queue_free()
		await _frames(2)
	player.actions.item_released.disconnect(items.release_item)
	print("PLACEMENT_RETREAT_OK: actual drop animation in all four facings keeps nearest point with small swept retreat; rear obstacles and missing support use safe alternatives")
	return true

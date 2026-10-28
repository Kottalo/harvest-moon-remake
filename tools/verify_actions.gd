extends SceneTree
## All source tool families/tiers/facings, real pickup input, door timing and fade clocks.
var world
var checks := 0

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

func _finish_action(action) -> bool:
	for frame in 900:
		if action.state == "fishing_wait":
			action.play("fishing",world.player.facing+4,"reel")
		if not action.busy():
			return true
		action.advance(1.0/60.0)
	return _require(false,"Source action did not finish: "+str([action.bank,action.range_id,action.state]))

func _key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _run() -> void:
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	await _frames(10)
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	var action = world.player.actions
	# This loop checks animation ranges; field results have their own real-input check.
	action.tool_used.disconnect(world.farm_field.use_tool)
	for kind in 5:
		for grade in 5:
			for facing in 4:
				for charged in [false,true]:
					world.player.facing = facing
					action.equipped = kind*5+1
					action.upgrade = grade
					if not _require(action.start_tool(),"Could not start a farm tool"):
						return
					if charged:
						action.advance(grade*20.0/30.0)
					var level: int = grade if charged else 0
					action.release_tool()
					if not _require(action.range_id==[72,92,112,132,152][kind]+facing*5+level and action.frame==level+1 and action.bank=="tool_%d"%grade,"Wrong source tool range, charge release frame or metal palette"):
						return
					if not _finish_action(action):
						return
					if not _require(world.player.sprite.offset==Vector2(0,53) and is_equal_approx(world.player.sprite.pixel_size,0.009827848),"Action changed the fixed world size or common pivot"):
						return
					checks += 1
	for tool in [26,27,28,29,56,57,30,31,32,34]:
		for facing in 4:
			world.player.facing = facing
			action.equipped = tool
			if not _require(action.start_tool(),"Could not start auxiliary tool "+str(tool)) or not _finish_action(action):
				return
			checks += 1
	for facing in 4:
		for grade in 5:
			world.player.facing = facing
			action.upgrade = grade
			action.play("refill",facing*5+grade,"refill")
			if not _finish_action(action):
				return
			checks += 1
	action.equipped = 1
	action.upgrade = 4
	action.start_tool()
	action.advance((80.0+61.0)/30.0)
	if not _require(action.state=="overcharge","Source overcharge timeout was lost") or not _finish_action(action):
		return
	print("TOOLS_OK: ",checks," source combinations; uncharged/charged, all metal tiers/facings, auxiliary tools and refills")
	action.tool_used.connect(world.farm_field.use_tool)
	world.player.set_physics_process(true)
	world.set_physics_process(true)
	var weed: Dictionary
	for record in world.loose_items.records[0]:
		if record.id == 64:
			weed = record
			break
	world._change_area(0,weed.position-Vector3(0,0,0.224)+Vector3.UP*0.05)
	world.player.facing = 0
	await _frames(20)
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	await _frames(30)
	if not _require(action.carried_id==64 and not weed.active and action.held_sprite.visible,"Real pickup input did not transfer the source weed into the hand"):
		return
	_key(KEY_RIGHT,true)
	await _frames(6)
	_key(KEY_RIGHT,false)
	if not _require(action.range_id==18 and action.carried_id==64,"Carry walking did not use source range 15+facing"):
		return
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	await _frames(45)
	if not _require(action.carried_id==0 and world.loose_items.flights.is_empty(),"Release/throw did not clear the hand and finish its source fall"):
		return
	print("CARRY_OK: physical E pickup, real carry walking and E discard; no duplicated item")
	var stone: Dictionary
	for record in world.loose_items.records[0]:
		if record.active and record.id == 58:
			stone = record
			break
	world._change_area(0,stone.position-Vector3(0,0,0.224)+Vector3.UP*0.05)
	world.player.facing = 0
	await _frames(20)
	var untouched := []
	for record in world.loose_items.records[0]:
		if record.active and record != stone:
			untouched.append({"record":record,"node_id":record.node.get_instance_id()})
	var batch_ids := {}
	for item in world.loose_items.batches:
		var mesh: MultiMesh = world.loose_items.batches[item].mesh
		batch_ids[item] = [mesh.get_instance_id(),mesh.instance_count]
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	await _frames(30)
	if not _require(action.carried_id==58 and int(world.loose_items.field_cells[stone.cell])==0x167,"Stone pickup did not free its original field cell"):
		return
	var planned: Dictionary = world.loose_items._placement(58)
	if not _require(not planned.get("blocked",false),"Stone has no valid continuous placement target"):
		return
	_key(KEY_E,true)
	await _frames(2)
	_key(KEY_E,false)
	await _frames(30)
	var copies := 0
	for record in world.loose_items.records[0]:
		if record.active and record.id==58 and record.position.distance_to(planned.position)<0.001:
			copies += 1
	var dropped: Dictionary = world.loose_items.batches[58].records.back()
	if not _require(action.carried_id==0 and copies==1 and dropped.free_position and world.loose_items.flights.is_empty() and int(world.loose_items.field_cells[dropped.cell])==58,"Continuous stone placement failed or duplicated the item"):
		return
	world.player.position.z -= 0.2
	world.player.velocity = Vector3.ZERO
	world.player.reset_physics_interpolation()
	await _frames(2)
	var approach: Vector3 = world.player.position
	_key(KEY_DOWN,true)
	await _frames(40) # The smaller source loose-item box takes longer to reach.
	_key(KEY_DOWN,false)
	if not _require(absf(world.player.position.z-(dropped.position.z-0.16))<0.006 and world.player.position.z>approach.z+0.02,"Placed stone did not restore its source-size obstruction at its actual position: "+str([approach,world.player.position,dropped.position])):
		return
	print("PLACEMENT_OK: physical E places one stone at its continuous target, restores obstruction at its actual position and preserves field bookkeeping")
	# Exercise hole removal, tail removal, an empty batch and repeated slot reuse.
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	var items = world.loose_items
	var placed: Dictionary = items.batches[58].records.back()
	for i in 24:
		items._remove(placed)
		items.placement = {"cell":placed.cell,"position":placed.position}
		items.release_item(58,false)
		if not _require(action.carried_id==0,"Repeated continuous placement failed and restored the held item"):
			return
		placed = items.batches[58].records.back()
		await _frames(1)
	for saved in untouched:
		if not _require(saved.record.active and saved.record.node.get_instance_id()==saved.node_id,"Placing one stone rebuilt an unrelated item/collider"):
			return
	# Emptying a type must not destroy/reallocate its GPU batch.
	for record in items.batches[58].records.duplicate():
		items._remove(record)
	if not _require(items.batches[58].mesh.visible_instance_count==0,"Empty stone batch still draws instances"):
		return
	var flight: Node3D = items._spawn(64,Vector3(0,2,0),false)
	items.flights.append({"node":flight,"direction":Vector3.ZERO,"velocity":0.0,"ground":0.0})
	items.placement = {"cell":placed.cell,"position":placed.position}
	items.release_item(58,false)
	if not _require(is_instance_valid(flight) and not flight.is_queued_for_deletion() and items.flights.size()==1,"Placement reset an unrelated item in flight"):
		return
	for item in items.batches:
		var batch: Dictionary = items.batches[item]
		if not _require(batch.mesh.get_instance_id()==batch_ids[item][0] and batch.mesh.instance_count==batch_ids[item][1],"Placement rebuilt/reallocated the GPU batch"):
			return
		if not _require(batch.mesh.visible_instance_count==batch.records.size(),"Visible batch count differs from live items"):
			return
		for slot in batch.records.size():
			var record: Dictionary = batch.records[slot]
			# The headless dummy renderer returns identity for instance transforms.
			# The isolated GPU run also checks the actual render-server coordinates.
			var position_ok: bool = DisplayServer.get_name()=="headless" or batch.mesh.get_instance_transform(slot).origin.is_equal_approx(record.position)
			if not _require(record.active and record.batch_slot==slot and record.node.position.is_equal_approx(record.position) and position_ok,"Dense batch swap changed an item's displayed position: "+str([item,slot,record.active,record.batch_slot,record.position,batch.mesh.get_instance_transform(slot).origin])):
				return
	print("INCREMENTAL_ITEMS_OK: physical pickup/place and 24 repeats preserve unrelated nodes/colliders, GPU batches/capacity and flights; empty batch restores correctly")
	var location := Node3D.new()
	var panel := Node3D.new()
	panel.name = "ZoneModel_00"
	location.add_child(panel)
	var twin := Node3D.new()
	twin.name = "ZoneModel_01"
	location.add_child(twin)
	root.add_child(location)
	var doors = load("res://game/world/source_doors.gd").new()
	root.add_child(doors)
	doors.set_physics_process(false)
	doors.open(location,{"model":0,"twin":1},0)
	for i in 16:
		doors._physics_process(1.0/30.0)
	if not _require(is_equal_approx(panel.rotation.y,-1056.0*TAU/4096) and is_equal_approx(twin.rotation.y,-panel.rotation.y),"Door acceleration/hinge or mirrored twin differs from source"):
		return
	for i in 27:
		doors._physics_process(1.0/30.0)
	if not _require(is_zero_approx(panel.rotation.y),"Door did not close after source hold and accelerated return"):
		return
	print("DOORS_OK: 16 opening ticks, 11 held ticks, 16 closing ticks, mirrored twin")
	var effect = world.transition_effect
	effect.set_process(false)
	for rate in [60,120]:
		effect.start_out()
		for i in int(rate*0.7):
			effect._process(1.0/rate)
		if not _require(effect.phase=="black" and effect.shade==1,"Source old-frame subtractive fade timing changed"):
			return
		effect.start_in()
		for i in int(rate*0.15):
			effect._process(1.0/rate)
		if not _require(effect.phase=="idle" and effect.shade==0,"Source 60 Hz new-scene fade timing changed"):
			return
	print("TRANSITIONS_OK: old frame subtracts 12/255 at 30 Hz; new scene fades at 60 Hz; identical at 60/120 FPS")
	print("ACTIONS_CHECK_OK")
	world.queue_free()
	location.queue_free()
	doors.queue_free()
	await process_frame
	quit()

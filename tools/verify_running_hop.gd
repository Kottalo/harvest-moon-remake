extends SceneTree
## Actual movement keys: one ground item, supported landing, source hop arc and restored collision.
const DIRS := [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)]
const KEYS := [KEY_DOWN,KEY_LEFT,KEY_UP,KEY_RIGHT]
var player
var items
var arena: Node3D
var floor_body: StaticBody3D
var checks := 0
func _initialize() -> void: run.call_deferred()
func require_ok(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func frames(seconds: float) -> void:
	var until := Engine.get_physics_frames()+ceili(seconds*Engine.physics_ticks_per_second)
	while Engine.get_physics_frames()<until:
		await physics_frame
		await process_frame
func key(code: int, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func box(point: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var resource := BoxShape3D.new()
	resource.size = size
	shape.shape = resource
	body.add_child(shape)
	body.position = point
	arena.add_child(body)
	return body
func drive(facing: int,running: bool,lateral := 0.0) -> Dictionary:
	player.hop.cancel()
	player.actions.state = ""
	player.position = -DIRS[facing]*0.65-Vector3(-0.03,0,0)+Vector3.UP*0.001
	player.position += Vector3(DIRS[facing].z,0,-DIRS[facing].x)*lateral
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await frames(0.1)
	key(KEY_X,running)
	key(KEYS[facing],true)
	var hops := 0
	var was_hopping := false
	var peak := 0.0
	var started := 0
	var hop_seconds := 0.0
	var max_exceptions := 0
	var until := Engine.get_physics_frames()+ceili(0.9*Engine.physics_ticks_per_second)
	while Engine.get_physics_frames()<until:
		await physics_frame
		await process_frame
		if player.hop.active and not was_hopping:
			hops += 1
			started = Engine.get_physics_frames()
		if not player.hop.active and was_hopping:
			hop_seconds = float(Engine.get_physics_frames()-started)/Engine.physics_ticks_per_second
		was_hopping = player.hop.active
		peak = maxf(peak,player.position.y)
		max_exceptions = maxi(max_exceptions,player.get_collision_exceptions().size())
	key(KEYS[facing],false)
	key(KEY_X,false)
	await frames(0.1)
	return {"hops":hops,"peak":peak,"time":hop_seconds,"end":player.get_node("CollisionShape3D").global_position,"exceptions":player.get_collision_exceptions().size(),"max_exceptions":max_exceptions}
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	arena = Node3D.new()
	root.add_child(arena)
	floor_body = box(Vector3(0,-0.05,0),Vector3(6,0.1,6))
	floor_body.collision_layer = 11
	player = load("res://game/player/player.tscn").instantiate()
	arena.add_child(player)
	items = load("res://game/items/loose_items.gd").new()
	arena.add_child(items)
	items.world = {"player":player,"transitioning":false}
	items.set_physics_process(false)
	items.catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	for item in [58,62,64]:
		for facing in 4:
			var obstacle: Node3D = items._spawn(item,Vector3.ZERO,true)
			var walking: Dictionary = await drive(facing,false)
			if not require_ok(walking.hops==0 and walking.end.dot(DIRS[facing])< -0.285,"Walking crossed a ground item: "+str([item,facing,walking])): return
			var running: Dictionary = await drive(facing,true)
			print("HOP_SAMPLE: ",[item,facing,running])
			if not require_ok(running.hops==1 and running.end.dot(DIRS[facing])>0.3 and running.peak>0.22 and running.peak<0.25 and running.time>=0.33 and running.time<0.42 and running.exceptions==0 and player.is_on_floor(),"Single-item running hop failed or changed the source vertical arc: "+str([item,facing,running])): return
			# A second blocked cell, an unrelated wall and a ceiling each refuse the hop.
			for blocker_kind in 3:
				var blocker: Node3D
				if blocker_kind==0: blocker = items._spawn(item,DIRS[facing]*0.4,true)
				elif blocker_kind==1: blocker = box(DIRS[facing]*0.4+Vector3.UP*0.3,Vector3(0.4,0.6,0.4))
				else: blocker = box(Vector3.UP*0.4,Vector3(1.8,0.04,1.8))
				var refused: Dictionary = await drive(facing,true)
				if not require_ok(refused.hops==0 and refused.end.dot(DIRS[facing])< -0.285 and refused.exceptions==0,"Unsafe hop was allowed: "+str([item,facing,blocker_kind,refused])): return
				blocker.free()
			obstacle.free()
			checks += 1
	# A seam between two lateral items is still one row, including slightly off-centre approaches.
	for facing in 4:
		var side := Vector3(DIRS[facing].z,0,-DIRS[facing].x)
		var left: Node3D = items._spawn(58,Vector3.ZERO,true)
		var right: Node3D = items._spawn(62,side*0.4,true)
		for offset in [0.19,0.2,0.21]:
			var crossing: Dictionary = await drive(facing,true,offset)
			if not require_ok(crossing.hops==1 and crossing.end.dot(DIRS[facing])>0.3 and crossing.max_exceptions==2 and crossing.exceptions==0,"Lateral single-row seam refused or leaked exceptions: "+str([facing,offset,crossing])): return
		var deeper: Node3D = items._spawn(64,DIRS[facing]*0.4+side*0.2,true)
		var two_rows: Dictionary = await drive(facing,true,0.2)
		if not require_ok(two_rows.hops==0 and two_rows.exceptions==0,"A second row behind the seam was ignored"): return
		deeper.free()
		var wall := box(Vector3.UP*0.3+side*0.4,Vector3(0.4,0.6,0.4))
		var solid_side: Dictionary = await drive(facing,true,0.2)
		if not require_ok(solid_side.hops==0 and solid_side.exceptions==0,"An unrelated lateral wall was treated as a jumpable item"): return
		wall.free()
		# Cancellation must release every body, including after one item is removed.
		player.hop.cancel();player.position=-DIRS[facing]*0.65+side*0.2+Vector3(0.03,0.001,0);player.velocity=Vector3.ZERO
		await frames(0.1);key(KEY_X,true);key(KEYS[facing],true)
		for tick in Engine.physics_ticks_per_second:
			await physics_frame;await process_frame
			if player.hop.active: break
		key(KEY_X,false);key(KEYS[facing],false)
		if not require_ok(player.hop.active and player.get_collision_exceptions().size()==2,"Cancellation fixture did not enter a multi-item row hop"): return
		left.free();player.hop.cancel()
		if not require_ok(player.get_collision_exceptions().is_empty(),"Cancelling left a lateral collision exception"): return
		right.free()
	print("HOP_ROW_SEAMS_OK: four directions, mixed stone/branch, 0.19/0.20/0.21 seams, two-row/wall refusal, multi-body cleanup")
	# Carrying retains its original airborne pose/item; oversized authored boxes refuse.
	var carried_obstacle: Node3D = items._spawn(62,Vector3.ZERO,true)
	player.actions.carried_id = 58
	var carrying: Dictionary = await drive(0,true)
	if not require_ok(carrying.hops==1 and player.actions.carried_id==58 and carrying.exceptions==0,"Carried-item hop lost the item or collision exception"): return
	player.actions.carried_id = 0
	carried_obstacle.free()
	var oversized: Node3D = items._spawn(58,Vector3.ZERO,true)
	var enlarged := BoxShape3D.new()
	enlarged.size = Vector3(0.6,0.4,0.4)
	oversized.get_node("Obstruction").get_child(0).shape = enlarged
	var too_wide: Dictionary = await drive(0,true)
	if not require_ok(too_wide.hops==0 and too_wide.exceptions==0,"Hop accepted an oversized authored obstacle"): return
	oversized.free()
	# Without a supported landing, a lone item must remain an obstruction.
	var obstacle: Node3D = items._spawn(58,Vector3.ZERO,true)
	floor_body.collision_layer = 3
	var supported_start := box(Vector3(0,-0.05,-1.5),Vector3(6,0.1,2.6))
	supported_start.collision_layer = 8
	var unsupported: Dictionary = await drive(0,true)
	if not require_ok(unsupported.hops==0 and unsupported.exceptions==0,"Hop accepted an unsupported landing"): return
	floor_body.collision_layer = 11
	supported_start.free()
	obstacle.free()
	# Generic low scenery is not automatically a jumpable farm item.
	var wall := box(Vector3.UP*0.15,Vector3(0.4,0.3,0.4))
	var solid: Dictionary = await drive(0,true)
	if not require_ok(solid.hops==0 and solid.end.z< -0.285,"Running jumped unrelated solid scenery"): return
	wall.free()
	print("RUNNING_HOP_OK: ",Engine.physics_ticks_per_second," Hz; ",checks," stone/branch/weeds approaches, real keys; walk blocks, single item hops, source arc, adjacent obstacles/walls/ceilings/unsupported landing refuse; exceptions restored")
	arena.free()
	quit()

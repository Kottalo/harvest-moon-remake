extends "res://tools/verify_running_hop.gd"
## Real blocked capsule contacts: stable scenery projection without changing player physics.
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	arena = Node3D.new();root.add_child(arena)
	floor_body = box(Vector3(0,-0.05,0),Vector3(6,0.1,6));floor_body.collision_layer = 11
	player = load("res://game/player/player.tscn").instantiate();arena.add_child(player)
	items = load("res://game/items/loose_items.gd").new();arena.add_child(items)
	items.world = {"player":player,"transitioning":false};items.set_physics_process(false)
	items.catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	var render_delta := 1.0 / Engine.physics_ticks_per_second
	var camera = load("res://game/camera/world_camera.gd").new();arena.add_child(camera)
	for facing in 4:
		var side := Vector3(DIRS[facing].z,0,-DIRS[facing].x)
		var a: Node3D = items._spawn(64,Vector3.ZERO,true)
		var b: Node3D = items._spawn(64,side*0.4,true)
		player.position = -DIRS[facing]*0.65+side*0.2+Vector3(0.03,0.001,0)
		player.velocity = Vector3.ZERO;player.reset_physics_interpolation()
		await frames(0.1);key(KEYS[facing],true);await frames(0.7)
		camera.follow(player,false,false)
		var first := true
		var origin := Vector3.ZERO
		var reference := Vector2.ZERO
		var rotation := Basis.IDENTITY
		var body_min: Vector3 = player.position
		var body_max := body_min
		var error := 0.0
		for tick in Engine.physics_ticks_per_second*2:
			await physics_frame;await process_frame
			camera.follow(player,false,true,render_delta)
			var projected: Vector2 = camera.unproject_position(Vector3(0.8,0,0.8))
			if first:
				origin = camera.position;reference = projected;rotation = camera.basis;first = false
			body_min = body_min.min(player.position);body_max = body_max.max(player.position)
			error = maxf(error,projected.distance_to(reference))
			if not require_ok(camera.position==origin and camera.basis==rotation and error<0.0001,"Scenery/camera jittered while the player was blocked: "+str([facing,error,camera.position-origin])): return
		key(KEYS[facing],false)
		print("BLOCKED_CAMERA_SAMPLE: ",facing," physical recovery range=",body_max-body_min," projected scenery drift=",error)
		# Reverse movement starts smoothly, then the camera tracks and settles.
		var began: Vector3 = player.position
		key(KEYS[(facing+2)%4],true)
		for tick in Engine.physics_ticks_per_second/3:
			await physics_frame;await process_frame
			var previous: Vector3 = camera.position
			var target: Vector3 = player.get_global_transform_interpolated().origin + camera.eye_offset
			camera.follow(player,false,true,render_delta)
			if tick == 2 and not require_ok(camera.position.distance_to(previous) < target.distance_to(previous),"Camera snapped to the first reverse step"):
				return
		key(KEYS[(facing+2)%4],false)
		if not require_ok((player.position-began).dot(-DIRS[facing])>0.25 and (camera.position-origin).length()>0.25,"Contact stabilization delayed real movement"): return
		for tick in Engine.physics_ticks_per_second/2:
			await physics_frame;await process_frame
			camera.follow(player,false,true,render_delta)
		var settled: Vector3 = camera.position
		await physics_frame;await process_frame
		camera.follow(player,false,true,render_delta)
		if not require_ok(camera.position==settled and (camera.position-player.position-camera.eye_offset).length()<0.004,"Camera did not settle after movement"):
			return
		player.position += Vector3(0,0.8,0);player.reset_physics_interpolation()
		camera.follow(player,false,false)
		if not require_ok((camera.position-player.position-camera.eye_offset).length()<0.00001,"Direct/teleport camera update kept an old contact anchor"): return
		a.free();b.free()
	arena.free()
	print("BLOCKED_CAMERA_OK: ",Engine.physics_ticks_per_second," Hz; four blocked seams have zero camera/projected-scenery drift; real movement/direct resets work")
	quit()

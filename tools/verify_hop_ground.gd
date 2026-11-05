extends "res://tools/verify_running_hop.gd"
## QQ20261103-220338: native farm floor recovery must not veto a free landing.
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	player = world.player
	for x in [-0.27,-0.28,-0.29]:
		player.hop.cancel()
		player.position = Vector3(x,0.001,0.11)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		await frames(0.1)
		# Reproduce the observed 0.155 mm floor penetration at the weeds' corner.
		# Native move_and_slide reports this body on_floor despite the penetration.
		player.position.y = -0.000155
		var started: Vector3 = player.position
		key(KEY_X,true);key(KEY_LEFT,true)
		var hopped := false
		for tick in 6:
			await physics_frame;await process_frame
			hopped = hopped or player.hop.active
		key(KEY_X,false);key(KEY_LEFT,false)
		if not require_ok(hopped,"Native farm floor was mistaken for a blocked landing: "+str([started,player.position])): return
		await frames(0.5)
		if not require_ok(player.is_on_floor() and not player.hop.active and player.get_collision_exceptions().is_empty() and player.position.x<started.x-0.45,"Hop did not land/restore collision"): return
		print("NATIVE_FARM_CORNER_OK: ",started," -> ",player.position)
	world.free()
	print("HOP_GROUND_OK: ",Engine.physics_ticks_per_second," Hz; native floor penetration, three corner approaches, supported landing, exception cleanup")
	quit()

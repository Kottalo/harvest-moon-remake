extends SceneTree
## Ground contact, source blob image, depth behind the body, and airborne separation.
var world
var viewport: SubViewport
func _initialize() -> void: run.call_deferred()
func require_ok(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func frames(count: int) -> void:
	for tick in count: await physics_frame
	await process_frame
func picture() -> Image:
	for frame in 3: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func pixels(label: String) -> bool:
	var player = world.player
	var shadow: Sprite3D = player.get_node("GroundShadow")
	player.set_physics_process(false)
	shadow.set_physics_process(false)
	var shown: Image = await picture()
	shown.save_png("res://verification/player_shadow_"+label+".png")
	shadow.hide()
	var no_shadow: Image = await picture()
	player.sprite.hide()
	var background: Image = await picture()
	var count := 0
	var body_changed := 0
	for y in range(1,shown.get_height()-1):
		for x in range(1,shown.get_width()-1):
			var a := shown.get_pixel(x,y)
			var b := no_shadow.get_pixel(x,y)
			var delta := Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()
			if delta>0.02: count += 1
			if delta<0.02: continue
			var inside_body := true
			for edge in [Vector2i.ZERO,Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]:
				var p: Vector2i = Vector2i(x,y)+edge
				var foreground := no_shadow.get_pixelv(p)
				var back := background.get_pixelv(p)
				if Vector3(foreground.r-back.r,foreground.g-back.g,foreground.b-back.b).length()<0.15: inside_body = false
			if inside_body: body_changed += 1
	player.sprite.show()
	shadow.show()
	player.set_physics_process(true)
	shadow.set_physics_process(true)
	print("SHADOW_GPU_PIXELS: ",label," visible=",count," body-interior changed=",body_changed)
	return require_ok(count>30 and body_changed==0,"Shadow is absent or draws over the character body")
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	viewport = SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_physics_process(false)
	for fixture in [[0,Vector3(0,0.1,-2),"standing"],[32,Vector3(1.205002,1,4.8),"slope"]]:
		world._change_area(fixture[0],fixture[1])
		await frames(Engine.physics_ticks_per_second)
		var shadow: Sprite3D = world.player.get_node("GroundShadow")
		var feet: Vector3 = world.player.global_position+Vector3.UP*world.player.sprite.position.y
		if not require_ok(shadow.visible and shadow.global_position.distance_to(feet)<0.00001 and shadow.offset==Vector2(0,48) and is_equal_approx(shadow.pixel_size,world.player.sprite.pixel_size),"Original shadow is not on the visible foot contact point"): return
		if DisplayServer.get_name()!="headless":
			if not await pixels(fixture[2]): return
	world._change_area(0,Vector3(0.03,0.01,-2.65))
	for record in world.loose_items.records[0]:
		if record.active: world.loose_items._remove(record)
	var record := {"id":58,"position":Vector3(0,0,-2),"active":true,"cell":11}
	world.loose_items.records[0].append(record)
	world.loose_items._add_record(record)
	await frames(5)
	Input.action_press("run")
	Input.action_press("move_down")
	var airborne := 0
	var until := Engine.get_physics_frames()+Engine.physics_ticks_per_second
	while Engine.get_physics_frames()<until:
		await frames(1)
		if world.player.hop.active:
			var shadow: Sprite3D = world.player.get_node("GroundShadow")
			if not require_ok(shadow.visible and absf(shadow.global_position.y)<0.00001,"Jumping lifted the shadow off the ground"): return
			if world.player.position.y>0.2: airborne += 1
	Input.action_release("run")
	Input.action_release("move_down")
	if not require_ok(airborne>0,"Shadow test never reached the source airborne arc"): return
	print("PLAYER_SHADOW_OK: ",Engine.physics_ticks_per_second," Hz; source UI shadow, fixed size/pivot, flat and visible ramp ground, ground remains below airborne body")
	viewport.free()
	quit()

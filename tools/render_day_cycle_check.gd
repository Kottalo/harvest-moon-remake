extends SceneTree
## GPU pixels for batched debris, original subtractive day tint and carry layering.
func _initialize() -> void:
	_run.call_deferred()

func _draw() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func _run() -> void:
	var actions: Dictionary = await load("res://tools/verify_actions_gpu.gd").new().run(root)
	print("GPU_CARRY_DONE: ",actions.ok)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320,320)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	var unused := SubViewport.new()
	unused.own_world_3d = true
	unused.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(unused)
	unused.add_child(world)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(1,0.9,1)
	camera.look_at(Vector3(0,0.3,0))
	camera.set_orthogonal(1.7,0.01,10)
	var items = load("res://game/items/loose_items.gd").new()
	viewport.add_child(items)
	items.world = world
	items.catalogue = world.loose_items.catalogue
	items.set_physics_process(false)
	var originals := []
	for i in 3:
		originals.append(items._spawn([58,62,64][i],Vector3((i-1)*0.4,0,0),false))
	await _draw()
	var original := viewport.get_texture().get_image()
	for node in originals: node.hide()
	for i in 3:
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = items._item_mesh([58,62,64][i])
		batch.multimesh.instance_count = 1
		batch.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3((i-1)*0.4,0,0)))
		viewport.add_child(batch)
	await _draw()
	var batched := viewport.get_texture().get_image()
	var different := 0
	for y in 320:
		for x in 320:
			var a := original.get_pixel(x,y)
			var b := batched.get_pixel(x,y)
			if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)+absf(a.a-b.a)>0.05:
				different += 1
	var batch_ok := different<30 and original.get_used_rect()==batched.get_used_rect()
	print("GPU_BATCH_DONE: ",batch_ok," pixels=",different)
	original.save_png("res://verification/item_sprites_before.png")
	batched.save_png("res://verification/item_sprites_batched.png")
	items.hide()
	for child in viewport.get_children():
		if child is MultiMeshInstance3D: child.hide()
	var canvas := CanvasLayer.new()
	canvas.layer = 0
	viewport.add_child(canvas)
	var background := ColorRect.new()
	background.color = Color(0.8,0.5,0.25)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(background)
	var clock = load("res://game/time/day_cycle.gd").new()
	viewport.add_child(clock)
	clock.setup(world)
	clock.clock_label.hide()
	var tint_cases := []
	var tint_ok := true
	for index in 5:
		world.current_area = 0 if index<4 else 80
		clock.minute = [360,720,960,1200,1200][index]
		clock.period = clock.time_period()
		clock.tint_rgb = clock._period_rgb(clock.period)
		clock.refresh()
		await _draw()
		var pixel := viewport.get_texture().get_image().get_pixel(160,160)
		var subtract: Vector3 = clock.tint_rgb/255 if index<4 else Vector3.ZERO
		var expected := Vector3(0.8,0.5,0.25)-subtract
		expected = expected.max(Vector3.ZERO)
		var correct := Vector3(pixel.r,pixel.g,pixel.b).distance_to(expected)<0.025
		print("GPU_TINT: ",index," ",correct)
		tint_cases.append({"minute":clock.minute,"indoor":index==4,"pixel":pixel,"expected":expected,"ok":correct})
		tint_ok = tint_ok and correct
	viewport.free()
	unused.free()
	# Four actual farm frames; the camera and scene geometry are identical.
	var farm_view := SubViewport.new()
	farm_view.size = Vector2i(960,720)
	farm_view.own_world_3d = true
	farm_view.msaa_3d = Viewport.MSAA_4X
	farm_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(farm_view)
	var farm = load("res://game/world/world.tscn").instantiate()
	farm_view.add_child(farm)
	farm.set_physics_process(false)
	farm.player.set_physics_process(false)
	var gallery := Image.create(960,720,false,Image.FORMAT_RGBA8)
	for i in 4:
		farm.day_cycle.minute = [360,720,960,1200][i]
		farm.day_cycle.period = farm.day_cycle.time_period()
		farm.day_cycle.tint_rgb = farm.day_cycle._period_rgb(farm.day_cycle.period)
		farm.day_cycle.refresh()
		await _draw()
		var picture := farm_view.get_texture().get_image()
		picture.resize(480,360,Image.INTERPOLATE_BILINEAR)
		gallery.blit_rect(picture,Rect2i(0,0,480,360),Vector2i(i%2*480,i/2 as int*360))
	gallery.save_png("res://verification/day_cycle_farm.png")
	farm._change_area(80,Vector3(-0.98,0.03,0.5))
	farm.player.facing = 1
	farm.player._update_animation(Vector2.ZERO,false,0)
	farm.day_cycle.interact()
	await _draw()
	farm_view.get_texture().get_image().save_png("res://verification/bed_menu.png")
	farm.day_cycle.close_menu()
	farm.player.position = Vector3(-1.35,0.04,0.96)
	farm.player.reset_physics_interpolation()
	farm.player.sprite.position.y = 0
	farm.player.actions.play("sleep",3,"bed_pose",0)
	farm._update_camera()
	await _draw()
	farm_view.get_texture().get_image().save_png("res://verification/bed_pose.png")
	var report := {"ok":actions.ok and batch_ok and tint_ok,"batch_pixel_match":batch_ok,"batch_changed_pixels":different,"original_item_bounds":original.get_used_rect(),"batched_item_bounds":batched.get_used_rect(),"tint_ok":tint_ok,"tint_cases":tint_cases,"source_item_layers":actions.source_lifo_item_layers,"source_item_layer_cases":actions.item_layer_cases}
	FileAccess.open("res://verification/day-cycle-gpu.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DAY_CYCLE_GPU: ",JSON.stringify(report))
	farm_view.free()
	await process_frame
	quit(0 if report.ok else 1)

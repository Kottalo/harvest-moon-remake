extends SceneTree
## Real orthographic farm and sprite hop, rendered on the isolated test desktop.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_physics_process(false)
	for record in world.loose_items.records[0]:
		if record.active: world.loose_items._remove(record)
	var point := Vector3(0,0,-2)
	var record := {"id":58,"position":point,"active":true,"cell":11,"free_position":true}
	world.loose_items.records[0].append(record)
	world.loose_items._add_record(record)
	world.player.position = point+Vector3(0.03,0.02,-0.65)
	world.player.reset_physics_interpolation()
	for frame in 10: await physics_frame
	Input.action_press("move_down")
	Input.action_press("run")
	var captured := false
	var peak := 0.0
	var until := Time.get_ticks_msec()+1200
	while Time.get_ticks_msec()<until:
		await physics_frame
		await process_frame
		peak = maxf(peak,world.player.position.y)
		if world.player.hop.active and world.player.hop.elapsed>=0.15 and not captured:
			await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://verification/running_hop_pose.png")
			captured = true
	Input.action_release("move_down")
	Input.action_release("run")
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://verification/orthographic_farm.png")
	if not captured or world.player.hop.active or not world.player.get_collision_exceptions().is_empty() or world.camera.projection!=Camera3D.PROJECTION_ORTHOGONAL or debug_collisions_hint or world.loose_items.batches[58].has("debug"):
		push_error("Native farm hop/orthographic camera/no-collider rendering check failed")
		quit(1)
		return
	print("RUNNING_HOP_GPU_OK: source jump pose captured in real orthographic farm, peak=",peak,"; item remains, capsule exception cleared, no debug overlay")
	viewport.free()
	quit()

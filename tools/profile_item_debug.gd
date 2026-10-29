extends SceneTree
## Paired GPU comparison in one process, same map/camera and native collision shapes.
## User args: absolute baseline loose_items.gd, absolute output JSON. Isolated runner only.
func _initialize() -> void:
	debug_collisions_hint = true
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var args := OS.get_cmdline_user_args()
	var baseline := load(args[0]) as GDScript
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_physics_process(false) # Keep clock/tint and camera position identical.
	while world.location_loader.ready.size()<world.location_loader.wanted.size():
		await process_frame
	var report := []
	for variant in ["native","batched","native","batched"]:
		world.loose_items.free()
		world.loose_items = (baseline if variant=="native" else load("res://game/items/loose_items.gd")).new()
		world.add_child(world.loose_items)
		world.loose_items.setup(world)
		var until := Time.get_ticks_usec()+1000000
		while Time.get_ticks_usec()<until: await process_frame
		var samples := []
		var last := Time.get_ticks_usec()
		until = last+4000000
		while Time.get_ticks_usec()<until:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			last = now
		samples.sort()
		var row := {"variant":variant,"p50_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*.95)],"frames":samples.size(),"draw_calls":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),"objects":viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_OBJECTS_IN_FRAME),"static_memory_mb":OS.get_static_memory_usage()/1048576.0,"video_memory_mb":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)/1048576.0}
		report.append(row)
		print("ITEM_DEBUG_PROFILE: ",JSON.stringify(row))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	viewport.free()
	quit()

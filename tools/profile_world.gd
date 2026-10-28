extends SceneTree
## Real GPU frame intervals, same hardware/resolution; use the isolated desktop launcher.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	var report := []
	for area in [0,48,52,60,64,80]:
		if not world.world.has(str(area)):
			continue
		var spawn: Array = world.world[str(area)].spawn
		var begin := Time.get_ticks_usec()
		world._change_area(area,Vector3(spawn[0],spawn[1],spawn[2]))
		var load_ms := (Time.get_ticks_usec()-begin)/1000.0
		var warm_until := Time.get_ticks_usec()+1500000
		while Time.get_ticks_usec()<warm_until:
			await process_frame
		var samples := []
		var cpu := []
		var physics := []
		var last := Time.get_ticks_usec()
		var until := last+2500000
		while Time.get_ticks_usec()<until:
			await process_frame
			var now := Time.get_ticks_usec()
			samples.append((now-last)/1000.0)
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000)
			last=now
		samples.sort()
		cpu.sort()
		physics.sort()
		var row := {"area":area,"name":world.world[str(area)].slug,"load_ms":load_ms,"frames":samples.size(),"p50_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*.95)],"p99_ms":samples[int(samples.size()*.99)],"cpu_p95_ms":cpu[int(cpu.size()*.95)],"physics_p95_ms":physics[int(physics.size()*.95)],"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)}
		report.append(row)
		print("PROFILE: ",JSON.stringify(row))
	var args := OS.get_cmdline_user_args()
	var path := args[0] if not args.is_empty() else "user://world-profile.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	viewport.free()
	quit()

extends SceneTree
## Real GPU startup and deferred serial neighbour-prefetch contract.
func _initialize() -> void:
	debug_collisions_hint = true
	run.call_deferred()
func require_ok(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	var loader = world.location_loader
	if not require_ok(loader.requested.is_empty(),"Startup issued background loads inside world._ready"): return
	for area in [0,80]:
		if area==80:
			var spawn: Array = world.world["80"].spawn
			world._change_area(80,Vector3(spawn[0],spawn[1],spawn[2]))
		var began := Time.get_ticks_msec()
		for frame in 600:
			await process_frame
			if not require_ok(loader.requested.size()<=1,"More than one neighbour scene loads concurrently"): return
			for path in loader.ready:
				if not require_ok(loader.wanted.has(path),"Obsolete scene cache retained after location change"): return
			if loader.requested.is_empty() and loader.ready.size()==loader.wanted.size(): break
			if not require_ok(Time.get_ticks_msec()-began<8000,"Neighbour prefetch stalled"): return
		if not require_ok(loader.ready.size()==loader.wanted.size(),"Neighbour prefetch did not complete"): return
		print("SERIAL_PREFETCH_OK: area=",area," scenes=",loader.ready.size()," elapsed_ms=",Time.get_ticks_msec()-began)
	world.queue_free()
	await process_frame
	print("STARTUP_CHECK_OK: debug main scene ready before background loading; serial queue drains and obsolete scenes are released")
	quit()

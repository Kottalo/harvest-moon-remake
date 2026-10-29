extends SceneTree
## Check the shared x=5 riser against the beach's single authoritative drawing.
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
	world._change_area(52,Vector3(4.5,0.01,0))
	for tick in 10: await physics_frame
	# Topology regression: only the beach owns the four source triangles on x=5.
	var counts := [0,0]
	for side in 2:
		var geometry: MeshInstance3D = world.get_node("Location/"+(["TownSquare","Beach"][side])+"/Geometry")
		geometry.force_update_transform()
		for surface in geometry.mesh.get_surface_count():
			var vertices: PackedVector3Array = geometry.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for i in range(0,vertices.size(),3):
				var boundary := true
				for corner in 3:
					boundary = boundary and absf((geometry.global_transform*vertices[i+corner]).x-5.0)<0.000001
				if boundary: counts[side] += 1
	if counts!=[0,4]:
		push_error("Duplicate shared stair boundary ownership: "+str(counts))
		quit(1)
		return
	print("COAST_BOUNDARY_OWNER_OK: town=0, beach=4 exact source triangles; no doubled riser")
	world.player.set_physics_process(false)
	for frame in 3: await RenderingServer.frame_post_draw
	var combined := viewport.get_texture().get_image()
	var args := OS.get_cmdline_user_args()
	combined.save_png(args[0] if not args.is_empty() else "res://verification/coast_seam_after.png")
	world.get_node("Location/TownSquare/Geometry").hide()
	for frame in 3: await RenderingServer.frame_post_draw
	var reference := viewport.get_texture().get_image()
	var differences := 0
	var maximum := 0.0
	for row in 6:
		for column in 32:
			var point := Vector3(5,-0.01-0.08*(row+0.5)/6.0,-0.38+0.76*(column+0.5)/32.0)
			var pixel := Vector2i(world.camera.unproject_position(point))
			var a := combined.get_pixelv(pixel)
			var b := reference.get_pixelv(pixel)
			var delta := Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()
			maximum = maxf(maximum,delta)
			if delta>0.02: differences += 1
	print("COAST_RISER_SAMPLES: ",differences,"/192 differ from beach-only reference; max_rgb_delta=",maximum)
	if args.has("--verify") and differences>0:
		push_error("Shared stair riser still has duplicate/coplanar town drawing")
		quit(1)
		return
	viewport.free()
	quit()

extends SceneTree
## Isolated native close-up of the doghouse lintel/roof; never controls the editor game.
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.day_cycle.set_process(false)
	world.player.hide()
	var focus := Vector3(-1.8,0.24,-3.6)
	world.camera.position = focus+world.camera.eye_offset
	world.camera.look_at(focus)
	world.camera.size = 0.85
	if OS.get_cmdline_user_args().has("--verify"):
		var geometry: MeshInstance3D = world.get_node("Location/Geometry")
		var counts := [0,0]
		var areas := [0.0,0.0]
		for surface in geometry.mesh.get_surface_count():
			var material: ShaderMaterial = geometry.mesh.surface_get_material(surface)
			var slot := 1 if material.get_shader_parameter("textured") else 0
			var vertices: PackedVector3Array = geometry.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for triangle in range(0,vertices.size(),3):
				var covered := true
				for point in vertices.slice(triangle,triangle+3):
					covered = covered and point.x>=-1.904001 and point.x<=-1.695999 and point.y>=0.359999 and point.y<=0.400001 and absf(point.z+3.4)<0.000001
				if covered:
					counts[slot] += 1
					areas[slot] += (vertices[triangle+1]-vertices[triangle]).cross(vertices[triangle+2]-vertices[triangle]).length()*0.5
		if counts!=[0,2] or absf(areas[1]-0.0072)>0.000001:
			push_error("Doghouse lintel must have one complete wooden surface: "+str([counts,areas]))
			quit(1)
			return
		print("DOGHOUSE_LINTEL_OK: grey/wood triangles=",counts,"; preserved wood area=",areas[1])
	for frame in 5: await RenderingServer.frame_post_draw
	var path := "res://verification/doghouse_after.png"
	for argument in OS.get_cmdline_user_args():
		if argument.ends_with(".png"): path = argument
	viewport.get_texture().get_image().save_png(path)
	print("DOGHOUSE_RENDER_OK: ",path)
	viewport.free()
	quit()

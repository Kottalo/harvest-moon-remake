extends RefCounted
## GPU check of actual exported VRAM-copy schedules, including the 31-row scroll reset.

func _material(path: String, framed: bool) -> ShaderMaterial:
	var scene: Node3D = load(path).instantiate()
	var mesh: ArrayMesh = scene.get_node("Geometry").mesh
	var selected: ShaderMaterial
	for surface in mesh.get_surface_count():
		var material: ShaderMaterial = mesh.surface_get_material(surface)
		var count = material.get_shader_parameter("motion_count")
		if material.shader.resource_path != "res://game/rendering/source_surface.gdshader" or count == null or int(count) == 0:
			continue
		var threshold = material.get_shader_parameter("alpha_scissor_threshold")
		if threshold != null and float(threshold) > 0.7:
			continue
		var timings: PackedVector4Array = material.get_shader_parameter("motion_timing")
		if (timings[0].w == 0) != framed:
			continue
		var sources: PackedVector4Array = material.get_shader_parameter("motion_source")
		var image: Image = material.get_shader_parameter("motion_texture").get_image()
		var first := sources[0]
		var varied := false
		for y in int(first.w):
			for x in int(first.z):
				var a := image.get_pixel(x, int(first.y) + y)
				var b := image.get_pixel(x, int(sources[1].y) + y) if framed else image.get_pixel(x, int(first.y) + (y + 2) % int(first.w))
				if a.a > 0.5 and a != b:
					varied = true
		if varied:
			selected = material.duplicate()
			break
	scene.free()
	return selected

func run(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 3)
	camera.look_at(Vector3.ZERO)
	camera.set_orthogonal(2, 0.05, 10)
	camera.current = true
	var report := {}
	for framed in [false, true]:
		var path := "res://game/locations/beach/beach.scn" if framed else "res://game/locations/hot_spring/hot_spring.scn"
		var material := _material(path, framed)
		if material == null:
			viewport.queue_free()
			return {"ok": false, "error": "No varied exported animation found: " + path}
		material.set_shader_parameter("motion_ripples", false) # Isolate timing/loop continuity from the extra water distortion.
		var destinations: PackedVector4Array = material.get_shader_parameter("motion_destination")
		var timing: PackedVector4Array = material.get_shader_parameter("motion_timing")
		var dest := destinations[0]
		var source: PackedVector4Array = material.get_shader_parameter("motion_source")
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1,-1,0),Vector3(-1,1,0),Vector3(1,-1,0),Vector3(1,-1,0),Vector3(-1,1,0),Vector3(1,1,0)])
		var uv := PackedVector2Array()
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			uv.append(Vector2(dest.x + (vertex.x + 1) * dest.z * 0.5, dest.y + (1 - vertex.y) * dest.w * 0.5) / 256.0)
		arrays[Mesh.ARRAY_TEX_UV] = uv
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var plane := MeshInstance3D.new()
		plane.mesh = mesh
		viewport.add_child(plane)
		var step: float = timing[0].y if framed else timing[0].w
		var cycle: float = timing[0].z if framed else ceilf(source[0].w / 2) * step
		var hashes := []
		for ticks in [0.1, step * 0.5, step + 0.1, cycle + 0.1]:
			material.set_shader_parameter("motion_test_time", ticks / 30.0)
			for frame in 3:
				await RenderingServer.frame_post_draw
			hashes.append(viewport.get_texture().get_image().get_region(Rect2i(8,8,112,112)).get_data().hex_encode().sha256_text())
		var passed: bool = hashes[0] != hashes[1] and hashes[1] != hashes[2] and hashes[0] == hashes[3]
		report["waves" if framed else "scroll"] = {"ok": passed, "smooth": true, "step_ticks": step, "cycle_ticks": cycle, "height": source[0].w}
		plane.free()
	report["ok"] = report.scroll.ok and report.waves.ok
	viewport.queue_free()
	return report

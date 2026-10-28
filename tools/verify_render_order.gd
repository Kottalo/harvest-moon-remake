extends RefCounted
## GPU regression, called through Godot AI game_eval: await new().run(current_scene).
## A billboard must be complete in front of a wall and occluded behind it.

func run(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 320)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(6.364, 4.5, 6.364)
	camera.look_at(Vector3.ZERO)
	camera.fov = 13.685546875
	camera.current = true
	var faces := PackedVector3Array([Vector3(-1, 0, 0), Vector3(-1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 0), Vector3(-1, 1, 0), Vector3(1, 1, 0)])
	var colors := PackedColorArray()
	var sorting := PackedFloat32Array()
	for point in faces:
		colors.append(Color(0.8, 0.1, 0.1))
		sorting.append_array(PackedFloat32Array([0, 0.5, 0, 0]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_CUSTOM0] = sorting
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
	var material := ShaderMaterial.new()
	material.shader = load("res://game/rendering/source_surface.gdshader")
	material.set_shader_parameter("textured", false)
	mesh.surface_set_material(0, material)
	var wall := MeshInstance3D.new()
	wall.mesh = mesh
	viewport.add_child(wall)
	var player: CharacterBody3D = load("res://game/player/player.tscn").instantiate()
	viewport.add_child(player)
	player.set_physics_process(false)
	var results := []
	for z in [0.07, -0.6]:
		player.position = Vector3(0, 0, z)
		for tick in 3:
			await RenderingServer.frame_post_draw
		# First idle frame, canvas pixel (64,84), inside the blue cap.
		var hat: Vector3 = player.position + camera.global_basis.y * (33.0 * player.sprite.pixel_size)
		var screen := camera.unproject_position(hat)
		var picture := viewport.get_texture().get_image()
		results.append(picture.get_pixelv(Vector2i(screen)))
	var front: Color = results[0]
	var behind: Color = results[1]
	var passed := front.b > front.r + 0.2 and behind.r > behind.b + 0.2
	viewport.queue_free()
	return {"ok": passed, "front_cap": front, "behind_wall": behind, "check": "one ground-anchored body depth; real GPU front/behind pixels"}

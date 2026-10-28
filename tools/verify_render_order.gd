extends RefCounted
## GPU regression, called through Godot AI game_eval: await new().run(current_scene).
## Check sprite ordering separately from intersecting solid geometry.

func run(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(480, 320)
	viewport.own_world_3d = true
	viewport.msaa_3d = parent.get_viewport().msaa_3d
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
	wall.queue_free()
	player.queue_free()
	await parent.get_tree().process_frame
	camera.position = Vector3(0, 0, 3)
	camera.look_at(Vector3.ZERO)
	camera.set_orthogonal(2.0, 0.05, 20.0)
	# One slanted blue face crosses a red face. A constant face depth breaks this.
	var flat := PackedVector3Array([Vector3(-0.7, -0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0.7, -0.7, 0), Vector3(0.7, -0.7, 0), Vector3(-0.7, 0.7, 0), Vector3(0.7, 0.7, 0)])
	for slanted in [false, true]:
		var solid_faces := flat.duplicate()
		var solid_colors := PackedColorArray()
		var solid_sorting := PackedFloat32Array()
		for index in solid_faces.size():
			if slanted:
				solid_faces[index].z = solid_faces[index].x * 0.5
			solid_colors.append(Color(0.1, 0.1, 0.8) if slanted else Color(0.8, 0.1, 0.1))
			solid_sorting.append_array(PackedFloat32Array([0, 0, 0, 0]))
		arrays[Mesh.ARRAY_VERTEX] = solid_faces
		arrays[Mesh.ARRAY_COLOR] = solid_colors
		arrays[Mesh.ARRAY_CUSTOM0] = solid_sorting
		var solid_mesh := ArrayMesh.new()
		solid_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
		solid_mesh.surface_set_material(0, material)
		var solid := MeshInstance3D.new()
		solid.mesh = solid_mesh
		viewport.add_child(solid)
	for tick in 3:
		await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var left := picture.get_pixelv(Vector2i(camera.unproject_position(Vector3(-0.35, 0, 0))))
	var right := picture.get_pixelv(Vector2i(camera.unproject_position(Vector3(0.35, 0, 0))))
	var geometry_passed := left.r > left.b + 0.2 and right.b > right.r + 0.2
	var blending := await _check_blending(viewport, camera, flat)
	viewport.queue_free()
	return {"ok": passed and geometry_passed and blending.ok, "sprite_order_ok": passed, "solid_geometry_ok": geometry_passed, "front_cap": front, "behind_wall": behind, "geometry_left": left, "geometry_right": right, "blending": blending, "check": "fixed sprite anchor; continuous solid geometry depth; PS1 blend/STP; real GPU pixels"}

func _quad(viewport: SubViewport, faces: PackedVector3Array, color: Color, material: Material, z: float) -> MeshInstance3D:
	var colors := PackedColorArray()
	var uv := PackedVector2Array()
	for point in faces:
		colors.append(color)
		uv.append(Vector2((point.x + 0.7) / 1.4, 0.5))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.z = z
	viewport.add_child(node)
	return node

func _check_blending(viewport: SubViewport, camera: Camera3D, faces: PackedVector3Array) -> Dictionary:
	for node in viewport.get_children():
		if node is MeshInstance3D:
			node.free()
	var base := ShaderMaterial.new()
	base.shader = load("res://game/rendering/source_surface.gdshader")
	base.set_shader_parameter("textured", false)
	_quad(viewport, faces, Color(0.1, 0.2, 0.4), base, 0)
	var left := Vector2i(camera.unproject_position(Vector3(-0.35, 0, 0)))
	var right := Vector2i(camera.unproject_position(Vector3(0.35, 0, 0)))
	for tick in 3:
		await RenderingServer.frame_post_draw
	var background := viewport.get_texture().get_image().get_pixelv(left)
	var pixels := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	pixels.set_pixel(0, 0, Color(0, 0, 0, 0.5))
	pixels.set_pixel(1, 0, Color(0.4, 0.4, 0.4, 0.5))
	var texture := ImageTexture.create_from_image(pixels)
	var blended := ShaderMaterial.new()
	blended.shader = load("res://game/rendering/source_blend_add.gdshader")
	blended.set_shader_parameter("albedo_texture", texture)
	_quad(viewport, faces, Color.WHITE, blended, 0.1)
	for tick in 3:
		await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var black := picture.get_pixelv(left)
	var water := picture.get_pixelv(right)
	var additive_ok := absf(black.r - background.r) + absf(black.g - background.g) + absf(black.b - background.b) < 0.03 and water.r > background.r + 0.1
	# Mixed STP: the left texel blends, the right texel is fully opaque.
	pixels.set_pixel(1, 0, Color(0.4, 0.4, 0.4, 1.0))
	texture.update(pixels)
	blended.shader = load("res://game/rendering/source_blend_average.gdshader")
	blended.set_shader_parameter("albedo_texture", texture)
	blended.set_shader_parameter("opacity", 0.5)
	var opaque := ShaderMaterial.new()
	opaque.shader = load("res://game/rendering/source_surface.gdshader")
	opaque.set_shader_parameter("albedo_texture", texture)
	opaque.set_shader_parameter("alpha_scissor_threshold", 0.75)
	_quad(viewport, faces, Color.WHITE, opaque, 0.1)
	for tick in 3:
		await RenderingServer.frame_post_draw
	picture = viewport.get_texture().get_image()
	var averaged := picture.get_pixelv(left)
	var solid := picture.get_pixelv(right)
	var stp_ok := averaged.b < background.b - 0.05 and averaged.b > 0.05 and absf(solid.r - solid.b) < 0.02 and solid.r > 0.3
	return {"ok": additive_ok and stp_ok, "additive_ok": additive_ok, "mixed_stp_ok": stp_ok, "background": background, "additive_black": black, "water": water, "averaged_black": averaged, "opaque_texel": solid}

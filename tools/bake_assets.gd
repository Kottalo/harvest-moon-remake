extends SceneTree
## Run after importing PNGs: godot --headless --path . --script tools/bake_assets.gd

func _initialize() -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/farm.json"))
	assert(source is Dictionary, "Run tools/import_disc.py first")
	var mesh := ArrayMesh.new()
	for surface in source.surfaces:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		for i in range(0, surface.vertices.size(), 3):
			vertices.append(Vector3(surface.vertices[i], surface.vertices[i + 1], surface.vertices[i + 2]))
			colors.append(Color(surface.colors[i], surface.colors[i + 1], surface.colors[i + 2]))
		for i in range(0, surface.uv.size(), 2):
			uv.append(Vector2(surface.uv[i], surface.uv[i + 1]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if not surface.texture.is_empty():
			material.albedo_texture = load("res://assets/original/" + surface.texture)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.5
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var farm := Node3D.new()
	farm.name = "OriginalFarm"
	var instance := MeshInstance3D.new()
	instance.name = "Geometry"
	instance.mesh = mesh
	farm.add_child(instance)
	instance.owner = farm
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape"
	var collision := mesh.create_trimesh_shape()
	collision.backface_collision = true
	shape.shape = collision
	farm.add_child(body)
	body.owner = farm
	body.add_child(shape)
	shape.owner = farm
	var scene := PackedScene.new()
	assert(scene.pack(farm) == OK)
	assert(ResourceSaver.save(scene, "res://scenes/original_farm.scn") == OK)
	print("BAKE_OK: ", mesh.get_surface_count(), " native mesh surfaces and collision saved")
	farm.free()
	quit()

extends SceneTree
## Run after importing PNGs: godot --headless --path . --script tools/bake_assets.gd

func _initialize() -> void:
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	assert(world is Dictionary, "Run tools/import_disc.py first")
	for area in world:
		if area == "0" and OS.get_cmdline_user_args().has("--skip-farm"):
			continue
		_bake_scene(world[area])
	quit()

func _bake_scene(info: Dictionary) -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string(info.source_json))
	assert(source is Dictionary, "Run tools/import_disc.py first")
	var texture_base: String = info.texture_base
	var farm := Node3D.new()
	farm.name = str(info.slug).to_pascal_case()
	farm.set_meta("area_id", info.id)
	_add_mesh(farm, farm, source.surfaces, texture_base)
	for entry in source.entries:
		var node := Node3D.new()
		node.name = "ZoneModel_%02d" % int(entry.index)
		node.position = Vector3(entry.position[0], entry.position[1], entry.position[2])
		node.rotation_order = EULER_ORDER_ZXY
		node.rotation = Vector3(entry.angle[0], entry.angle[1], entry.angle[2]) * TAU / 4096.0
		node.set_meta("source_position", entry.source_position)
		node.set_meta("source_flags", entry.flags)
		farm.add_child(node)
		node.owner = farm
		_add_mesh(farm, node, entry.surfaces, texture_base)
	var scene := PackedScene.new()
	assert(scene.pack(farm) == OK)
	assert(ResourceSaver.save(scene, info.scene) == OK)
	print("BAKE_OK: area ", info.id, ", ", source.entries.size(), " positioned zone models")
	farm.free()

func _add_mesh(farm: Node3D, parent: Node3D, surfaces: Array, texture_base: String) -> void:
	var mesh := ArrayMesh.new()
	for surface in surfaces:
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
		material.resource_name = texture_base.trim_suffix("/").get_file() + "_material_%02d" % mesh.get_surface_count()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if not surface.texture.is_empty():
			material.albedo_texture = load(texture_base + surface.texture)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			material.alpha_scissor_threshold = 0.5
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var instance := MeshInstance3D.new()
	instance.name = "Geometry"
	instance.mesh = mesh
	parent.add_child(instance)
	instance.owner = farm
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape"
	var collision := mesh.create_trimesh_shape()
	collision.backface_collision = true
	shape.shape = collision
	parent.add_child(body)
	body.owner = farm
	body.add_child(shape)
	shape.owner = farm

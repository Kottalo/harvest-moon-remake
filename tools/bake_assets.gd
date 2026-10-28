extends SceneTree
## Run after importing PNGs: godot --headless --path . --script tools/bake_assets.gd

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("--check"):
		_check_ramp_cut()
		quit()
		return
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	assert(world is Dictionary, "Run tools/import_disc.py first")
	var selected_area := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--area="):
			selected_area = argument.get_slice("=", 1)
	for area in world:
		if not selected_area.is_empty() and str(area) != selected_area:
			continue
		if OS.get_cmdline_user_args().has("--ramps-only") and not FileAccess.file_exists(world[area].texture_base + "walkable_ramps.json"):
			continue
		if area == "0" and OS.get_cmdline_user_args().has("--skip-farm"):
			continue
		_bake_scene(world[area])
	quit()

func _bake_scene(info: Dictionary) -> void:
	var source = JSON.parse_string(FileAccess.get_file_as_string(info.source_json))
	assert(source is Dictionary, "Run tools/import_disc.py first")
	var texture_base: String = info.texture_base
	var ramps: Array = []
	if FileAccess.file_exists(texture_base + "walkable_ramps.json"):
		ramps = JSON.parse_string(FileAccess.get_file_as_string(texture_base + "walkable_ramps.json"))
	for ramp in ramps:
		ramp["clip_planes"] = _ramp_planes(ramp)
	var farm := Node3D.new()
	farm.name = str(info.slug).to_pascal_case()
	farm.set_meta("area_id", info.id)
	_add_mesh(farm, farm, source.surfaces, texture_base, ramps)
	_add_ramps(farm, ramps)
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

func _ramp_planes(ramp: Dictionary) -> Array:
	var low := _ramp_point(ramp, [minf(ramp["from"][0], ramp.to[0]), minf(ramp["from"][1], ramp.to[1]) - 0.001], ramp.cross[0])
	var high := _ramp_point(ramp, [maxf(ramp["from"][0], ramp.to[0]), maxf(ramp["from"][1], ramp.to[1]) + 0.001], ramp.cross[1])
	return [Plane(Vector3.LEFT, -low.x), Plane(Vector3.RIGHT, high.x), Plane(Vector3.FORWARD, -low.z), Plane(Vector3.BACK, high.z), Plane(Vector3.DOWN, -low.y), Plane(Vector3.UP, high.y)]

func _outside_ramp(polygon: PackedVector3Array, planes: Array) -> Array:
	var pieces := []
	var remainder := polygon
	for plane: Plane in planes:
		var outside := Geometry3D.clip_polygon(remainder, Plane(-plane.normal, -plane.d))
		if outside.size() >= 3:
			pieces.append(outside)
		remainder = Geometry3D.clip_polygon(remainder, plane)
		if remainder.size() < 3:
			break
	return pieces

func _check_ramp_cut() -> void:
	var ramp := {"axis": "x", "from": [0, 0], "to": [1, 0.2], "cross": [0, 1]}
	var face := PackedVector3Array([Vector3(-1, 0, -1), Vector3(3, 0, -1), Vector3(-1, 0, 3)])
	var area := 0.0
	for polygon: PackedVector3Array in _outside_ramp(face, _ramp_planes(ramp)):
		for i in range(1, polygon.size() - 1):
			area += (polygon[i] - polygon[0]).cross(polygon[i + 1] - polygon[0]).length() * 0.5
	assert(absf(area - 7.0) < 0.0001, "Ramp must cut its own footprint while preserving the surrounding platform")
	print("RAMP_CUT_OK: unit ramp footprint removed; surrounding platform area preserved")

func _ramp_point(ramp: Dictionary, end: Array, side: float) -> Vector3:
	return Vector3(end[0], end[1], side) if ramp.axis == "x" else Vector3(side, end[1], end[0])

func _add_ramps(farm: Node3D, ramps: Array) -> void:
	if ramps.is_empty():
		return
	var group := Node3D.new()
	group.name = "WalkableRamps"
	farm.add_child(group)
	group.owner = farm
	for ramp in ramps:
		var a := _ramp_point(ramp, ramp["from"], ramp.cross[0])
		var b := _ramp_point(ramp, ramp["from"], ramp.cross[1])
		var c := _ramp_point(ramp, ramp.to, ramp.cross[0])
		var d := _ramp_point(ramp, ramp.to, ramp.cross[1])
		var faces := PackedVector3Array([a, c, b, b, c, d])
		if (faces[1] - faces[0]).cross(faces[2] - faces[0]).y < 0:
			faces = PackedVector3Array([a, b, c, b, d, c])
		var body := StaticBody3D.new()
		body.name = str(ramp.name).to_pascal_case()
		body.collision_layer = 10 # Physical floor and walkability query.
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var plane := ConcavePolygonShape3D.new()
		plane.set_faces(faces)
		plane.backface_collision = true
		shape.shape = plane
		group.add_child(body)
		body.owner = farm
		body.add_child(shape)
		shape.owner = farm

func _add_mesh(farm: Node3D, parent: Node3D, surfaces: Array, texture_base: String, ramps: Array = []) -> void:
	var mesh := ArrayMesh.new()
	var walkable_faces := PackedVector3Array()
	var ground_faces := PackedVector3Array()
	var solid_faces := PackedVector3Array()
	for surface in surfaces:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var sorting := PackedFloat32Array()
		var uv := PackedVector2Array()
		for i in range(0, surface.vertices.size(), 3):
			vertices.append(Vector3(surface.vertices[i], surface.vertices[i + 1], surface.vertices[i + 2]))
			colors.append(Color(surface.colors[i], surface.colors[i + 1], surface.colors[i + 2]))
			var flags := int(surface.primitive_flags[i / 9])
			var bias := (0.14 if flags & 0x8000 == 0 else 0.0) + (0.004 if flags & 0x4000 else 0.0)
			sorting.append_array(PackedFloat32Array([surface.sort_centers[i], surface.sort_centers[i + 1], surface.sort_centers[i + 2], bias]))
		assert(surface.has("primitive_flags") and surface.primitive_flags.size() * 3 == vertices.size(), "Re-extract source ground flags before baking")
		if parent != farm:
			solid_faces.append_array(vertices)
		if parent == farm:
			for triangle in surface.primitive_flags.size():
				var polygons := [vertices.slice(triangle * 3, triangle * 3 + 3)]
				for ramp in ramps:
					var remaining := []
					for polygon: PackedVector3Array in polygons:
						remaining.append_array(_outside_ramp(polygon, ramp.clip_planes))
					polygons = remaining
				for polygon: PackedVector3Array in polygons:
					for i in range(1, polygon.size() - 1):
						var face := PackedVector3Array([polygon[0], polygon[i], polygon[i + 1]])
						if (face[1] - face[0]).cross(face[2] - face[0]).length_squared() < 0.000000000001:
							continue
						if (int(surface.primitive_flags[triangle]) & 0xC080) == 0:
							ground_faces.append_array(face)
						if (int(surface.primitive_flags[triangle]) & 0xE080) == 0:
							walkable_faces.append_array(face)
		if not surface.visible:
			continue # Keep collision above; omit neutral additive-black drawing below.
		for i in range(0, surface.uv.size(), 2):
			uv.append(Vector2(surface.uv[i], surface.uv[i + 1]))
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_CUSTOM0] = sorting
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
		var material := ShaderMaterial.new()
		material.resource_name = texture_base.trim_suffix("/").get_file() + "_material_%02d" % mesh.get_surface_count()
		material.shader = load("res://game/rendering/source_surface.gdshader")
		material.set_shader_parameter("textured", not surface.texture.is_empty())
		if not surface.texture.is_empty():
			material.set_shader_parameter("albedo_texture", load(texture_base + surface.texture))
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	var instance := MeshInstance3D.new()
	instance.name = "Geometry"
	instance.mesh = mesh
	parent.add_child(instance)
	instance.owner = farm
	var body := StaticBody3D.new()
	body.name = "Collision"
	if parent == farm:
		# Render-only stair risers/roofs are not original collision geometry.
		body.name = "VisualGeometryReference"
		body.collision_layer = 4
		body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape"
	var collision := mesh.create_trimesh_shape()
	if parent != farm:
		collision = ConcavePolygonShape3D.new()
		collision.set_faces(solid_faces)
	collision.backface_collision = true
	shape.shape = collision
	parent.add_child(body)
	body.owner = farm
	body.add_child(shape)
	shape.owner = farm
	for definition in [["Ground", 2, ground_faces], ["WalkableGround", 8, walkable_faces]]:
		if definition[2].is_empty():
			continue
		var ground := StaticBody3D.new()
		ground.name = definition[0]
		ground.collision_layer = definition[1]
		ground.collision_mask = 0
		var ground_shape := CollisionShape3D.new()
		var ground_mesh := ConcavePolygonShape3D.new()
		ground_mesh.set_faces(definition[2])
		ground_mesh.backface_collision = true
		ground_shape.shape = ground_mesh
		parent.add_child(ground)
		ground.owner = farm
		ground.add_child(ground_shape)
		ground_shape.owner = farm

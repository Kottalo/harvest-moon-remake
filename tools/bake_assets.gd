extends SceneTree
## Run after importing PNGs: godot --headless --path . --script tools/bake_assets.gd
var motion_textures := {}

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
	if selected_area in ["", "52", "56"]:
		load("res://tools/bake_coast.gd").new().bake()
	motion_textures.clear()
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
		# Both closed clipping half-spaces include coplanar faces. A riser exactly
		# on a ramp endpoint belongs inside the cut, not in the retained outside.
		var extends_outside := false
		for point in outside:
			extends_outside = extends_outside or plane.distance_to(point) > 0.000001
		if outside.size() >= 3 and extends_outside:
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
	var endpoint := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.2, 0), Vector3(0, 0, 1)])
	assert(_outside_ramp(endpoint, _ramp_planes(ramp)).is_empty(), "A coplanar endpoint riser must not block the continuous ramp")
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
		if texture_base.ends_with("/mother_hill_summit/") and surface.texture.get_file() in ["mother_hill_summit_atlas_09.png", "mother_hill_summit_atlas_03_blend.png"]:
			# Enlarge the original sky and distant-mountain backdrops in the camera
			# plane. Keep their horizon edges and view depth; gameplay stays put.
			var stars: bool = surface.texture.get_file() == "mother_hill_summit_atlas_09.png"
			var right := Vector3(1, 0, -1).normalized()
			var up := Vector3(-1, sqrt(8.0), -1).normalized() # Original 9:4.5 camera slope.
			var left := INF
			var bottom := INF
			var top := -INF
			var edge := -INF
			for point in vertices:
				left = minf(left, point.dot(right))
				edge = maxf(edge, point.dot(right))
				bottom = minf(bottom, point.dot(up))
				top = maxf(top, point.dot(up))
			for i in vertices.size():
				var point := vertices[i]
				vertices[i] += right * (point.dot(right) - (left + edge) * 0.5) * 2.0 + up * (point.dot(up) - (bottom if stars else top)) * (2.0 if stars else 1.0)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_CUSTOM0] = sorting
		var material := ShaderMaterial.new()
		material.resource_name = texture_base.trim_suffix("/").get_file() + "_material_%02d" % mesh.get_surface_count()
		material.shader = load("res://game/rendering/source_surface.gdshader")
		material.set_shader_parameter("textured", not surface.texture.is_empty())
		var blend_mode := int(surface.get("blend_mode", -1))
		if blend_mode >= 0:
			material.set_shader_parameter("alpha_scissor_threshold", 0.75)
		if not surface.texture.is_empty():
			material.set_shader_parameter("albedo_texture", load(texture_base + surface.texture))
		_set_motion(material, surface, texture_base)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
		if blend_mode >= 0:
			var blended := ShaderMaterial.new()
			blended.resource_name = material.resource_name + "_blend"
			var effect: String = ["average", "add", "subtract", "add"][blend_mode]
			blended.shader = load("res://game/rendering/source_blend_" + effect + ".gdshader")
			blended.set_shader_parameter("albedo_texture", load(texture_base + surface.texture))
			blended.set_shader_parameter("opacity", [0.5, 1.0, 1.0, 0.25][blend_mode])
			_set_motion(blended, surface, texture_base)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT))
			mesh.surface_set_material(mesh.get_surface_count() - 1, blended)
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

func _set_motion(material: ShaderMaterial, surface: Dictionary, texture_base: String) -> void:
	var motion: Dictionary = surface.get("motion", {})
	if motion.is_empty():
		return
	var path: String = texture_base + motion.texture
	if not motion_textures.has(path):
		var image := Image.load_from_file(path)
		assert(image != null, "Missing motion atlas: " + path)
		var texture := ImageTexture.create_from_image(image)
		texture.resource_name = motion.texture.get_file().get_basename()
		motion_textures[path] = texture
	material.set_shader_parameter("motion_texture", motion_textures[path])
	material.set_shader_parameter("motion_size", Vector2(motion.size[0], motion.size[1]))
	material.set_shader_parameter("motion_count", motion.records.size())
	material.set_shader_parameter("motion_ripples", texture_base.trim_suffix("/").get_file() in ["farm", "yodel_ranch", "beach", "mother_hill_lake", "hot_spring", "lumberjack_forest"])
	for field in ["destination", "source", "timing"]:
		var values := PackedVector4Array()
		for record in motion.records:
			var value: Array = record["dest" if field == "destination" else field]
			values.append(Vector4(value[0], value[1], value[2], value[3]))
		values.resize(16)
		material.set_shader_parameter("motion_" + field, values)

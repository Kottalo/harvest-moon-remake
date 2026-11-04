extends SceneTree
## Export the static scene's opaque-pass mesh projection for bake_camera_coverage.py.

func _initialize() -> void:
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	var flags: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/time/day_cycle_catalog.json")).areas
	var camera = preload("res://game/camera/world_camera.gd").new()
	camera.basis = Basis.looking_at(-camera.eye_offset)
	var coverage := {}
	for id: String in catalogue:
		if int(flags[id].source_flags)&0x1800 or id=="56":
			continue
		var path: String = "res://game/world/coast.tscn" if id=="52" else catalogue[id].scene
		var location: Node3D = load(path).instantiate()
		var meshes: Array = [location.get_node("TownSquare/Geometry"),location.get_node("Beach/Geometry")] if id=="52" else [location.get_node("Geometry")]
		var surfaces := []
		for geometry: MeshInstance3D in meshes:
			var transform: Transform3D = geometry.transform if id!="52" else geometry.get_parent().transform*geometry.transform
			for surface in geometry.mesh.get_surface_count():
				var material: ShaderMaterial = geometry.mesh.surface_get_material(surface)
				if material.shader.resource_path.get_file()!="source_surface.gdshader":
					continue
				var arrays := geometry.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var albedo: Texture2D = material.get_shader_parameter("albedo_texture")
				var motion: Texture2D = material.get_shader_parameter("motion_texture")
				var points := []
				for i in range(0,vertices.size(),3):
					var a: Vector2 = camera._project(transform*vertices[i])
					var b: Vector2 = camera._project(transform*vertices[i+1])
					var c: Vector2 = camera._project(transform*vertices[i+2])
					if (b-a).cross(c-a)>=-0.00000001:
						continue
					for corner in 3:
						var position: Vector2 = [a,b,c][corner]
						var uv := uvs[i+corner]
						points.append_array([position.x,position.y,uv.x,uv.y])
				var count: int = material.get_shader_parameter("motion_count") if motion != null else 0
				var copies := []
				if count>0:
					var destinations = material.get_shader_parameter("motion_destination")
					var sources = material.get_shader_parameter("motion_source")
					for i in count:
						var dest: Vector4 = destinations[i]
						var src: Vector4 = sources[i]
						copies.append([[dest.x,dest.y,dest.z,dest.w],[src.x,src.y,src.z,src.w]])
				surfaces.append([_texture(albedo),_texture(motion),copies,points])
		coverage[id] = surfaces
		location.free()
	camera.free()
	var file := FileAccess.open("res://tools/generated/camera_coverage_source.json",FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(coverage))
	file.close()
	quit()

func _texture(texture: Texture2D) -> Array:
	if texture==null:
		return []
	if texture is AtlasTexture:
		var rect: Rect2 = texture.region
		return [texture.atlas.resource_path,[rect.position.x,rect.position.y,rect.size.x,rect.size.y]]
	return [texture.resource_path,[]]

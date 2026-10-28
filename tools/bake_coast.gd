extends RefCounted
## The originals contain non-walkable previews of each other. Cut those at the
## shared upper landing, retaining one staircase and interpolating UV/color edges.

func bake() -> void:
	for entry in [["town_square", Plane(Vector3.RIGHT, 5.0)], ["beach", Plane(Vector3.LEFT, 7.4)]]:
		var folder: String = "res://game/locations/" + entry[0] + "/"
		var scene: Node3D = load(folder + entry[0] + ".scn").instantiate()
		var geometry: MeshInstance3D = scene.get_node("Geometry")
		geometry.mesh = _clip_mesh(geometry.mesh, entry[1])
		for shape_node: CollisionShape3D in scene.find_children("*", "CollisionShape3D", true, false):
			var source: ConcavePolygonShape3D = shape_node.shape
			var faces := PackedVector3Array()
			var original := source.get_faces()
			for index in range(0, original.size(), 3):
				var polygon := Geometry3D.clip_polygon(original.slice(index, index + 3), entry[1])
				for corner in range(1, polygon.size() - 1):
					if (polygon[corner] - polygon[0]).cross(polygon[corner + 1] - polygon[0]).length_squared() > 0.000000000001:
						faces.append_array(PackedVector3Array([polygon[0], polygon[corner], polygon[corner + 1]]))
			if faces.is_empty():
				shape_node.free()
			else:
				var clipped := ConcavePolygonShape3D.new()
				clipped.set_faces(faces)
				clipped.backface_collision = true
				shape_node.shape = clipped
		var packed := PackedScene.new()
		assert(packed.pack(scene) == OK)
		assert(ResourceSaver.save(packed, folder + "coast_segment.scn") == OK)
		scene.free()
		print("COAST_SEGMENT_OK: ", entry[0])

func _clip_mesh(source: ArrayMesh, plane: Plane) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var uv := PackedVector2Array()
		for triangle in range(0, arrays[Mesh.ARRAY_VERTEX].size(), 3):
			var input := []
			for corner in 3:
				var index := triangle + corner
				input.append({"point": arrays[Mesh.ARRAY_VERTEX][index], "uv": arrays[Mesh.ARRAY_TEX_UV][index], "color": arrays[Mesh.ARRAY_COLOR][index]})
			var polygon := []
			for corner in 3:
				var a: Dictionary = input[corner]
				var b: Dictionary = input[(corner + 1) % 3]
				var da := plane.distance_to(a.point)
				var db := plane.distance_to(b.point)
				var inside_a := da <= 0.000001
				var inside_b := db <= 0.000001
				if inside_a:
					polygon.append(a)
				if inside_a != inside_b:
					var weight := clampf(da / (da - db), 0, 1)
					polygon.append({"point": a.point.lerp(b.point, weight), "uv": a.uv.lerp(b.uv, weight), "color": a.color.lerp(b.color, weight)})
			for corner in range(1, polygon.size() - 1):
				var a: Vector3 = polygon[0].point
				var b: Vector3 = polygon[corner].point
				var c: Vector3 = polygon[corner + 1].point
				if (b - a).cross(c - a).length_squared() < 0.000000000001:
					continue
				for index in [0, corner, corner + 1]:
					vertices.append(polygon[index].point)
					colors.append(polygon[index].color)
					uv.append(polygon[index].uv)
		if vertices.is_empty():
			continue
		var clipped := []
		clipped.resize(Mesh.ARRAY_MAX)
		clipped[Mesh.ARRAY_VERTEX] = vertices
		clipped[Mesh.ARRAY_COLOR] = colors
		clipped[Mesh.ARRAY_TEX_UV] = uv
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clipped)
		result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	return result

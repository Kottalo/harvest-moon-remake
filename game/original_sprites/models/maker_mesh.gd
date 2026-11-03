@tool
extends MeshInstance3D
## Builds a standalone mesh from the original barn/coop TMD triangles.

const MODEL_DATA := "res://game/original_sprites/models/makers.json"

@export_enum("mayonnaise_maker", "cheese_maker", "yarn_maker")
var source_model: String = "mayonnaise_maker":
	set(value):
		source_model = value
		if is_node_ready():
			_build()


func _ready() -> void:
	_build()


func _build() -> void:
	var models: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MODEL_DATA))
	var result := ArrayMesh.new()
	for surface: Dictionary in models[source_model]["surfaces"]:
		var vertices := PackedVector3Array()
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.vertex_color_use_as_albedo = true
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		var uv_origin := Vector2.ZERO
		var uv_scale := Vector2.ONE
		if surface.has("atlas"):
			material.albedo_texture = load(surface["atlas"])
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			var atlas_size := material.albedo_texture.get_size()
			var region: Array = surface["region"]
			uv_origin = Vector2(region[0], region[1]) / atlas_size
			uv_scale = Vector2(region[2], region[3]) / atlas_size
		for index in range(surface["vertices"].size() / 3):
			var vertex := index * 3
			var uv := index * 2
			var points: Array = surface["vertices"]
			var tint: Array = surface["colors"]
			vertices.append(Vector3(points[vertex], points[vertex + 1], points[vertex + 2]))
			colors.append(Color(tint[vertex], tint[vertex + 1], tint[vertex + 2]))
			uvs.append(uv_origin + Vector2(surface["uv"][uv], surface["uv"][uv + 1]) * uv_scale)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(result.get_surface_count() - 1, material)
	mesh = result

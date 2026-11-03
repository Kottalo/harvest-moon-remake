extends MeshInstance3D
## Opaque visual continuation behind the native map; never ground or collision.
var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://game/rendering/outdoor_backdrops/catalog.json"))
var map_name := ""

func _init() -> void:
	name = "OutdoorBackdrop"
	mesh = QuadMesh.new()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 1000

func configure(slug: String) -> void:
	map_name = slug
	visible = catalogue.has(slug)
	material_override = load(catalogue[slug]) if visible else null

func fit(camera: Camera3D) -> void:
	if not visible: return
	var viewport := camera.get_viewport().get_visible_rect().size
	if viewport.y<=0: return
	# A real camera-space quad uses the engine's depth projection in every backend.
	# Two pixels of overscan also cover MSAA samples at the screen edge.
	var wanted := Vector2(camera.size*viewport.x/viewport.y,camera.size)*(1.0+4.0/minf(viewport.x,viewport.y))
	if mesh.size!=wanted: mesh.size = wanted
	position.z = -camera.far*0.9

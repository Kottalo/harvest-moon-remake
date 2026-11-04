extends Sprite3D
## Shared source blob and circular character-to-character clearance on the ground.
const SHADOW_WIDTH_PIXELS := 24.0
const SAME_LEVEL_HEIGHT := 0.2
const FOOTPRINT_GROUP := &"character_ground_shadows"
const CONTACT_GAP := 0.001

@onready var actor: CharacterBody3D = get_parent()
var _sort_height := 0.0


func _ready() -> void:
	add_to_group(FOOTPRINT_GROUP)


func _physics_process(_delta: float) -> void:
	# NPC routes already provide their ground height.
	if actor.collision_layer == 0:
		hide()
		return
	show()
	place_on_ground(actor.global_position)


func place_on_ground(point: Vector3, sort_height := 0.0) -> void:
	if global_position != point:
		global_position = point
	if _sort_height != sort_height:
		_sort_height = sort_height
		material_override.set_shader_parameter("sort_height",sort_height)


func footprint_radius() -> float:
	return SHADOW_WIDTH_PIXELS * pixel_size * absf(global_basis.x.length()) * 0.5


func occupied(point: Vector3) -> bool:
	for other in get_tree().get_nodes_in_group(FOOTPRINT_GROUP):
		if not _shares_ground(other,point.y):
			continue
		var relative: Vector3 = point - other.global_position
		var spacing: float = footprint_radius() + other.footprint_radius() + CONTACT_GAP
		if Vector2(relative.x,relative.z).length_squared() < spacing*spacing:
			return true
	return false


func motion_fraction(point: Vector3, motion: Vector3) -> float:
	var step := Vector2(motion.x,motion.z)
	if step.is_zero_approx():
		return 1.0
	var allowed := 1.0
	for other in get_tree().get_nodes_in_group(FOOTPRINT_GROUP):
		if not _shares_ground(other,point.y):
			continue
		var offset: Vector3 = point - other.global_position
		var relative := Vector2(offset.x,offset.z)
		if relative.dot(step) >= 0.0:
			continue # Moving away, including recovery from a scripted overlap.
		var spacing: float = footprint_radius() + other.footprint_radius() + CONTACT_GAP
		if relative.length_squared() <= spacing*spacing:
			return 0.0
		var hit := Geometry2D.segment_intersects_circle(relative,relative+step,Vector2.ZERO,spacing)
		if hit >= 0.0:
			allowed = minf(allowed,hit)
	return allowed


func _shares_ground(other: Sprite3D, height: float) -> bool:
	return other != self and other.is_visible_in_tree() and absf(other.global_position.y-height) < SAME_LEVEL_HEIGHT

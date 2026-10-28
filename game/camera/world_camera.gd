extends Camera3D
## Original farm projection/angle, with the user's wider framing.
const HORIZONTAL_DISTANCE := 9000.0 / 1000.0
const HEIGHT := 4500.0 / 1000.0
const DISTANCE_SCALE := 1.44
const YAW := -512.0 * TAU / 4096.0
const PROJECTION_DISTANCE := 1000.0
var eye_offset := Vector3(-sin(YAW) * HORIZONTAL_DISTANCE, HEIGHT, cos(YAW) * HORIZONTAL_DISTANCE) * DISTANCE_SCALE

func _ready() -> void:
	keep_aspect = Camera3D.KEEP_HEIGHT
	reset_perspective()

func reset_perspective() -> void:
	set_perspective(rad_to_deg(2.0 * atan(120.0 / PROJECTION_DISTANCE)), 0.05, 200.0)

func follow(player: CharacterBody3D, overview: bool) -> void:
	if not overview:
		position = player.position + eye_offset
		look_at(player.position)

func show_overview(location: Node3D) -> void:
	var bounds: AABB = location.get_node("Geometry").mesh.get_aabb()
	var focus := bounds.get_center()
	set_orthogonal(maxf(bounds.size.x, bounds.size.z) * 1.25, 0.05, 200)
	position = focus + eye_offset * 3
	look_at(focus)

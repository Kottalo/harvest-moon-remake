extends Camera3D
## Orthographic gameplay at the existing angle and centre-plane framing.
const HORIZONTAL_DISTANCE := 9000.0 / 1000.0
const HEIGHT := 4500.0 / 1000.0
const DISTANCE_SCALE := 1.44
const YAW := -512.0 * TAU / 4096.0
const PROJECTION_DISTANCE := 1000.0
var eye_offset := Vector3(-sin(YAW) * HORIZONTAL_DISTANCE, HEIGHT, cos(YAW) * HORIZONTAL_DISTANCE) * DISTANCE_SCALE
var _settled_focus := Vector3.INF

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	keep_aspect = Camera3D.KEEP_HEIGHT
	reset_gameplay()

func reset_gameplay() -> void:
	set_orthogonal(sqrt(HORIZONTAL_DISTANCE*HORIZONTAL_DISTANCE+HEIGHT*HEIGHT)*DISTANCE_SCALE*240.0/PROJECTION_DISTANCE, 0.05, 200.0)

func follow(player: CharacterBody3D, overview: bool, interpolate := false) -> void:
	if not overview:
		var focus := player.get_global_transform_interpolated().origin if interpolate else player.global_position
		var actions = player.get("actions")
		if actions != null and actions.cinematic:
			focus.y = actions.bed_ground_y # The source bed arc lifts the body, not the camera.
		if player.hop.active:
			focus.y = player.hop.ground_y
		# move_and_slide can recover a millimetre against floor/item contacts even
		# with zero resolved velocity. Do not turn that recovery into camera motion.
		if interpolate and player.is_on_floor() and player.velocity.length_squared()<0.000001 and not player.hop.active and (actions==null or not actions.cinematic):
			if focus.distance_to(_settled_focus)>maxf(player.safe_margin*4.0,0.0001):
				_settled_focus = focus
			focus = _settled_focus
		else:
			_settled_focus = Vector3.INF
		position = focus + eye_offset
		# Constant angle: subtracting large world coordinates in look_at introduced
		# additional tiny rotations, which also changed billboard orientations.
		basis = Basis.looking_at(-eye_offset)

func show_overview(location: Node3D) -> void:
	var bounds: AABB
	var first := true
	for geometry: MeshInstance3D in location.find_children("*", "MeshInstance3D", true, false):
		var part: AABB = location.global_transform.affine_inverse() * geometry.global_transform * geometry.mesh.get_aabb()
		bounds = part if first else bounds.merge(part)
		first = false
	var focus := bounds.get_center()
	set_orthogonal(maxf(bounds.size.x, bounds.size.z) * 1.25, 0.05, 200)
	position = focus + eye_offset * 3
	look_at(focus)

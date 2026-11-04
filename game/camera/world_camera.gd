extends Camera3D
## Orthographic gameplay at the existing angle and centre-plane framing.
const HORIZONTAL_DISTANCE := 9000.0 / 1000.0
const HEIGHT := 4500.0 / 1000.0
const EDGE_PADDING := 0.05
const FARM_TRIAL_PADDING := 0.45
const FOLLOW_RESPONSE_SECONDS := 0.035
const FOLLOW_SETTLE_DISTANCE := 0.00005
const YAW := -512.0 * TAU / 4096.0
const PROJECTION_DISTANCE := 1000.0
var eye_offset := Vector3(-sin(YAW) * HORIZONTAL_DISTANCE, HEIGHT, cos(YAW) * HORIZONTAL_DISTANCE)
var _settled_focus := Vector3.INF
var _render_focus := Vector3.INF
var _coverage := PackedVector2Array()
var _limits := PackedVector2Array()
var _screen_bounds := Rect2()
var _half_view := Vector2.ZERO
var _viewport_size := Vector2.ZERO
var _edge_padding := EDGE_PADDING

func set_location(location: Node3D, outdoors: bool) -> void:
	_coverage.clear()
	_limits.clear()
	_half_view = Vector2.ZERO
	_viewport_size = Vector2.ZERO
	reset_gameplay()
	if not outdoors: return
	basis = Basis.looking_at(-eye_offset)
	var points := PackedVector2Array()
	for geometry: MeshInstance3D in location.find_children("*","MeshInstance3D",true,false):
		if geometry.mesh==null or not geometry.is_visible_in_tree(): continue
		for vertex in geometry.mesh.get_faces():
			points.append(_project(geometry.global_transform*vertex))
	if points.size()<3: return
	# Strict camera bounds: do not relax them to recenter a border-positioned player.
	_coverage = Geometry2D.convex_hull(points)
	if _coverage[0].is_equal_approx(_coverage[-1]): _coverage.remove_at(_coverage.size()-1)
	_screen_bounds = Rect2(_coverage[0],Vector2.ZERO)
	for point in _coverage: _screen_bounds = _screen_bounds.expand(point)

func set_farm_edge_trial(enabled: bool) -> void:
	_edge_padding = FARM_TRIAL_PADDING if enabled else EDGE_PADDING
	_half_view = Vector2.ZERO

func _project(point: Vector3) -> Vector2:
	return Vector2(point.dot(basis.x),point.dot(basis.y))

func _update_limits(half: Vector2) -> void:
	_half_view = half
	_limits = _coverage.duplicate()
	var centre := Vector2.ZERO
	for vertex in _coverage: centre += vertex/_coverage.size()
	for i in _coverage.size():
		var point := _coverage[i]
		var edge := _coverage[(i+1)%_coverage.size()]-point
		var inward := Vector2(-edge.y,edge.x).normalized()
		if inward.dot(centre-point)<0: inward = -inward
		var boundary := inward.dot(point)+inward.abs().dot(half)+_edge_padding
		var clipped := PackedVector2Array()
		for j in _limits.size():
			var a := _limits[j]
			var b := _limits[(j+1)%_limits.size()]
			var da := inward.dot(a)-boundary
			var db := inward.dot(b)-boundary
			if da>=0: clipped.append(a)
			if (da>=0)!=(db>=0): clipped.append(a.lerp(b,da/(da-db)))
		_limits = clipped
		if _limits.is_empty(): break

func limited_focus(focus: Vector3) -> Vector3:
	if _coverage.is_empty(): return focus
	var viewport := get_viewport().get_visible_rect().size
	if viewport.y<=0: return focus
	if not viewport.is_equal_approx(_viewport_size):
		_viewport_size = viewport
		reset_gameplay()
	var half := Vector2(size*viewport.x/viewport.y,size)*0.5
	if not half.is_equal_approx(_half_view):
		_render_focus = Vector3.INF
		_update_limits(half)
		# A very wide viewport or narrow location may have no valid camera
		# centre at the requested zoom. Tighten only on that projection change.
		for attempt in 80:
			if _limits.size()>=3: break
			size *= 0.95
			half = Vector2(size*viewport.x/viewport.y,size)*0.5
			_update_limits(half)
	var anchor := _project(focus)
	var target := anchor
	if _limits.size()>=3:
		if not Geometry2D.is_point_in_polygon(anchor,_limits):
			var best := INF
			for i in _limits.size():
				var closest := Geometry2D.get_closest_point_to_segment(anchor,_limits[i],_limits[(i+1)%_limits.size()])
				var distance := anchor.distance_squared_to(closest)
				if distance<best: best = distance;target = closest
	else:
		# Maps narrower than the viewport cannot fill it at the retained zoom.
		for axis in 2:
			var low := _screen_bounds.position[axis]+half[axis]
			var high := _screen_bounds.end[axis]-half[axis]
			target[axis] = clampf(anchor[axis],low,high) if low<=high else _screen_bounds.get_center()[axis]
	return focus+basis.x*(target.x-anchor.x)+basis.y*(target.y-anchor.y)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	keep_aspect = Camera3D.KEEP_HEIGHT
	reset_gameplay()

func reset_gameplay() -> void:
	_render_focus = Vector3.INF
	_settled_focus = Vector3.INF
	set_orthogonal(sqrt(HORIZONTAL_DISTANCE*HORIZONTAL_DISTANCE+HEIGHT*HEIGHT)*240.0/PROJECTION_DISTANCE, 0.05, 200.0)

func follow(player: CharacterBody3D, overview: bool, interpolate := false, delta := 0.0) -> void:
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
		# Constant angle: subtracting large world coordinates in look_at introduced
		# additional tiny rotations, which also changed billboard orientations.
		var direction_basis := Basis.looking_at(-eye_offset)
		if basis != direction_basis:
			basis = direction_basis
		var desired := limited_focus(focus)
		if interpolate and delta > 0.0 and _render_focus.is_finite():
			# Both centres fit the same convex map limits, so the blend fits too.
			var weight := 1.0 - exp(-delta / FOLLOW_RESPONSE_SECONDS)
			_render_focus = _render_focus.lerp(desired,weight)
			if _render_focus.distance_squared_to(desired) <= FOLLOW_SETTLE_DISTANCE * FOLLOW_SETTLE_DISTANCE:
				_render_focus = desired
		else:
			_render_focus = desired
		var target := _render_focus + eye_offset
		if position != target:
			position = target

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

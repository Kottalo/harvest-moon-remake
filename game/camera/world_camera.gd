extends Camera3D
## Orthographic gameplay at the existing angle and centre-plane framing.
const HORIZONTAL_DISTANCE := 9000.0 / 1000.0
const HEIGHT := 4500.0 / 1000.0
const DISTANCE_SCALE := 1.44
const YAW := -512.0 * TAU / 4096.0
const PROJECTION_DISTANCE := 1000.0
var eye_offset := Vector3(-sin(YAW) * HORIZONTAL_DISTANCE, HEIGHT, cos(YAW) * HORIZONTAL_DISTANCE) * DISTANCE_SCALE
var _settled_focus := Vector3.INF
var _coverage := PackedVector2Array()
var _limits := PackedVector2Array()
var _screen_bounds := Rect2()
var _half_view := Vector2.ZERO
var backdrop: MeshInstance3D

func set_location(location: Node3D, outdoors: bool, map_name := "") -> void:
	backdrop.configure(map_name if outdoors else "")
	backdrop.fit(self)
	_coverage.clear()
	_limits.clear()
	_half_view = Vector2.ZERO
	_settled_focus = Vector3.INF
	if not outdoors: return
	basis = Basis.looking_at(-eye_offset)
	var points := PackedVector2Array()
	for geometry: MeshInstance3D in location.find_children("*","MeshInstance3D",true,false):
		if geometry.mesh==null or not geometry.is_visible_in_tree(): continue
		for vertex in geometry.mesh.get_faces():
			points.append(_project(geometry.global_transform*vertex))
	if points.size()<3: return
	# The envelope limits the native map. The separate opaque visual backdrop
	# covers concave cutouts/narrow tips while the full player remains visible.
	_coverage = Geometry2D.convex_hull(points)
	if _coverage[0].is_equal_approx(_coverage[-1]): _coverage.remove_at(_coverage.size()-1)
	_screen_bounds = Rect2(_coverage[0],Vector2.ZERO)
	for point in _coverage: _screen_bounds = _screen_bounds.expand(point)

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
		var boundary := inward.dot(point)+inward.abs().dot(half)
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
	var half := Vector2(size*viewport.x/viewport.y,size)*0.5
	if not half.is_equal_approx(_half_view): _update_limits(half)
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
	# At narrow tips/exit zones, exposing some void is preferable to losing the
	# player off-screen. Reserve room above the feet for the complete sprite.
	target.x = clampf(target.x,anchor.x-maxf(half.x-0.22,0.1),anchor.x+maxf(half.x-0.22,0.1))
	target.y = clampf(target.y,anchor.y-maxf(half.y-0.6,0.1),anchor.y+maxf(half.y-0.15,0.1))
	return focus+basis.x*(target.x-anchor.x)+basis.y*(target.y-anchor.y)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	keep_aspect = Camera3D.KEEP_HEIGHT
	reset_gameplay()
	backdrop = preload("res://game/rendering/outdoor_backdrop.gd").new()
	add_child(backdrop)

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
		# Constant angle: subtracting large world coordinates in look_at introduced
		# additional tiny rotations, which also changed billboard orientations.
		basis = Basis.looking_at(-eye_offset)
		position = limited_focus(focus) + eye_offset
		backdrop.fit(self)

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
	backdrop.fit(self)

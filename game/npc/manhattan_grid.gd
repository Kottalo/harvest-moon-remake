extends RefCounted
## Four-connected A* over the native ground and solid collision layers.
const SOIL_EDGE := Vector2(-4.4,-1.6)
const SOIL_SIZE := 0.4
const CELL_SIZE := SOIL_SIZE / 2.0
const DIRECTIONS := [Vector2i.DOWN,Vector2i.LEFT,Vector2i.UP,Vector2i.RIGHT]
const MAX_FLOOR_ANGLE := PI / 3.0
const PROBE_HEIGHT := 0.75
const CLEARANCE := 0.004

class ManhattanAStar extends AStar2D:
	func _estimate_cost(from_id: int, to_id: int) -> float:
		var difference := (get_point_position(from_id) - get_point_position(to_id)).abs()
		return difference.x + difference.y

var graph := ManhattanAStar.new()
var positions := {}
var region: Rect2i
var scanned := 0
var space: PhysicsDirectSpaceState3D
var capsule_query := PhysicsShapeQueryParameters3D.new()
var capsule_lift: float
var floor_bounds := Vector2.ZERO
var ground_shadow


static func cell_at(point: Vector3) -> Vector2i:
	var relative := (Vector2(point.x,point.z) - SOIL_EDGE) / CELL_SIZE
	# Tolerate float error at exact grid boundaries, including negative cells.
	return Vector2i((relative + Vector2.ONE*0.00001).floor())


static func center_of(cell: Vector2i) -> Vector2:
	return SOIL_EDGE + (Vector2(cell) + Vector2(0.5,0.5)) * CELL_SIZE


func begin(state: PhysicsDirectSpaceState3D, bounds: Rect2i, body: CharacterBody3D,
		shape: CapsuleShape3D, center_y: float, floor_y: float, goal_y := INF) -> void:
	space = state
	ground_shadow = body.get_node_or_null("GroundShadow")
	region = bounds
	if not is_finite(goal_y):
		goal_y = floor_y
	floor_bounds = Vector2(minf(floor_y,goal_y),maxf(floor_y,goal_y))
	scanned = 0
	graph.clear()
	positions.clear()
	capsule_query.shape = shape
	capsule_query.collision_mask = body.collision_mask
	capsule_query.exclude = [body.get_rid()]
	capsule_lift = center_y + CLEARANCE


func build_step(budget: int) -> bool:
	var total := region.size.x * region.size.y
	for index in range(scanned,mini(scanned + budget,total)):
		_add_cell(region.position + Vector2i(index % region.size.x,floori(float(index) / region.size.x)))
	scanned = mini(scanned + budget,total)
	return scanned == total


func refresh_near(point: Vector3) -> void:
	var margin := Vector2i.ONE*2
	var patch := region.intersection(Rect2i(cell_at(point)-margin,margin*2+Vector2i.ONE))
	for y in range(patch.position.y,patch.end.y):
		for x in range(patch.position.x,patch.end.x):
			var cell := Vector2i(x,y)
			if positions.erase(cell):
				graph.remove_point(_id(cell))
	for y in range(patch.position.y,patch.end.y):
		for x in range(patch.position.x,patch.end.x):
			_add_cell(Vector2i(x,y))


func path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not positions.has(start) or not positions.has(goal):
		return result
	# An open straight or L-shaped route is already Manhattan-shortest.
	var offset := goal-start
	var first := Vector2i(signi(offset.x),0)
	var second := Vector2i(0,signi(offset.y))
	if absi(offset.y)>absi(offset.x):
		var swap := first
		first = second
		second = swap
	result = _elbow_path(start,goal,first,second)
	if not result.is_empty():
		return result
	result = _elbow_path(start,goal,second,first)
	if not result.is_empty():
		return result
	for point in graph.get_point_path(_id(start),_id(goal)):
		result.append(Vector2i(point))
	return result


func _elbow_path(start: Vector2i, goal: Vector2i, first: Vector2i, second: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [start]
	var current := start
	for direction: Vector2i in [first,second]:
		var distance := (goal-current).abs()*direction.abs()
		for step in distance.x+distance.y:
			var next := current+direction
			if not positions.has(next) or not graph.are_points_connected(_id(current),_id(next)):
				return []
			cells.append(next)
			current = next
	return cells


func nearby_cells(point: Vector3, radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var centre := cell_at(point)
	for x in range(centre.x-radius,centre.x+radius+1):
		for z in range(centre.y-radius,centre.y+radius+1):
			var cell := Vector2i(x,z)
			if positions.has(cell):
				result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i):
		return point.distance_squared_to(positions[a])<point.distance_squared_to(positions[b]))
	return result


func _id(cell: Vector2i) -> int:
	var local := cell - region.position
	return local.y * region.size.x + local.x


func _ground(horizontal: Vector2) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(
		Vector3(horizontal.x,floor_bounds.y+PROBE_HEIGHT,horizontal.y),
		Vector3(horizontal.x,floor_bounds.x-PROBE_HEIGHT,horizontal.y),8)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < cos(MAX_FLOOR_ANGLE):
		return Vector3.INF
	return hit.position


func _add_cell(cell: Vector2i) -> void:
	var point := _ground(center_of(cell))
	if not point.is_finite() or (ground_shadow != null and ground_shadow.occupied(point)):
		return
	capsule_query.motion = Vector3.ZERO
	capsule_query.transform.origin = point + Vector3.UP*capsule_lift
	if not space.intersect_shape(capsule_query,1).is_empty():
		return
	positions[cell] = point
	var id := _id(cell)
	graph.add_point(id,Vector2(cell))
	for direction in DIRECTIONS:
		var neighbour: Vector2i = cell + direction
		if positions.has(neighbour) and _edge_clear(point,positions[neighbour]):
			graph.connect_points(id,_id(neighbour))


func _edge_clear(from: Vector3, to: Vector3) -> bool:
	if ground_shadow != null and ground_shadow.motion_fraction(from,to-from) < 1.0:
		return false
	var middle := _ground(Vector2((from.x + to.x)*0.5,(from.z + to.z)*0.5))
	if not middle.is_finite():
		return false
	var max_rise := tan(MAX_FLOOR_ANGLE) * CELL_SIZE * 0.5
	if absf(from.y - middle.y) > max_rise or absf(middle.y - to.y) > max_rise:
		return false
	return _sweep_clear(from,middle) and _sweep_clear(middle,to)


func _sweep_clear(from: Vector3, to: Vector3) -> bool:
	capsule_query.motion = Vector3.ZERO
	capsule_query.transform.origin = from + Vector3.UP*capsule_lift
	if not space.intersect_shape(capsule_query,1).is_empty():
		return false
	capsule_query.motion = to - from
	var result := space.cast_motion(capsule_query)
	return result.size() == 2 and result[0] >= 1.0

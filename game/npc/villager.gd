extends CharacterBody3D
## A scheduled villager follows native waypoints on the shared Manhattan grid.
const Grid := preload("res://game/npc/manhattan_grid.gd")
const CELLS_PER_TICK := 16
const RETRY_SECONDS := 0.5
const GRID_EPSILON := 0.00001

@onready var sprite: Sprite3D = $Sprite3D
@onready var footprint: CollisionShape3D = $Footprint
@onready var ground_shadow = $GroundShadow

var world
var display_name: String
var art
var poses: Array
var textures: Array = []
var itinerary: Array
var loop_start: int
var speed: float
var grid := Grid.new()
var path: Array[Vector2i] = []
var route_goal: Variant = null
var last_cell: Vector2i
var waypoint := 0
var attempts := 0
var building := false
var placed := false
var wait := 0.0
var facing := 0
var walk_frame := 0
var walk_elapsed := 0.0
var walking := false
var talk_wait := 0.0
var elapsed_at_spawn := 0.0
var spawn_pass := 0


func _ready() -> void:
	sprite.hide()
	for sequence: Array in poses:
		var frames := []
		for frame: Dictionary in sequence:
			frames.append(art.frame_texture(frame))
		textures.append(frames)


func set_itinerary(points: Array, repeat_from: int, seconds_since_start := 0.0, keep_position := false) -> void:
	itinerary = points
	loop_start = repeat_from
	waypoint = 1 if placed and keep_position and points.size()>1 else 0
	elapsed_at_spawn = 0.0
	if not placed:
		_resume_itinerary(seconds_since_start)
	# Every new row takes its facing and pauses from the same source cells.
	path.clear()
	route_goal = null
	wait = 0.0
	attempts = 0
	spawn_pass = 0
	building = false


func _resume_itinerary(elapsed: float) -> void:
	var arrival: Array[float] = [0.0]
	for i in range(1,itinerary.size()):
		var from: Vector3 = itinerary[i-1][0]
		var to: Vector3 = itinerary[i][0]
		arrival.append(arrival[i-1]+float(itinerary[i-1][2])+from.distance_to(to)/speed)
	if loop_start>=0 and elapsed>=arrival[loop_start]:
		var last: Array = itinerary.back()
		var end: Vector3 = last[0]
		var loop_point: Vector3 = itinerary[loop_start][0]
		var duration: float = arrival.back()+float(last[2])+end.distance_to(loop_point)/speed-arrival[loop_start]
		if duration>0.0:
			elapsed = arrival[loop_start]+fposmod(elapsed-arrival[loop_start],duration)
	for i in range(1,arrival.size()):
		if elapsed<arrival[i]:
			break
		waypoint = i
	elapsed_at_spawn = elapsed-arrival[waypoint]


func _physics_process(delta: float) -> void:
	if world!=null and ((world.transitioning and placed) or world.day_cycle.menu_open or world.day_cycle.sleeping):
		return
	if talk_wait > 0.0:
		talk_wait -= delta
		return
	if wait > 0.0:
		wait -= delta
		return
	if waypoint >= itinerary.size():
		return
	var point: Vector3 = itinerary[waypoint][0]
	if path.is_empty():
		if not building:
			if placed and grid.region.grow(-2).has_point(Grid.cell_at(point)) and _find_path(point):
				return
			_begin_path(point)
		if grid.build_step(CELLS_PER_TICK):
			building = false
			_finish_path(point)
		return
	var next_cell := path[0]
	var target: Vector3 = grid.positions[next_cell]
	var difference := target - global_position
	if difference.length_squared() < 0.0000001:
		last_cell = next_cell
		path.pop_front()
		global_position = target
		if path.is_empty():
			_arrive()
			return
		target = grid.positions[path[0]]
		difference = target-global_position
	var step := difference.limit_length(speed*delta)
	var clearance: float = ground_shadow.motion_fraction(global_position,step)
	var motion := step*clearance
	# Sweep the capsule before applying the exact axis step. Collision recovery
	# must not nudge the actor sideways between adjacent grid centres.
	var blocked := test_move(global_transform,motion)
	if not blocked:
		global_position = target if clearance==1.0 and step==difference else global_position+motion
	if blocked or clearance < 1.0:
		path.clear()
		grid.refresh_near(global_position+step)
		if not _find_path(point):
			attempts = mini(attempts+1,2)
			_begin_path(point)
			_idle()
		return
	_walk(_facing_for(difference),delta)


func _begin_path(point: Vector3) -> void:
	var goal := Grid.cell_at(point)
	var start := Grid.cell_at(global_position) if placed else goal
	var margin := Vector2i.ONE * (2 + spawn_pass*2 if not placed else 4 + attempts*4)
	var bounds := Rect2i(start.min(goal)-margin, (start-goal).abs()+margin*2+Vector2i.ONE)
	grid.begin(get_world_3d().direct_space_state,bounds,self,footprint.shape,footprint.position.y,
		global_position.y if placed else point.y,point.y)
	building = true


func _finish_path(point: Vector3) -> void:
	if not placed:
		var goals := grid.nearby_cells(point,2 + spawn_pass*2)
		for goal in goals:
			var spawn: Vector3 = grid.positions[goal]
			if ground_shadow.occupied(spawn):
				continue
			last_cell = goal
			global_position = spawn
			reset_physics_interpolation()
			collision_layer = 1
			placed = true
			sprite.show()
			ground_shadow.place_on_ground(spawn)
			ground_shadow.show()
			_arrive()
			return
		wait = RETRY_SECONDS
		# A scheduled waypoint can be outside the accessible part of a door.
		waypoint += 1
		if waypoint==itinerary.size() and spawn_pass==0:
			waypoint = 0
			spawn_pass = 1
		elapsed_at_spawn = 0.0
		return
	if _find_path(point):
		return
	attempts = mini(attempts+1,2)
	wait = RETRY_SECONDS
	_idle()


func _find_path(point: Vector3) -> bool:
	var starts := grid.nearby_cells(global_position,1)
	if ground_shadow.occupied(point):
		return false
	var goal_cell := Grid.cell_at(point)
	var goals: Array[Vector2i] = []
	if route_goal != null:
		goals.append(route_goal)
	elif grid.positions.has(goal_cell):
		goals.append(goal_cell)
	else:
		goals = grid.nearby_cells(point,2)
	var reachable: Array[Vector2i] = []
	for start in starts:
		var step: Vector3 = grid.positions[start]-global_position
		# After a mid-edge collision, resume from a reachable end of that edge.
		if (absf(step.x)>GRID_EPSILON and absf(step.z)>GRID_EPSILON) \
				or absf(step.x)+absf(step.z)>Grid.CELL_SIZE+GRID_EPSILON:
			continue
		if step.length_squared()>0.0000001 and (ground_shadow.motion_fraction(global_position,step)<1.0
				or test_move(global_transform,step)):
			continue
		reachable.append(start)
	for goal in goals:
		for start in reachable:
			path = grid.path(start,goal)
			if not path.is_empty():
				route_goal = goal
				return true
	return false


func _arrive() -> void:
	var record: Array = itinerary[waypoint]
	facing = int(record[1])
	wait = maxf(wait,float(record[2])-elapsed_at_spawn)
	elapsed_at_spawn = 0.0
	attempts = 0
	route_goal = null
	waypoint += 1
	if waypoint == itinerary.size() and loop_start >= 0:
		waypoint = loop_start
	_idle()


func greet(point: Vector3) -> void:
	facing = _facing_for(point-global_position)
	talk_wait = 1.2
	_idle()


func _facing_for(direction: Vector3) -> int:
	if absf(direction.x)>absf(direction.z):
		return 1 if direction.x<0.0 else 3
	return 2 if direction.z<0.0 else 0


func _show_pose(animation: int, frame: int) -> void:
	var texture: AtlasTexture = textures[animation][frame]
	if sprite.texture != texture:
		sprite.texture = texture
		sprite.material_override.set_shader_parameter("albedo_texture",texture)


func _idle() -> void:
	walking = false
	_show_pose(0,facing)


func _walk(next_facing: int, delta: float) -> void:
	var animation := next_facing + 1
	if animation >= poses.size():
		facing = next_facing
		_idle()
		return
	if not walking or facing != next_facing:
		facing = next_facing
		walking = true
		walk_elapsed = 0.0
		walk_frame = 0
	var sequence: Array = poses[animation]
	walk_elapsed += delta
	var frame: Dictionary = sequence[walk_frame]
	var duration := maxf(ceilf(float(frame.duration)/2.0),1.0)/30.0
	if walk_elapsed >= duration:
		walk_elapsed -= duration
		var control := int(frame.control)
		if control != 255:
			walk_frame = (control & 127) if (control & 128) else (walk_frame + 1) % sequence.size()
	_show_pose(animation,walk_frame)

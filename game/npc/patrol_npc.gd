extends CharacterBody3D
## Follows cardinal cell centres and advances the original ANI walk cycles.
const Grid := preload("res://game/npc/manhattan_grid.gd")
const SpriteLibrary := preload("res://game/original_sprites/sprite_library.gd")
const WALK_SPEED := 0.82
const CELLS_PER_TICK := 12
const PAUSE_SECONDS := 0.7

@export var search_region := Rect2i()
@export var patrol: Array[Vector2i] = []
@export_file("*.json") var animation_path: String
@onready var sprite: Sprite3D = $Sprite3D
@onready var footprint: CollisionShape3D = $Footprint

var world
var grid := Grid.new()
var route: Array[Vector2i] = []
var cell := Vector2i.ZERO
var goal_index := 1
var building := false
var active := false
var replan := true
var pause_remaining := 0.0
var poses: Array
var textures: Array = []
var facing := 0
var walk_frame := 0
var walk_elapsed := 0.0
var walking := false


func _ready() -> void:
	sprite.hide()
	if world == null or patrol.size() < 2 or not search_region.has_area():
		set_physics_process(false)
		return
	cell = patrol[0]


func _physics_process(delta: float) -> void:
	if world.transitioning or world.day_cycle.menu_open:
		return
	if pause_remaining > 0.0:
		pause_remaining -= delta
		return
	if replan and not building:
		grid.begin(get_world_3d().direct_space_state,search_region,self,footprint.shape,
			footprint.position.y,0.0)
		building = true
	if building:
		if grid.build_step(CELLS_PER_TICK):
			building = false
			replan = false
			if not active:
				if not grid.positions.has(cell):
					_retry()
					return
				global_position = grid.positions[cell]
				reset_physics_interpolation()
				collision_layer = 1
				active = true
				_load_animations()
			_plan()
		return
	if route.is_empty():
		_plan()
		return
	var next := route[0]
	var target: Vector3 = grid.positions[next]
	var difference := target - global_position
	if difference.length_squared() < 0.0000001:
		cell = next
		route.pop_front()
		if route.is_empty():
			goal_index = (goal_index + 1) % patrol.size()
			pause_remaining = PAUSE_SECONDS
			_idle()
		return
	var horizontal := Vector2(difference.x,difference.z)
	var direction := Vector2i(signf(horizontal.x),0) if absf(horizontal.x) > absf(horizontal.y) else Vector2i(0,signf(horizontal.y))
	var next_facing := Grid.DIRECTIONS.find(direction)
	if move_and_collide(difference.limit_length(WALK_SPEED*delta)) != null:
		_retry()
		return
	if next_facing >= 0:
		_walk(next_facing,delta)


func _plan() -> void:
	route = grid.path(cell,patrol[goal_index])
	if route.is_empty():
		_retry()
		return
	if global_position.distance_squared_to(grid.positions[cell]) < 0.0000001:
		route.pop_front()


func _retry() -> void:
	route.clear()
	replan = true
	pause_remaining = PAUSE_SECONDS
	if active:
		_idle()


func _load_animations() -> void:
	var library := SpriteLibrary.new(animation_path)
	poses = library.catalogue["ranges"]
	for sequence: Array in poses:
		var frames := []
		for frame: Dictionary in sequence:
			frames.append(library.frame_texture(frame))
		textures.append(frames)
	_idle()
	sprite.show()


func _show_pose(animation: int, frame: int) -> void:
	var texture: AtlasTexture = textures[animation][frame]
	if sprite.texture != texture:
		sprite.texture = texture
		sprite.material_override.set_shader_parameter("albedo_texture",texture)


func _idle() -> void:
	walking = false
	_show_pose(0,facing)


func _walk(next_facing: int, delta: float) -> void:
	if not walking or facing != next_facing:
		facing = next_facing
		walking = true
		walk_elapsed = 0.0
		walk_frame = 0
	var sequence: Array = poses[facing + 1]
	walk_elapsed += delta
	var frame: Dictionary = sequence[walk_frame]
	var duration := maxf(ceilf(float(frame.duration) / 2.0),1.0) / 30.0
	if walk_elapsed >= duration:
		walk_elapsed -= duration
		var control := int(frame.control)
		if control != 255:
			walk_frame = (control & 127) if (control & 128) else (walk_frame + 1) % sequence.size()
	_show_pose(facing + 1,walk_frame)

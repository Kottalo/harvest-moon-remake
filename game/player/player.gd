extends CharacterBody3D
## Player input, ground movement and original ANI playback. No world-loading dependencies.
var facing := 0
var animation := 0
var animation_frame := 0
var animation_time := 0.0
var animation_data: Dictionary
@onready var sprite: Sprite3D = $Sprite3D
@onready var footprint: CapsuleShape3D = $CollisionShape3D.shape
const WALK_SPEED := 41.0 * 30.0 / 1000.0
const RUN_SPEED := 73.0 * 30.0 / 1000.0
# player.c: GROUND_TOLERANCE_DEFAULT=200; player_slide_on_bump probes 48 units ahead.
const GROUND_PROBE_HEIGHT := 200.0 / 1000.0
const GROUND_PROBE_REACH := 48.0 / 1000.0

func _ready() -> void:
	_setup_input()
	animation_data = JSON.parse_string(FileAccess.get_file_as_string("res://game/player/player_animations.json"))

func _physics_process(delta: float) -> void:
	var direction := _movement_direction()
	var running := Input.is_action_pressed("run")
	var speed := RUN_SPEED if running else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.y * speed
	velocity.y -= 14 * delta
	_constrain_to_ground(Vector3(velocity.x, 0, velocity.z) * delta)
	move_and_slide()
	_update_animation(direction, running, delta)

func _constrain_to_ground(motion: Vector3) -> void:
	if velocity.y > 0 or motion.is_zero_approx():
		return
	# farm_probe.c: settle against walkable ground, not every visible model face.
	# The native capsule must reach the next tread even when one 120 Hz step is tiny.
	var ahead := motion + motion.normalized() * maxf(GROUND_PROBE_REACH, footprint.radius)
	# Original integer edge tests include triangle seams. Native rays can miss exactly on them.
	for edge in [Vector3.ZERO, Vector3(0.001, 0, 0), Vector3(-0.001, 0, 0), Vector3(0, 0, 0.001), Vector3(0, 0, -0.001)]:
		var query := PhysicsRayQueryParameters3D.create(global_position + up_direction * GROUND_PROBE_HEIGHT + ahead + edge, global_position - up_direction * GROUND_PROBE_HEIGHT + ahead + edge)
		query.exclude = [get_rid()]
		query.collision_mask = 8 # Original forward probe: skip mask 0xE080.
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.normal.dot(up_direction) >= cos(floor_max_angle):
			return
	velocity.x = 0
	velocity.z = 0

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"run": [KEY_SHIFT], "interact": [KEY_E, KEY_ENTER]
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _movement_direction() -> Vector2:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# player_dpad_facing: diagonals choose a single original world axis.
	if input.y > 0 and input.x <= 0:
		return Vector2(0, 1) # PS1 -Z -> screen southwest
	if input.x < 0:
		return Vector2(-1, 0) # PS1 -X -> screen northwest
	if input.y < 0:
		return Vector2(0, -1) # PS1 +Z -> screen northeast
	if input.x > 0:
		return Vector2(1, 0) # PS1 +X -> screen southeast
	return Vector2.ZERO

func _update_animation(direction: Vector2, running: bool, delta: float) -> void:
	var moving := direction.length_squared() > 0.01
	if moving:
		if absf(direction.x) > absf(direction.y):
			facing = 3 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y > 0 else 2
	# Original player.c: idle range 0 indexed by facing; walk 1+facing; run 6+facing.
	var selected := (6 if running else 1) + facing if moving else 0
	if selected != animation:
		animation = selected
		animation_frame = 0
		animation_time = 0.0
	var frames: Array = animation_data.animations[animation]
	if moving:
		animation_time += delta
		# anim.c advances one 30 Hz tick per ceil(duration / 2).
		var duration := maxf(ceilf(float(frames[animation_frame].duration) / 2.0), 1.0) / 30.0
		while animation_time >= duration:
			animation_time -= duration
			var control := int(frames[animation_frame].control)
			if control == 0xff:
				animation_time = 0.0
				break
			animation_frame += 1
			if control & 0x80 or animation_frame >= frames.size():
				animation_frame = control & 0x7f
			animation_frame = clampi(animation_frame, 0, frames.size() - 1)
			duration = maxf(ceilf(float(frames[animation_frame].duration) / 2.0), 1.0) / 30.0
	else:
		animation_frame = facing
	sprite.frame = int(frames[animation_frame].tile)

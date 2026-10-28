extends CharacterBody3D
## Player input, ground movement and original ANI playback. No world-loading dependencies.
var facing := 0
var animation := 0
var animation_frame := 0
var animation_time := 0.0
var animation_data: Dictionary
var actions
var input_locked := false
var scripted_direction := Vector2.ZERO
var scripted_walk_time := 0.0
var normal_texture: Texture2D
@onready var sprite: Sprite3D = $Sprite3D
@onready var footprint: CapsuleShape3D = $CollisionShape3D.shape
const WALK_SPEED := 41.0 * 30.0 / 1000.0
const RUN_SPEED := 73.0 * 30.0 / 1000.0
# player.c: GROUND_TOLERANCE_DEFAULT=200; player_slide_on_bump probes 48 units ahead.
const GROUND_PROBE_HEIGHT := 200.0 / 1000.0
const GROUND_PROBE_REACH := 48.0 / 1000.0

func _ready() -> void:
	_setup_input()
	sprite.material_override = sprite.material_override.duplicate()
	animation_data = JSON.parse_string(FileAccess.get_file_as_string("res://game/player/player_animations.json"))
	normal_texture = sprite.texture
	actions = load("res://game/player/player_actions.gd").new()
	add_child(actions)
	actions.setup(self)
	_update_animation(Vector2.ZERO, false, 0.0)

func _physics_process(delta: float) -> void:
	actions.poll_input()
	var direction := Vector2.ZERO if input_locked or actions.busy() else _movement_direction()
	if scripted_walk_time > 0:
		direction = scripted_direction
		scripted_walk_time = maxf(0,scripted_walk_time-delta)
	var running := Input.is_action_pressed("run") and not input_locked
	var speed := RUN_SPEED if running else WALK_SPEED
	velocity.x = direction.x * speed
	velocity.z = direction.y * speed
	velocity.y -= 14 * delta
	_constrain_to_ground(Vector3(velocity.x, 0, velocity.z) * delta)
	move_and_slide()
	# Align the visible feet to the support plane, not the capsule's rounded bottom.
	sprite.position.y = -footprint.radius * (1.0 / get_floor_normal().y - 1.0) if is_on_floor() else 0.0
	if is_on_floor():
		# Smooth collision ramps can sit below the visible road joints or stair treads.
		var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * GROUND_PROBE_HEIGHT, global_position - Vector3.UP * GROUND_PROBE_HEIGHT, 4)
		var surface := get_world_3d().direct_space_state.intersect_ray(query)
		if not surface.is_empty() and surface.normal.y >= cos(floor_max_angle):
			sprite.position.y = surface.position.y - global_position.y
	if actions.busy():
		actions.advance(delta)
	else:
		_update_animation(direction, running, delta)
	actions.update_held(running and not direction.is_zero_approx())

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
		"run": [KEY_SHIFT], "interact": [KEY_E, KEY_ENTER],
		"use_tool": [KEY_SPACE, KEY_X], "next_tool": [KEY_Q], "tool_level": [KEY_R], "refill_can": [KEY_G]
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
	if actions != null and actions.carried_id != 0:
		actions.draw_carry(direction,running,delta)
		return
	if sprite.texture != normal_texture:
		sprite.texture = normal_texture
		sprite.hframes = 8
		sprite.vframes = 12
		sprite.material_override.set_shader_parameter("albedo_texture",normal_texture)
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
	# ANI frame/part offsets are already baked into the common atlas canvas.
	# Keep its pivot fixed: alpha bounds move naturally as the legs and body animate.
	sprite.frame = int(frames[animation_frame].tile)

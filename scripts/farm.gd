extends Node3D
## Native Godot farm. Geometry and texture layouts come from coalslav/hmbtn-decomp.

var camera: Camera3D
var player: CharacterBody3D
var hud: Label
var overview := false
var sprite: Sprite3D
var animation_data: Dictionary
var facing := 0
var animation := 0
var animation_frame := 0
var animation_time := 0.0
# scene_view.c: PS1 eye=(6363,-4500,-6363), H=1000 on a 320x240 frame.
const CAMERA_OFFSET := Vector3(6.363, 4.5, 6.363)
const PROJECTION_DISTANCE := 1000.0
const WALK_SPEED := 41.0 * 30.0 / 1000.0
const RUN_SPEED := 73.0 * 30.0 / 1000.0

func _ready() -> void:
	_setup_input()
	camera = Camera3D.new()
	camera.name = "FarmCamera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.set_perspective(rad_to_deg(2.0 * atan(120.0 / PROJECTION_DISTANCE)), 0.05, 200.0)
	add_child(camera)
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.ZERO)
	_build_player()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(18, 650)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	hud.text = "移植校准版 · ↑东北 ↓西南 ←西北 →东南\nShift 跑步 · Tab 全景 / 原版镜头"
	_update_camera()
	print("FARM_READY: native meshes loaded, no disc reader or PS1 runtime")

func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"run": [KEY_SHIFT]
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)

func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 0)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.18
	capsule.height = 0.85
	shape.shape = capsule
	shape.position.y = 0.425
	player.add_child(shape)
	add_child(player)
	animation_data = JSON.parse_string(FileAccess.get_file_as_string("res://assets/original/player.json"))
	sprite = Sprite3D.new()
	sprite.name = "OriginalPlayerSprite"
	sprite.texture = load("res://assets/original/player.png")
	sprite.hframes = 8
	sprite.vframes = int(sprite.texture.get_height() / 128.0)
	# player_draw projects (x+150,y-100,z-150), then draws ANI pixels at 1:1 size.
	sprite.position = Vector3(0.15, 0.1, 0.15)
	sprite.offset = Vector2(0, 48)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	player.add_child(sprite)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var direction := _movement_direction()
	var running := Input.is_action_pressed("run")
	var speed := RUN_SPEED if running else WALK_SPEED
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.y * speed
	player.velocity.y -= 14 * delta
	player.move_and_slide()
	if player.position.y < -10:
		player.position = Vector3(0, 3, 0)
	_update_animation(direction, running, delta)
	_update_camera()

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

func _update_camera() -> void:
	if not overview:
		var focus := player.position
		camera.position = focus + CAMERA_OFFSET
		camera.look_at(focus)
		# The original character is a screen-space sprite, so its pixel size stays constant.
		sprite.pixel_size = -camera.to_local(sprite.global_position).z / PROJECTION_DISTANCE
	else:
		sprite.pixel_size = CAMERA_OFFSET.length() / PROJECTION_DISTANCE

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

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		overview = not overview
		if overview:
			camera.set_orthogonal(32, 0.05, 200)
			camera.position = Vector3(2, 0, 2) + CAMERA_OFFSET * 2.6
			camera.look_at(Vector3(2, 0, 2))
		else:
			camera.set_perspective(rad_to_deg(2.0 * atan(120.0 / PROJECTION_DISTANCE)), 0.05, 200)
		_update_camera()

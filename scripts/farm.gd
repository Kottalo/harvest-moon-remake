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
const CAMERA_OFFSET := Vector3(6.364, 4.5, -6.364)

func _ready() -> void:
	_setup_input()
	camera = Camera3D.new()
	camera.name = "FarmCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12
	add_child(camera)
	camera.position = CAMERA_OFFSET
	camera.look_at(Vector3.ZERO)
	_build_player()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(24, 20)
	hud.add_theme_font_size_override("font_size", 20)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	hud.text = "HARVEST MOON  /  GODOT REMAKE\n原版农场与主角 · 移植开发中\nWASD / 方向键：移动    Shift：跑步    Tab：全景 / 跟随"
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
	player.position = Vector3(0, 3, 0)
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
	sprite.pixel_size = 0.018
	sprite.position.y = 48 * sprite.pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	player.add_child(sprite)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Match screen directions to the original -512 yaw (scene_view.c).
	var direction := Vector2(input_direction.y - input_direction.x, -input_direction.x - input_direction.y) * 0.70710678
	var running := Input.is_action_pressed("run")
	var speed := 4.8 if running else 2.6
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.y * speed
	player.velocity.y -= 14 * delta
	player.move_and_slide()
	if player.position.y < -10:
		player.position = Vector3(0, 3, 0)
	_update_animation(direction, running, delta)
	if not overview:
		var focus := player.position + Vector3(0, 0.5, 0)
		camera.position = focus + CAMERA_OFFSET
		camera.look_at(focus)

func _update_animation(direction: Vector2, running: bool, delta: float) -> void:
	var moving := direction.length_squared() > 0.01
	if moving:
		if absf(direction.x) > absf(direction.y):
			facing = 3 if direction.x > 0 else 1
		else:
			facing = 0 if direction.y < 0 else 2
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
		camera.size = 32 if overview else 12
		if overview:
			camera.position = Vector3(2, 0, -2) + CAMERA_OFFSET * 2.6
			camera.look_at(Vector3(2, 0, -2))

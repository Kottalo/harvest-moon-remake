extends Node3D
## Owns location loading, original exits and navigation prompts. Player/camera logic is separate.
@onready var player = $Player
@onready var camera = $WorldCamera
var hud: Label
var world: Dictionary
var current_area := 0
var overview := false
var awaiting_interact_release := false
var transitioning := false
var nearby_exit: Dictionary = {}

func _ready() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Label.new()
	hud.position = Vector2(18, 650)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	_refresh_hud()
	_update_camera()
	print("WORLD_READY: ", world.size(), " native locations")

func _physics_process(delta: float) -> void:
	if transitioning:
		return
	if player.position.y < -10:
		var spawn: Array = world[str(current_area)].spawn
		player.position = Vector3(spawn[0], spawn[1] + 0.05, spawn[2])
		player.velocity = Vector3.ZERO
	_check_exits(delta)

func _process(_delta: float) -> void:
	_update_camera()

func _update_camera() -> void:
	camera.follow(player, overview)

func _set_overview() -> void:
	camera.show_overview(get_node("Location"))

func _refresh_hud() -> void:
	hud.text = str(world[str(current_area)].name) + " · ↑东北 ↓西南 ←西北 →东南\nShift 跑步 · E 进出 · Tab 全景"
	if not nearby_exit.is_empty():
		hud.text += "\nE 进入 " + str(world[str(int(nearby_exit.target))].name)

func _check_exits(_delta: float) -> void:
	nearby_exit = {}
	if not Input.is_action_pressed("interact"):
		awaiting_interact_release = false
	var point := Vector2(player.position.x, player.position.z)
	var ahead: Vector2 = point + [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][player.facing] * 0.224
	for exit in world[str(current_area)].exits:
		var bounds := Rect2(Vector2(exit.min[0], exit.min[1]), Vector2(exit.max[0] - exit.min[0], exit.max[1] - exit.min[1]))
		var action: bool = exit.requires_action
		if not bounds.has_point(point) and not (action and bounds.has_point(ahead)):
			continue
		if exit.requires_facing and int(exit.facing) in [0, 1, 2, 3] and int(exit.facing) != player.facing:
			continue
		nearby_exit = exit
		if action and (awaiting_interact_release or not Input.is_action_just_pressed("interact")):
			break
		transitioning = true
		_change_area.call_deferred(int(exit.target), Vector3(exit.entry[0], exit.entry[1], exit.entry[2]))
		break
	_refresh_hud()

func _change_area(area: int, entry: Vector3) -> void:
	if not world.has(str(area)):
		transitioning = false
		push_error("Destination has not been imported: " + str(area))
		return
	var packed: PackedScene = load(world[str(area)].scene)
	if packed == null:
		transitioning = false
		return
	var previous := get_node("Location")
	remove_child(previous)
	previous.free()
	var scene := packed.instantiate()
	scene.name = "Location"
	add_child(scene)
	current_area = area
	player.position = entry + Vector3(0, 0.015, 0)
	player.velocity = Vector3.ZERO
	# Source arrival coordinates already sit outside automatic return zones.
	# Consume a held action button without disabling any destination exits.
	awaiting_interact_release = Input.is_action_pressed("interact")
	transitioning = false
	nearby_exit = {}
	if overview:
		_set_overview()
	_update_camera()
	_refresh_hud()
	print("AREA_READY: ", area, " ", world[str(area)].name)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		overview = not overview
		if overview:
			_set_overview()
		else:
			camera.reset_perspective()
		_update_camera()

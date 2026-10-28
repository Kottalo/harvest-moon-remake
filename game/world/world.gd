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
var doors
var transition_effect
var loose_items
var transition_token := 0
var day_cycle
var hud_elapsed := 0.0
var location_loader

func area_to_world(area: int, point: Vector3) -> Vector3:
	if area == 56:
		return point + Vector3(12.4, 0, 0.8)
	return point

func world_to_area(area: int, point: Vector3) -> Vector3:
	return point - area_to_world(area, Vector3.ZERO)

func _ready() -> void:
	world = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	location_loader = load("res://game/world/location_loader.gd").new()
	location_loader.catalogue = world
	location_loader.warm(0)
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	hud = Label.new()
	# One CJK-capable font avoids a font/texture switch between Chinese and ASCII.
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	hud.add_theme_font_override("font",ui_font)
	hud.position = Vector2(18, 620)
	hud.add_theme_font_size_override("font_size", 16)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x", 2)
	hud.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(hud)
	doors = load("res://game/world/source_doors.gd").new()
	add_child(doors)
	transition_effect = load("res://game/world/location_transition.gd").new()
	add_child(transition_effect)
	loose_items = load("res://game/items/loose_items.gd").new()
	loose_items.name = "LooseItems"
	add_child(loose_items)
	loose_items.setup(self)
	day_cycle = load("res://game/time/day_cycle.gd").new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.setup(self)
	day_cycle.sleep_requested.connect(_sleep_until_morning)
	player.actions.interact_requested.connect(day_cycle.interact)
	_refresh_hud()
	_update_camera()
	print("WORLD_READY: ", world.size(), " native locations")

func _physics_process(delta: float) -> void:
	if transitioning:
		return
	day_cycle.advance(delta,overview)
	if transitioning or day_cycle.menu_open:
		return
	if player.position.y < -10:
		var spawn: Array = world[str(current_area)].spawn
		player.position = area_to_world(current_area, Vector3(spawn[0], spawn[1] + 0.05, spawn[2]))
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
	if player.actions.busy():
		return
	_check_exits(delta)

func _process(delta: float) -> void:
	location_loader.poll()
	_update_camera(true)
	hud_elapsed += delta
	if hud_elapsed >= 0.1:
		hud_elapsed = 0
		_refresh_hud()

func _update_camera(interpolate := false) -> void:
	camera.follow(player, overview, interpolate)

func _set_overview() -> void:
	camera.show_overview(get_node("Location"))

func _refresh_hud() -> void:
	hud.text = str(world[str(current_area)].name) + " · ↑东北 ↓西南 ←西北 →东南\nShift 跑步 · E 交互 · Space/X 工具 · Q 换工具 · R 等级 · Tab 全景"
	hud.text += "\n" + player.actions.tool_name()
	if player.actions.state == "charge":
		hud.text += " · 蓄力 " + str(mini(int(player.actions.charge_ticks/20),player.actions.upgrade))
	if player.actions.carried_id != 0:
		hud.text += " · E / Space 放下或丢弃 · Shift+Space 投掷"
	if not nearby_exit.is_empty():
		hud.text += "\nE 进入 " + str(world[str(int(nearby_exit.target))].name)
	elif day_cycle != null and day_cycle.nearby_bed():
		hud.text += "\nE 床边休息"

func _check_exits(_delta: float) -> void:
	nearby_exit = {}
	if current_area in [52, 56]:
		# The two coast segments stay loaded. Crossing only changes the region label.
		current_area = 52 if player.position.x < 5.0 else 56
	if not Input.is_action_pressed("interact"):
		awaiting_interact_release = false
	var local := world_to_area(current_area, player.position)
	var point := Vector2(local.x, local.z)
	var ahead: Vector2 = point + [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][player.facing] * 0.224
	for exit in world[str(current_area)].exits:
		if current_area in [52, 56] and int(exit.target) in [52, 56]:
			continue
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
		_begin_transition.call_deferred(exit.duplicate(true))
		break

func _begin_transition(exit: Dictionary) -> void:
	var token := transition_token
	var origin := current_area
	player.input_locked = true
	if exit.has("door"):
		var panel = doors.open(get_node("Location"),exit.door,player.facing)
		player.scripted_direction = Vector2(player.actions.DIRECTIONS[player.facing].x,player.actions.DIRECTIONS[player.facing].z)
		player.scripted_walk_time = 10.0/30.0
		while is_instance_valid(panel) and not doors.is_open(panel):
			await get_tree().physics_frame
			if token != transition_token:
				return
	player.scripted_walk_time = 0
	transition_effect.start_out()
	while transition_effect.phase != "black":
		await get_tree().process_frame
		if token != transition_token:
			return
	_change_area(int(exit.target),Vector3(exit.entry[0],exit.entry[1],exit.entry[2]),true)
	for reverse in world[str(current_area)].exits:
		if int(reverse.target) == origin and reverse.has("door"):
			doors.open(get_node("Location"),reverse.door,int(reverse.facing),true)
			break
	transition_effect.start_in()
	while transition_effect.phase != "idle":
		await get_tree().process_frame
		if token != transition_token:
			return
	player.input_locked = false
	transitioning = false

func _change_area(area: int, entry: Vector3, during_transition := false) -> void:
	if not during_transition:
		transition_token += 1
		player.input_locked = false
		player.scripted_walk_time = 0
		transition_effect.reset()
	if not world.has(str(area)):
		transitioning = false
		push_error("Destination has not been imported: " + str(area))
		return
	var packed: PackedScene = location_loader.get_scene(area)
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
	location_loader.warm(area)
	player.position = area_to_world(area, entry) + Vector3(0, 0.015, 0)
	player.velocity = Vector3.ZERO
	player.actions.cinematic = false
	player.reset_physics_interpolation()
	# Source arrival coordinates already sit outside automatic return zones.
	# Consume a held action button without disabling any destination exits.
	awaiting_interact_release = Input.is_action_pressed("interact")
	transitioning = during_transition
	nearby_exit = {}
	loose_items.set_area(area)
	day_cycle.refresh()
	if overview:
		_set_overview()
	_update_camera()
	_refresh_hud()
	print("AREA_READY: ", area, " ", world[str(area)].name)

func _unhandled_key_input(event: InputEvent) -> void:
	if day_cycle.menu_open or day_cycle.sleeping:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		overview = not overview
		if overview:
			_set_overview()
		else:
			camera.reset_perspective()
		_update_camera()

func _sleep_until_morning(automatic: bool) -> void:
	if transitioning:
		return
	transitioning = true
	player.input_locked = true
	player.scripted_walk_time = 0
	var token := transition_token
	if not automatic:
		var bed: Array = day_cycle.catalogue.bed_position
		await player.actions.go_to_bed(Vector3(bed[0],bed[1],bed[2]))
		if token != transition_token:
			day_cycle.sleeping = false
			return
	transition_effect.start_out()
	while transition_effect.phase != "black":
		await get_tree().process_frame
		if token != transition_token:
			day_cycle.sleeping = false
			return
	day_cycle.wake_next_morning(automatic)
	player.actions.state = ""
	player.actions.range_id = -1
	player.animation = -1
	var wake: Array = day_cycle.catalogue.wake_position
	_change_area(int(day_cycle.catalogue.wake_area),Vector3(wake[0],wake[1],wake[2]),true)
	player.facing = 0
	player._update_animation(Vector2.ZERO,false,0)
	transition_effect.start_in()
	while transition_effect.phase != "idle":
		await get_tree().process_frame
		if token != transition_token:
			day_cycle.sleeping = false
			return
	day_cycle.sleeping = false
	player.input_locked = false
	transitioning = false

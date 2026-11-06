extends Node3D
## Owns location loading, original exits and navigation prompts. Player/camera logic is separate.
const DoorAccess := preload("res://game/world/door_access.gd")
const WorldHistory := preload("res://game/world/world_history.gd")
@onready var player = $Player
@onready var camera = $WorldCamera
var hud: Label
var world: Dictionary
var object_notices: Dictionary
var current_area := 0
var overview := false
var awaiting_interact_release := false
var transitioning := false
var sound
var nearby_exit: Dictionary = {}
var nearby_exit_locked := false
var doors
var transition_effect
var loose_items
var transition_token := 0
var day_cycle
var hud_elapsed := 0.0
var location_loader
var farm_field
var mine_field
var economy
var tool_picker
var rucksack_menu
var npcs
var history := WorldHistory.new()

func record_history(kind: String, actor: String, content: String, witnesses: PackedStringArray) -> int:
	var minute: int = day_cycle.minute
	var date := "第%d年%s季第%d天 %02d:%02d" % [
		day_cycle.year+1,["春","夏","秋","冬"][day_cycle.season],day_cycle.day+1,minute/60,minute%60]
	return history.record(kind,actor,content,witnesses,world[str(current_area)].name,date)

func record_player_action(content: String) -> void:
	record_history("action","player",content,npcs.people_near(player) if npcs != null else [])

func area_to_world(area: int, point: Vector3) -> Vector3:
	if area == 56:
		return point + Vector3(12.4, 0, 0.8)
	return point

func world_to_area(area: int, point: Vector3) -> Vector3:
	return point - area_to_world(area, Vector3.ZERO)

func area_at(point: Vector3) -> int:
	# The two coast segments stay loaded and share a world-space boundary.
	if current_area in [52,56]:
		return 52 if point.x < 5.0 else 56
	return current_area

func _enter_tree() -> void:
	print("BOOT_STAGE: world entered")

func _ready() -> void:
	print("BOOT_STAGE: world setup")
	var refresh_rate := DisplayServer.screen_get_refresh_rate()
	if Engine.max_fps > 0 and refresh_rate > 0.0 and refresh_rate <= Engine.max_fps + 0.5 \
			and DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED:
		# VSync already meets the cap on this display. Avoid a second sleep timer.
		Engine.max_fps = 0
	if Engine.is_embedded_in_editor():
		# The editor and preview share one GPU. Keep the standalone render scale.
		get_viewport().scaling_3d_scale = minf(get_viewport().scaling_3d_scale,0.70)
	var location := get_node("Location") as Node3D
	current_area = int(location.get_meta("area_id"))
	_wireframe_colliders(location)
	world = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/location_catalog.json"))
	object_notices = JSON.parse_string(FileAccess.get_file_as_string("res://game/world/object_notices.json"))
	location_loader = load("res://game/world/location_loader.gd").new()
	location_loader.catalogue = world
	location_loader.warm(current_area)
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
	doors.prepare(location,world[str(current_area)].exits)
	transition_effect = load("res://game/world/location_transition.gd").new()
	add_child(transition_effect)
	sound = preload("res://game/audio/sound_effects.gd").new()
	sound.name = "SoundEffects"
	add_child(sound)
	player.actions.sound_requested.connect(sound.cue)
	loose_items = load("res://game/items/loose_items.gd").new()
	loose_items.name = "LooseItems"
	add_child(loose_items)
	loose_items.action_committed.connect(record_player_action)
	loose_items.setup(self)
	print("BOOT_STAGE: items ready")
	day_cycle = load("res://game/time/day_cycle.gd").new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.setup(self)
	_place_player(current_area,_wake_entry())
	loose_items.clock = day_cycle
	day_cycle.sleep_requested.connect(_sleep_until_morning)
	farm_field = load("res://game/field/farm_field.gd").new()
	farm_field.name = "FarmField"
	add_child(farm_field)
	farm_field.setup(self)
	mine_field = load("res://game/field/mine_field.gd").new()
	mine_field.name = "MineField"
	add_child(mine_field)
	mine_field.setup(self)
	economy = preload("res://game/economy/farm_economy.gd").new()
	add_child(economy)
	economy.setup(self)
	tool_picker = preload("res://game/player/tool_picker.gd").new()
	add_child(tool_picker)
	tool_picker.setup(player.actions,ui_font,economy.count,hud,day_cycle.clock_label,economy.rucksack,sound.cue)
	rucksack_menu = preload("res://game/items/rucksack_menu.gd").new()
	add_child(rucksack_menu)
	rucksack_menu.setup(economy,ui_font)
	_refresh_hud()
	_configure_camera_limits()
	_update_camera()
	npcs = preload("res://game/npc/npc_schedule.gd").new()
	npcs.name = "NpcSchedule"
	add_child(npcs)
	npcs.world = self
	npcs.dialogue = preload("res://game/npc/dialogue/npc_dialogue.gd").new()
	npcs.add_child(npcs.dialogue)
	npcs.dialogue.setup(self,ui_font)
	economy.dialogue = npcs.dialogue
	npcs.enter_location(location)
	player.actions.interact_requested.connect(_interact)
	if OS.is_debug_build():
		var debug_scenes = load("res://game/debug/test_scene_menu.gd").new()
		debug_scenes.setup(self,ui_font)
		add_child(debug_scenes)
	print("WORLD_READY: ", world.size(), " native locations")

func _wireframe_colliders(location: Node3D) -> void:
	if OS.is_debug_build() and get_tree().debug_collisions_hint:
		# Floor, walkability and visual-reference meshes overlap. Keep every
		# native edge visible without blending their triangle fills over the map.
		for collision: CollisionShape3D in location.find_children("*","CollisionShape3D",true,false):
			collision.debug_fill = false

func _physics_process(delta: float) -> void:
	if transitioning:
		return
	day_cycle.advance(delta,overview)
	npcs.update(delta)
	if transitioning or day_cycle.menu_open:
		return
	if player.position.y < -10:
		var spawn: Array = world[str(current_area)].spawn
		player.position = area_to_world(current_area, Vector3(spawn[0], spawn[1] + 0.05, spawn[2]))
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		_update_camera()
	if player.actions.busy():
		return
	_check_exits(delta)

func _process(delta: float) -> void:
	# Finish the small action warmup before starting the neighbouring map queue.
	if player.actions.poll_hop_atlases():
		location_loader.poll()
	_update_camera(true,delta)
	hud_elapsed += delta
	if hud_elapsed >= 0.1:
		hud_elapsed = 0
		_refresh_hud()

func _configure_camera_limits() -> void:
	var flags: int = day_cycle.catalogue.areas[str(current_area)].source_flags
	camera.set_location(get_node("Location"),flags&0x1800==0,current_area)

func _update_camera(interpolate := false, delta := 0.0) -> void:
	camera.follow(player, overview, interpolate, delta)

func _set_overview() -> void:
	camera.show_overview(get_node("Location"))

func _refresh_hud() -> void:
	var text := str(world[str(current_area)].name)
	text += "\n%d G · " % economy.gold + player.actions.tool_name()
	if player.actions.equipped == 21:
		text += " · 水量 %d" % farm_field.crops.water_remaining
	if not farm_field.crops.message.is_empty():
		text += " · " + farm_field.crops.message
	if player.actions.state == "charge":
		text += " · 蓄力 " + str(mini(int(player.actions.charge_ticks/20),player.actions.upgrade))
	if not nearby_exit.is_empty():
		var destination: String = world[str(int(nearby_exit.target))].name
		text += "\nZ 查看 " + destination + " · 门锁着" if nearby_exit_locked else "\nZ 进入 " + destination
	elif mine_field.ladder_near():
		text += "\nZ 下到矿洞第 %d 层" % (mine_field.depth+2)
	elif economy.shipping_near():
		text += "\nZ 出货"
	elif _toolbox_ahead():
		text += "\nZ 打开工具箱"
	elif day_cycle != null and day_cycle.nearby_bed():
		text += "\nZ 床边休息"
	elif npcs != null:
		var notice := _notice_ahead()
		var prompt: String = economy.livestock.prompt()
		if prompt.is_empty():
			prompt = "Z 查看 " + notice[0] if not notice.is_empty() else npcs.prompt()
		if not prompt.is_empty():
			text += "\n" + prompt
	if not economy.message.is_empty():
		text += "\n"+economy.message
	if hud.text != text:
		hud.text = text

func _notice_ahead() -> Array:
	if player.actions.carried_id != 0:
		return []
	var zone := _front_zone(object_notices.zones)
	return [] if zone.is_empty() else object_notices.messages[str(int(zone[0]))]

func _toolbox_ahead() -> bool:
	return player.actions.can_select_tool() and not _front_zone(object_notices.toolboxes).is_empty()

func _front_zone(zones: Dictionary) -> Array:
	var rows: Array = zones.get(str(current_area),[])
	if rows.is_empty():
		return []
	var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
	var probe := world_to_area(current_area,player.global_position)+direction*0.224
	for zone: Array in rows:
		if int(zone[1])!=5 and int(zone[1])!=player.facing:
			continue
		# farm_zone_at_probe uses strict horizontal bounds and vertical slack.
		if zone[2]<probe.x and probe.x<zone[5] and zone[3]-0.120<probe.y and probe.y<zone[6]+0.128 and zone[4]<probe.z and probe.z<zone[7]:
			return zone
	return []

func _interact() -> void:
	if transitioning or awaiting_interact_release or npcs.dialogue.overlay.visible:
		return
	if nearby_exit.is_empty():
		if _toolbox_ahead():
			# The imported FarmZoneModel carries SCENE_ENTRY_PAN on the toolbox lid.
			for model in get_node("Location").get_children():
				if int(model.get_meta("source_flags",0)) & 0x40:
					tool_picker.open(model)
					return
			tool_picker.open()
			return
		if mine_field.descend():
			return
		if economy.shipping_near():
			economy.show_shipping()
			return
		if economy.livestock.interact() or economy.supermarket.interact():
			return
	loose_items.interact()
	if player.actions.carried_id != 0:
		return
	day_cycle.interact()
	farm_field.crops.pick_crop()
	npcs.greet()

func _check_exits(_delta: float) -> void:
	nearby_exit = {}
	nearby_exit_locked = false
	current_area = area_at(player.global_position)
	if not Input.is_action_pressed("interact"):
		awaiting_interact_release = false
	var pressed := not awaiting_interact_release and Input.is_action_just_pressed("interact")
	var local := world_to_area(current_area, player.position)
	var point := Vector2(local.x, local.z)
	var ahead: Vector2 = point + [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)][player.facing] * 0.224
	for exit in world[str(current_area)].exits:
		if current_area in [52, 56] and int(exit.target) in [52, 56]:
			continue
		var bounds := Rect2(Vector2(exit.min[0], exit.min[1]), Vector2(exit.max[0] - exit.min[0], exit.max[1] - exit.min[1]))
		var action: bool = exit.requires_action
		# farm_zone_find tests the player's actual foot position, strictly inside
		# the door zone. A forward interaction probe opened doors too early.
		var inside := bounds.has_point(point)
		if exit.has("door"):
			inside = point.x>bounds.position.x and point.x<bounds.end.x and point.y>bounds.position.y and point.y<bounds.end.y
			if not inside:
				inside = doors.at_threshold(get_node("Location"),int(exit.index),point,player)
			if not inside:
				# A native capsule can stop a few centimetres before a narrow indoor
				# door zone that the original 48-unit point probe could enter.
				# Check both capsule and walkability blocking, even when standing still.
				# Never replace this with the old .224 interaction reach.
				var facing: Vector3 = player.actions.DIRECTIONS[player.facing]
				var shape: CollisionShape3D = player.get_node("CollisionShape3D")
				var reach := maxf(player.footprint.radius-player.GROUND_PROBE_REACH+shape.position.dot(facing),0)
				var foot := point+Vector2(facing.x,facing.z)*reach
				inside = foot.x>bounds.position.x and foot.x<bounds.end.x and foot.y>bounds.position.y and foot.y<bounds.end.y and (not player.has_walkable_ground(facing*player.RUN_SPEED/Engine.physics_ticks_per_second) or player.test_move(player.global_transform,facing*0.005))
		elif action:
			inside = inside or bounds.has_point(ahead)
		if not inside: continue
		if exit.requires_facing and int(exit.facing) in [0, 1, 2, 3] and int(exit.facing) != player.facing:
			continue
		nearby_exit = exit
		var refusal := DoorAccess.refusal(int(exit.event),day_cycle.minute,day_cycle.season,
			day_cycle.day,day_cycle.weekday,npcs.scheduled_areas)
		nearby_exit_locked = not refusal.is_empty()
		if nearby_exit_locked:
			if pressed:
				npcs.dialogue.show_notice(world[str(int(exit.target))].name,refusal)
			break
		if action and not pressed:
			break
		transitioning = true
		_begin_transition.call_deferred(exit.duplicate(true))
		break
	if pressed and nearby_exit.is_empty() and not day_cycle.nearby_bed():
		var notice := _notice_ahead()
		if not notice.is_empty():
			npcs.dialogue.show_notice(notice[0],notice[1])

func _begin_transition(exit: Dictionary) -> void:
	var token := transition_token
	var origin := current_area
	player.input_locked = true
	if exit.has("door"):
		doors.open(get_node("Location"),exit.door,player.facing)
		sound.cue("door")
		player.set_door_passage(true)
		var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
		# player_walk_start -> facing_buttons -> player_dpad_facing reverses facing:
		# first turn away/back out for 10, then turn back/enter for 20.
		# The source checks countdown==0 after moving, so each stage includes tick 0.
		for ticks in [10,20]:
			var motion: Vector3 = -direction if ticks==10 else direction
			player.scripted_direction = Vector2(motion.x,motion.z)
			player.scripted_walk_time = (ticks+1)/30.0
			while player.scripted_walk_time>0:
				await get_tree().physics_frame
				if token != transition_token:
					return
	player.scripted_walk_time = 0
	transition_effect.start_out()
	while transition_effect.phase != "black":
		await get_tree().process_frame
		if token != transition_token:
			return
	record_player_action("前往%s" % world[str(int(exit.target))].name)
	_change_area(int(exit.target),Vector3(exit.entry[0],exit.entry[1],exit.entry[2]),true)
	var arrival_panel: Node3D
	for reverse in world[str(current_area)].exits:
		if int(reverse.target) == origin and reverse.has("door"):
			arrival_panel = doors.open(get_node("Location"),reverse.door,int(reverse.facing),true)
			if arrival_panel != null:
				var outward: Vector3 = -player.actions.DIRECTIONS[int(reverse.facing)]
				doors.guard_arrival(arrival_panel,player,outward)
				if not doors.arrival_clear(arrival_panel):
					player.facing = posmod(int(reverse.facing)+2,4)
					player.scripted_direction = Vector2(outward.x,outward.z)
					player.scripted_walk_time = 21/30.0
			break
	transition_effect.start_in()
	while transition_effect.phase != "idle" or player.scripted_walk_time>0:
		await get_tree().physics_frame
		if token != transition_token:
			return
		if arrival_panel != null and doors.arrival_clear(arrival_panel):
			player.scripted_walk_time = 0
	player.input_locked = false
	transitioning = false

func _change_area(area: int, entry: Vector3, during_transition := false) -> void:
	player.set_door_passage(false)
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
	player.hop.cancel()
	var previous := get_node("Location")
	remove_child(previous)
	previous.free()
	var scene := packed.instantiate()
	doors.prepare(scene,world[str(area)].exits)
	_wireframe_colliders(scene)
	scene.name = "Location"
	add_child(scene)
	current_area = area
	location_loader.warm(area)
	player.actions.cinematic = false
	_place_player(area,entry)
	# Source arrival coordinates already sit outside automatic return zones.
	# Consume a held action button without disabling any destination exits.
	awaiting_interact_release = Input.is_action_pressed("interact")
	transitioning = during_transition
	nearby_exit = {}
	nearby_exit_locked = false
	loose_items.set_area(area)
	farm_field.bind_location()
	mine_field.bind_location()
	economy.livestock.bind_location()
	economy.supermarket.bind_location()
	economy.message = ""
	day_cycle.refresh()
	_configure_camera_limits()
	if overview:
		_set_overview()
	_update_camera()
	npcs.enter_location(scene)
	_refresh_hud()
	print("AREA_READY: ", area, " ", world[str(area)].name)

func _place_player(area: int, entry: Vector3) -> void:
	player.position = area_to_world(area,entry)+Vector3.UP*0.015
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()

func _wake_entry() -> Vector3:
	var wake: Array = day_cycle.catalogue.wake_position
	return Vector3(wake[0],wake[1],wake[2])

func _unhandled_key_input(event: InputEvent) -> void:
	if transitioning or day_cycle.menu_open or day_cycle.sleeping:
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.is_action_pressed("backpack"):
		rucksack_menu.open()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_I:
		tool_picker.open()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		overview = not overview
		if overview:
			_set_overview()
		else:
			camera.reset_gameplay()
		_update_camera()

func _sleep_until_morning(automatic: bool) -> void:
	if transitioning:
		return
	var actions = player.actions
	if automatic and actions.state == "pickup":
		actions._finish()
	transitioning = true
	player.input_locked = true
	player.scripted_walk_time = 0
	var token := transition_token
	if not automatic:
		var bed: Array = day_cycle.catalogue.bed_position
		var blanket := get_node_or_null("Location/ZoneModel_01/Geometry") as MeshInstance3D
		await player.actions.go_to_bed(Vector3(bed[0],bed[1],bed[2]),blanket)
		if token != transition_token:
			day_cycle.sleeping = false
			return
	transition_effect.start_sleep_out(45 if automatic else 30)

	while transition_effect.phase != "black":
		await get_tree().process_frame
		if token != transition_token:
			day_cycle.sleeping = false
			return
	day_cycle.wake_next_morning(automatic)
	player.actions.state = ""
	player.actions.range_id = -1
	player.animation = -1
	_change_area(int(day_cycle.catalogue.wake_area),_wake_entry(),true)
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

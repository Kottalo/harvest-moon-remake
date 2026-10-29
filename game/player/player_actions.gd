extends Node
## Original ANI action ranges and 30 Hz timing; movement remains in player.gd.
signal interact_requested
signal item_released(item: int, thrown: bool)
signal tool_used(tool: int, charge: int)
var player
var data: Dictionary
var items: Dictionary
var textures := {}
var frame_textures := {}
var state := ""
var bank := ""
var range_id := -1
var frame := 0
var elapsed := 0.0
var charge_ticks := 0.0
var equipped := 6
var upgrade := 0
var carried_id := 0
var pending_item := 0
var held_sprite: Sprite3D
var cinematic := false
var bed_ground_y := 0.0
const TOOL_IDS := [1,6,11,16,21,26,27,28,29,56,57,30,31,32,34]
const TOOL_NAMES := ["镰刀","锄头","斧头","锤子","水壶","挤奶器","剪毛器","刷子","铃铛","钓竿","高级钓竿","动物药","牛孕药","羊孕药","种子"]
const LEVEL_NAMES := ["普通","铜","银","金","秘银"]
const DIRECTIONS := [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)]

func setup(body) -> void:
	player = body
	data = JSON.parse_string(FileAccess.get_file_as_string("res://game/player/actions/action_catalog.json"))
	items = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json")).pictures
	held_sprite = Sprite3D.new()
	held_sprite.name = "CarriedItem"
	held_sprite.pixel_size = player.sprite.pixel_size
	held_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	held_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	held_sprite.material_override = player.sprite.material_override.duplicate()
	held_sprite.visible = false
	player.add_child(held_sprite)

func busy() -> bool:
	return not state.is_empty()

func tool_name() -> String:
	var index := TOOL_IDS.find(equipped)
	return TOOL_NAMES[index] + (" · " + LEVEL_NAMES[upgrade] if equipped <= 25 else "")

func poll_input() -> void:
	if player.input_locked:
		return
	if busy():
		if state == "charge" and not Input.is_action_pressed("use_tool"):
			release_tool()
		elif state == "fishing_wait" and not Input.is_action_pressed("use_tool"):
			play("fishing", player.facing + 4, "reel")
		return
	if Input.is_action_just_pressed("next_tool") and carried_id == 0:
		equipped = TOOL_IDS[(TOOL_IDS.find(equipped) + 1) % TOOL_IDS.size()]
		# player_check_tool_slots: show animation 0x47 for ten source ticks.
		play("base",71,"show_tool",player.facing)
		return
	if Input.is_action_just_pressed("tool_level") and equipped <= 25:
		upgrade = (upgrade + 1) % 5
	if Input.is_action_just_pressed("use_tool"):
		if carried_id != 0:
			if Input.is_action_pressed("run"):
				start_drop(true)
			else:
				interact_requested.emit()
		else:
			start_tool()
	elif Input.is_action_just_pressed("interact"):
		interact_requested.emit()
	elif Input.is_action_just_pressed("refill_can") and equipped == 21 and carried_id == 0:
		play("refill", player.facing * 5 + upgrade, "refill")

func play(source: String, animation: int, action: String, start := 0) -> void:
	bank = source
	range_id = animation
	frame = start
	elapsed = 0
	state = action
	_draw()

func start_tool() -> bool:
	if busy() or carried_id != 0 or player.input_locked:
		return false
	if equipped <= 25:
		charge_ticks = 1
		play("base", 72 + ((equipped-1)/5 as int)*20 + player.facing*5 + upgrade, "charge")
	elif equipped in [56,57]:
		play("fishing", player.facing, "cast")
	elif equipped in [26,27,28,29]:
		play(["milker","clippers","brush","bell"][equipped-26], player.facing, "animal_tool")
	elif equipped == 30:
		play("medicine",player.facing,"animal_tool")
	elif equipped in [31,32]:
		play("potion",player.facing,"animal_tool")
	else:
		play("seeds",1,"seed") # ItemInfo[ITEM_TURNIP_SEEDS].plantAnimation
	return true

func release_tool() -> void:
	if state != "charge":
		return
	var level := mini(int(charge_ticks / 20),upgrade)
	play("tool_%d" % upgrade,72 + ((equipped-1)/5 as int)*20 + player.facing*5 + level,"swing",level+1)

func start_pickup(item: int) -> bool:
	if busy() or carried_id != 0 or player.input_locked or not items.has(str(item)):
		return false
	pending_item = item
	play("base",11+player.facing,"pickup")
	return true

func start_drop(thrown := false) -> bool:
	if busy() or carried_id == 0 or player.input_locked:
		return false
	play("base",23+player.facing,"throw" if thrown else "drop")
	return true

func go_to_bed(target: Vector3) -> void:
	# player_start_result_scene / player_result_camera_step (house level 0).
	cinematic = true
	bed_ground_y = player.position.y
	player.facing = 0
	player.velocity = Vector3.ZERO
	player.sprite.position.y = 0
	play("sleep",0,"bedtime")
	while busy():
		await get_tree().physics_frame
		if not cinematic: return
	play("sleep",1,"bed_pose")
	var begin: Vector3 = player.position
	target.y = begin.y+0.04
	var height := begin.y
	# Eighteen source ticks at 30 Hz, independent of the native physics rate.
	for tick in 18:
		var remaining := 1.0/30.0
		while remaining>0.000001:
			await get_tree().physics_frame
			if not cinematic: return
			remaining -= get_physics_process_delta_time()
		var offset := (absi(tick-8)*111/8 as int)/1000.0
		height = maxf(height+(offset if tick<9 else -offset),begin.y+0.04)
		player.position = begin.lerp(target,tick/17.0)
		player.position.y = height
	play("sleep",2,"bed_pose")
	var wait := 0.0
	while wait<0.5:
		await get_tree().physics_frame
		if not cinematic: return
		wait += get_physics_process_delta_time()
	play("sleep",3,"bedtime")
	while busy():
		await get_tree().physics_frame
		if not cinematic: return

func advance(delta: float) -> void:
	if state == "show_tool":
		elapsed += delta
		if elapsed+0.0000001 >= 10.0/30.0: _finish()
		return
	if state == "bed_hold":
		_draw()
		return
	if state == "charge":
		charge_ticks += delta*30.0
		frame = mini(int(charge_ticks/20),upgrade)
		if charge_ticks >= upgrade*20 + 61:
			play("overcharge",0,"overcharge")
		_draw()
		return
	if state == "fishing_wait":
		_draw()
		return
	elapsed += delta
	var frames: Array = data.banks[bank].ranges[str(range_id)]
	while elapsed + 0.0000001 >= maxf(ceilf(float(frames[frame].duration)/2.0),1)/30.0:
		elapsed -= maxf(ceilf(float(frames[frame].duration)/2.0),1)/30.0
		var control := int(frames[frame].control)
		if control == 255:
			_finish()
			return
		if control & 128:
			frame = control & 127
		elif frame + 1 < frames.size():
			frame += 1
		else:
			_finish()
			return
	_draw()

func _finish() -> void:
	var finished := state
	if finished == "bed_pose":
		state = "bed_hold"
		return
	if finished == "cast":
		play("fishing",8,"fishing_wait",player.facing)
		return
	if finished == "pickup":
		carried_id = pending_item
		pending_item = 0
	if finished in ["drop","throw"]:
		var item := carried_id
		carried_id = 0
		item_released.emit(item,finished=="throw")
	if finished in ["swing","animal_tool","reel","refill","seed"]:
		tool_used.emit(equipped+upgrade if equipped<=25 else equipped,mini(int(charge_ticks/20),upgrade))
	state = ""
	range_id = -1
	player.animation = -1

func draw_carry(direction: Vector2, running: bool, delta: float) -> void:
	var selected: int = (19 if running else 15) + player.facing if not direction.is_zero_approx() else 27
	if range_id != selected or bank != "base":
		play("base",selected,"",player.facing if selected==27 else 0)
	if selected != 27:
		advance(delta)
	else:
		frame = player.facing
	_draw()

func update_held(running: bool) -> void:
	var showing := state == "show_tool"
	var item := (equipped+upgrade if equipped<=25 else equipped) if showing else (pending_item if pending_item != 0 else carried_id)
	held_sprite.visible = item != 0
	if item == 0:
		return
	held_sprite.texture = _texture(data.tool_pictures[str(item)] if showing else items[str(item)].texture)
	held_sprite.material_override.set_shader_parameter("albedo_texture",held_sprite.texture)
	var group := 0 if showing or pending_item != 0 or state in ["drop","throw"] else (2 if running else 1)
	var offset: Array = data.item_offsets[0 if showing else group*4+player.facing]
	held_sprite.offset = Vector2(offset[0],player.sprite.offset.y-offset[1])
	held_sprite.position = player.sprite.position
	# PS1 addPrim prepends: item submitted before body is drawn AFTER it.
	# Carry poses put the object in front; pickup/release use the facing order.
	var carrying: bool = carried_id != 0 and state not in ["drop","throw"]
	var behind: bool = not (showing or carrying or player.facing in [0,3])
	held_sprite.material_override.set_shader_parameter("sort_bias",0.005 if behind else -0.005)

func _texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load(path)
	return textures[path]

func _draw() -> void:
	var source: Dictionary = data.banks[bank]
	var pose: Dictionary = source.ranges[str(range_id)][frame]
	var key: String = source.pages[pose.page]+str(pose.rect)
	if not frame_textures.has(key):
		var texture := AtlasTexture.new()
		texture.atlas = _texture(source.pages[pose.page])
		texture.region = Rect2(pose.rect[0],pose.rect[1],pose.rect[2],pose.rect[3])
		# Restore the entire 256-pixel source canvas. This is never a foot/pivot adjustment.
		texture.margin = Rect2(pose.margin[0],pose.margin[1],pose.margin[2],pose.margin[3])
		frame_textures[key] = texture
	var texture: AtlasTexture = frame_textures[key]
	if player.sprite.texture != texture:
		player.sprite.texture = texture
		player.sprite.material_override.set_shader_parameter("albedo_texture",texture)
		player.sprite.hframes = 1
		player.sprite.vframes = 1
		player.sprite.frame = 0

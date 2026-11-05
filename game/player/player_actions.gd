extends Node
## Original ANI action ranges and 30 Hz timing; movement remains in player.gd.
signal interact_requested
signal item_released(item: int, thrown: bool)
signal tool_used(tool: int, charge: int)
signal equipment_selected(tool: int)
signal sound_requested(cue: String)

var player
var data: Dictionary
var items: Dictionary
var textures := {}
var frame_textures := {}
var hop_atlas_paths: Array[String] = []
var hop_atlas_request := ""
var state := ""
var bank := ""
var range_id := -1
var frame := 0
var elapsed := 0.0
var charge_ticks := 0.0
var equipped := 6
var service_tool := 0
var equipment_available: Callable
var quick_switch: Callable
var item_art
var item_images := {}
var upgrade := 0
var selected_seed := 34
var _sow_after_show := false
var seed_catalogue := {}
var crop_produce := {}
var crop_picture_provider: Callable
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
	var source: Dictionary = data.banks.base
	for animation in ["10","28"]:
		for pose: Dictionary in source.ranges[animation]:
			var path: String = source.pages[pose.page]
			if not hop_atlas_paths.has(path):
				hop_atlas_paths.append(path)
	held_sprite = Sprite3D.new()
	held_sprite.name = "CarriedItem"
	held_sprite.pixel_size = player.sprite.pixel_size
	held_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	held_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	held_sprite.material_override = player.sprite.material_override.duplicate()
	held_sprite.visible = false
	player.add_child(held_sprite)

func poll_hop_atlases() -> bool:
	# The first hop otherwise loads the full base action atlas during _draw().
	if not hop_atlas_request.is_empty():
		var status := ResourceLoader.load_threaded_get_status(hop_atlas_request)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return false
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			textures[hop_atlas_request] = ResourceLoader.load_threaded_get(hop_atlas_request)
		hop_atlas_request = ""
	while not hop_atlas_paths.is_empty():
		var path: String = hop_atlas_paths.pop_front()
		if not textures.has(path) and ResourceLoader.load_threaded_request(path,"Texture2D") == OK:
			hop_atlas_request = path
			return false
	return true

func busy() -> bool:
	return not state.is_empty()

func tool_name() -> String:
	if equipped==0:
		return "空手"
	if equipped == 34 and seed_catalogue.has(str(selected_seed)):
		return seed_catalogue[str(selected_seed)].name + "种子"
	var index := TOOL_IDS.find(equipped)
	return TOOL_NAMES[index] + (" · " + LEVEL_NAMES[upgrade] if equipped <= 25 else "")

func can_select_tool() -> bool:
	return not player.input_locked and not busy() and carried_id == 0

func owns_tool(tool: int) -> bool:
	return tool!=service_tool and (not equipment_available.is_valid() or equipment_available.call(tool))

func select_tool(tool: int, seed := -1) -> bool:
	if not can_select_tool() or not TOOL_IDS.has(tool) or not owns_tool(tool):
		return false
	if seed != -1:
		if tool != 34 or not seed_catalogue.has(str(seed)):
			return false
	set_bag_tool(seed if seed!=-1 else (selected_seed if tool==34 else tool))
	# player_check_tool_slots: show animation 0x47 for ten source ticks.
	play("base",71,"show_tool",player.facing)
	return true

func set_bag_tool(item: int) -> void:
	if seed_catalogue.has(str(item)):
		selected_seed = item
		equipped = 34
	else:
		equipped = item
	equipment_selected.emit(equipped)

func tool_picture(tool: int, seed := -1, level := -1) -> Texture2D:
	if tool == 34 and seed != 34 and seed_catalogue.has(str(seed)):
		return crop_picture_provider.call(seed_catalogue[str(seed)].icon)
	var item := tool + (upgrade if level<0 else level) if tool <= 25 else tool
	return _texture(data.tool_pictures[str(item)])

static func menu_icon(picture: Texture2D) -> Texture2D:
	if picture is not AtlasTexture:
		return picture
	var icon := AtlasTexture.new()
	icon.atlas = picture.atlas
	icon.region = picture.region
	if picture.region.size==Vector2(128,128):
		# The source tool pictures fit this part of their ANI canvas.
		icon.region = Rect2(picture.region.position+Vector2(46,83),Vector2(36,37))
	icon.filter_clip = true
	return icon

func poll_input() -> void:
	if player.input_locked:
		return
	if busy():
		if state == "show_tool" and equipped == 34 and Input.is_action_just_pressed("use_tool"):
			_sow_after_show = true
		elif state == "charge" and not Input.is_action_pressed("use_tool"):
			release_tool()
		elif state == "fishing_wait" and not Input.is_action_pressed("use_tool"):
			play("fishing", player.facing + 4, "reel")
		return
	if Input.is_action_just_pressed("next_tool") and quick_switch.is_valid() and quick_switch.call():
		return
	if Input.is_action_just_pressed("tool_level"):
		if equipped <= 25:
			equipment_selected.emit(equipped)
		elif equipped == 34 and not seed_catalogue.is_empty():
			selected_seed = 34 + (selected_seed - 33) % seed_catalogue.size()
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
	_sow_after_show = false
	_draw()
	# player_collect_target and player_check_tool_slots both call sound_play(7).
	if action in ["show_tool","pickup"]:
		sound_requested.emit("show_item")

func start_tool() -> bool:
	if busy() or carried_id != 0 or player.input_locked or equipped==0 or not owns_tool(equipped):
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
		var seed: Dictionary = seed_catalogue.get(str(selected_seed), {})
		play("seeds",int(seed.get("animation",1)),"seed")
	return true

func release_tool() -> void:
	if state != "charge":
		return
	var level := mini(int(charge_ticks / 20),upgrade)
	var name: String = ["sickle","hoe","axe","hammer","water"][(equipped-1)/5]
	sound_requested.emit("tool_%s_%d" % [name,level])
	play("tool_%d" % upgrade,72 + ((equipped-1)/5 as int)*20 + player.facing*5 + level,"swing",level+1)

func start_pickup(item: int) -> bool:
	if busy() or carried_id != 0 or player.input_locked or (not items.has(str(item)) and not crop_produce.has(item)):
		return false
	pending_item = item
	play("base",11+player.facing,"pickup")
	return true

func start_drop(thrown := false) -> bool:
	if busy() or carried_id==0 or player.input_locked or (not thrown and not items.has(str(carried_id))):
		return false
	play("base",23+player.facing,"throw" if thrown else "drop")
	return true

func go_to_bed(target: Vector3, bed: MeshInstance3D) -> void:
	if bed != null:
		# scene_link_handback opens the blanket in eight farm ticks.
		bed.create_tween().tween_property(bed,"blend_shapes/Folded",1.0,8.0/30.0)
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
	if is_instance_valid(bed):
		var blanket := bed.create_tween().set_parallel()
		blanket.tween_property(bed,"blend_shapes/Folded",0.0,12.0/30.0)
		blanket.tween_property(bed,"blend_shapes/Tucked",1.0,12.0/30.0)
	var wait := 0.0
	while wait<0.5:
		await get_tree().physics_frame
		if not cinematic: return
		wait += get_physics_process_delta_time()
	play("sleep",3,"bed_pose")
	while state != "bed_hold":
		await get_tree().physics_frame
		if not cinematic: return

func advance(delta: float) -> void:
	if state == "show_tool":
		elapsed += delta
		if elapsed+0.0000001 >= 10.0/30.0:
			var sow := _sow_after_show
			_sow_after_show = false
			_finish()
			if sow:
				start_tool()
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
		sound_requested.emit("put_down")
		var item := carried_id
		carried_id = 0
		item_released.emit(item,finished=="throw")
	if finished == "seed":
		sound_requested.emit("sow")
	elif finished == "refill":
		sound_requested.emit("refill")
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
	if showing:
		held_sprite.texture = tool_picture(equipped,selected_seed)
	else:
		held_sprite.texture = item_picture(item)
	if held_sprite.texture==null:
		held_sprite.hide()
		return
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

func item_picture(item: int) -> Texture2D:
	if crop_produce.has(item):
		return crop_produce[item]
	if items.has(str(item)):
		return _texture(items[str(item)].texture)
	return source_item_picture(item)

func source_item_picture(item: int) -> Texture2D:
	if item_art==null:
		item_art = preload("res://game/original_sprites/sprite_library.gd").new(
			"res://game/original_sprites/item_picture_catalogue.json")
	if not item_images.has(item):
		var frame: Dictionary = item_art.catalogue.items.get(str(item),{})
		item_images[item] = item_art.frame_texture(frame) if not frame.is_empty() else null
	return item_images[item]

func _texture(path: String) -> Texture2D:
	if not textures.has(path):
		textures[path] = load(path)
	return textures[path]

func _draw() -> void:
	var source: Dictionary = data.banks[bank]
	var pose: Dictionary = source.ranges[str(range_id)][frame]
	# Identical cropped pictures may share an atlas region but retain different ANI offsets.
	var key: String = source.pages[pose.page]+str(pose.rect)+str(pose.margin)
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

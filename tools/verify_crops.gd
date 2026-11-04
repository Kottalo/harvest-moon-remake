extends SceneTree
## Source crop lifecycle checks at the game action and clock entry points.
var world
var field
var crops
var actions
const ORIGIN := Vector2i(20,12)

func _initialize() -> void:
	_run.call_deferred()

func _require(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _position(cell: Vector2i, facing := 0) -> void:
	world.player.position = Vector3(cell.x*0.4-4.2,0.02,cell.y*0.4-1.4)
	world.player.facing = facing
	world.player.reset_physics_interpolation()

func _finish() -> bool:
	for frame in 360:
		if not actions.busy():
			return true
		actions.advance(1.0/60.0)
	return _require(false,"Original crop action timed out")

func _tool(tool: int) -> bool:
	actions.equipped = tool
	actions.upgrade = 0
	if not _require(actions.start_tool(),"Crop tool refused"):
		return false
	if actions.state == "charge":
		actions.release_tool()
	return _finish()

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _sow_from_picker(seed: int, target: int) -> bool:
	actions.equipped = 6
	world.player.set_physics_process(true)
	await _ticks(5)
	world.player.facing = 0
	_key(KEY_I,true)
	_key(KEY_I,false)
	if not _require(world.tool_picker.panel.visible and paused,"I did not open the seed picker"): return false
	_key(KEY_TAB,true)
	_key(KEY_TAB,false)
	world.tool_picker.entries[seed].pressed.emit()
	await _ticks(2)
	if not _require(actions.state == "show_tool" and not paused,"Seed picker did not equip the seed bag"): return false
	_key(KEY_SPACE,true)
	await _ticks(2)
	_key(KEY_SPACE,false)
	var poses := {}
	var expected_animation: int = crops.data.seeds[str(seed)].animation
	for tick in ceili(Engine.physics_ticks_per_second*1.2):
		await _ticks(1)
		if actions.state == "seed":
			if not _require(actions.range_id==expected_animation,"Picker played the wrong seed animation: "+str(seed)): return false
			poses[actions.frame] = true
			if not _require(crops.plants.is_empty(),"Ground changed before the original sowing pose completed"): return false
	world.player.set_physics_process(false)
	return _require(poses.size()==3 and crops.plants.has(target) and field.pixels[target]==3,
		"Space during the equip pose lost the sowing action or source soil update: "+str(seed))

func _dawn() -> void:
	world.day_cycle.minute = 359
	world.day_cycle._tick_minute()

func _run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	await physics_frame
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	field = world.farm_field
	crops = field.crops
	actions = world.player.actions
	for record in world.loose_items.records[0]:
		if record.active:
			world.loose_items._remove(record)
	await physics_frame
	await process_frame
	var target: int = field.cell_index(ORIGIN + Vector2i.DOWN)
	_position(ORIGIN)
	world.player.set_physics_process(true)
	await _ticks(5)
	_key(KEY_SPACE,true)
	await _ticks(2)
	_key(KEY_SPACE,false)
	await _ticks(Engine.physics_ticks_per_second)
	world.player.set_physics_process(false)
	if not _require(field.states[target]==field.TILLED and not actions.busy(),"Physical Space did not hoe the plot used for sowing"):
		return
	if not _require(field.material.get_shader_parameter("crop_ground") is Texture2D,"The original sown soil texture is not bound"):
		return
	if not await _sow_from_picker(34,target):
		return
	if not _require(crops.message == "已播种 · 1 格","Sowing did not report the changed plot count"):
		return
	if not _tool(34) or not _require(crops.plants.size()==1 and crops.message == "周围没有可播种的空耕地","Repeated sowing failed to report no eligible plots"):
		return
	_dawn()
	if not _require(crops.plants[target].days == 0,"Dry seed grew"):
		return
	if not _tool(21) or not _require(field.pixels[target] == 4,"Watering action did not wet the seed"):
		return
	world.day_cycle.minute = 359
	world.day_cycle.wake_next_morning()
	if not _require(crops.plants[target].days == 1 and field.pixels[target] == 3,"Sleep did not advance a watered seed exactly once"):
		return
	for i in 3:
		if not _tool(21):
			return
		_dawn()
	if not _require(crops.plants[target].stage == 2 and crops.colliders.has(target),"Turnip did not mature in four watered days"):
		return
	actions.interact_requested.emit()
	if not _finish() or not _require(actions.carried_id == 65 and not crops.plants.has(target) and not crops.colliders.has(target),"Harvest did not pick up ripe turnip"):
		return
	actions.interact_requested.emit()
	if not _require(actions.carried_id == 0 and crops.harvest.get(65,0) == 1,"Harvest pouch did not receive crop"):
		return
	var ids := range(34,55)
	ids.append(377)
	for plant_id in ids:
		var seed: int = 51 if plant_id == 377 else plant_id
		crops.plants.clear()
		field.states.fill(field.SOIL)
		field.set_soil(target,field.TILLED)
		var crop_id: int = 376 if plant_id == 51 else plant_id
		var row: Dictionary = crops.data.crops[str(crop_id)]
		world.day_cycle.season = 0
		world.day_cycle.day = 0
		crops.water_remaining = 100
		if not await _sow_from_picker(seed,target):
			return
		if int(row.season) not in [0,4]:
			if not _require(crops.message.contains("次日会枯萎"),"No warning for a successfully planted off-season seed: "+str([seed,crops.message])):
				return
			_dawn()
			if not _require(not crops.plants.has(target) and field.pixels[target]==1,"Off-season seed did not wither at dawn"):
				return
			world.day_cycle.season = row.season
			if not _tool(34) or not _require(crops.plants.has(target),"Seed did not plant in its own season: "+str(seed)):
				return
		if seed == 51:
			# Exercise both outcomes without relying on the 1-in-25 roll in a test.
			crops.plants[target].id = crop_id
		for length in row.days:
			for day in maxi(1,int(length)):
				if seed != 54 and not _tool(21):
					return
				_dawn()
		if not _require(crops.plants[target].stage == row.mature,"Wrong maturation duration for seed "+str(seed)):
			return
		if seed == 54:
			if not _tool(1) or not _require(crops.harvest.get(104,0) == 1 and crops.plants[target].stage == 1,"Mature grass did not make fodder"):
				return
			world.day_cycle.season = 2
			world.day_cycle.day = 29
			_dawn()
			if not _require(crops.plants.has(target) and crops.plants[target].stage == 1,"Grass did not overwinter"):
				return
		else:
			actions.interact_requested.emit()
			if not _finish() or not _require(actions.carried_id > 0,"Mature crop did not harvest: "+str(seed)):
				return
			actions.interact_requested.emit()
			if not _require(crops.plants.has(target) == (row.regrow >= 0),"Wrong regrowth for seed "+str(seed)):
				return
			if row.regrow >= 0:
				if not _require(crops.plants[target].stage == row.regrow,"Wrong regrowth stage"):
					return
				if not _tool(21):
					return
				_dawn()
				if not _require(crops.plants[target].days == 0 and not crops.plants[target].skip,"Harvest day should not count toward regrowth"):
					return
				world.day_cycle.day = 29
				_dawn()
				if not _require(not crops.plants.has(target),"Season rollover left a seasonal crop alive"):
					return
	print("CROPS_OK: physical hoe, picker + Space, 21 seed tools sow in spring with all 3 source poses, off-season withers at dawn, 22 crop records, water, dry day, sleep, produce harvests, fodder, regrowth and seasons")
	quit()

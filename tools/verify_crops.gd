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

func _dawn() -> void:
	world.day_cycle.minute = 359
	world.day_cycle._tick_minute()

func _run() -> void:
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
	field.set_soil(target,field.TILLED)
	world.day_cycle.season = 1
	if not _tool(34) or not _require(crops.plants.is_empty(),"Out-of-season seed planted"):
		return
	world.day_cycle.season = 0
	if not _tool(34) or not _require(crops.plants.has(target) and field.pixels[target] == 3,"Source seed action did not sow the front tile"):
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
		var selected: Dictionary = crops.data.seeds[str(seed)]
		actions.selected_seed = seed
		crops.plants.clear()
		field.states.fill(field.SOIL)
		field.set_soil(target,field.TILLED)
		var crop_id: int = 376 if plant_id == 51 else plant_id
		var row: Dictionary = crops.data.crops[str(crop_id)]
		world.day_cycle.season = 0 if row.season == 4 else row.season
		world.day_cycle.day = 0
		crops.water_remaining = 100
		if not _tool(34) or not _require(crops.plants.has(target) and actions.bank == "seeds","Seed did not plant: "+str([seed,selected.animation])):
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
	print("CROPS_OK: 21 seed actions, 22 crop records, water, dry day, sleep, produce harvests, fodder, regrowth and seasons")
	quit()

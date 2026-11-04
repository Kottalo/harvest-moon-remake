extends Node3D
## Crop records are indexed by the same cells as the farm soil.
const CATALOGUE := "res://game/field/crop_catalog.json"
const GRASS := 54
const FODDER := 104
var field
var world
var data: Dictionary
var plants := {}
var batches := {}
var pictures := {}
var atlas_pages := {}
var crop_body := StaticBody3D.new()
var crop_shape := BoxShape3D.new()
var colliders := {}
var harvest := {}
var water_remaining := 100
var message := ""


func setup(owner_field) -> void:
	field = owner_field
	world = field.world
	data = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))
	var actions = world.player.actions
	actions.seed_catalogue = data.seeds
	actions.crop_picture_provider = picture
	actions.interact_requested.connect(pick_crop)
	world.day_cycle.day_started.connect(next_day)
	crop_body.name = "CropObstructions"
	crop_body.collision_mask = 0
	crop_shape.size = Vector3(0.4,0.28,0.4)
	add_child(crop_body)


func picture(entry: Array) -> AtlasTexture:
	var key := str(entry)
	if pictures.has(key):
		return pictures[key]
	var rect: Array = entry[1]
	var offset: Array = entry[2]
	var texture := AtlasTexture.new()
	if not atlas_pages.has(entry[0]):
		atlas_pages[entry[0]] = load_atlas(entry[0])
	texture.atlas = atlas_pages[entry[0]]
	texture.region = Rect2(rect[0],rect[1],rect[2],rect[3])
	texture.margin = Rect2(64 + offset[0],112 + offset[1],128 - rect[2],128 - rect[3])
	texture.filter_clip = true
	pictures[key] = texture
	return texture


static func load_atlas(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	# Headless verification can run before the editor has imported a new PNG.
	if DisplayServer.get_name() == "headless":
		return ImageTexture.create_from_image(Image.load_from_file(path))
	return null


func bind_location() -> void:
	visible = world.current_area == 0
	crop_body.collision_layer = 1 if visible else 0
	if visible:
		refresh_plots()


func use_tool(tool: int, charge: int, origin: Vector2i) -> void:
	var actions = world.player.actions
	var facing: int = world.player.facing
	if tool >= 21 and tool <= 25 and actions.state == "refill":
		water_remaining = 100
		return
	if tool == 34:
		var seed: int = actions.selected_seed
		# field_event_dispatch always sows eligible outdoor soil outside winter.
		# The original checks the crop's season at dawn, after the seeds land.
		var planted := 0
		for offset: Array in data.sow[facing]:
			var cell := origin + Vector2i(offset[0],offset[1])
			var index: int = field.cell_index(cell)
			if index < 0 or plants.has(index) or field.states[index] not in [field.TILLED,field.WATERED] or not field.plot_clear(cell):
				continue
			var plant_id := (377 if randi_range(1,25)==1 else 376) if seed == 51 else seed
			plants[index] = {"id":plant_id,"stage":0,"days":0,"skip":false}
			planted += 1
		if planted > 0:
			message = "已播种 · %d 格" % planted
			var crop: Dictionary = data.crops[str(376 if seed == 51 else seed)]
			if crop.season != world.day_cycle.season and crop.season != 4:
				message += " · 非当季，次日会枯萎"
			refresh_plots(false)
		else:
			message = "周围没有可播种的空耕地"
	elif tool >= 21 and tool <= 25:
		var offsets: Array = data.water[charge][facing]
		var count := mini(mini(offsets.size(),int(data.water_steps[charge])),water_remaining)
		water_remaining -= count
		for i in count:
			var offset: Array = offsets[i]
			var cell := origin + Vector2i(offset[0],offset[1])
			var index: int = field.cell_index(cell)
			if index >= 0 and field.states[index] == field.TILLED and (plants.has(index) or field.plot_clear(cell)):
				field.states[index] = field.WATERED
		refresh_plots(false)
	elif tool >= 1 and tool <= 5:
		for offset: Array in data.cut[charge][facing]:
			var index: int = field.cell_index(origin + Vector2i(offset[0],offset[1]))
			if not plants.has(index):
				continue
			var plant: Dictionary = plants[index]
			var crop: Dictionary = data.crops[str(plant.id)]
			if plant.id == GRASS:
				if plant.stage == crop.mature:
					harvest[FODDER] = harvest.get(FODDER,0) + 1
					after_harvest(index,crop)
			else:
				plants.erase(index)
		refresh_plots()


func next_day(_previous_season: int) -> void:
	var season: int = world.day_cycle.season
	for index in plants.keys():
		var plant: Dictionary = plants[index]
		var crop: Dictionary = data.crops[str(plant.id)]
		if plant.id == GRASS and season == 3:
			if plant.stage > 0:
				plant.stage = 1
			plant.days = 0
			plant.skip = false
			continue
		if crop.season != season and crop.season != 4:
			plants.erase(index)
			field.states[index] = field.TILLED
			continue
		if plant.stage == crop.mature:
			continue
		if field.states[index] != field.WATERED and plant.id != GRASS:
			continue
		if plant.skip:
			plant.skip = false
			continue
		plant.days += 1
		if plant.days >= crop.days[plant.stage]:
			plant.stage += 1
			plant.days = 0
	for index in field.states.size():
		if field.states[index] == field.WATERED:
			field.states[index] = field.TILLED
	message = ""
	refresh_plots()


func pick_crop() -> void:
	if world.transitioning:
		return
	var actions = world.player.actions
	if actions.carried_id != 0:
		if data.produce.has(str(actions.carried_id)):
			var item: int = actions.carried_id
			harvest[item] = harvest.get(item,0) + 1
			message = "已收起 · 该作物共 %d 个" % harvest[item]
			actions.carried_id = 0
		return
	if world.current_area != 0 or world.day_cycle.season == 3:
		return
	var direction: Vector3 = actions.DIRECTIONS[world.player.facing]
	var index: int = field.cell_index(field.cell_at(world.player.position + direction*0.4))
	if not plants.has(index):
		return
	var plant: Dictionary = plants[index]
	var crop: Dictionary = data.crops[str(plant.id)]
	if crop.harvest <= 0 or plant.stage != crop.mature:
		return
	var item := int(crop.harvest)
	actions.crop_produce[item] = picture(data.produce[str(item)])
	if actions.start_pickup(item):
		after_harvest(index,crop)
		refresh_plots()


func after_harvest(index: int, crop: Dictionary) -> void:
	if crop.regrow < 0:
		plants.erase(index)
	else:
		plants[index].stage = int(crop.regrow)
		plants[index].days = 0
		plants[index].skip = true


func refresh_plots(rebuild := true) -> void:
	var season: int = world.day_cycle.season
	for index in field.states.size():
		field.pixels[index] = 2 if field.states[index] == field.WATERED else (1 if field.states[index] == field.TILLED else 0)
	var groups := {}
	for index: int in plants:
		var plant: Dictionary = plants[index]
		if plant.stage == 0:
			field.pixels[index] = 4 if field.states[index] == field.WATERED else 3
			continue
		if plant.id == GRASS:
			field.pixels[index] = 4 + int(plant.stage)
			continue
		if not rebuild or not visible or season == 3:
			continue
		var art: Array = data.crops[str(plant.id)].frames[plant.stage]
		var key := str(art)
		if not groups.has(key):
			groups[key] = {"art":art,"cells":[]}
		groups[key].cells.append(index)
	field.upload_soil()
	if not rebuild:
		return
	_sync_colliders()
	for key in batches:
		batches[key].multimesh.visible_instance_count = 0
	for key in groups:
		if not batches.has(key):
			batches[key] = _make_batch(groups[key].art)
		var batch: MultiMesh = batches[key].multimesh
		var cells: Array = groups[key].cells
		if batch.instance_count < cells.size():
			batch.instance_count = cells.size()
		for slot in cells.size():
			var index: int = cells[slot]
			var center := _plot_center(index)
			batch.set_instance_transform(slot,Transform3D(Basis.IDENTITY,center))
		batch.visible_instance_count = cells.size()


func _plot_center(index: int) -> Vector3:
	return Vector3((index % 45)*0.4 - 4.2,0,(index / 45 as int)*0.4 - 1.4)


func _sync_colliders() -> void:
	for index in colliders.keys():
		if plants.has(index) and plants[index].id != GRASS and plants[index].stage > 0:
			continue
		var shape: CollisionShape3D = colliders[index]
		crop_body.remove_child(shape)
		shape.queue_free()
		colliders.erase(index)
	for index in plants:
		if colliders.has(index) or plants[index].id == GRASS or plants[index].stage == 0:
			continue
		var shape := CollisionShape3D.new()
		shape.shape = crop_shape
		shape.position = _plot_center(index) + Vector3.UP * 0.14
		shape.debug_fill = false
		crop_body.add_child(shape)
		colliders[index] = shape


func _make_batch(art: Array) -> MultiMeshInstance3D:
	var texture := picture(art)
	var size := texture.region.size
	var offset: Array = art[2]
	var quad := QuadMesh.new()
	var scale: float = world.player.sprite.pixel_size
	quad.size = size * scale
	quad.center_offset = Vector3((offset[0] + size.x*0.5)*scale,(-offset[1] - size.y*0.5)*scale,0)
	var material := ShaderMaterial.new()
	material.shader = load("res://game/rendering/player_sprite.gdshader")
	material.set_shader_parameter("draw_offset",Vector3(0.15,0.1,0.15))
	preload("res://game/rendering/atlas_binding.gd").bind(material,"albedo_texture",texture)
	quad.material = material
	var batch := MultiMeshInstance3D.new()
	batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.mesh = quad
	add_child(batch)
	return batch

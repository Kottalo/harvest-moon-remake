extends Node3D
## Native loose-item records; initial debris positions come from title_layout0_cells.
var world
var catalogue: Dictionary
var records := {}
var current_area := -1
var materials := {}
var flights := []
var ticks := 0.0
var field_cells: Array
var placement := {}

func setup(owner_world) -> void:
	world = owner_world
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	field_cells = catalogue.field_cells.duplicate()
	records[0] = []
	for item in catalogue.initial_farm:
		records[0].append({"id":int(item.id),"cell":int(item.cell),"position":Vector3(item.position[0],item.position[1],item.position[2]),"active":true})
	world.player.actions.interact_requested.connect(interact)
	world.player.actions.item_released.connect(release_item)
	world.player.actions.tool_used.connect(use_tool)
	set_area(0)

func set_area(area: int) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	flights.clear()
	current_area = area
	if not records.has(area):
		records[area] = []
	for record in records[area]:
		if record.active:
			record["node"] = _spawn(record.id,record.position,true)

func _spawn(item: int, point: Vector3, solid: bool) -> Node3D:
	var node := Node3D.new()
	node.name = catalogue.pictures[str(item)].name.to_pascal_case()
	node.position = point
	add_child(node)
	var sprite := Sprite3D.new()
	sprite.texture = load(catalogue.pictures[str(item)].texture)
	sprite.offset = Vector2(0,48)
	sprite.pixel_size = world.player.sprite.pixel_size
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if not materials.has(item):
		var material := ShaderMaterial.new()
		material.shader = load("res://game/rendering/player_sprite.gdshader")
		material.set_shader_parameter("albedo_texture",sprite.texture)
		materials[item] = material
	sprite.material_override = materials[item]
	node.add_child(sprite)
	if solid and item in [58,62]:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.16,0.12,0.16)
		shape.shape = box
		shape.position.y = 0.06
		node.add_child(body)
		body.add_child(shape)
	return node

func _target() -> Dictionary:
	var ahead: Vector3 = world.player.position + world.player.actions.DIRECTIONS[world.player.facing]*0.224
	var best := 0.22
	var selected := {}
	for record in records[current_area]:
		if not record.active:
			continue
		var distance := Vector2(record.position.x-ahead.x,record.position.z-ahead.z).length()
		if distance < best and absf(record.position.y-world.player.position.y) < 0.2:
			selected = record
			best = distance
	return selected

func interact() -> void:
	if world.transitioning:
		return
	var actions = world.player.actions
	if actions.carried_id != 0:
		placement = _placement(actions.carried_id)
		if placement.get("blocked",false):
			return
		actions.start_drop(placement.is_empty())
		return
	var record := _target()
	if not record.is_empty() and actions.start_pickup(record.id):
		_remove(record)

func _remove(record: Dictionary) -> void:
	record.active = false
	record.node.queue_free()
	if current_area == 0 and record.has("cell"):
		field_cells[record.cell] = 0x167 # ITEM_SOIL

func _placement(item: int) -> Dictionary:
	if current_area != 0 or not catalogue.pictures[str(item)].place_on_farm:
		return {}
	# player_selection_to_result uses facing_steps[0..3] (400 units), then
	# field_world_to_cell's original 399-unit integer cell conversion.
	var point: Vector3 = world.player.position + world.player.actions.DIRECTIONS[world.player.facing]*0.4
	var column := floori((point.x+4.4)/0.399)
	var row := floori((point.z+1.6)/0.399)
	if column < 0 or column >= 45 or row < 0 or row >= 25:
		return {}
	var cell := row*45+column
	if int(field_cells[cell]) != 0x167:
		return {"blocked":true}
	return {"cell":cell,"position":Vector3(column*0.4-4.2,0,row*0.4-1.4)}

func release_item(item: int, thrown: bool) -> void:
	var direction: Vector3 = world.player.actions.DIRECTIONS[world.player.facing]
	if thrown:
		var node := _spawn(item,world.player.position+Vector3.UP*0.3,false)
		flights.append({"node":node,"direction":direction,"velocity":0.0,"ground":world.player.position.y})
	else:
		if placement.is_empty():
			world.player.actions.carried_id = item
			return
		var point: Vector3 = placement.position
		var record := {"id":item,"position":point,"active":true,"cell":placement.cell}
		record.node = _spawn(item,point,true)
		records[current_area].append(record)
		field_cells[placement.cell] = item
	placement = {}

func use_tool(tool: int, _charge: int) -> void:
	var record := _target()
	if record.is_empty():
		return
	var kind := ""
	if tool >= 1 and tool <= 25:
		kind = ["sickle","hoe","axe","hammer","watering_can"][(tool-1)/5 as int]
	if kind == catalogue.pictures[str(record.id)].tool:
		_remove(record)

func _physics_process(delta: float) -> void:
	if world == null or world.transitioning:
		return
	ticks += delta*30.0
	while ticks >= 1.0:
		ticks -= 1.0
		for i in range(flights.size()-1,-1,-1):
			var flight: Dictionary = flights[i]
			flight.node.position += flight.direction*0.044 + Vector3.UP*flight.velocity
			flight.velocity = maxf(flight.velocity-0.009,-0.045)
			if flight.node.position.y <= flight.ground:
				flight.node.queue_free()
				flights.remove_at(i)

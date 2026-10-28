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
var batches := {}
var meshes := {}
var obstruction_shape: BoxShape3D
const FIELD_CELL_SIZE := 0.399 # field_world_to_cell: the source 399-unit grid.

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
	batches.clear()
	current_area = area
	if not records.has(area):
		records[area] = []
	# Static debris shares three tightly cropped meshes, rather than 423 Sprite3Ds.
	if records[area].is_empty() and area != 0:
		return
	for item in [58,62,64]:
		var batch := MultiMeshInstance3D.new()
		batch.name = catalogue.pictures[str(item)].name.to_pascal_case()+"Batch"
		# These are stationary items. Slot reuse is a discrete change, not motion
		# from the former occupant's position to the newly placed item's position.
		batch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.mesh = _item_mesh(item)
		# At most one item per field cell. Allocate once when entering the map;
		# visible_instance_count draws only the dense active prefix, not spare slots.
		batch.multimesh.instance_count = field_cells.size()
		batch.multimesh.visible_instance_count = 0
		add_child(batch)
		batches[item] = {"mesh":batch.multimesh,"records":[]}
	for record in records[area]:
		if record.active:
			_add_record(record)

func _item_mesh(item: int) -> ArrayMesh:
	if meshes.has(item):
		return meshes[item]
	var texture: Texture2D = load(catalogue.pictures[str(item)].texture)
	var bounds := texture.get_image().get_used_rect().grow(1).intersection(Rect2i(0,0,128,128))
	var scale: float = world.player.sprite.pixel_size
	var left := (bounds.position.x-64)*scale
	var right := (bounds.end.x-64)*scale
	var top := (64-bounds.position.y+48)*scale
	var bottom := (64-bounds.end.y+48)*scale
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(left,bottom,0),Vector3(right,bottom,0),Vector3(right,top,0),Vector3(left,top,0)])
	var uv := Rect2(bounds)
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(uv.position.x,uv.end.y)/128,uv.end/128,Vector2(uv.end.x,uv.position.y)/128,uv.position/128])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2,0,2,3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://game/rendering/player_sprite.gdshader")
	material.set_shader_parameter("albedo_texture",texture)
	mesh.surface_set_material(0,material)
	meshes[item] = mesh
	return mesh

func _add_record(record: Dictionary) -> void:
	var batch: Dictionary = batches[record.id]
	var slot: int = batch.records.size()
	batch.mesh.set_instance_transform(slot,Transform3D(Basis.IDENTITY,record.position))
	batch.records.append(record)
	batch.mesh.visible_instance_count = batch.records.size()
	record["batch_slot"] = slot
	record["node"] = _spawn(record.id,record.position,true)

func _spawn(item: int, point: Vector3, solid: bool) -> Node3D:
	var node := Node3D.new()
	node.name = catalogue.pictures[str(item)].name.to_pascal_case()
	node.position = point
	add_child(node)
	if not solid:
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
	# farm_tables.c: stone/branch/weeds use blocked tile rules 3/6/2.
	# The field probe blocks their occupied CELL, not just the sprite's centre.
	if solid and item in [58,62,64]:
		var body := StaticBody3D.new()
		body.name = "Obstruction"
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		if obstruction_shape == null:
			obstruction_shape = BoxShape3D.new()
			# A vertical barrier adapts the source's 2D occupancy test: the native
			# rounded capsule must not climb onto a low box representing a sprite.
			obstruction_shape.size = Vector3(FIELD_CELL_SIZE,0.4,FIELD_CELL_SIZE)
		shape.shape = obstruction_shape
		var column := floori((point.x+4.4)/FIELD_CELL_SIZE)
		var row := floori((point.z+1.6)/FIELD_CELL_SIZE)
		var centre := _cell_bounds(column,row).get_center()
		shape.position = Vector3(centre.x-point.x,0.2,centre.y-point.z)
		node.add_child(body)
		body.add_child(shape)
	return node

func _cell_bounds(column: int, row: int) -> Rect2:
	return Rect2(Vector2(column*FIELD_CELL_SIZE-4.4,row*FIELD_CELL_SIZE-1.6),Vector2.ONE*FIELD_CELL_SIZE)

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
	if not record.active:
		return
	record.active = false
	var batch: Dictionary = batches[record.id]
	var slot: int = record.batch_slot
	var last: Dictionary = batch.records.pop_back()
	if slot < batch.records.size():
		# Fill just this hole with the last live instance; its collider stays put.
		batch.records[slot] = last
		last.batch_slot = slot
		batch.mesh.set_instance_transform(slot,Transform3D(Basis.IDENTITY,last.position))
	batch.mesh.visible_instance_count = batch.records.size()
	record.batch_slot = -1
	record.node.queue_free()
	if current_area == 0 and record.has("cell"):
		field_cells[record.cell] = 0x167 # ITEM_SOIL

func _placement(item: int) -> Dictionary:
	if current_area != 0 or not catalogue.pictures[str(item)].place_on_farm:
		return {}
	# player_selection_to_result uses facing_steps[0..3] (400 units), then
	# field_world_to_cell's original 399-unit integer cell conversion.
	var point: Vector3 = world.player.position + world.player.actions.DIRECTIONS[world.player.facing]*0.4
	var column := floori((point.x+4.4)/FIELD_CELL_SIZE)
	var row := floori((point.z+1.6)/FIELD_CELL_SIZE)
	if column < 0 or column >= 45 or row < 0 or row >= 25:
		return {}
	var cell := row*45+column
	if int(field_cells[cell]) != 0x167:
		return {"blocked":true}
	# A native capsule can straddle a cell edge. Do not create a blocker inside it.
	var bounds := _cell_bounds(column,row)
	var feet := Vector2(world.player.position.x,world.player.position.z)
	var nearest := feet.clamp(bounds.position,bounds.end)
	if feet.distance_to(nearest) < world.player.footprint.radius:
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
		records[current_area].append(record)
		field_cells[placement.cell] = item
		_add_record(record)
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

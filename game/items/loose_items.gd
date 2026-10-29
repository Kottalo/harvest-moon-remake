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
var prefab_scenes := {58:preload("res://game/items/prefabs/stone.tscn"),62:preload("res://game/items/prefabs/branch.tscn"),64:preload("res://game/items/prefabs/weeds.tscn")}
var prefab_definitions := {}
const VISUAL_CELL_SIZE := 0.4 # Original field quad spacing; placement shares its centres.
const PLACEMENT_PROBE_SIZE := 0.8

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
		if OS.is_debug_build() and get_tree().debug_collisions_hint and not _prefab_definition(item).field.debug_fill and not _prefab_definition(item).loose.debug_fill:
			# Draw the actual native box meshes together; hundreds of separate
			# debug MeshInstances otherwise undo the item sprite batching.
			var wire := MultiMeshInstance3D.new()
			wire.name = batch.name+"Colliders"
			wire.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			wire.multimesh = MultiMesh.new()
			wire.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			wire.multimesh.use_colors = true
			# Preserve native edges, but replace their cached vertex tint with white:
			# MultiMesh instance colours carry each actual shape's debug colour.
			var edges := _obstruction_box(item).get_debug_mesh().surface_get_arrays(0)
			var colours := PackedColorArray()
			colours.resize(edges[Mesh.ARRAY_VERTEX].size())
			colours.fill(Color.WHITE)
			edges[Mesh.ARRAY_COLOR] = colours
			wire.multimesh.mesh = ArrayMesh.new()
			wire.multimesh.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,edges)
			wire.multimesh.instance_count = field_cells.size()
			wire.multimesh.visible_instance_count = 0
			var material := StandardMaterial3D.new()
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.vertex_color_use_as_albedo = true
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			wire.material_override = material
			add_child(wire)
			batches[item]["debug"] = wire.multimesh
	for record in records[area]:
		if record.active:
			_add_record(record)

func _item_mesh(item: int) -> ArrayMesh:
	if meshes.has(item):
		return meshes[item]
	var definition := _prefab_definition(item)
	var texture: Texture2D = definition.texture
	var bounds := texture.get_image().get_used_rect().grow(1).intersection(Rect2i(0,0,128,128))
	var scale: float = definition.pixel_size
	var offset: Vector2 = definition.offset
	var left: float = (bounds.position.x-64+offset.x)*scale*definition.scale.x
	var right: float = (bounds.end.x-64+offset.x)*scale*definition.scale.x
	var top: float = (64-bounds.position.y+offset.y)*scale*definition.scale.y
	var bottom: float = (64-bounds.end.y+offset.y)*scale*definition.scale.y
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
	material.set_shader_parameter("draw_offset",definition.position)
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
	# CollisionObject3D creates its native debug instances when shapes enter.
	# Suppress only that synchronous creation; the exact boxes are drawn below.
	var native_debug := get_tree().debug_collisions_hint
	if batch.has("debug"): get_tree().debug_collisions_hint = false
	record["node"] = _spawn(record.id,record.position,true,not record.get("free_position",false))
	get_tree().debug_collisions_hint = native_debug
	if batch.has("debug"):
		var collision: CollisionShape3D = record.node.get_node("Obstruction").get_child(0)
		# Native box edges, scaled to this actual authored shape, including
		# independently edited placed-item sizes, rotations and offsets.
		var wire_scale: Vector3 = collision.shape.size/_obstruction_box(record.id).size
		var wire_transform := global_transform.affine_inverse()*collision.global_transform
		batch.debug.set_instance_transform(slot,wire_transform.scaled_local(wire_scale))
		batch.debug.set_instance_color(slot,collision.debug_color)
		batch.debug.visible_instance_count = batch.records.size()

func _spawn(item: int, point: Vector3, solid: bool, cell_aligned := true) -> Node3D:
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
		var definition: Dictionary = _prefab_definition(item)["field" if cell_aligned else "loose"]
		shape.shape = _obstruction_box(item,not cell_aligned)
		shape.transform = definition.transform
		shape.debug_color = definition.debug_color
		shape.debug_fill = definition.debug_fill
		node.add_child(body)
		body.add_child(shape)
		# Release can query a just-created neighbour in the same frame.
		body.force_update_transform()
		shape.force_update_transform()
	return node

func _prefab_definition(item: int) -> Dictionary:
	if prefab_definitions.has(item):
		return prefab_definitions[item]
	var prefab: Node3D = prefab_scenes[item].instantiate()
	var sprite: Sprite3D = prefab.get_node("GroundSprite")
	var definition := {"texture":sprite.texture,"pixel_size":sprite.pixel_size,"offset":sprite.offset,"scale":sprite.scale,"position":sprite.position}
	for kind in ["field","loose"]:
		var node: CollisionShape3D = prefab.get_node("Obstruction/"+("FieldFootprint" if kind=="field" else "LooseFootprint"))
		var transform: Transform3D = prefab.get_node("Obstruction").transform*node.transform
		var shape := BoxShape3D.new()
		shape.size = node.shape.size*transform.basis.get_scale().abs()
		definition[kind] = {"shape":shape,"transform":Transform3D(transform.basis.orthonormalized(),transform.origin),"debug_color":node.debug_color,"debug_fill":node.debug_fill}
	prefab.free()
	prefab_definitions[item] = definition
	return definition

func _obstruction_box(item: int, free_position := false) -> BoxShape3D:
	return _prefab_definition(item)["loose" if free_position else "field"].shape

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
		if batch.has("debug"):
			batch.debug.set_instance_transform(slot,batch.debug.get_instance_transform(batch.records.size()))
			batch.debug.set_instance_color(slot,batch.debug.get_instance_color(batch.records.size()))
	batch.mesh.visible_instance_count = batch.records.size()
	if batch.has("debug"):
		batch.debug.visible_instance_count = batch.records.size()
	record.batch_slot = -1
	# Same-tick placement queries must not see a collider awaiting queue_free().
	var body: Node = record.node.get_node_or_null("Obstruction")
	if body != null:
		body.collision_layer = 0
	record.node.queue_free()
	if current_area == 0 and record.has("cell"):
		field_cells[record.cell] = 0x167 # ITEM_SOIL

func _placement(item: int) -> Dictionary:
	if current_area != 0 or not catalogue.pictures[str(item)].place_on_farm:
		return {}
	# User requests nearest available visual cell centre, rather than a free drop.
	var facing: Vector3 = world.player.actions.DIRECTIONS[world.player.facing]
	var point: Vector3 = world.player.position + facing*0.4
	# A full valid cell is sufficient even in a crowded patch. Neighbours must
	# not veto the empty cell through an unrelated total free-area threshold.
	var best := {"blocked":true}
	var feet := Vector2(world.player.position.x,world.player.position.z)
	var ideal := Vector2(point.x,point.z)
	var direction := Vector2(facing.x,facing.z)
	var column := floori((point.x+4.4)/VISUAL_CELL_SIZE)
	var row := floori((point.z+1.6)/VISUAL_CELL_SIZE)
	# The 3x3 cells overlapping the forward detector; snap to their real centres.
	var candidates: Array[Vector2i] = []
	var reach := ceili(PLACEMENT_PROBE_SIZE*0.5/VISUAL_CELL_SIZE)
	for y in range(row-reach,row+reach+1):
		for x in range(column-reach,column+reach+1):
			if x>=0 and x<45 and y>=0 and y<25:
				candidates.append(Vector2i(x,y))
	candidates.sort_custom(func(a: Vector2i,b: Vector2i):
		var da := _placement_cell_center(a).distance_squared_to(ideal)
		var db := _placement_cell_center(b).distance_squared_to(ideal)
		return _placement_cell_center(a).distance_squared_to(feet)<_placement_cell_center(b).distance_squared_to(feet) if is_equal_approx(da,db) else da<db)
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	# One source unit of clearance permits touching neighbouring occupied cells.
	var footprint := _obstruction_box(item,true).size
	var local: Transform3D = _prefab_definition(item).loose.transform
	var extent: AABB = Transform3D(local.basis,Vector3.ZERO)*AABB(-footprint*0.5,footprint)
	var half_size := Vector2(extent.size.x,extent.size.z)*0.5
	box.size = footprint-Vector3(0.002,0.01,0.002)
	query.shape = box
	query.collision_mask = 1
	query.exclude = [world.player.get_rid()]
	var space := get_world_3d().direct_space_state
	var field := Rect2(Vector2(-4.4,-1.6),Vector2(45,25)*VISUAL_CELL_SIZE)
	for cell in candidates:
		var centre := _placement_cell_center(cell)
		if (centre-feet).dot(direction)<=0:
			continue
		var collision_centre := centre+Vector2(local.origin.x,local.origin.z)
		var bounds := Rect2(collision_centre-half_size,half_size*2)
		if not field.encloses(bounds):
			continue
		var ray := PhysicsRayQueryParameters3D.create(Vector3(centre.x,world.player.position.y+0.5,centre.y),Vector3(centre.x,world.player.position.y-0.5,centre.y),2)
		var floor_hit := space.intersect_ray(ray)
		if floor_hit.is_empty() or floor_hit.normal.y<cos(world.player.floor_max_angle):
			continue
		var height: float = floor_hit.position.y
		query.transform = Transform3D(local.basis,Vector3(centre.x,height,centre.y)+local.origin)
		if not space.intersect_shape(query,1).is_empty():
			continue
		ray = PhysicsRayQueryParameters3D.create(world.player.position+Vector3.UP*0.2,Vector3(collision_centre.x,height+local.origin.y,collision_centre.y),1)
		ray.exclude = query.exclude
		if not space.intersect_ray(ray).is_empty():
			continue
		var target := Vector3(centre.x,height,centre.y)
		var backstep := _placement_backstep(target+local.origin,facing,half_size)
		if backstep<0:
			continue
		return {"cell":cell.y*45+cell.x,"position":target,"backstep":backstep}
	return best

func _placement_cell_center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x*VISUAL_CELL_SIZE-4.2,cell.y*VISUAL_CELL_SIZE-1.4)

func _placement_backstep(point: Vector3, facing: Vector3, half_size: Vector2) -> float:
	var delta: Vector3 = point-world.player.get_node("CollisionShape3D").global_position
	var forward_half := half_size.dot(Vector2(absf(facing.x),absf(facing.z)))
	var side_half := half_size.dot(Vector2(absf(facing.z),absf(facing.x)))
	var lateral := maxf(absf(delta.dot(Vector3(-facing.z,0,facing.x)))-side_half,0)
	var radius: float = world.player.footprint.radius+0.002
	if lateral>=radius:
		return 0
	var distance := maxf(forward_half+sqrt(radius*radius-lateral*lateral)-delta.dot(facing),0)
	if distance==0:
		return 0
	var motion := -facing*distance
	if distance>0.2 or world.player.test_move(world.player.global_transform,motion):
		return -1
	# Never step through an obstacle or back off the supported farm floor.
	for fraction in [0.5,1.0]:
		var feet: Vector3 = world.player.position+motion*fraction
		var ray := PhysicsRayQueryParameters3D.create(feet+Vector3.UP*0.2,feet-Vector3.UP*0.2,8)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<cos(world.player.floor_max_angle) or absf(hit.position.y-world.player.position.y)>0.02:
			return -1
	return distance

func release_item(item: int, thrown: bool) -> void:
	var direction: Vector3 = world.player.actions.DIRECTIONS[world.player.facing]
	if thrown:
		var node := _spawn(item,world.player.position+Vector3.UP*0.3,false)
		flights.append({"node":node,"direction":direction,"velocity":0.0,"ground":world.player.position.y})
	else:
		# Re-evaluate after the release animation in case an obstacle moved in.
		placement = _placement(item)
		if placement.is_empty() or placement.get("blocked",false):
			world.player.actions.carried_id = item
			placement = {}
			return
		if placement.backstep>0:
			# Native swept body motion clears the overlap before creating the item.
			if world.player.move_and_collide(-direction*placement.backstep)!=null:
				world.player.actions.carried_id = item
				placement = {}
				return
		var point: Vector3 = placement.position
		var record := {"id":item,"position":point,"active":true,"cell":placement.cell,"free_position":true}
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

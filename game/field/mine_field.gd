extends Node
## Source mine_dig: one cell 400 units ahead, independent of hoe charge/season.
signal found(item: int)
var world
var loot: Dictionary
var depth := 0
var ladder := Vector2i(-1,-1)
var exit_chance := 0
var entry := Vector2i(-1,-1)
var unique_find := {}
var ladder_marker: Label3D
var catalogue: Dictionary
var states := {}
var textures := {}
var material: ShaderMaterial
var obstruction: BoxShape3D
func setup(owner_world) -> void:
	world = owner_world
	loot = JSON.parse_string(FileAccess.get_file_as_string("res://game/economy/source_economy.json")).mines
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/field/mine_field_catalog.json"))
	obstruction = BoxShape3D.new()
	obstruction.size = Vector3(0.398,0.35,0.398)
	world.player.actions.tool_used.connect(use_tool)
	bind_location()
func bind_location() -> void:
	material = null
	ladder_marker = null
	depth = 0
	ladder = Vector2i(-1,-1)
	exit_chance = 0
	entry = Vector2i(-1,-1)
	var area := str(world.current_area)
	# farm_main resets mine_clear_grid on the two outdoor entrance locations.
	if int(world.world[area].location) in [0xC,0xD]:
		states.clear()
		textures.clear()
		return
	if not catalogue.has(area): return
	if not states.has(area):
		var pixels := PackedByteArray()
		pixels.resize(100)
		pixels.fill(0)
		states[area] = pixels
		textures[area] = ImageTexture.create_from_image(Image.create_from_data(10,10,false,Image.FORMAT_R8,pixels))
	var geometry: MeshInstance3D = world.get_node("Location/Geometry")
	for surface in geometry.mesh.get_surface_count():
		var source: ShaderMaterial = geometry.mesh.surface_get_material(surface)
		var texture: Texture2D = source.get_shader_parameter("albedo_texture")
		if texture==null or texture.resource_path!=catalogue[area].bare_texture: continue
		material = ShaderMaterial.new()
		material.shader = load("res://game/field/mine_soil.gdshader")
		preload("res://game/rendering/atlas_binding.gd").bind(material,"albedo_texture",texture)
		preload("res://game/rendering/atlas_binding.gd").bind(material,"dug_texture",load(catalogue[area].dug_texture))
		material.set_shader_parameter("cell_states",textures[area])
		material.set_shader_parameter("orientations",PackedFloat32Array(catalogue[area].orientations))
		geometry.set_surface_override_material(surface,material)
		return
	push_error("Original mine cell surface was not found: "+area)
func use_tool(tool: int,_charge: int) -> void:
	var area := str(world.current_area)
	if tool<6 or tool>10 or material==null or world.transitioning: return
	var point: Vector3 = world.player.position+world.player.actions.DIRECTIONS[world.player.facing]*0.4
	var cell := Vector2i(floori((point.x+2.0)/0.4),floori((point.z+2.0)/0.4))
	if cell.x<0 or cell.y<0 or cell.x>=10 or cell.y>=10: return
	var index := cell.y*10+cell.x
	var pixels: PackedByteArray = states[area]
	if pixels[index]!=0: return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = obstruction
	query.collision_mask = 1
	query.exclude = [world.player.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,Vector3(cell.x*0.4-1.8,0.2,cell.y*0.4-1.8))
	if not world.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return
	pixels[index] = 255
	states[area] = pixels
	textures[area].update(Image.create_from_data(10,10,false,Image.FORMAT_R8,pixels))
	if depth<9 and ladder.x<0 and (entry.x<0 or maxi(absi(cell.x-entry.x),absi(cell.y-entry.y))>1) and randi_range(0,99)<exit_chance:
		ladder = cell
		ladder_marker = Label3D.new()
		ladder_marker.text = "↓"
		ladder_marker.font_size = 42
		ladder_marker.pixel_size = 0.007
		ladder_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		ladder_marker.position = _center(cell)+Vector3.UP*0.12
		world.get_node("Location").add_child(ladder_marker)
		return
	var item := _roll(area)
	exit_chance += 1 if item==0 else 2
	if item!=0:
		found.emit(item)

func _roll(area: String) -> int:
	var table: Dictionary = loot[area]
	var roll := randi_range(0,99)
	for slot in table.weights[depth].size():
		roll -= int(table.weights[depth][slot])
		if roll>=0:
			continue
		var item := int(table.events[slot])
		if item in [99,103]:
			var key := "%s:%d" % [area,item]
			if unique_find.has(key):
				return 0
			unique_find[key] = true
		return item
	return 0

func _center(cell: Vector2i) -> Vector3:
	return Vector3(cell.x*0.4-1.8,0,cell.y*0.4-1.8)

func ladder_near() -> bool:
	if material==null or ladder.x<0:
		return false
	var foot: Vector3 = world.player.position
	return foot.distance_squared_to(_center(ladder))<0.32*0.32

func descend() -> bool:
	if not ladder_near() or world.player.actions.carried_id!=0:
		return false
	depth += 1
	entry = ladder
	ladder = Vector2i(-1,-1)
	exit_chance = 0
	ladder_marker.queue_free()
	ladder_marker = null
	var area := str(world.current_area)
	var pixels: PackedByteArray = states[area]
	pixels.fill(0)
	states[area] = pixels
	textures[area].update(Image.create_from_data(10,10,false,Image.FORMAT_R8,pixels))
	world.economy.message = "矿洞第 %d 层" % (depth+1)
	return true

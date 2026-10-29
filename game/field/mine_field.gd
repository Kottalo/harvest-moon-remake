extends Node
## Source mine_dig: one cell 400 units ahead, independent of hoe charge/season.
var world
var catalogue: Dictionary
var states := {}
var textures := {}
var material: ShaderMaterial
var obstruction: BoxShape3D
func setup(owner_world) -> void:
	world = owner_world
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/field/mine_field_catalog.json"))
	obstruction = BoxShape3D.new()
	obstruction.size = Vector3(0.398,0.35,0.398)
	world.player.actions.tool_used.connect(use_tool)
	bind_location()
func bind_location() -> void:
	material = null
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
		material.set_shader_parameter("albedo_texture",texture)
		material.set_shader_parameter("dug_texture",load(catalogue[area].dug_texture))
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

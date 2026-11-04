extends Node
## Source hoe result steps and soil state; updates a tiny texture, never scene geometry.
const SOIL := 0x167
const TILLED := 0x168
const WATERED := 0x169
var world
var crops
var catalogue: Dictionary
var states := PackedInt32Array()
var pixels := PackedByteArray()
var state_texture: ImageTexture
var material: ShaderMaterial
var pending: Array = []
var origin := Vector2i.ZERO
var step := 0
var step_limit := -1
var elapsed := 0.0
var owns_lock := false

func setup(owner_world) -> void:
	world = owner_world
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/field/farm_field_catalog.json"))
	states.resize(1125)
	states.fill(SOIL)
	pixels.resize(1125)
	pixels.fill(0)
	state_texture = ImageTexture.create_from_image(Image.create_from_data(45,25,false,Image.FORMAT_R8,pixels))
	crops = load("res://game/field/farm_crops.gd").new()
	add_child(crops)
	crops.setup(self)
	world.loose_items.occupied_crop_cells = crops.plants
	world.player.actions.tool_used.connect(use_tool)
	bind_location()

func bind_location() -> void:
	_cancel()
	crops.bind_location()
	if world.current_area!=0:
		return
	var geometry: MeshInstance3D = world.get_node("Location/Geometry")
	for surface in geometry.mesh.get_surface_count():
		var source: ShaderMaterial = geometry.mesh.surface_get_material(surface)
		var texture: Texture2D = source.get_shader_parameter("albedo_texture")
		if texture==null or texture.resource_path!=catalogue.bare_texture:
			continue
		material = ShaderMaterial.new()
		material.shader = load("res://game/field/farm_soil.gdshader")
		preload("res://game/rendering/atlas_binding.gd").bind(material,"albedo_texture",texture)
		preload("res://game/rendering/atlas_binding.gd").bind(material,"tilled_texture",load(catalogue.tilled_texture))
		preload("res://game/rendering/atlas_binding.gd").bind(material,"watered_texture",load(catalogue.watered_texture))
		material.set_shader_parameter("field_states",state_texture)
		material.set_shader_parameter("crop_ground",crops.load_atlas("res://game/original_sprites/field_ground.png"))
		material.set_shader_parameter("field_season",world.day_cycle.season)
		geometry.set_surface_override_material(surface,material)
		return
	push_error("Original farm field surface was not found")

func use_tool(tool: int, charge: int) -> void:
	if world.current_area!=0 or world.transitioning or world.day_cycle.season==3:
		return
	_cancel()
	origin = cell_at(world.player.position)
	if tool < 6 or tool > 10:
		crops.use_tool(tool,charge,origin)
		return
	var level := clampi(charge,0,tool-6)
	pending = catalogue.patterns[str(world.player.facing)][level]
	step = 0
	step_limit = int(catalogue.step_limits[level])
	elapsed = 0
	owns_lock = not world.player.input_locked
	if owns_lock:
		world.player.input_locked = true
	_advance_step()

func _advance_step() -> void:
	if step>step_limit:
		_cancel()
		return
	if step<pending.size():
		var offset: Array = pending[step]
		var cell := origin+Vector2i(offset[0],offset[1])
		if cell.x>=0 and cell.x<45 and cell.y>=0 and cell.y<25:
			if not _till(cell):
				step = step_limit # Source: a refused dig ends all later steps.
	step += 1

func cell_at(point: Vector3) -> Vector2i:
	return Vector2i(floori((point.x+4.4)/0.399),floori((point.z+1.6)/0.399))

func cell_index(cell: Vector2i) -> int:
	return cell.y*45+cell.x if Rect2i(0,0,45,25).has_point(cell) else -1

func _till(cell: Vector2i) -> bool:
	var index := cell_index(cell)
	if index < 0 or crops.plants.has(index) or not plot_clear(cell):
		return false
	set_soil(index,WATERED if states[index]==WATERED else TILLED)
	return true

func plot_clear(cell: Vector2i) -> bool:
	var index := cell_index(cell)
	# Initial grid occupants and user-authored free prefabs both block the real plot.
	for record in world.loose_items.records[0]:
		if record.active and not record.get("free_position",false) and record.get("cell",-1)==index:
			return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.398,0.35,0.398)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1
	query.exclude = [world.player.get_rid()]
	query.transform = Transform3D(Basis.IDENTITY,Vector3(cell.x*0.4-4.2,0.2,cell.y*0.4-1.4))
	return world.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func set_soil(index: int, value: int) -> void:
	states[index] = value
	pixels[index] = 2 if value==WATERED else (1 if value==TILLED else 0)
	upload_soil()

func upload_soil() -> void:
	state_texture.update(Image.create_from_data(45,25,false,Image.FORMAT_R8,pixels))
	if material != null:
		material.set_shader_parameter("field_season",world.day_cycle.season)

func _cancel() -> void:
	step_limit = -1
	pending = []
	if owns_lock:
		if not world.transitioning:
			world.player.input_locked = false
		owns_lock = false

func _physics_process(delta: float) -> void:
	if step_limit<0 or world.transitioning:
		return
	elapsed += delta
	while elapsed+0.0000001>=1.0/30.0 and step_limit>=0:
		elapsed -= 1.0/30.0
		_advance_step()

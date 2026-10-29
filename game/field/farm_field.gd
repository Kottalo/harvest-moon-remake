extends Node
## Source hoe result steps and soil state; updates a tiny texture, never scene geometry.
const SOIL := 0x167
const TILLED := 0x168
const WATERED := 0x169
var world
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
	world.player.actions.tool_used.connect(use_tool)
	bind_location()

func bind_location() -> void:
	_cancel()
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
		material.set_shader_parameter("albedo_texture",texture)
		material.set_shader_parameter("tilled_texture",load(catalogue.tilled_texture))
		material.set_shader_parameter("watered_texture",load(catalogue.watered_texture))
		material.set_shader_parameter("field_states",state_texture)
		geometry.set_surface_override_material(surface,material)
		return
	push_error("Original farm field surface was not found")

func use_tool(tool: int, charge: int) -> void:
	if tool<6 or tool>10 or world.current_area!=0 or world.transitioning or world.day_cycle.season==3:
		return
	_cancel()
	var point: Vector3 = world.player.position
	origin = Vector2i(floori((point.x+4.4)/0.399),floori((point.z+1.6)/0.399))
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

func _till(cell: Vector2i) -> bool:
	var index := cell.y*45+cell.x
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
	if not world.player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		return false
	# field_request_dispatch keeps already-watered ground wet when hoed again.
	set_soil(index,WATERED if states[index]==WATERED else TILLED)
	return true

func set_soil(index: int, value: int) -> void:
	states[index] = value
	pixels[index] = 2 if value==WATERED else (1 if value==TILLED else 0)
	state_texture.update(Image.create_from_data(45,25,false,Image.FORMAT_R8,pixels))

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

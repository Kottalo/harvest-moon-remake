extends SceneTree
## Real Space-key hoe swings, source ranges and persistent soil; runs offscreen or headless.
var world
var field
var viewport: SubViewport
const COUNTS := [1,2,3,4,6]
const DIRECTIONS := [Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,0)]
const ORIGIN := Vector2i(20,12)

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
	await process_frame

func _require(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok

func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _reset() -> void:
	field._cancel()
	field.states.fill(field.SOIL)
	field.pixels.fill(0)
	field.state_texture.update(Image.create_from_data(45,25,false,Image.FORMAT_R8,field.pixels))
	world.player.position = Vector3(ORIGIN.x*0.399-4.2005,0.02,ORIGIN.y*0.399-1.4005)
	world.player.velocity = Vector3.ZERO
	world.player.reset_physics_interpolation()

func _settle_result() -> bool:
	for tick in range(Engine.physics_ticks_per_second*4):
		if not world.player.actions.busy() and field.step_limit<0:
			return true
		await _frames(1)
	return _require(false,"Hoe/result animation did not finish or input stayed locked")

func _swing(facing: int,level: int) -> bool:
	world.player.facing = facing
	var action = world.player.actions
	action.equipped = 6
	action.upgrade = level
	_key(true)
	await _frames(2)
	if not _require(action.state=="charge","Space did not start charging the hoe"): return false
	action.advance(level*20.0/30.0)
	if not _require(field.states.count(field.TILLED)==0,"Ground changed during charge instead of after the swing"): return false
	_key(false)
	await _frames(1)
	if not _require(action.state=="swing","Releasing Space did not start the source hoe swing"): return false
	return await _settle_result()

func _run() -> void:
	Engine.max_fps = 0
	if OS.get_cmdline_user_args().has("--120hz"):
		Engine.physics_ticks_per_second = 120
	world = load("res://game/world/world.tscn").instantiate()
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(world)
	await _frames(10)
	world.set_physics_process(false)
	world.day_cycle.set_process(false)
	world.day_cycle.tint.hide()
	field = world.farm_field
	# Clear the fixture field once; user game and prefab assets are untouched.
	for record in world.loose_items.records[0]:
		world.loose_items._remove(record)
	await _frames(2)
	var geometry_id: int = world.get_node("Location/Geometry").get_instance_id()
	var mesh_id: int = world.get_node("Location/Geometry").mesh.get_instance_id()
	var batch_id: int = world.loose_items.batches[58].mesh.get_instance_id()
	for facing in 4:
		for level in 5:
			_reset()
			await _frames(3)
			if not await _swing(facing,level): return
			if not _require(field.states.count(field.TILLED)==COUNTS[level],"Wrong source hoe length: "+str([facing,level,field.states.count(field.TILLED)])): return
			for distance in range(1,COUNTS[level]+1):
				var cell: Vector2i = ORIGIN+DIRECTIONS[facing]*distance
				if not _require(field.states[cell.y*45+cell.x]==field.TILLED,"Hoe affected wrong direction/cell"): return
			# Dummy rendering has no GPU texture readback; the isolated GPU run checks it.
			var uploaded: bool = DisplayServer.get_name()=="headless" or field.state_texture.get_image().get_data()==field.pixels
			if not _require(not world.player.input_locked and uploaded,"Result did not release input or upload soil pixels: "+str([world.player.input_locked,uploaded])): return
	print("HOE_INPUT_OK: ",Engine.physics_ticks_per_second," Hz; real Space down/up, four facings x five tiers, source lengths 1/2/3/4/6, no charge-time mutation")
	_reset()
	world.player.facing = 3
	var blocked := ORIGIN+Vector2i(2,0)
	var stone := {"id":58,"active":true,"cell":blocked.y*45+blocked.x,"position":Vector3(blocked.x*0.4-4.2,0,blocked.y*0.4-1.4)}
	world.loose_items.records[0].append(stone)
	world.loose_items._add_record(stone)
	await _frames(2)
	field.use_tool(10,4)
	if not await _settle_result(): return
	if not _require(field.states.count(field.TILLED)==1 and stone.active,"Charged hoe passed through a blocked plot or removed its item"): return
	world.loose_items._remove(stone)
	await _frames(2)
	field.use_tool(10,4)
	if not await _settle_result(): return
	if not _require(field.states.count(field.TILLED)==6,"Cleared obstruction still blocks hoe results"): return
	var first := (ORIGIN.y)*45+ORIGIN.x+1
	field.set_soil(first,field.WATERED)
	field.use_tool(6,0)
	if not await _settle_result(): return
	if not _require(field.states[first]==field.WATERED,"Re-hoeing wet soil dried it contrary to source"): return
	world.day_cycle.season = 3
	var before: PackedInt32Array = field.states.duplicate()
	field.use_tool(10,4)
	if not _require(field.step_limit<0 and field.states==before,"Winter hoe mutated outdoor soil"): return
	world.day_cycle.season = 0
	field.use_tool(10,4)
	world.transitioning = true
	field.bind_location()
	if not _require(world.player.input_locked and field.step_limit<0,"Cancelled hoe result released the world transition's input lock"): return
	world.transitioning = false
	world.player.input_locked = false # The transition owner releases its own lock.
	if not _require(world.get_node("Location/Geometry").get_instance_id()==geometry_id and world.get_node("Location/Geometry").mesh.get_instance_id()==mesh_id and world.loose_items.batches[58].mesh.get_instance_id()==batch_id,"Hoe rebuilt scene geometry or item batches"): return
	var spawn: Array = world.world["52"].spawn
	world._change_area(52,Vector3(spawn[0],spawn[1],spawn[2]))
	field.use_tool(10,4)
	if not _require(field.states==before and field.step_limit<0,"Hoe modified the farm from another area"): return
	world._change_area(0,Vector3(0,0,-2))
	await _frames(2)
	if not _require(field.states==before and field.material.get_shader_parameter("field_states")==field.state_texture,"Soil disappeared on leaving and returning to farm"): return
	print("HOE_STATE_OK: source stop-on-obstruction, clear/retry, wet-soil preservation, winter/other-area rejection, transition lock, persistent map return; geometry and batches never rebuilt")
	if DisplayServer.get_name()!="headless":
		if not await _gpu_effect(): return
	world.queue_free()
	await process_frame
	print("HOE_CHECK_OK")
	quit()

func _gpu_effect() -> bool:
	_reset()
	world.player.facing = 3
	world.player.actions.upgrade = 0
	world.player.actions.equipped = 6
	await _frames(3)
	world._update_camera()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var before := viewport.get_texture().get_image()
	before.save_png("res://verification/hoe_before.png")
	if not await _swing(3,0): return false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var after := viewport.get_texture().get_image()
	after.save_png("res://verification/hoe_after.png")
	world.player.hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	var cell := ORIGIN+Vector2i(1,0)
	var start := Vector3(cell.x*0.4-4.4,0,cell.y*0.4-1.6)
	var reference := MeshInstance3D.new()
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([start,start+Vector3(0.4,0,0),start+Vector3(0,0,0.4),start+Vector3(0.4,0,0),start+Vector3(0.4,0,0.4),start+Vector3(0,0,0.4)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(159.5,176.5)/256,Vector2(159.5,207.5)/256,Vector2(128.5,176.5)/256,Vector2(159.5,207.5)/256,Vector2(128.5,207.5)/256,Vector2(128.5,176.5)/256])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load(field.catalogue.tilled_texture)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mesh.surface_set_material(0,material)
	reference.mesh = mesh
	world.add_child(reference)
	world.get_node("Location/Geometry").hide()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var expected := viewport.get_texture().get_image()
	var changed := 0
	var worst := 0.0
	for z in [0.2,0.5,0.8]:
		for x in [0.2,0.5,0.8]:
			var pixel: Vector2i = world.camera.unproject_position(start+Vector3(x*0.4,0,z*0.4))
			var a := actual.get_pixelv(pixel)
			var b := expected.get_pixelv(pixel)
			var error := Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()
			worst = maxf(worst,error)
			var old := before.get_pixelv(pixel)
			if Vector3(a.r-old.r,a.g-old.g,a.b-old.b).length()>0.05: changed += 1
	if not _require(changed>=5 and worst<0.04,"Hoe ground effect is invisible or differs from source CLUT/UV: "+str([changed,worst])): return false
	print("HOE_GPU_OK: actual Space swing visibly changes ground; ",changed,"/9 samples differ; source tilled quad/CLUT pixel comparison max error=",worst)
	return true

extends SceneTree
## Actual Space swings, source mine UV/CLUT reference, single-cell/season/area rules.
var world
var viewport: SubViewport
func _initialize() -> void: run.call_deferred()
func require_ok(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func frames(count: int) -> void:
	var until := Engine.get_physics_frames()+count
	while Engine.get_physics_frames()<until:
		await physics_frame
		await process_frame
func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func count_dug(area: String) -> int:
	var count := 0
	for value in world.mine_field.states[area]:
		if value!=0: count += 1
	return count
func reference_pixels(area: String) -> bool:
	for frame in 3: await RenderingServer.frame_post_draw
	var actual := viewport.get_texture().get_image()
	actual.save_png("res://verification/"+str(world.world[area].slug)+"_dug.png")
	var vertices := PackedVector3Array([Vector3(0.4,0,0.4),Vector3(0.4,0,0.8),Vector3(0,0,0.4),Vector3(0.4,0,0.8),Vector3(0,0,0.8),Vector3(0,0,0.4)])
	var uv := PackedVector2Array()
	for point in [Vector2(131.5,31.5),Vector2(131.5,0.5),Vector2(159.5,31.5),Vector2(131.5,0.5),Vector2(159.5,0.5),Vector2(159.5,31.5)]: uv.append(point/256.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material := ShaderMaterial.new()
	material.shader = load("res://game/rendering/source_surface.gdshader")
	material.set_shader_parameter("albedo_texture",load(world.mine_field.catalogue[area].dug_texture))
	mesh.surface_set_material(0,material)
	var reference := MeshInstance3D.new()
	reference.mesh = mesh
	world.add_child(reference)
	world.get_node("Location/Geometry").hide()
	for frame in 3: await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var maximum := 0.0
	for z in [0.46,0.6,0.74]:
		for x in [0.06,0.2,0.34]:
			var pixel := Vector2i(world.camera.unproject_position(Vector3(x,0,z)))
			var a := actual.get_pixelv(pixel)
			var b := picture.get_pixelv(pixel)
			maximum = maxf(maximum,Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length())
	reference.free()
	world.get_node("Location/Geometry").show()
	print("MINE_GPU_SOURCE_QUAD_OK: area=",area," nine sample RGB max delta=",maximum)
	return require_ok(maximum<0.02,"Mine digging does not match the original retextured FT4/CLUT")
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	viewport = SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_physics_process(false)
	var farm_before: PackedInt32Array = world.farm_field.states.duplicate()
	for area in [234,245]:
		world._change_area(area,Vector3(0.2,0.01,0.2))
		world.day_cycle.season = 3 # Mine digging is valid in winter too.
		var geometry: MeshInstance3D = world.get_node("Location/Geometry")
		var original_mesh := geometry.mesh.get_rid()
		var texture: ImageTexture = world.mine_field.textures[str(area)]
		for facing in 4:
			world.player.facing = facing
			world.player.actions.equipped = 6
			world.player.actions.upgrade = 0
			await frames(3)
			key(true)
			await frames(2)
			key(false)
			for tick in Engine.physics_ticks_per_second*2:
				if not world.player.actions.busy(): break
				await frames(1)
			var index: int = [65,54,45,56][facing]
			if not require_ok(world.mine_field.states[str(area)][index]==255 and count_dug(str(area))==facing+1,"Physical Space hoe did not dig exactly the source-facing cell: "+str([area,facing])): return
			if facing==0 and DisplayServer.get_name()!="headless":
				if not await reference_pixels(str(area)): return
		if not require_ok(geometry.mesh.get_rid()==original_mesh and world.mine_field.textures[str(area)]==texture,"Digging rebuilt the mine mesh or state texture"): return
		world.player.position = Vector3(-0.2,0.01,-0.2)
		world.player.facing = 2
		world.mine_field.use_tool(10,4)
		world.mine_field.use_tool(10,4)
		if not require_ok(count_dug(str(area))==5,"A charged hoe dug multiple mine cells or repeat digging duplicated state"): return
		var wall := StaticBody3D.new()
		wall.position = Vector3(1,0.2,0.2)
		wall.collision_layer = 1
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.4,0.4,0.4)
		collision.shape = shape
		wall.add_child(collision)
		world.add_child(wall)
		wall.force_update_transform()
		collision.force_update_transform()
		world.player.position = Vector3(0.6,0.01,0.2)
		world.player.facing = 3
		world.mine_field.use_tool(6,0)
		if not require_ok(count_dug(str(area))==5,"Mine digging ignored a real obstruction"): return
		wall.free()
		world.player.position = Vector3(1.8,0.01,0.2)
		world.mine_field.use_tool(6,0)
		world.mine_field.use_tool(16,0)
		if not require_ok(count_dug(str(area))==5,"Mine digging accepted outside-grid coordinates or another tool"): return
		world._change_area(0,Vector3.ZERO)
		world._change_area(area,Vector3(0.2,0.01,0.2))
		if not require_ok(count_dug(str(area))==5 and world.mine_field.textures[str(area)]==texture,"Mine dig cells did not persist on reload"): return
		print("MINE_DIG_AREA_OK: ",area," four facings, real Space, single-cell charged action, winter, blockers/bounds, repeat/reload, stable mesh/texture")
	world._change_area(68,Vector3.ZERO)
	if not require_ok(world.mine_field.states.is_empty(),"Leaving through an original outdoor entrance did not reset the mine visit"): return
	world._change_area(234,Vector3(0.2,0.01,0.2))
	if not require_ok(count_dug("234")==0,"A fresh mine visit retained the prior visit's dig cells"): return
	if not require_ok(world.farm_field.states==farm_before,"Mine digging changed farm soil state"): return
	print("MINE_DIG_OK: ",Engine.physics_ticks_per_second," Hz; both native mines retain independent original dug-cell state")
	viewport.free()
	quit()

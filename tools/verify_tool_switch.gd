extends SceneTree
## Physical A input: original show-tool body/mark, ten source ticks, no tool-use effect.
var world
var effects := 0
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
func key(code: int,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	world.set_physics_process(false)
	world.player.position = Vector3(0,0.05,-2)
	await frames(10)
	var action = world.player.actions
	for tool in action.TOOL_IDS:
		world.economy.stock[tool] = 1
	action.tool_used.connect(func(_tool,_level): effects += 1)
	var checks := 0
	for facing in 4:
		for index in action.TOOL_IDS.size():
			action.equipped = action.TOOL_IDS[posmod(index-1,action.TOOL_IDS.size())]
			var bag = world.economy.rucksack
			bag.next_tool = 0
			bag.tools[0] = action.selected_seed if action.TOOL_IDS[index]==34 else action.TOOL_IDS[index]
			bag.tools[1] = 0
			action.upgrade = index%5
			world.player.facing = facing
			var before: Vector3 = world.player.position
			var began := Engine.get_physics_frames()
			key(KEY_A,true)
			await frames(1)
			key(KEY_A,false)
			await frames(1)
			var id: int = action.equipped+action.upgrade if action.equipped<=25 else action.equipped
			if not require_ok(action.state=="show_tool" and action.bank=="base" and action.range_id==71 and action.frame==facing and action.equipped==action.TOOL_IDS[index],"A did not select and play original show-tool range"): return
			if not require_ok(action.held_sprite.visible and action.held_sprite.texture.resource_path==action.data.tool_pictures[str(id)] and action.held_sprite.offset==Vector2(-8,59) and action.held_sprite.material_override.get_shader_parameter("sort_bias")<0,"Tool picture, body-relative offset or front layering is wrong"): return
			key(KEY_RIGHT,true)
			if facing==0 and index==1 and DisplayServer.get_name()!="headless":
				for frame in 2: await RenderingServer.frame_post_draw
				viewport.get_texture().get_image().save_png("res://verification/tool_switch_pose.png")
			var moved_while_busy := false
			while action.busy():
				await frames(1)
				if action.busy() and Vector2(world.player.position.x-before.x,world.player.position.z-before.z).length()>0.002: moved_while_busy = true
			key(KEY_RIGHT,false)
			var seconds := float(Engine.get_physics_frames()-began)/Engine.physics_ticks_per_second
			if not require_ok(seconds>=0.3 and seconds<=0.37 and not moved_while_busy and not action.held_sprite.visible,"Showing tool has wrong duration, allows motion or leaves picture visible: "+str([seconds,world.player.position,before])): return
			checks += 1
	# All metal-tier icons must be distinct, hydrated native images; carry/input lock refuse A.
	for id in range(1,26):
		if not require_ok(ResourceLoader.exists(action.data.tool_pictures[str(id)]),"Missing metal-tier tool picture"): return
	for locked in [false,true]:
		action.carried_id = 58 if not locked else 0
		world.player.input_locked = locked
		var previous: int = action.equipped
		key(KEY_A,true)
		await frames(2)
		key(KEY_A,false)
		await frames(2)
		if not require_ok(action.equipped==previous and not action.busy(),"A switched while carrying or input-locked"): return
	world.player.input_locked = false
	action.carried_id = 0
	var picker = world.tool_picker
	_picker_key(viewport,KEY_I)
	await process_frame
	if not require_ok(paused and picker.panel.visible and picker.entries.size()==35
			and picker.tabs.current_tab==1,"I did not open the modal on the equipped seed tab"): return
	for id in picker.entries:
		var button: Button = picker.entries[id]
		if not require_ok(button.icon != null and button.icon.get_width() in [16,36],"Picker icon is missing or includes its transparent source canvas: "+str(id)): return
	_picker_key(viewport,KEY_F1)
	if not require_ok(paused and picker.panel.visible and not world.day_cycle.debug_panel.panel.visible,"Picker let another pause menu open"): return
	_picker_key(viewport,KEY_TAB)
	if not require_ok(picker.tabs.current_tab==0,"Tab did not switch to tools"): return
	await process_frame
	var can: Button = picker.entries[21]
	if not require_ok(viewport.get_visible_rect().encloses(can.get_global_rect()),"Tool grid is clipped at the gameplay resolution"): return
	for pressed in [true,false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		click.position = can.get_global_rect().get_center()
		viewport.push_input(click,true)
	await frames(2)
	if not require_ok(not paused and not picker.panel.visible and action.equipped==21
			and action.state=="show_tool" and action.range_id==71,"Picker failed to equip the watering can with the source pose"): return
	while action.busy(): await frames(1)
	_picker_key(viewport,KEY_I)
	_picker_key(viewport,KEY_TAB)
	picker.entries[54].pressed.emit()
	await frames(2)
	if not require_ok(not paused and action.equipped==34 and action.selected_seed==54
			and action.state=="show_tool" and action.held_sprite.texture==action.tool_picture(34,54),"Picker failed to equip grass with its own seed bag"): return
	while action.busy(): await frames(1)
	_picker_key(viewport,KEY_I)
	_picker_key(viewport,KEY_ESCAPE)
	if not require_ok(not paused and not picker.panel.visible and action.selected_seed==54 and not action.busy(),"Cancel altered the selection or left the game paused"): return
	action.carried_id = 58
	_picker_key(viewport,KEY_I)
	if not require_ok(not paused and not picker.panel.visible,"I opened while carrying an item"): return
	if not require_ok(effects==0 and world.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and not debug_collisions_hint,"Switching used a tool, changed the orthographic camera or enabled colliders"): return
	print("TOOL_SWITCH_OK: ",Engine.physics_ticks_per_second," Hz; ",checks," physical A selections/facings, source 0x47 pose and ten-tick hold, correct item PNG/offset/front order, input lock, no tool effects; orthographic/no debug colliders; modal tool and seed selection, icon crop, tabs, pause and cancellation")
	viewport.free()
	quit()

func _picker_key(viewport: Viewport, code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	viewport.push_input(event,true)

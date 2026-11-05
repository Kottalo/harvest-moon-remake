extends SceneTree
## Exercise the native runtime and physical desktop keys.
var world

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tick(count := 1) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func tap(code: Key) -> void:
	key(code,true)
	await tick(2)
	key(code,false)
	await tick(2)

func run() -> void:
	var capture := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			capture = argument.trim_prefix("--capture=")
	if not capture.is_empty():
		if not check(DisplayServer.get_name()!="headless","Backpack screenshots require the isolated GPU runner"): return
		root.size = Vector2i(960,720)
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	await tick(10)
	var player = world.player
	var actions = player.actions
	var economy = world.economy
	var menu = world.rucksack_menu
	for code in [KEY_W,KEY_A,KEY_S,KEY_D]:
		key(code,true)
		if not check(Input.get_vector("move_left","move_right","move_up","move_down")==Vector2.ZERO,"WASD still drives movement"): return
		key(code,false)
	key(KEY_RIGHT,true)
	if not check(Input.is_action_pressed("move_right"),"Arrow does not drive movement"): return
	key(KEY_SHIFT,true)
	if not check(not Input.is_action_pressed("run"),"Shift still starts running"): return
	key(KEY_SHIFT,false)
	key(KEY_X,true)
	if not check(Input.is_action_pressed("run") and Input.is_action_pressed("ui_cancel"),"X is not shared by running and cancel"): return
	key(KEY_X,false)
	key(KEY_RIGHT,false)
	if not check(menu.marks!=null and menu.icons[0]!=null and menu.icons[1]!=null and menu.icons[2]!=null,"The default bag assets were not warmed before the first Space"): return
	var cached_icons: int = menu.icon_cache.size()
	var opened_at := Time.get_ticks_usec()
	key(KEY_SPACE,true)
	var open_usec := Time.get_ticks_usec()-opened_at
	await tick(2)
	key(KEY_SPACE,false)
	await tick(2)
	print("RUCKSACK_OPEN_CPU: ",open_usec," us")
	if not check(menu.panel.visible and paused and menu._slot_visible(1) and not menu._slot_visible(3),"Space did not open the original two-slot bag"): return
	if not check(menu.detail.text.count("\n")==3 and not world.hud.visible and not world.day_cycle.clock_label.visible,"The original help and shaded field were not shown"): return
	if not check(menu.frame.size==Vector2(320,240) and menu.marks.get_size()==Vector2(616,36),"Original screen coordinates or sprite atlas are missing"): return
	if not check(menu.icon_cache.size()==cached_icons,"Opening the default bag loaded additional icons"): return
	var scale_factor: float = menu.frame.scale.y
	if not check(menu.detail.get_parent()==menu.panel and menu.detail.scale==Vector2.ONE
			and menu.detail.get_theme_font_size("font_size")==roundi(10*scale_factor),"Text inherits pixel-art scaling"): return
	var help_bottom: float = menu.frame.position.y+226*scale_factor
	if not check(menu.detail.position.y+menu.detail.get_minimum_size().y<=help_bottom,"Localized help overflows the original bottom frame"): return
	var marks := Image.new()
	if not check(marks.load_png_from_buffer(FileAccess.get_file_as_bytes("res://game/items/rucksack_marks.png"))==OK,"Original marks PNG could not be read"): return
	var ring := Rect2(marks.get_region(Rect2i(0,0,44,36)).get_used_rect())
	var hand := Rect2(marks.get_region(Rect2i(44,0,44,36)).get_used_rect())
	if not check((ring.get_center()-Vector2(10,0)+menu.SELECTION_OFFSET).is_equal_approx(menu.SLOT_SIZE*0.5)
			and is_equal_approx(hand.get_center().x-10+menu.CURSOR_OFFSET.x,menu.SLOT_SIZE.x*0.5),"Ring or cursor is off-centre relative to the original slot"): return
	if not capture.is_empty():
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		if not check(screenshot!=null and screenshot.save_png(capture)==OK,"Could not save isolated backpack screenshot"): return
	await tap(KEY_C)
	if not check(menu.explaining and menu.detail.text.contains("锄头"),"C did not open the original item explanation panel"): return
	await tap(KEY_X)
	if not check(menu.panel.visible and not menu.explaining,"X did not return from item explanation"): return
	await tap(KEY_RIGHT)
	if not check(menu.cursor==1,"Original directional links did not select first tool slot"): return
	await tap(KEY_Z)
	if not check(menu.marked==1,"Z did not mark the selected tool"): return
	await tap(KEY_X)
	if not check(menu.marked==-1 and paused,"X did not cancel the marked tool"): return
	await tap(KEY_Z)
	await tap(KEY_Z)
	if not check(actions.equipped==1 and economy.rucksack.tools[0]==6,"Z swap did not move the original held tool into the bag"): return
	await tap(KEY_SPACE)
	if not check(not paused and not menu.panel.visible and world.hud.visible and world.day_cycle.clock_label.visible,"Space did not close backpack"): return
	economy.rucksack.next_tool = 0
	await tap(KEY_A)
	if not check(actions.equipped==6 and actions.state=="show_tool","A did not quick-switch to the stored tool"): return
	await tick(30)
	await tap(KEY_C)
	if not check(actions.busy(),"C did not use the equipped tool"): return
	await tick(90)

	if not check(economy.rucksack.add_item(124) and economy.rucksack.add_item(65) and not economy.rucksack.add_item(66),"Backpack capacity did not prevent overflow"): return
	actions.carried_id = 66
	world._interact()
	if not check(actions.carried_id==66 and economy.count(66)==0,"A full bag discarded the held item"): return
	await tap(KEY_SPACE)
	await tap(KEY_DOWN)
	await tap(KEY_RIGHT)
	await tap(KEY_Z)
	await tap(KEY_Z)
	if not check(actions.carried_id==124 and economy.count(66)==1 and menu.icons[9]!=null,"Swap with the hand did not show the original ore icon"): return
	await tap(KEY_X)
	if not check(not paused,"X did not close the unmarked menu"): return

	world._change_area(180,Vector3.ZERO)
	economy.gold = 10000
	if not check(economy.buy("jeff",153)=="背包已满。" and economy.gold==10000,"Full-bag purchase spent money"): return
	if not check(economy.buy("jeff",109).begins_with("已购买") and economy.rucksack.capacity==4,"First original backpack upgrade did not unlock four cells"): return
	if not check(not economy.buy("jeff",110).begins_with("已购买"),"Large bag was available during the original delivery timer"): return
	for day in 10:
		world.day_cycle.day_started.emit(0)
	if not check(economy.buy("jeff",110).begins_with("已购买") and economy.rucksack.capacity==8,"Second original backpack upgrade did not unlock eight cells"): return
	print("RUCKSACK_OK: Space, original D-pad cells, Z swap, X cancel, C tool, A switch, WASD ignored, full inventory and 2/4/8 upgrades")
	quit()

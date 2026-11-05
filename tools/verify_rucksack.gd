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
	key(KEY_RIGHT,false)
	await tap(KEY_SPACE)
	if not check(menu.panel.visible and paused and menu.buttons[1].visible and not menu.buttons[3].visible,"Space did not open the original two-slot bag"): return
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
	if not check(not paused and not menu.panel.visible,"Space did not close backpack"): return
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
	if not check(actions.carried_id==124 and economy.count(66)==1 and menu.buttons[9].icon!=null,"Swap with the hand did not show the original ore icon"): return
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

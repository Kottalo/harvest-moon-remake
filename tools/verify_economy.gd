extends SceneTree
## Transactions through the source counter, original shop data, and live world.
var world

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, detail: String) -> bool:
	if not condition:
		push_error(detail)
		quit(1)
	return condition

func click(label: String) -> bool:
	for button: Button in world.npcs.dialogue.choices_panel.get_children():
		if button.text.begins_with(label):
			button.pressed.emit()
			return true
	return check(false,"Missing choice: "+label)

func _frames(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame

func _press(code: Key) -> void:
	for pressed in [true,false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await _frames(2)

func run() -> void:
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.day_cycle.minute = 10*60
	world._change_area(180,Vector3(0.19,0,1.2))
	for tick in 120:
		if world.npcs.active.has("jeff") and world.npcs.active.jeff.placed:
			break
		await physics_frame
	var economy = world.economy
	var player = world.player
	player.facing = 2
	if not check(world.npcs.active.has("jeff") and economy.counter_actor()==world.npcs.active.jeff,"Source grocery counter cannot find Jeff"): return
	world._interact()
	var labels: Array = economy.dialogue.choices_panel.get_children().map(func(button): return button.text)
	if not check(labels.has("交谈"),"The normal shop menu lost the AI conversation option"): return
	var shop = economy.shop_menu
	if not click("购买商品") or not check(shop.overlay.visible and not economy.dialogue.overlay.visible
			and paused and shop.products.has(34) and not world.hud.visible,"Counter did not open a dedicated purchase list"): return
	shop.products[34].grab_focus()
	await _press(KEY_Z)
	if not check(economy.gold==380 and economy.count(34)==2 and shop.products[34].has_focus()
			and shop.balance.text.contains("380") and shop.feedback.text.begins_with("已购买"),
			"Keyboard purchase did not update price, balance, feedback or focus"): return
	await _press(KEY_X)
	if not check(not shop.overlay.visible and paused and economy.dialogue.overlay.visible,
			"X did not return to the shopkeeper options"): return
	economy.dialogue.close()
	var display = economy.supermarket
	if not check(display.sprites.size()==13 and display.sprites[0].visible and not display.sprites[1].visible,
			"Supermarket is missing the source shelf displays or shows off-season seeds"): return
	player.position = Vector3(0,0,1.25)
	player.facing = 2
	world._interact()
	if not check(shop.overlay.visible and shop.products.has(34) and not shop.products.has(154),
			"Selecting a seed stand did not open only the goods on that display"): return
	await _press(KEY_X)
	if not check(not shop.overlay.visible and not paused and world.hud.visible,
			"Closing a shelf purchase list did not resume gameplay"): return
	player.position = Vector3(1.061,0,0.6)
	player.facing = 3
	world._interact()
	await _frames(2)
	if not check(shop.overlay.visible and shop.products.size()==1 and shop.products.has(100)
			and shop.scroll.custom_minimum_size.y==shop.ROW_HEIGHT and not shop.scroll.get_v_scroll_bar().visible
			and root.get_visible_rect().encloses(shop.panel.get_global_rect()),
			"The basket shelf did not use the compact single-product layout"): return
	var icon: TextureRect = shop.products[100].find_child("Icon",true,false)
	if not check(icon.texture!=null,"The basket row did not display the original item art"): return
	var price: Label = shop.products[100].find_child("Price",true,false)
	if not check(price.text=="5000 G" and price.horizontal_alignment==HORIZONTAL_ALIGNMENT_RIGHT
			and price.get_theme_color("font_color")==shop.REFUSAL_INK,
			"The basket price was not right-aligned and marked unaffordable"): return
	await _press(KEY_Z)
	if not check(economy.gold==380 and economy.count(100)==0 and shop.feedback.text.contains("钱不够")
			and shop.products[100].has_focus(),"Unaffordable basket purchase changed cash or lost focus"): return
	await _press(KEY_X)
	world.day_cycle.season = 1
	display.refresh()
	if not check(not display.sprites[0].visible and display.sprites[1].visible,"Seasonal stand visibility failed to change"): return
	if not check(economy.goods_for("jeff").has(39) and not economy.goods_for("jeff").has(34),"Grocery season did not change seeds"): return
	if not check(not economy.buy("jeff",109).begins_with("已购买") and economy.gold==380,"Unaffordable purchase changed cash"): return

	world._change_area(0,Vector3(-4.68,0,-3.02))
	player.facing = 1
	economy.rucksack.add_item(65)
	if not check(economy.shipping_near(),"Farm shipping interaction is inaccessible"): return
	world._interact()
	if not click("芜菁") or not check(economy.shipped_value==60 and economy.gold==380,"Shipping removed stock without recording native price"): return
	economy.dialogue.close()
	world.day_cycle.minute = 17*60+57
	world.day_cycle._tick_minute()
	if not check(economy.gold==440 and economy.shipped_value==0,"Shipping did not pay once at native cutoff"): return

	var fish = economy.fishing
	if not check(not player.actions.owns_tool(56),"Fishing rod was usable before receiving it"): return
	economy.stock[56] = 1
	if not check(player.actions.owns_tool(56),"Received fishing rod is unusable"): return
	fish._water_ahead()
	var polygon: Array = fish.source.water["0"]
	var water := Vector3((polygon[0]+polygon[2]+polygon[4])/3000.0,0,(polygon[1]+polygon[3]+polygon[5])/3000.0)
	player.position = water+Vector3.RIGHT*1.4
	player.facing = 1
	if not check(fish._water_ahead()!=Vector3.INF,"Source farm fishing surface was not recognized"): return
	fish.source.catches["4"] = [100,163]
	fish.pull = 0.1
	player.actions.tool_used.emit(56,0)
	if not check(economy.count(163)==1,"Reeling in a bite did not add the fish"): return

	world._change_area(234,Vector3(0.2,0.01,0.2))
	if not check(PackedInt32Array(world.mine_field.loot["234"].events)==PackedInt32Array([0,102,312,124,123,122,96,103]),"Spring mine does not use the native order of finds"): return
	world.mine_field.ladder = Vector2i(5,5)
	var marker := Label3D.new()
	world.get_node("Location").add_child(marker)
	world.mine_field.ladder_marker = marker
	if not check(world.mine_field.descend() and world.mine_field.depth==1,"Dug ladder cannot descend to the next loot table"): return

	# A deterministic copper roll through the real hoe, held pose and throw controls.
	world._change_area(234,Vector3(0.2,0.01,0.2))
	world.mine_field.loot["234"] = {"events":[124],"weights":[[100]]}
	player.facing = 0
	player.actions.equipped = 6
	player.actions.upgrade = 0
	await _frames(4)
	await _press(KEY_C)
	var showed_ore := false
	for tick in 100:
		await _frames(1)
		showed_ore = showed_ore or player.actions.pending_item==124
		if player.actions.carried_id==124:
			break
	if not check(showed_ore and player.actions.carried_id==124 and economy.count(124)==0,
			"Dug ore bypassed the held pose or was put in the bag"): return
	await _press(KEY_C)
	if not check(player.actions.carried_id==124 and not player.actions.busy(),"C released the held ore"): return
	await _press(KEY_Z)
	var flew := false
	for tick in 100:
		await _frames(1)
		if not world.loose_items.flights.is_empty():
			flew = true
			var ore: Dictionary = world.loose_items.flights[0]
			if not check(ore.item==124 and ore.node.get_child(0).texture==player.actions.item_picture(124),
					"Thrown ore used the wrong picture"): return
		elif flew:
			break
	if not check(flew and world.loose_items.flights.is_empty() and player.actions.carried_id==0
			and economy.count(124)==0 and economy.message=="丢弃了铜矿石","Throw did not clear the ore at landing"): return
	world.mine_field.exit_chance = 0
	player.facing = 1
	await _press(KEY_C)
	await _frames(75)
	if not check(player.actions.carried_id==124,"Second mined ore did not return to the hand"): return
	economy.rucksack.items[0] = 0
	economy.rucksack.items[1] = 163
	var stow_cues: Array[String] = []
	player.actions.sound_requested.connect(func(cue: String): stow_cues.append(cue))
	await _press(KEY_S)
	if not check(player.actions.state=="stow" and player.actions.range_id==0x1D+player.facing
			and player.actions.carried_id==124 and not player.actions.held_sprite.visible
			and economy.count(124)==0 and stow_cues==["stow"],
			"S did not begin the original stow pose, sound and delayed transfer"): return
	await _frames(42)
	if not check(player.actions.carried_id==0 and not player.actions.busy()
			and economy.rucksack.items.slice(0,2)==[163,124] and economy.count(124)==1
			and stow_cues==["stow"],"S did not compact the backpack and store exactly one copper ore"): return
	await _press(KEY_S)
	if not check(player.actions.carried_id==163 and player.actions.state=="pickup"
			and player.actions.range_id==0x0B+player.facing and player.actions.held_sprite.visible
			and economy.rucksack.items.slice(0,2)==[124,0] and stow_cues==["stow","show_item"],
			"Empty-hand S did not take out and show the first item"): return
	await _frames(45)
	if not check(player.actions.carried_id==163 and not player.actions.busy() and economy.count(163)==0,
			"The pickup pose lost or duplicated the withdrawn item"): return
	await _press(KEY_S)
	await _frames(42)
	if not check(player.actions.carried_id==0 and economy.rucksack.items.slice(0,2)==[124,163]
			and stow_cues==["stow","show_item","stow"],"Stowing again did not rotate the bag in R2 order"): return

	world.day_cycle.minute = 11*60
	world._change_area(156,Vector3.ZERO)
	if not check(world.npcs.active.has("saibara"),"Blacksmith service is bound to the wrong original area"): return
	economy.gold = 20000
	if not check(not economy.upgrade_tool(6,1).begins_with("赛巴拉收下") and economy.gold==20000,"Untrained upgrade changed cash"): return
	economy.experience[6] = 6000
	if not check(economy.upgrade_tool(6,1).begins_with("赛巴拉收下") and economy.gold==19000 and economy.count(124)==0 and player.actions.service_tool==6,"Tool order did not reserve the tool and payment"): return
	for day in 2:
		world.day_cycle.day_started.emit(0)
	if not check(economy.collect_upgrade()=="升级完成。" and economy.levels[6]==1 and player.actions.upgrade==1,"Forged tool did not become available after the order"): return

	world.day_cycle.weekday = 0
	world._change_area(136,Vector3.ZERO)
	if not check(world.npcs.active.has("barley"),"Ranch service is bound to the wrong original area"): return
	if not check(economy.buy("barley",353).begins_with("已购买") and economy.buy("barley",357).begins_with("已购买"),"Ranch cannot sell cows and sheep"): return
	world._change_area(128,Vector3.ZERO)
	if not check(world.npcs.active.has("lillia"),"Poultry service is bound to the wrong original area"): return
	if not check(economy.buy("lillia",265).begins_with("已购买") and economy.buy("lillia",105).begins_with("已购买"),"Poultry farm cannot sell chickens and feed"): return
	world._change_area(96,Vector3.ZERO)
	if not check(economy.livestock.visible_animals.size()==2,"Purchased cow and sheep are missing from the barn"): return
	world._change_area(112,Vector3(-0.85,0,0.99))
	player.facing = 2
	if not check(economy.livestock.visible_animals.size()==1 and economy.livestock.interact(),"Purchased chicken is missing from the coop"): return
	if not click("喂食") or not check(economy.animals[2].fed and economy.count(105)==0,"Feeding failed to use purchased chicken feed"): return
	economy.dialogue.close()
	world.day_cycle.day_started.emit(0)
	if not check(economy.livestock.interact(),"Chicken is no longer reachable after dawn"): return
	if not click("捡鸡蛋") or not check(economy.count(134)==1 and economy.gold==7500-economy.buy_price(105),"Production or original animal pricing mismatch"): return
	economy.dialogue.close()
	print("ECONOMY_OK: original counter, seasonal stock, shipping, fishing, mine ladder, blacksmith order, three animal purchases, feed and eggs")
	quit()

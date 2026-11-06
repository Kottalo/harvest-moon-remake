extends SceneTree
## Exercises the original schedule catalogue through normal world entry and clock updates.

class TestPi extends "res://game/npc/dialogue/pi_agent.gd":
	var last_messages: Array
	var prompt: Dictionary
	var memory: String
	var problem := ""
	var sent_prompts: Array[Dictionary] = []
	var fail_speaker := ""
	var hold := false

	func ask(messages: Array) -> void:
		last_messages = messages
		prompt = JSON.parse_string(messages.back().content)
		memory = JSON.stringify(prompt.memory)
		sent_prompts.append({"context":messages[0].content,"memory":memory})
		if not fail_speaker.is_empty() and messages[0].content.contains("角色："+fail_speaker+"。"):
			answered.emit("","第二个角色断线")
			return
		if not problem.is_empty():
			answered.emit("",problem)
			return
		if not hold:
			finish()

	func finish() -> void:
		partial.emit("今天想")
		partial.emit("今天想尝点什么？")
		answered.emit("今天想尝点什么？","")



func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


func tap_enter() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.physical_keycode = KEY_ENTER
	event.pressed = true
	root.push_input(event,true)
	var released := event.duplicate() as InputEventKey
	released.pressed = false
	root.push_input(released,true)


func run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_process(false)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	var npc = world.npcs
	var clock = world.day_cycle
	var data: Dictionary = npc.library.catalogue
	if not check(data.actors.size()==32 and data.helpers.size()==7,"Ordinary NPC roster is incomplete"):
		return
	for name in data.actors:
		if not await see_villager(world,name,data.actors[name],data.routes):
			return
	var dialogue = npc.dialogue
	dialogue.client.free()
	var transport := TestPi.new()
	dialogue.client = transport
	dialogue.add_child(transport)
	transport.partial.connect(dialogue._on_partial)
	transport.answered.connect(dialogue._on_answer)

	world._change_area(80,Vector3.ZERO)
	tap_enter()
	if not check(dialogue.composer.visible and dialogue.entry.has_focus() and transport.sent_prompts.is_empty(),
			"Enter did not focus the composer without an NPC or attempted an API call"):
		return
	dialogue.entry.text = "出门吧。"
	tap_enter()
	if not check(dialogue.bubbles.player.label.text=="出门吧。" and not dialogue.entry.has_focus()
			and world.history.entries.back().known_by==PackedStringArray(["player"]) and transport.sent_prompts.is_empty(),
			"Enter did not submit local speech without an NPC"):
		return

	clock.season = 0
	clock.weekday = 1
	clock.minute = 479
	world._change_area(180,Vector3(-100,0,-100))
	if not check(not npc.active.has("jeff"),"Jeff appeared in the shop before his shift"):
		return
	clock.minute = 480
	npc.update(0.0)
	if not check(npc.active.has("jeff"),"Jeff did not enter the shop at 08:00"):
		return
	var jeff = npc.active.jeff
	for tick in 40:
		if jeff.placed:
			break
		await physics_frame
	npc.update(0.2)
	if not check(not npc.player_arrivals.has("jeff"),"Jeff noticed a player outside his range"):
		return
	world.player.global_position = jeff.global_position+Vector3(0.25,0,0)
	jeff.walking = false
	jeff.facing = 1
	npc.update(0.2)
	if not check(npc.player_arrivals.has("jeff") and jeff.facing==3 and transport.sent_prompts.is_empty(),
			"Entering Jeff's sight did not register and turn him, or used a model request"):
		return
	jeff.facing = 1
	npc.update(0.2)
	if not check(jeff.facing==1,"Staying in sight repeatedly triggered the arrival"):
		return
	tap_enter()
	dialogue.entry.text = "杰夫，早上好。"
	tap_enter()
	if not check(dialogue.composer.visible and dialogue.bubbles.has("jeff")
			and transport.sent_prompts.size()==1 and transport.prompt.message=="杰夫，早上好。"
			and transport.last_messages[0].content.contains("你刚注意到玩家走近")
			and transport.last_messages[0].content.contains("你在杂货店")
			and transport.last_messages[0].content.contains("你在这里的职责是经营杂货店"),
			"Jeff did not receive his current shop and duty"):
		return
	dialogue.close()
	world.player.global_position = Vector3(-100,0,-100)
	npc.update(0.2)
	if not check(not npc.player_arrivals.has("jeff"),"Leaving sight retained Jeff's current awareness"):
		return
	var offscreen: Dictionary = npc.presence("rick")
	if not check(npc.presence("jeff").live and not offscreen.live and offscreen.area>=0 and offscreen.point.is_finite(),
			"Presence did not distinguish a live actor from an offscreen scheduled point"):
		return
	clock.minute = 840
	npc.update(0.0)
	for tick in 45:
		await physics_frame
	var karen = npc.active.karen
	var anna = npc.active.anna
	if not check(karen.placed and anna.placed,"The source store visitors failed to spawn"):
		return
	karen.global_position = Vector3(0.2,0,1.2)
	anna.global_position = Vector3(0.65,0,1.2)
	await physics_frame
	world.player.global_position = karen.global_position+Vector3(-0.25,0,0)
	dialogue.begin(karen)
	var shop_context: String = transport.last_messages[0].content
	if not check(shop_context.contains("安娜（就在你东南侧）") and shop_context.contains("杰夫")
			and not shop_context.contains("里克（"),"Karen did not know the nearby visitor and shopkeeper without leaking Rick's remote location"):
		return
	var divider := StaticBody3D.new()
	var divider_collision := CollisionShape3D.new()
	var divider_box := BoxShape3D.new()
	divider_box.size = Vector3(0.1,1.2,0.18)
	divider_collision.shape = divider_box
	divider.add_child(divider_collision)
	world.get_node("Location").add_child(divider)
	divider.global_position = Vector3(0.425,0.4,1.2)
	divider.force_update_transform()
	await physics_frame
	dialogue._submit("店里还有谁？")
	shop_context = transport.last_messages[0].content
	if not check(shop_context.get_slice("没看清他们的站位：",1).contains("安娜")
			and not shop_context.contains("安娜（就在你东南侧）") and not npc.people_near(karen).has("anna"),
			"Occlusion did not separate shop presence, exact position and conversation audience"):
		return
	divider.free()
	dialogue.close()
	clock.minute = 1080
	npc.update(0.0)
	if not check(not npc.active.has("jeff"),"Jeff stayed in the shop after leaving"):
		return

	clock.minute = 420
	world._change_area(36,Vector3(-100,0,-100))
	var basil = npc.active["basil"]
	for tick in 35:
		if basil.placed:
			break
		await physics_frame
	var start: Vector3 = basil.global_position
	var walk_frames := {}
	for tick in 150:
		await physics_frame
		if basil.walking:
			walk_frames[basil.sprite.texture] = true
			if basil.global_position.distance_to(start)>0.3 and walk_frames.size()>3:
				break
	if not check(basil.placed and basil.global_position.distance_to(start)>0.3 and walk_frames.size()>3,
			"Basil did not walk and animate on his source morning route"):
		return
	world.player.global_position = basil.global_position+Vector3(0.25,0,0)
	dialogue.begin(basil)
	dialogue._submit("你在哪儿？刚才在做什么？")
	if not check(dialogue.composer.visible and not basil.walking
			and transport.last_messages[0].content.contains("你在图书馆街区。打招呼前，你正沿这里的路线走动")
			and not transport.last_messages[0].content.contains("你在这里的职责"),
			"Stopping to greet lost Basil's actual place or walking activity"):
		return
	dialogue.close()

	clock.minute = 360
	world._change_area(204,Vector3(-100,0,-100))
	if not check(not npc.active.has("kai"),"Kai appeared outside summer"):
		return
	clock.season = 1
	npc.update(0.0)
	if not check(npc.active.has("kai"),"Kai was missing from his summer schedule"):
		return
	clock.season = 0
	world._change_area(200,Vector3(-100,0,-100))
	for tick in 35:
		await physics_frame
	for name in data.helpers:
		var helper = npc.active[name]
		if not check(helper.placed and helper.sprite.texture!=null and helper.ground_shadow.visible,
				"Missing source helper appearance or shadow: "+name):
			return
	var chef = npc.active.chef
	if not check(dialogue.profiles.size()==39,"Missing character profiles"):
		return
	for name in data.actors.keys()+data.helpers.keys():
		if not check(not str(dialogue.profiles.get(name,"")).is_empty(),"Missing character profile: "+name):
			return
	var origin: Vector3 = chef.global_position
	npc.active.nappy.global_position = origin+Vector3(0,0,-0.35)
	npc.active.hoggy.global_position = origin+Vector3(0,0,0.75)
	npc.active.bold.global_position = origin+Vector3(0,0,3.0)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.25,1.0,0.1)
	collision.shape = box
	wall.add_child(collision)
	root.add_child(wall)
	wall.global_position = origin+Vector3(0,0.4,0.37)
	await physics_frame
	await physics_frame
	world.player.global_position = chef.global_position+Vector3(0.33,0,0)
	world.player.facing = 1
	world.record_history("action","player","捡到了一枚蓝色贝壳",["chef","gray"])
	for tick in 9:
		world.record_history("action","player","扫了地",["gray"])
	world.record_player_action("放下了树枝")
	if not check(world.history.entries.back().known_by.has("chef"),
			"The nearby NPC did not witness the action"):
		return
	var before_greeting: int = world.history.entries.size()
	var snapshots: Array[String] = []
	transport.partial.connect(func(_text: String):
		snapshots.append(dialogue.bubbles.chef.label.text if world.history.entries.size()==before_greeting else "saved too early"))
	world.player.actions.interact_requested.emit()
	if not check(dialogue.composer.visible and not paused and dialogue.npc_id=="chef" and chef.facing==3,
			"Facing the helper and pressing interact did not open live conversation"):
		return
	if not check(dialogue.bubbles.chef.label.text=="今天想尝点什么？" and transport.last_messages[0].content.contains("料理")
			and snapshots==["今天想","今天想尝点什么？"]
			and transport.last_messages[0].content.contains("你在小矮人之家。打招呼前，你在原地停留")
			and transport.memory.contains("放下了树枝")
			and world.history.entries.back().actor=="chef",
			"NPC reply or persona was missing"):
		return
	var people: String = transport.last_messages[0].content.get_slice("你附近可见的其他人：",1)
	if not check(people.contains("纳皮") and not people.contains("霍格")
			and not people.contains("博尔德") and not people.contains("切夫"),
			"Dialogue did not distinguish visible neighbors from blocked, distant or self"):
		return
	transport.problem = "连接失败"
	var before_speech: int = world.history.entries.size()
	dialogue._submit("这是我们的秘密")
	if not check(dialogue.status.text==transport.problem and dialogue.entry.editable
			and world.history.entries.size()==before_speech+1
			and world.history.entries.back().known_by==PackedStringArray(["player","chef"]),
			"A failed reply was stored as NPC speech or prevented recovery"):
		return
	transport.problem = ""
	dialogue._submit("")
	if not check(world.history.entries.size()==before_speech+2
			and transport.prompt.message=="这是我们的秘密"
			and not transport.memory.contains("这是我们的秘密")
			and transport.memory.contains("今天想尝点什么？"),
			"Retry duplicated speech or lost this NPC's earlier reply"):
		return
	transport.sent_prompts.clear()
	dialogue._submit("附近有谁？")
	if not check(transport.sent_prompts.size()==1 and dialogue.speaker_id=="chef",
			"An ordinary private turn provoked an interruption"):
		return
	transport.sent_prompts.clear()
	dialogue._submit("现在能玩游戏吗？")
	if not check(transport.sent_prompts.size()==2 and dialogue.bubbles.has("chef") and dialogue.bubbles.has("nappy")
			and transport.sent_prompts[1].context.contains("角色：纳皮。")
			and transport.sent_prompts[1].memory.contains('"actor":"切夫"')
			and not transport.sent_prompts[0].memory.contains("这是我们的秘密")
			and not transport.sent_prompts[1].memory.contains("这是我们的秘密")
			and world.history.entries.back().known_by.has("chef"),
			"The relevant bystander failed to join or received earlier private speech"):
		return
	transport.sent_prompts.clear()
	dialogue._submit("那怎么玩游戏？")
	if not check(transport.sent_prompts.size()==1,"The same topic repeatedly provoked unsolicited replies"):
		return
	transport.sent_prompts.clear()
	var before_group: int = world.history.entries.size()
	transport.fail_speaker = "纳皮"
	# Select the closest guest on this explicit group request.
	dialogue.last_guest = ""
	dialogue._submit("你们觉得呢？")
	if not check(transport.sent_prompts.size()==2 and dialogue.status.text=="第二个角色断线"
			and world.history.entries.size()==before_group+2 and dialogue.bubbles.has("chef"),
			"Failure of the second speaker lost the first reply or duplicated the turn"):
		return
	transport.fail_speaker = ""
	dialogue._submit("")
	if not check(transport.sent_prompts.size()==3 and world.history.entries.size()==before_group+3
			and world.history.entries.back().actor=="nappy"
			and not world.history.entries.back().known_by.has("hoggy"),
			"Group retry replayed the first speaker or included a neighbor behind a wall"):
		return
	transport.sent_prompts.clear()
	dialogue._submit("纳皮，你呢？")
	if not check(transport.sent_prompts.size()==1 and dialogue.speaker_id=="nappy"
			and world.history.entries.back().known_by==PackedStringArray(["nappy","player"]),
			"Directly addressing a nearby character did not switch to a private reply"):
		return
	transport.sent_prompts.clear()
	transport.hold = true
	dialogue._submit("还在营业吗？")
	dialogue._submit("下次见。")
	if not check(not paused and dialogue.entry.editable and dialogue.queued.size()==1
			and dialogue.bubbles.player.label.text=="下次见。" and transport.sent_prompts.size()==1,
			"Live composer failed to show or queue speech while Pi was streaming"):
		return
	transport.finish()
	if not check(transport.sent_prompts.size()==2 and transport.prompt.message=="下次见。" and dialogue.pending,
			"Queued live speech did not reach Pi after the current reply"):
		return
	transport.hold = false
	transport.finish()
	await process_frame
	if not check(dialogue.composer.position.y>0 and dialogue.composer.get_rect().end.y<=dialogue.bubble_layer.size.y
			and dialogue.bubbles.player.visible and dialogue.bubbles.nappy.visible,
			"Composer or head-anchored bubbles are outside the viewport"):
		return
	dialogue.close()
	if not check(not paused and not dialogue.composer.visible,"Closing dialogue did not restore gameplay"):
		return
	wall.free()
	await physics_frame
	dialogue.begin(chef)
	if not check(transport.last_messages[0].content.get_slice("你附近可见的其他人：",1).contains("霍格"),
			"A fresh conversation did not pick up a neighbor after the wall was removed"):
		return
	dialogue.close()
	if not await see_villager(world,"gray",data.actors.gray,data.routes):
		return
	world.player.global_position = npc.active.gray.global_position+Vector3(0.25,0,0)
	dialogue.begin(npc.active.gray)
	if not check(transport.last_messages[0].content.contains("赛巴拉")
			and not transport.memory.contains("这是我们的秘密")
			and not transport.memory.contains("蓝色贝壳"),
			"Another actor received the wrong persona or conversation history"):
		return
	dialogue._submit("蓝色贝壳和我们的秘密是什么？")
	if not check(transport.memory.contains("蓝色贝壳")
			and not transport.memory.contains("这是我们的秘密")
			and not transport.memory.contains("known_by")
			and transport.prompt.memory.size()<=11,
			"Topic recall failed to find old known events or exposed private history"):
		return
	world._change_area(80,Vector3.ZERO)
	if not check(not is_instance_valid(chef) and npc.active.is_empty() and not paused,"NPCs leaked between locations"):
		return
	if not check(world.history.memory_for("chef","我们的秘密").any(func(event): return event.content=="这是我们的秘密"),
			"NPC knowledge was lost on a map change"):
		return
	world.free()
	print("NPC_ROSTER_OK: 32 villagers and 7 helpers placed, original shop hours, persona dialogue and history isolation and clean area lifecycle")
	quit()


func see_villager(world, name: String, record: Dictionary, routes: Dictionary) -> bool:
	for day_index in range(28):
		var variant := int(record.days[day_index])
		if variant<0:
			continue
		for step: Array in record.schedules[variant]:
			var area := int(step[1])
			if area<0 or routes[str(area)][str(int(step[2]))][0].is_empty():
				continue
			world.day_cycle.season = day_index/7
			world.day_cycle.weekday = day_index%7
			world.day_cycle.minute = (int(step[0])+360)%1440
			world._change_area(area,Vector3(-100,0,-100))
			var actor = world.npcs.active.get(name)
			if actor==null:
				continue
			for tick in 40:
				if actor.placed:
					break
				await physics_frame
			if actor.placed and actor.sprite.texture!=null and actor.ground_shadow.visible:
				return true
	return check(false,"No original schedule step could show "+name)

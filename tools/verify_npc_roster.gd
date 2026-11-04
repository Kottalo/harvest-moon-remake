extends SceneTree
## Exercises the original schedule catalogue through normal world entry and clock updates.

class TestDeepSeek extends "res://game/npc/dialogue/deepseek.gd":
	var last_messages: Array
	var prompt: Dictionary
	var memory: String
	var problem := ""

	func ask(messages: Array) -> void:
		last_messages = messages
		prompt = JSON.parse_string(messages.back().content)
		memory = JSON.stringify(prompt.memory)
		answered.emit("今天想尝点什么？" if problem.is_empty() else "",problem)


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition


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
	var transport := TestDeepSeek.new()
	dialogue.client = transport
	dialogue.add_child(transport)
	transport.answered.connect(dialogue._on_answer)

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
	dialogue.begin(jeff)
	if not check(dialogue.overlay.visible and transport.last_messages[0].content.contains("你在杂货店")
			and transport.last_messages[0].content.contains("你在这里的职责是经营杂货店"),
			"Jeff did not receive his current shop and duty"):
		return
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
	dialogue.begin(basil)
	dialogue._submit("你在哪儿？刚才在做什么？")
	if not check(dialogue.overlay.visible and not basil.walking
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
	world.player.actions.interact_requested.emit()
	if not check(dialogue.overlay.visible and paused and dialogue.npc_id=="chef" and chef.facing==3,
			"Facing the helper and pressing interact did not open a paused conversation"):
		return
	if not check(dialogue.reply.text=="今天想尝点什么？" and transport.last_messages[0].content.contains("料理")
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
	dialogue.close()
	if not check(not paused and not dialogue.overlay.visible,"Closing dialogue did not restore gameplay"):
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
	if not check(world.history.memory_for("chef","").any(func(event): return event.content=="这是我们的秘密"),
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

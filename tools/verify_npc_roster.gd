extends SceneTree
## Exercises the original schedule catalogue through normal world entry and clock updates.

class TestDeepSeek extends "res://game/npc/dialogue/deepseek.gd":
	var last_messages: Array
	var problem := ""

	func ask(messages: Array) -> void:
		last_messages = messages
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
	if not check(basil.placed and basil.global_position.distance_to(start)>0.3 and walk_frames.size()>3,
			"Basil did not walk and animate on his source morning route"):
		return

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
	var dialogue = npc.dialogue
	if not check(dialogue.profiles.size()==39,"Missing character profiles"):
		return
	for name in data.actors.keys()+data.helpers.keys():
		if not check(not str(dialogue.profiles.get(name,"")).is_empty(),"Missing character profile: "+name):
			return
	dialogue.client.free()
	var transport := TestDeepSeek.new()
	dialogue.client = transport
	dialogue.add_child(transport)
	transport.answered.connect(dialogue._on_answer)
	world.player.global_position = chef.global_position+Vector3(0.33,0,0)
	world.player.facing = 1
	world.player.actions.interact_requested.emit()
	if not check(dialogue.overlay.visible and paused and dialogue.npc_id=="chef" and chef.facing==3,
			"Facing the helper and pressing interact did not open a paused conversation"):
		return
	if not check(dialogue.reply.text=="今天想尝点什么？" and transport.last_messages[0].content.contains("料理"),
			"NPC reply or persona was missing"):
		return
	transport.problem = "连接失败"
	dialogue._submit("你喜欢吃什么？")
	if not check(dialogue.status.text==transport.problem and dialogue.entry.editable and dialogue.history["chef"].size()==2,
			"A failed reply was stored as NPC speech or prevented recovery"):
		return
	transport.problem = ""
	dialogue._submit("")
	if not check(transport.last_messages.size()==4 and transport.last_messages.back().content=="你喜欢吃什么？",
			"Follow-up did not retain this actor's conversation"):
		return
	dialogue.close()
	if not check(not paused and not dialogue.overlay.visible,"Closing dialogue did not restore gameplay"):
		return
	dialogue.begin("gray","格雷")
	if not check(transport.last_messages.size()==2 and transport.last_messages[0].content.contains("赛巴拉"),
			"Another actor received the wrong persona or conversation history"):
		return
	world._change_area(80,Vector3.ZERO)
	if not check(not is_instance_valid(chef) and npc.active.is_empty() and not paused,"NPCs leaked between locations"):
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

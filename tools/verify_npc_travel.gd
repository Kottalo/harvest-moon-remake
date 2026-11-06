extends SceneTree

class TestPi extends "res://game/npc/dialogue/pi_agent.gd":
	var instruction := ""

	func ask(messages: Array) -> void:
		instruction = messages[0].content
		if instruction.begins_with("你是对话调度员"):
			answered.emit("jeff","")
			return
		last_destination = "market_street"
		partial.emit("我这就去。")
		answered.emit("我这就去。","")


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok


func run() -> void:
	var world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	world.day_cycle.minute = 550
	world._change_area(180,Vector3(-0.3,0,1.3))
	var roster = world.npcs
	var jeff = roster.active.jeff
	for i in 60:
		if jeff.placed:
			break
		await physics_frame
	if not check(jeff.placed,"Jeff could not be placed for the travel test"): return
	jeff.global_position = Vector3(0.1,0,1.3)
	world.player.global_position = Vector3(-0.3,0,1.3)
	jeff.set_itinerary([],-1)
	await physics_frame
	world.day_cycle.minute = 480
	if not check(roster.travel.options(jeff,"现在去图书馆").is_empty(),
			"A closed public building was offered as an action destination"): return
	if not check(roster.travel.options(jeff,"去自宅").is_empty(),"A private destination was offered"): return
	world.day_cycle.minute = 550
	var dialogue = roster.dialogue
	dialogue.client.free()
	var transport := TestPi.new()
	dialogue.client = transport
	dialogue.add_child(transport)
	transport.partial.connect(dialogue._on_partial)
	transport.answered.connect(dialogue._on_answer)
	dialogue.composer.show()
	dialogue._submit("杰夫，你能去杂货店街区看看吗？")
	if not check(transport.instruction.contains("travel_options") and roster.travel.trips.has("jeff")
			and dialogue.bubbles.jeff.speech=="我这就去。" and world.history.entries.back().kind=="action",
			"The dialogue did not accept the allowed destination or leaked its structured action"): return

	var start: Vector3 = jeff.global_position
	var previous := start
	var walked := 0.0
	for frame in 600:
		roster.update(1.0/60.0)
		await physics_frame
		if not roster.active.has("jeff"):
			break
		var point: Vector3 = jeff.global_position
		var moved := point-previous
		if not check(moved.length()<0.035 and (absf(moved.x)<0.001 or absf(moved.z)<0.001),
				"NPC travel snapped or stepped diagonally instead of using the grid"): return
		walked += moved.length()
		previous = point
	var presence: Dictionary = roster.presence("jeff")
	if not check(walked>0.45 and previous.z>1.65 and presence.area==40 and not presence.live,
			"Jeff did not walk through the supermarket exit before changing maps: "+str([walked,previous,presence])): return
	var entrance: Vector3 = presence.point
	world._change_area(40,entrance+Vector3(0.45,0,0))
	for frame in 90:
		roster.update(1.0/60.0)
		await physics_frame
		if roster.active.has("jeff") and roster.active.jeff.placed:
			break
	presence = roster.presence("jeff")
	if not check(presence.live and presence.area==40 and entrance.distance_to(presence.point)<0.45,
			"The traveller did not arrive at the destination's authored entrance"): return
	world.free()
	print("NPC_TRAVEL_OK: dialogue intent, cardinal exit walking, and arrival at the authored entrance")
	quit()

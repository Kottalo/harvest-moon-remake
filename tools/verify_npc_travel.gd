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
	var opened_before_entry := false
	var arrival_start := Vector3.INF
	for frame in 180:
		roster.update(1.0/60.0)
		await physics_frame
		if not roster.active.has("jeff"):
			for door in world.doors.doors.values():
				opened_before_entry = opened_before_entry or door.phase=="opening"
			continue
		var arrival = roster.active.jeff
		if not arrival.placed:
			continue
		if not arrival_start.is_finite():
			arrival_start = arrival.global_position
		if arrival.waypoint>=arrival.itinerary.size():
			break
	presence = roster.presence("jeff")
	if not check(opened_before_entry and presence.live and presence.area==40
			and arrival_start.distance_to(presence.point)>0.2 and entrance.distance_to(presence.point)<0.45,
			"The traveller did not emerge from the open door and walk away: "+str([opened_before_entry,arrival_start,presence])): return
	var returning = roster.active.jeff
	for frame in 90:
		await physics_frame
		if world.doors.doors.values().all(func(door): return door.phase=="closed"):
			break
	if not check(world.doors.doors.values().all(func(door): return door.phase=="closed"),
			"The arrival door did not close after the NPC cleared it"): return
	roster.travel._finish("jeff")
	world.player.global_position = entrance+Vector3(1.5,0,0)
	var stepped_inside := false
	var saw_closed_approach := false
	for frame in 420:
		roster.update(1.0/60.0)
		await physics_frame
		if not roster.active.has("jeff"):
			break
		var trip: Dictionary = roster.travel.trips.get("jeff",{})
		var panel = trip.get("departure_panel")
		if not is_instance_valid(panel):
			continue
		var stop: StaticBody3D = panel.get_meta("doorway_stop")
		var inward: Vector3 = stop.get_meta("inward")
		var depth: float = (returning.global_position-stop.global_position).dot(inward)
		saw_closed_approach = saw_closed_approach or (depth<0.0 and world.doors.is_opening(panel))
		stepped_inside = stepped_inside or (depth>0.05 and returning.walking)
	if not check(saw_closed_approach and stepped_inside and not roster.active.has("jeff"),
			"The departing NPC did not wait for the door and cross the threshold"): return
	if not await verify_house_entries(world):
		return
	world.free()
	print("NPC_TRAVEL_OK: dialogue intent, cardinal exits and seven native building entrances")
	quit()


func verify_house_entries(world) -> bool:
	var roster = world.npcs
	world.day_cycle.minute = 600
	for pair in [[0,80],[0,92],[36,160],[40,180],[40,188],[44,196],[48,204]]:
		roster.travel.trips.clear()
		world._change_area(pair[0],Vector3(-100,0,-100))
		var exit: Dictionary
		for candidate in world.world[str(pair[0])].exits:
			if int(candidate.target)==pair[1]:
				exit = candidate
				break
		await physics_frame
		await physics_frame
		var stop: StaticBody3D = world.get_node("Location/DoorStop_%02d" % int(exit.index))
		var inward: Vector3 = stop.get_meta("inward")
		var approach: Vector3 = roster.travel._surface(stop.global_position-inward*0.66)
		roster.travel._begin("jeff",pair[0],world.world_to_area(pair[0],approach),[exit],pair[1],false)
		var crossed := false
		for frame in 750:
			roster.travel.tick(1.0/60.0)
			await physics_frame
			var trip: Dictionary = roster.travel.trips.get("jeff",{})
			if trip.is_empty() or trip.area==pair[1]:
				crossed = not trip.is_empty()
				break
		if not check(crossed,"NPC did not cross the outside doorway: "+str(pair)):
			return false
		world._change_area(pair[1],Vector3(-100,0,-100))
		var room_facing := -1
		for reverse in world.world[str(pair[1])].exits:
			if int(reverse.target)==pair[0]:
				room_facing = posmod(int(reverse.facing)+2,4)
				break
		var into_room: Vector3 = roster.travel.FACING[room_facing]
		var entry := Vector3.INF
		var end := Vector3.INF
		var previous := Vector3.INF
		for frame in 370:
			roster.travel.tick(1.0/60.0)
			await physics_frame
			var actor = roster.active.get("jeff")
			if not is_instance_valid(actor) or not actor.placed:
				continue
			end = actor.global_position
			if not entry.is_finite():
				entry = end
				if not check(actor.facing==room_facing,"NPC entered facing away from the room: "+str(pair)):
					return false
			if previous.is_finite() and not check(previous.distance_to(end)<0.04,"NPC snapped inside: "+str(pair)):
				return false
			previous = end
			if not roster.travel.trips.has("jeff"):
				break
		if not check(entry.is_finite() and (end-entry).dot(into_room)>0.25 and not roster.travel.trips.has("jeff"),
				"NPC did not take real steps into the room: "+str(pair)):
			return false
	return true

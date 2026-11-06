extends RefCounted
## Loaded legs use the villager's Manhattan navigator. Unloaded legs consume
## travel time between the same authored exits until the player loads the map.
const DoorAccess := preload("res://game/world/door_access.gd")
const PUBLIC_DESTINATIONS := [0,24,28,32,36,40,44,48,52,56,60,64,68,72,76,156,160,180,188,196,204]
const VISIT_SECONDS := 48.0
const FACING := [Vector3.BACK,Vector3.LEFT,Vector3.FORWARD,Vector3.RIGHT]

var roster
var world
var trips := {}
var serial := 0
var retry_after := {}


func setup(owner) -> void:
	roster = owner
	world = owner.world


func options(actor, message: String) -> Dictionary:
	var result := {}
	if trips.has(str(actor.name)) or not ["去","前往","走","到","等你","找你"].any(func(word): return message.contains(word)):
		return result
	var area: int = world.area_at(actor.global_position)
	for destination in PUBLIC_DESTINATIONS:
		var place: Dictionary = world.world[str(destination)]
		var mentioned: bool = message.contains(place.name) or (destination==52 and message.contains("广场"))
		if mentioned and not _route(area,destination,true).is_empty():
			result[place.slug] = {"area":destination,"name":place.name}
	return result


func start(actor, destination: int, requested: bool) -> bool:
	var id := str(actor.name)
	if trips.has(id) or not actor.placed or Time.get_ticks_msec()<retry_after.get(id,0):
		return false
	var area: int = world.area_at(actor.global_position)
	var route: Array
	if destination<0:
		var nearest := INF
		for exit in world.world[str(area)].exits:
			var distance: float = actor.global_position.distance_squared_to(world.area_to_world(area,_exit_point(exit)))
			if distance<nearest:
				nearest = distance
				route = [exit]
	else:
		route = _route(area,destination,requested)
	if route.is_empty():
		return false
	_begin(id,area,world.world_to_area(area,actor.global_position),route,destination,requested)
	return true


func arrive_for_schedule(id: String, origin: int, point: Vector3, destination: int, first_stop: Vector3) -> bool:
	var route := _route(origin,destination,false) if origin>=0 and point.is_finite() else []
	if not route.is_empty():
		_begin(id,origin,point,route,destination,false)
		return true
	# Some original rows only mark the NPC as away. Use the native entrance
	# nearest their first scheduled stop when no earlier mapped position exists.
	var distance := INF
	var landing := Vector3.ZERO
	for place in world.world.values():
		for exit in place.exits:
			if int(exit.target)!=destination:
				continue
			var entry := Vector3(exit.entry[0],exit.entry[1],exit.entry[2])
			var squared := entry.distance_squared_to(first_stop)
			if squared<distance:
				distance = squared
				landing = entry
	if is_inf(distance):
		return false
	_begin(id,destination,landing,[],destination,false)
	return true


func _begin(id: String, area: int, point: Vector3, route: Array, destination: int, requested: bool) -> void:
	serial += 1
	trips[id] = {"area":area,"point":point,"route":route,"requested":requested,"destination":destination,"key":serial,
		"phase":"visit" if route.is_empty() else "walk","door_wait":0.0,"elapsed":0.0}


func _route(origin: int, destination: int, requested: bool) -> Array:
	if origin==destination:
		return []
	var paths := {origin:[]}
	var queue: Array[int] = [origin]
	while not queue.is_empty():
		var area: int = queue.pop_front()
		for exit in world.world[str(area)].exits:
			var next := int(exit.target)
			if paths.has(next) or (requested and not _open(exit)):
				continue
			paths[next] = paths[area]+[exit]
			if next==destination:
				return paths[next]
			queue.append(next)
	return []


func _open(exit: Dictionary) -> bool:
	var clock = world.day_cycle
	return DoorAccess.refusal(int(exit.event),clock.minute,clock.season,clock.day,clock.weekday,
		roster.scheduled_areas).is_empty()


func _exit_point(exit: Dictionary) -> Vector3:
	var centre := Vector3((exit.min[0]+exit.max[0])*0.5,0,(exit.min[1]+exit.max[1])*0.5)
	var direction: Vector3 = FACING[int(exit.facing)] if int(exit.facing) in range(4) else Vector3.ZERO
	return centre-direction*0.18 if exit.has("door") else centre


func _loaded(area: int) -> bool:
	return area==world.current_area or (area in [52,56] and world.current_area in [52,56])


func _surface(point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*3,8)
	var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.get("position",point)


func tick(delta: float) -> void:
	if delta<=0.0:
		return
	for id in trips.keys():
		var trip: Dictionary = trips[id]
		var actor = roster.active.get(id)
		var loaded := _loaded(trip.area)
		if trip.phase=="visit":
			if loaded and not is_instance_valid(actor):
				_open_arrival(trip)
				_mount(id,trip,[])
			if trip.requested:
				trip.elapsed += delta
				if trip.elapsed>=VISIT_SECONDS:
					_finish(id)
			elif not loaded or (is_instance_valid(actor) and actor.placed):
				_finish(id)
			continue
		var exit: Dictionary = trip.route[0]
		var target := int(exit.target)
		var seam: bool = trip.area in [52,56] and target in [52,56]
		var goal: Vector3 = world.world_to_area(trip.area,world.area_to_world(target,Vector3(
			exit.entry[0],exit.entry[1],exit.entry[2]))) if seam else _exit_point(exit)
		trip.elapsed += delta
		if loaded:
			if not is_instance_valid(actor) or actor.get_meta("travel_key",-1)!=trip.key:
				if not is_instance_valid(actor):
					_open_arrival(trip)
				trip.world_goal = _surface(world.area_to_world(trip.area,goal))
				_mount(id,trip,[[trip.world_goal,clampi(int(exit.facing),0,3),0.0]])
				continue
			var destination: Vector3 = trip.world_goal
			if actor.placed:
				trip.point = world.world_to_area(trip.area,actor.global_position)
			if not actor.placed or actor.waypoint<actor.itinerary.size():
				if trip.elapsed>90.0:
					_finish(id,true)
				continue
			if actor.global_position.distance_to(destination)>0.55:
				_finish(id,true)
				continue
			if trip.requested and not _open(exit):
				_finish(id,true)
				continue
			if exit.has("door") and trip.phase=="walk":
				world.doors.open(roster.location,exit.door,int(exit.facing))
				trip.phase = "door"
				trip.door_wait = 0.55
			if trip.door_wait>0.0:
				trip.door_wait -= delta
				continue
		else:
			if trip.requested and not _open(exit):
				_finish(id,true)
				continue
			var flags: int = world.day_cycle.catalogue.areas[str(trip.area)].source_flags
			var speed: float = roster.INDOOR_SPEED if flags&0x1000 else roster.OUTDOOR_SPEED
			goal.y = trip.point.y
			trip.point = trip.point.move_toward(goal,speed*delta)
			if trip.point.distance_to(goal)>0.05:
				continue
		var landing := Vector3(exit.entry[0],exit.entry[1],exit.entry[2])
		if seam and is_instance_valid(actor):
			landing = world.world_to_area(target,actor.global_position)
			actor.remove_meta("travel_key")
		else:
			roster._remove(id)
		trip.arrived_from = trip.area
		trip.area = target
		trip.point = landing
		trip.route.pop_front()
		trip.elapsed = 0.0
		trip.door_wait = 0.0
		trip.phase = "visit" if trip.route.is_empty() else "walk"
		if trip.destination<0:
			_finish(id)


func _open_arrival(trip: Dictionary) -> void:
	for exit in world.world[str(trip.area)].exits:
		if exit.has("door") and int(exit.target)==int(trip.get("arrived_from",-1)):
			world.doors.open(roster.location,exit.door,int(exit.facing),true)
			return


func _mount(id: String, trip: Dictionary, points: Array) -> void:
	var actor = roster.active.get(id)
	if not is_instance_valid(actor) or not actor.placed:
		points.push_front([world.area_to_world(trip.area,trip.point),0,0.0])
	if points.is_empty():
		return
	actor = roster.place_traveller(id,trip.area,points)
	actor.set_meta("travel_key",trip.key)


func _finish(id: String, failed := false) -> void:
	trips.erase(id)
	if failed:
		retry_after[id] = Time.get_ticks_msec()+15_000
		var actor = roster.active.get(id)
		if is_instance_valid(actor) and actor.placed:
			actor.set_itinerary([],-1)
	roster.clock_key = Vector4i(-1,-1,-1,-1)

extends Node
## doors.c: 8 turn units of acceleration, 0x420 limit, 11-tick hold, mirrored twin.
var doors := {}
var clock := 0.0

func open(location: Node3D, metadata: Dictionary, facing: int, arriving := false) -> Node3D:
	var matches := location.find_children("ZoneModel_%02d" % int(metadata.model),"Node3D",true,false)
	if matches.is_empty():
		return null
	var panel: Node3D = matches[0]
	var key := panel.get_instance_id()
	if not doors.has(key):
		var twin: Node3D
		if int(metadata.twin) >= 0:
			var twins := location.find_children("ZoneModel_%02d" % int(metadata.twin),"Node3D",true,false)
			if not twins.is_empty():
				twin = twins[0]
		doors[key] = {"panel":panel,"twin":twin,"base":panel.rotation.y,"twin_base":twin.rotation.y if twin != null else 0.0,"angle":0,"draw_angle":0,"speed":0,"phase":"opening","hold":11,"facing":facing}
	var door: Dictionary = doors[key]
	if arriving:
		door.phase = "hold"
		door.speed = 0
		door.hold = 11
		door.angle = 0x420
		door.draw_angle = door.angle
		_apply(door)
	elif door.phase=="hold":
		# farm_zone_trigger extends an already-open door without restarting it.
		door.hold += 5
	else:
		door.facing = facing
		door.phase = "opening"
	return panel

func is_open(panel: Node3D) -> bool:
	return is_instance_valid(panel) and doors.has(panel.get_instance_id()) and doors[panel.get_instance_id()].phase != "opening"

func guard_arrival(panel: Node3D, player: CharacterBody3D, outward: Vector3) -> void:
	var door: Dictionary = doors[panel.get_instance_id()]
	var limit := -INF
	for leaf in [door.panel,door.twin]:
		if not is_instance_valid(leaf): continue
		var radius := 0.0
		for geometry: MeshInstance3D in leaf.find_children("*","MeshInstance3D",true,false):
			var bounds := geometry.mesh.get_aabb()
			for corner in 8:
				var offset: Vector3 = geometry.global_transform*bounds.get_endpoint(corner)-leaf.global_position
				radius = maxf(radius,Vector2(offset.x,offset.z).length())
		# A full hinge-radius bound contains the complete closing arc, including twins.
		limit = maxf(limit,leaf.global_position.dot(outward)+radius+0.02)
	door["clearance"] = {"player":player,"outward":outward,"limit":limit}

func arrival_clear(panel: Node3D) -> bool:
	if not is_instance_valid(panel) or not doors.has(panel.get_instance_id()): return true
	var door: Dictionary = doors[panel.get_instance_id()]
	if not door.has("clearance"): return true
	var guard: Dictionary = door.clearance
	if not is_instance_valid(guard.player): return true
	var shape: CollisionShape3D = guard.player.get_node("CollisionShape3D")
	return shape.global_position.dot(guard.outward)-guard.player.footprint.radius>guard.limit

func _apply(door: Dictionary) -> void:
	var sign := 1.0 if int(door.facing) in [1,2] else -1.0
	var turn: float = sign*door.draw_angle*TAU/4096.0
	door.panel.rotation.y = door.base+turn
	if is_instance_valid(door.twin):
		door.twin.rotation.y = door.twin_base-turn

func _physics_process(delta: float) -> void:
	clock += delta*30.0
	while clock >= 1:
		clock -= 1
		for key in doors.keys():
			var door: Dictionary = doors[key]
			if not is_instance_valid(door.panel):
				doors.erase(key)
				continue
			match door.phase:
				"opening":
					door.speed += 8
					door.angle += door.speed
					# doors.c applies the new turn BEFORE clamping its logical state.
					door.draw_angle = door.angle
					if door.angle >= 0x420:
						door.angle = 0x420
						door.hold = 11
						door.phase = "hold"
						door.speed = 0
				"hold":
					if not arrival_clear(door.panel): continue
					door.hold -= 1
					if door.hold <= 0:
						door.phase = "closing"
				"closing":
					if not arrival_clear(door.panel): continue
					door.speed -= 8
					door.angle = maxi(door.angle+door.speed,0)
					door.draw_angle = door.angle
					if door.angle == 0:
						door.phase = "closed"
						door.speed = 0
						door.erase("clearance")
			_apply(door)

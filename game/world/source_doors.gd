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
		doors[key] = {"panel":panel,"twin":twin,"base":panel.rotation.y,"twin_base":twin.rotation.y if twin != null else 0.0,"angle":0,"speed":0,"phase":"opening","hold":11,"facing":facing}
	var door: Dictionary = doors[key]
	door.phase = "hold" if arriving else "opening"
	door.speed = 0
	door.hold = 11
	if arriving:
		door.angle = 0x420
		_apply(door)
	return panel

func is_open(panel: Node3D) -> bool:
	return is_instance_valid(panel) and doors.has(panel.get_instance_id()) and doors[panel.get_instance_id()].phase != "opening"

func _apply(door: Dictionary) -> void:
	var sign := 1.0 if int(door.facing) in [1,2] else -1.0
	var turn: float = sign*door.angle*TAU/4096.0
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
					door.angle = mini(door.angle+door.speed,0x420)
					if door.angle == 0x420:
						door.phase = "hold"
						door.speed = 0
				"hold":
					door.hold -= 1
					if door.hold <= 0:
						door.phase = "closing"
				"closing":
					door.speed -= 8
					door.angle = maxi(door.angle+door.speed,0)
					if door.angle == 0:
						door.phase = "closed"
			_apply(door)

extends Node
## doors.c: 8 turn units of acceleration, 0x420 limit, 11-tick hold, mirrored twin.
var doors := {}
var clock := 0.0
const STOP_LAYER := 1 << 4 # Player-only doorway stop, outside the NPC and ground probes.
const STOP_THICKNESS := 0.016
const DIRECTIONS := [Vector3.BACK,Vector3.LEFT,Vector3.FORWARD,Vector3.RIGHT]


func prepare(location: Node3D, exits: Array) -> void:
	for exit: Dictionary in exits:
		if not exit.has("door"):
			continue
		var panel := _leaf(location,int(exit.door.model))
		if panel == null:
			continue
		var bounds := _prepare_leaf(panel)
		var twin := _leaf(location,int(exit.door.twin))
		if twin != null:
			bounds = bounds.merge(_prepare_leaf(twin))
		var inward: Vector3 = DIRECTIONS[int(exit.facing)]
		var border := inward.abs()*0.025
		_clear_doorway_wall(location,AABB(bounds.position-border,bounds.size+border*2))
		var index := int(exit.index)
		_add_threshold(location,bounds,inward,index)
		panel.set_meta("doorway_stop",_add_stop(location,bounds,inward,index))


func _leaf(location: Node3D, index: int) -> Node3D:
	return location.get_node_or_null("ZoneModel_%02d" % index) if index >= 0 else null


func _prepare_leaf(leaf: Node3D) -> AABB:
	var geometry: MeshInstance3D = leaf.get_node("Geometry")
	for body: CollisionObject3D in leaf.find_children("*","CollisionObject3D",true,false):
		body.free()
	return leaf.transform * geometry.transform * geometry.get_aabb()


func _clear_doorway_wall(location: Node3D, opening: AABB) -> void:
	# A few door planes also live in the map's native physical mesh. Cut only
	# wall faces inside the leaf aperture; keep both the floor and the jambs.
	var ground := location.get_node_or_null("Ground")
	if ground == null:
		return
	var collider: CollisionShape3D = ground.get_child(0)
	var original: ConcavePolygonShape3D = collider.shape
	var faces := original.get_faces()
	var result := PackedVector3Array()
	var cut := false
	var end := opening.end
	var planes := [
		Plane(Vector3.LEFT,-opening.position.x),Plane(Vector3.RIGHT,end.x),
		Plane(Vector3.DOWN,-opening.position.y),Plane(Vector3.UP,end.y),
		Plane(Vector3.FORWARD,-opening.position.z),Plane(Vector3.BACK,end.z),
	]
	for index in range(0,faces.size(),3):
		var a := faces[index]
		var b := faces[index+1]
		var c := faces[index+2]
		var bounds := AABB(a,Vector3.ZERO).expand(b).expand(c)
		if not bounds.intersects(opening) or absf((b-a).cross(c-a).normalized().y)>0.1:
			result.append_array(PackedVector3Array([a,b,c]))
			continue
		var inside := PackedVector3Array([a,b,c])
		for plane: Plane in planes:
			inside = Geometry3D.clip_polygon(inside,plane)
			if inside.size()<3:
				break
		if inside.size()<3:
			result.append_array(PackedVector3Array([a,b,c]))
			continue
		cut = true
		var remaining := PackedVector3Array([a,b,c])
		for plane: Plane in planes:
			var outside := Geometry3D.clip_polygon(remaining,Plane(-plane.normal,-plane.d))
			var extends_outside := false
			for point in outside:
				extends_outside = extends_outside or plane.distance_to(point)>0.000001
			if outside.size()>=3 and extends_outside:
				for corner in range(1,outside.size()-1):
					result.append_array(PackedVector3Array([outside[0],outside[corner],outside[corner+1]]))
			remaining = Geometry3D.clip_polygon(remaining,plane)
	if cut:
		var replacement := ConcavePolygonShape3D.new()
		replacement.backface_collision = original.backface_collision
		replacement.set_faces(result)
		collider.shape = replacement


func _add_threshold(location: Node3D, bounds: AABB, inward: Vector3, index: int) -> void:
	# Bridge only the sill around the closed hinge line, including its support
	# and forward walkability layers. Keep the surrounding steps and walls.
	var across := Vector3(inward.z,0,-inward.x)
	var centre := bounds.get_center()
	centre.y = bounds.position.y
	var side := across * bounds.size.dot(across.abs()) * 0.5
	var front := centre - inward*0.18
	var back := centre + inward*0.14
	var surface := ConcavePolygonShape3D.new()
	surface.set_faces(PackedVector3Array([front-side,back-side,front+side,front+side,back-side,back+side]))
	surface.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "DoorThreshold_%02d" % index
	body.collision_layer = 14 # Physical floor, feet placement, and forward walkability.
	body.collision_mask = 0
	var left := centre-side
	var right := centre+side+inward*0.065
	body.set_meta("entry_band",Rect2(Vector2(left.x,left.z),Vector2(right.x-left.x,right.z-left.z)).abs())
	var shape := CollisionShape3D.new()
	shape.shape = surface
	body.add_child(shape)
	location.add_child(body)


func _add_stop(location: Node3D, bounds: AABB, inward: Vector3, index: int) -> StaticBody3D:
	var stop := StaticBody3D.new()
	stop.name = "DoorStop_%02d" % index
	stop.collision_layer = STOP_LAYER
	stop.collision_mask = 0
	var across := Vector3(inward.z,0,-inward.x)
	var width := bounds.size.dot(across.abs())
	stop.position = bounds.get_center() - inward*(bounds.size.dot(inward.abs())*0.5+STOP_THICKNESS*0.5)
	stop.set_meta("inward",inward)
	stop.set_meta("half_width",width*0.5)
	var box := BoxShape3D.new()
	box.size = across.abs()*width+inward.abs()*STOP_THICKNESS+Vector3.UP*(bounds.size.y+0.16)
	var collision := CollisionShape3D.new()
	collision.shape = box
	collision.debug_fill = false
	stop.add_child(collision)
	location.add_child(stop)
	return stop


func at_threshold(location: Node3D, index: int, point: Vector2, player: CharacterBody3D) -> bool:
	var threshold := location.get_node_or_null("DoorThreshold_%02d" % index)
	if threshold == null:
		return false
	var band: Rect2 = threshold.get_meta("entry_band")
	if band.has_point(point):
		return true
	var stop: StaticBody3D = location.get_node_or_null("DoorStop_%02d" % index)
	if stop == null:
		return false
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var offset := location.to_local(capsule.global_position)-stop.position
	var inward: Vector3 = stop.get_meta("inward")
	var across := Vector3(inward.z,0,-inward.x)
	var depth := offset.dot(inward)
	var reach: float = player.footprint.radius+STOP_THICKNESS*0.5+0.02
	var shape: BoxShape3D = stop.get_child(0).shape
	return depth >= -reach and depth <= 0.05 and absf(offset.dot(across)) <= float(stop.get_meta("half_width")) \
		and absf(offset.y) <= shape.size.y*0.5


func open(location: Node3D, metadata: Dictionary, facing: int, arriving := false) -> Node3D:
	var panel := _leaf(location,int(metadata.model))
	if panel == null:
		return null
	var key := panel.get_instance_id()
	if not doors.has(key):
		var twin := _leaf(location,int(metadata.twin))
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
	var stop: StaticBody3D = panel.get_meta("doorway_stop",null)
	if is_instance_valid(stop):
		stop.collision_layer = 0

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
					var stop: StaticBody3D = door.panel.get_meta("doorway_stop",null)
					if is_instance_valid(stop) and stop.collision_layer==0:
						stop.collision_layer = STOP_LAYER
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

extends SceneTree
## Strict native bounds, closer zoom, viewport corners and indoor bypass.
var world: Node3D
var checks := 0
func _initialize() -> void: run.call_deferred()
func require_ok(ok: bool, message: String) -> bool:
	if not ok: push_error(message);quit(1)
	return ok
func covered_corners(camera, focus: Vector3) -> bool:
	var projected: Vector2 = camera._project(focus)
	for offset in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,-1),Vector2(1,1)]:
		var point: Vector2 = projected+offset*(camera._half_view-Vector2.ONE*0.0001)
		# Check each half-plane directly; Godot's point-in-polygon has a wider
		# boundary epsilon than this sub-millimetre viewport-corner check.
		var centre := Vector2.ZERO
		for vertex in camera._coverage: centre += vertex/camera._coverage.size()
		for i in camera._coverage.size():
			var a: Vector2 = camera._coverage[i]
			var edge: Vector2 = camera._coverage[(i+1)%camera._coverage.size()]-a
			var inward := Vector2(-edge.y,edge.x).normalized()
			if inward.dot(centre-a)<0: inward = -inward
			if inward.dot(point-a)<-0.00001: return false
	return true
func run() -> void:
	world = load("res://game/world/world.tscn").instantiate();root.add_child(world)
	world.set_process(false);world.set_physics_process(false);world.player.set_physics_process(false)
	var camera = world.camera
	var original_size: float = camera.size
	var original_eye: Vector3 = camera.eye_offset
	var outdoor_count := 0
	var indoor_count := 0
	# Real geometry and source flags: all outdoors including both loaded coast segments.
	for id in world.world:
		var info: Dictionary = world.world[id]
		var spawn := Vector3(info.spawn[0],info.spawn[1],info.spawn[2])
		world._change_area(int(id),spawn)
		var outdoors: bool = int(world.day_cycle.catalogue.areas[id].source_flags)&0x1800==0
		if outdoors: outdoor_count+=1
		else: indoor_count+=1
		if not require_ok((not camera._coverage.is_empty())==outdoors,"Indoor/outdoor limit classification failed: "+id): return
		for viewport in [Vector2i(960,720),Vector2i(1280,720),Vector2i(1920,720),Vector2i(720,960)]:
			root.size = viewport
			var foot: Vector3 = world.player.position
			var poses: Array[Vector3] = [foot,foot+Vector3(12,0,12),foot-Vector3(12,0,12)]
			for point in poses:
				world.player.position = point
				camera.follow(world.player,false,false)
				if not require_ok(camera.size<=original_size+0.00001 and camera.eye_offset==original_eye and camera.projection==Camera3D.PROJECTION_ORTHOGONAL and camera.basis.is_equal_approx(Basis.looking_at(-original_eye)),"Limits zoomed farther out or changed angle/projection: "+id): return
				if outdoors:
					if not require_ok(camera._limits.size()>=3 and covered_corners(camera,camera.position-camera.eye_offset),"Strict camera limit exposed the native boundary: "+str([id,viewport,point])): return
				else:
					if not require_ok(camera.limited_focus(point)==point and (camera.position-point-original_eye).length()<0.00001,"Indoor camera was clamped: "+id): return
				checks+=1
			if outdoors and camera._limits.size()>=3:
				# Feasible centre: all four viewport corners lie inside real projected
				# map bounds, independent of the player visibility fallback at narrow tips.
				var centre := Vector2.ZERO
				for vertex in camera._limits: centre += vertex/camera._limits.size()
				var point: Vector3 = camera.basis.x*centre.x+camera.basis.y*centre.y
				if not require_ok(covered_corners(camera,camera.limited_focus(point)),"Viewport escaped the map envelope: "+str([id,viewport])): return
		print("CAMERA_LOCATION_OK: ",id," ",info.slug," outdoors=",outdoors)
	# Trial is explicit, farm-only, and locks the outward component at a fixed edge.
	world._change_area(0,Vector3(-4.55,0,9.5))
	root.size = Vector2i(1152,720)
	var trial_foot := Vector3(-4.55,0,9.5)
	var normal_focus: Vector3 = camera.limited_focus(trial_foot)
	world.set_farm_camera_trial(true)
	var trial_focus: Vector3 = camera.limited_focus(trial_foot)
	if not require_ok(is_equal_approx(camera.size,original_size) and trial_focus.distance_to(normal_focus)>0.1,
			"Opt-in farm edge did not stop earlier at the original scale"): return
	var boundary: PackedVector2Array = camera._limits
	var edge := boundary[1]-boundary[0]
	var outward := Vector2(edge.y,-edge.x).normalized()
	var middle := (boundary[0]+boundary[1])*0.5
	var centre := Vector2.ZERO
	for vertex in boundary: centre += vertex/boundary.size()
	if outward.dot(centre-middle)>0: outward = -outward
	for extra in [0.1,0.6]:
		var probe: Vector2 = middle+outward*extra
		var desired: Vector3 = camera.basis.x*probe.x+camera.basis.y*probe.y
		var clamped: Vector2 = camera._project(camera.limited_focus(desired))
		if not require_ok(clamped.distance_to(middle)<0.001,"Trial continued past its fixed edge"): return
	world._change_area(52,Vector3(0,0,0))
	if not require_ok(camera._edge_padding==camera.EDGE_PADDING,"Farm trial affected town square"): return
	world._change_area(0,trial_foot)
	if not require_ok(camera._edge_padding==camera.FARM_TRIAL_PADDING,"Farm trial did not resume on return"): return
	world.set_farm_camera_trial(false)
	if not require_ok(camera.limited_focus(trial_foot).is_equal_approx(normal_focus),"Turning off the trial did not restore normal limits"): return
	print("FARM_FIXED_EDGE_TRIAL_OK: opt-in, original distance, stops at the fixed edge, farm only, reversible")
	# Square plane: test all edges using an independent known geometry boundary.
	var location := Node3D.new();root.add_child(location)
	var geometry := MeshInstance3D.new();var plane := PlaneMesh.new();plane.size=Vector2(20,20);geometry.mesh=plane;location.add_child(geometry)
	camera.set_location(location,true);root.size=Vector2i(960,720)
	var moved := 0
	for foot in [Vector3(0,0,0),Vector3(8,0,0),Vector3(-8,0,0),Vector3(0,0,8),Vector3(0,0,-8)]:
		var limited: Vector3 = camera.limited_focus(foot)
		if limited.distance_to(foot)>0.001: moved+=1
		if not require_ok(covered_corners(camera,limited),"Square-ground edge still exposes void: "+str([foot,limited])): return
	if not require_ok(moved>=4,"Camera never stopped following at the outdoor edges"): return
	# Too-small map: fit closer rather than relax the border or add scenery.
	plane.size=Vector2(0.5,0.5);camera.set_location(location,true)
	var once: Vector3 = camera.limited_focus(Vector3.ZERO)
	if not require_ok(once.is_finite() and once==camera.limited_focus(Vector3.ZERO) and camera.size<original_size and covered_corners(camera,once),"Small map camera did not fit inside its real boundary"): return
	# Overview does not consume/rebuild the gameplay envelope and exiting restores it.
	camera.set_location(location,true);camera.show_overview(location);camera.reset_gameplay();camera.follow(world.player,false,false)
	if not require_ok(camera.size<=original_size and not camera._coverage.is_empty(),"Overview lost gameplay zoom or map bounds"): return
	location.free();world.free()
	print("CAMERA_LIMITS_OK: ",outdoor_count," outdoor + ",indoor_count," indoor areas; ",checks," poses; four aspect ratios, edge coverage, narrow map, strict bounds even for border/outside player poses, closer-only zoom fitting, overview restore")
	quit()

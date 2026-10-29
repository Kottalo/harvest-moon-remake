extends SceneTree
## Real room exits: arrive with native collision, clear the hinge sweep, then close.
const KEYS := [KEY_DOWN,KEY_LEFT,KEY_UP,KEY_RIGHT]
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for tick in count: await physics_frame
	await process_frame
func require_ok(ok: bool,message: String) -> bool:
	if not ok:
		push_error(message)
		quit(1)
	return ok
func key(code: int,pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	if OS.get_cmdline_user_args().has("--120hz"): Engine.physics_ticks_per_second = 120
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = load("res://game/world/world.tscn").instantiate()
	viewport.add_child(world)
	for route in [[80,false],[96,false],[188,false],[196,false],[80,true]]:
		var area: int = route[0]
		var exit: Dictionary
		for candidate in world.world[str(area)].exits:
			if int(candidate.target)<80: exit = candidate
		var direction: Vector3 = world.player.actions.DIRECTIONS[int(exit.facing)]
		var centre := Vector3((exit.min[0]+exit.max[0])*0.5,0,(exit.min[1]+exit.max[1])*0.5)
		var start := centre-direction*0.45
		world._change_area(area,start+Vector3.UP)
		await frames(2)
		var query := PhysicsRayQueryParameters3D.create(start+Vector3.UP*2,start-Vector3.UP*2,2)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		if not require_ok(not hit.is_empty(),"Exit fixture has no actual ground"): return
		world.player.position = hit.position+Vector3.UP*0.01
		world.player.velocity = Vector3.ZERO
		world.player.reset_physics_interpolation()
		await frames(5)
		key(KEYS[int(exit.facing)],true)
		for tick in Engine.physics_ticks_per_second*3:
			if world.current_area!=area: break
			await frames(1)
		key(KEYS[int(exit.facing)],false)
		if not require_ok(world.current_area==int(exit.target),"Physical room exit did not arrive"): return
		var panel: Node3D
		for candidate in world.world[str(world.current_area)].exits:
			if int(candidate.target)==area and candidate.has("door"):
				panel = world.get_node("Location").find_children("ZoneModel_%02d"%int(candidate.door.model),"Node3D",true,false)[0]
		if not require_ok(panel!=null,"Arrival has no matching door panel"): return
		var door: Dictionary = world.doors.doors[panel.get_instance_id()]
		if route[1]:
			var blocker := StaticBody3D.new()
			blocker.collision_layer = 1
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(0.1,0.5,0.8)
			shape.shape = box
			blocker.add_child(shape)
			world.add_child(blocker)
			var outward: Vector3 = door.clearance.outward
			blocker.global_position = world.player.global_position+outward*0.12+Vector3.UP*0.25
			await frames(Engine.physics_ticks_per_second)
			if not require_ok(not world.transitioning and not world.player.input_locked and world.player.scripted_walk_time==0 and not world.doors.arrival_clear(panel) and door.phase=="hold","Blocked exit failed to release controls and hold the door safely"): return
			blocker.free()
			key(KEYS[world.player.facing],true)
			await frames(Engine.physics_ticks_per_second/2)
			key(KEYS[world.player.facing],false)
			print("DOOR_EXIT_BLOCKED_OK: actual wall stops native movement; bounded auto-walk releases input, door waits until manual clearance")
		var unsafe_hold := 0
		var closed := false
		for tick in Engine.physics_ticks_per_second*3:
			if not require_ok(world.player.collision_mask==3 and not world.player.door_passage,"Arrival disabled normal player collision"): return
			if not world.doors.arrival_clear(panel):
				unsafe_hold += 1
				if not require_ok(door.phase=="hold" and door.angle==0x420,"Door closed before capsule cleared its entire sweep"): return
			if door.phase=="closing":
				var shape: CollisionShape3D = world.player.get_node("CollisionShape3D")
				var overlap := PhysicsShapeQueryParameters3D.new()
				overlap.shape = shape.shape
				overlap.transform = shape.global_transform
				overlap.collision_mask = 1
				overlap.exclude = [world.player.get_rid()]
				for contact in world.get_world_3d().direct_space_state.intersect_shape(overlap):
					if not require_ok(not panel.is_ancestor_of(contact.collider) and (not is_instance_valid(door.twin) or not door.twin.is_ancestor_of(contact.collider)),"Closing leaf overlaps the actual capsule"): return
			if door.phase=="closed":
				closed = true
				break
			await frames(1)
		if not require_ok(closed and not world.transitioning and not world.player.input_locked,"Egress did not clear, close and release input"): return
		print("DOOR_EXIT_OK: ",area," -> ",exit.target," unsafe arrival ticks held=",unsafe_hold," normal capsule remains enabled, closing overlap=0")
		if area==196 and DisplayServer.get_name()!="headless":
			for frame in 2: await RenderingServer.frame_post_draw
			viewport.get_texture().get_image().save_png("res://verification/door_exit_clear.png")
	# An open indoor door must remain usable when the native ground probe stops
	# the capsule just outside the original point-zone, even after releasing movement.
	world._change_area(180,Vector3(-1.3,0.015,-1.254))
	world.player.facing = 1
	var indoor: Dictionary = world.world["180"].exits[0]
	var indoor_panel: Node3D = world.doors.open(world.get_node("Location"),indoor.door,1,true)
	world.doors.guard_arrival(indoor_panel,world.player,Vector3.RIGHT)
	key(KEY_LEFT,true)
	await frames(Engine.physics_ticks_per_second/2)
	key(KEY_LEFT,false)
	await frames(8)
	key(KEY_E,true)
	await frames(2)
	key(KEY_E,false)
	if not require_ok(world.transitioning and world.player.door_passage,"Standing at an open indoor door could not re-enter via actual E"): return
	print("DOOR_EXIT_RETURN_OK: stationary E re-enters an open door at the native walkability boundary")
	# A stationary player must keep the door open without disabling physics.
	world._change_area(44,Vector3(1.303,0.015,1.826))
	world.player.set_physics_process(false)
	world.set_physics_process(false)
	var reverse: Dictionary = world.world["44"].exits[0]
	var panel: Node3D = world.doors.open(world.get_node("Location"),reverse.door,int(reverse.facing),true)
	var outward: Vector3 = -world.player.actions.DIRECTIONS[int(reverse.facing)]
	world.player.global_position = panel.global_position+outward*0.1
	world.doors.guard_arrival(panel,world.player,outward)
	var door: Dictionary = world.doors.doors[panel.get_instance_id()]
	world.doors._physics_process(2)
	if not require_ok(not world.doors.arrival_clear(panel) and door.phase=="hold" and door.angle==0x420 and world.player.collision_mask==3,"Blocked/stationary arrival allowed closing"): return
	world.player.global_position += outward*2
	world.doors._physics_process(0.5)
	if not require_ok(door.phase=="closing","Clear capsule did not release the hold timer"): return
	world.player.global_position -= outward*2
	var angle: int = door.angle
	world.doors._physics_process(0.2)
	if not require_ok(door.angle==angle,"Door continued closing after capsule re-entered sweep"): return
	world.player.global_position += outward*2
	world.doors._physics_process(2)
	if not require_ok(door.phase=="closed","Door did not resume closing once clear again"): return
	print("DOOR_EXIT_GUARD_OK: stationary player holds indefinitely, re-entry pauses closing, leaving resumes; no collision disable")
	viewport.free()
	print("DOOR_EXIT_CHECK_OK: ",Engine.physics_ticks_per_second," Hz; four real exits plus blocked exit, single/twin clearance and native capsule overlap")
	quit()

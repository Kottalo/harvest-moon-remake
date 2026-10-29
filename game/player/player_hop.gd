extends RefCounted
## Source single-cell running hop; the native capsule still sweeps against the rest of the scene.
var player: CharacterBody3D
var active := false
var ground_y := 0.0
var target: StaticBody3D
var direction := Vector3.ZERO
var distance := 0.0
var elapsed := 0.0
# player.c: -80 launch, +16 gravity, 51 horizontal units per 30 Hz tick.
# Exact continuous interpolation of the eleven source positions: 88*n - 8*n*n.
const DURATION := 11.0/30.0
const GRAVITY := 14.4
const RISE_SPEED := 2.64

func _init(body: CharacterBody3D) -> void:
	player = body

func try_start(motion_direction: Vector3, delta: float) -> bool:
	if active or not player.is_on_floor() or motion_direction.is_zero_approx(): return false
	var hit := KinematicCollision3D.new()
	if not player.test_move(player.global_transform,motion_direction*player.RUN_SPEED*delta,hit): return false
	var obstacle := hit.get_collider() as StaticBody3D
	if obstacle==null or not obstacle.get_meta("hop_obstacle",false): return false
	var collision := obstacle.get_child(0) as CollisionShape3D
	if collision==null or not collision.shape is BoxShape3D: return false
	var box: BoxShape3D = collision.shape
	# Only one low ground item; authored oversized/tilted boxes and all buildings remain solid.
	if box.size.x>0.4001 or box.size.z>0.4001 or box.size.y>0.4001 or collision.global_basis.y.dot(Vector3.UP)<0.999: return false
	if absf(collision.global_position.y-box.size.y*0.5-player.global_position.y)>0.02: return false
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var half := (absf(collision.global_basis.x.dot(motion_direction))*box.size.x+absf(collision.global_basis.z.dot(motion_direction))*box.size.z)*0.5
	var travel := maxf(51.0*11.0/1000.0,(collision.global_position-capsule.global_position).dot(motion_direction)+half+player.footprint.radius+0.004)
	if travel>0.8: return false
	var landing := player.global_position+motion_direction*travel
	var space := player.get_world_3d().direct_space_state
	var floor_query := PhysicsRayQueryParameters3D.create(landing+Vector3.UP*0.2,landing-Vector3.UP*0.2,8)
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty() or floor_hit.normal.y<cos(player.floor_max_angle) or absf(floor_hit.position.y-player.global_position.y)>0.02: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.collision_mask = 3
	query.exclude = [player.get_rid()]
	query.transform = capsule.global_transform.translated(motion_direction*travel)
	if not space.intersect_shape(query,1).is_empty(): return false
	# Source farm_probe_steps refuses two blocked cells. Also sweep the whole arc
	# for walls/ceilings and neighbouring objects, excluding only the one hopped item.
	query.exclude = [player.get_rid(),obstacle.get_rid()]
	var previous := Vector3.ZERO
	for step in range(1,23):
		var time := DURATION*step/22.0
		var offset := motion_direction*travel*time/DURATION+Vector3.UP*(RISE_SPEED*time-GRAVITY*time*time*0.5)
		query.transform = capsule.global_transform.translated(previous+Vector3.UP*0.003)
		query.motion = offset-previous
		if space.cast_motion(query)[0]<0.9999: return false
		previous = offset
	# Full-cell boxes are intentionally taller/wider than the source point probe.
	# Ignore this one item during its verified hop, never walls or other items.
	target = obstacle
	player.add_collision_exception_with(target)
	direction = motion_direction
	distance = travel
	elapsed = 0
	ground_y = player.global_position.y
	active = true
	player.facing = [Vector3(0,0,1),Vector3(-1,0,0),Vector3(0,0,-1),Vector3(1,0,0)].find(direction)
	player.actions.play("base",28 if player.actions.carried_id!=0 else 10,"hop",player.facing)
	player.sprite.position.y = 0
	return true

func advance(delta: float) -> void:
	var horizontal_time := minf(delta,maxf(DURATION-elapsed,0))
	player.velocity = direction*distance/DURATION*horizontal_time/delta
	player.velocity.y = RISE_SPEED-GRAVITY*(elapsed+delta*0.5)
	player.move_and_slide()
	elapsed += delta
	player.sprite.position.y = 0
	player.actions.update_held(false)
	if elapsed+0.000001>=DURATION and player.is_on_floor(): cancel()

func cancel() -> void:
	if is_instance_valid(target): player.remove_collision_exception_with(target)
	target = null
	active = false
	if player.actions.state=="hop":
		player.actions.state = ""
		player.actions.range_id = -1
		player.animation = -1

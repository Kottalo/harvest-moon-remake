extends RefCounted
## Source single-row running hop; the native capsule still sweeps against the rest of the scene.
var player: CharacterBody3D
var active := false
var ground_y := 0.0
var _exception_rids: Array[RID] = []
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

func _hop_shape(obstacle: StaticBody3D) -> CollisionShape3D:
	if obstacle==null or not obstacle.get_meta("hop_obstacle",false) or obstacle.get_child_count()==0: return null
	var collision := obstacle.get_child(0) as CollisionShape3D
	if collision==null or not collision.shape is BoxShape3D: return null
	var box: BoxShape3D = collision.shape
	if box.size.x>0.4001 or box.size.z>0.4001 or box.size.y>0.4001 or collision.global_basis.y.dot(Vector3.UP)<0.999: return null
	if absf(collision.global_position.y-box.size.y*0.5-player.global_position.y)>0.02: return null
	return collision

func try_start(motion_direction: Vector3, delta: float) -> bool:
	if active or not player.is_on_floor() or motion_direction.is_zero_approx(): return false
	var hit := KinematicCollision3D.new()
	if not player.test_move(player.global_transform,motion_direction*player.RUN_SPEED*delta,hit): return false
	var obstacle := hit.get_collider() as StaticBody3D
	var collision := _hop_shape(obstacle)
	if collision==null: return false
	var box: BoxShape3D = collision.shape
	var capsule: CollisionShape3D = player.get_node("CollisionShape3D")
	var half := (absf(collision.global_basis.x.dot(motion_direction))*box.size.x+absf(collision.global_basis.z.dot(motion_direction))*box.size.z)*0.5
	var travel := maxf(51.0*11.0/1000.0,(collision.global_position-capsule.global_position).dot(motion_direction)+half+player.footprint.radius+0.004)
	var space := player.get_world_3d().direct_space_state
	# One row can contain two side-by-side boxes under the capsule. Collect only
	# eligible contacts in its actual lane and at the same longitudinal centre.
	var row: Array[StaticBody3D] = [obstacle]
	var row_shape := BoxShape3D.new()
	row_shape.size = motion_direction.abs()*(half*2+0.002)+motion_direction.cross(Vector3.UP).abs()*(player.footprint.radius*2+player.safe_margin*2)+Vector3.UP*box.size.y
	var row_center := capsule.global_position+motion_direction*(collision.global_position-capsule.global_position).dot(motion_direction)
	row_center.y = collision.global_position.y
	var row_query := PhysicsShapeQueryParameters3D.new()
	row_query.shape = row_shape
	row_query.transform.origin = row_center
	row_query.collision_mask = 1
	for contact in space.intersect_shape(row_query,32):
		var other := contact.collider as StaticBody3D
		var shape := _hop_shape(other)
		if shape==null or row.has(other) or absf((shape.global_position-collision.global_position).dot(motion_direction))>0.002: continue
		var size: Vector3 = shape.shape.size
		var extent := (absf(shape.global_basis.x.dot(motion_direction))*size.x+absf(shape.global_basis.z.dot(motion_direction))*size.z)*0.5
		travel = maxf(travel,(shape.global_position-capsule.global_position).dot(motion_direction)+extent+player.footprint.radius+0.004)
		row.append(other)
	if travel>0.8: return false
	if player.get_node("GroundShadow").motion_fraction(player.global_position,motion_direction*travel)<1.0: return false
	var landing := player.global_position+motion_direction*travel
	var floor_query := PhysicsRayQueryParameters3D.create(landing+Vector3.UP*0.2,landing-Vector3.UP*0.2,8)
	var floor_hit := space.intersect_ray(floor_query)
	if floor_hit.is_empty() or floor_hit.normal.y<cos(player.floor_max_angle) or absf(floor_hit.position.y-player.global_position.y)>0.02: return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule.shape
	query.collision_mask = 3
	query.exclude = [player.get_rid()]
	# Collision recovery can leave the grounded body slightly below its support.
	# Test clearance above the destination support, not inside the floor mesh.
	var support_clearance: float = floor_hit.position.y-player.global_position.y+maxf(0.003,player.safe_margin*2.0)
	query.transform = capsule.global_transform.translated(motion_direction*travel+Vector3.UP*support_clearance)
	if not space.intersect_shape(query,1).is_empty(): return false
	# Source farm_probe_steps refuses two blocked cells. Also sweep the whole arc
	# for walls/ceilings and neighbouring rows. Exclude only the validated row.
	var exclusions: Array[RID] = [player.get_rid()]
	for body in row: exclusions.append(body.get_rid())
	query.exclude = exclusions
	var previous := Vector3.ZERO
	for step in range(1,23):
		var time := DURATION*step/22.0
		var offset := motion_direction*travel*time/DURATION+Vector3.UP*(RISE_SPEED*time-GRAVITY*time*time*0.5)
		query.transform = capsule.global_transform.translated(previous+Vector3.UP*0.003)
		query.motion = offset-previous
		if space.cast_motion(query)[0]<0.9999: return false
		previous = offset
	# Full-cell boxes are intentionally taller/wider than the source point probe.
	# Ignore this one row during its verified hop, never walls or deeper rows.
	for body in row:
		var rid := body.get_rid()
		_exception_rids.append(rid)
		PhysicsServer3D.body_add_collision_exception(player.get_rid(),rid)
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
	var travel := direction*distance/DURATION*horizontal_time
	var foot := Vector3(player.global_position.x,ground_y,player.global_position.z)
	var clearance: float = player.get_node("GroundShadow").motion_fraction(foot,travel)
	player.velocity = travel*clearance/delta
	player.velocity.y = RISE_SPEED-GRAVITY*(elapsed+delta*0.5)
	player.move_and_slide()
	elapsed += delta
	player.sprite.position.y = 0
	player.actions.update_held(false)
	if elapsed+0.000001>=DURATION and player.is_on_floor(): cancel()

func cancel() -> void:
	# A picked-up/freed body can disappear before cancellation. Retain its RID
	# so even that stale exception is removed from the physics server.
	for rid in _exception_rids: PhysicsServer3D.body_remove_collision_exception(player.get_rid(),rid)
	_exception_rids.clear()
	active = false
	if player.actions.state=="hop":
		player.actions.state = ""
		player.actions.range_id = -1
		player.animation = -1

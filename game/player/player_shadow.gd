extends "res://game/characters/ground_shadow.gd"
## Player-only support sampling for ramps, hops, and the bed action.
func _physics_process(_delta: float) -> void:
	var player := actor
	var ground := player.global_position
	var grounded: bool = player.is_on_floor() and not player.hop.active and not player.actions.cinematic
	if grounded:
		ground.y += player.sprite.position.y
	else:
		var query := PhysicsRayQueryParameters3D.create(ground+Vector3.UP*0.2,ground-Vector3.UP*2,4)
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<cos(player.floor_max_angle):
			query.collision_mask = 2
			hit = space.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<cos(player.floor_max_angle):
			hide()
			return
		ground.y = hit.position.y
	show()
	# The visible stair tread can be above its smooth physical ramp.
	place_on_ground(ground,player.global_position.y-ground.y if grounded else 0.0)

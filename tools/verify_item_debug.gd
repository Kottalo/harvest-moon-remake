extends SceneTree
## Offscreen native collision rendering; no substitute debug meshes or user-game input.
const ITEMS := [58,62,64]
const COLOURS := [Color(1,0.15,0.65,1),Color(1,0.7,0.05,1),Color(0.45,1,0.1,1)]

func _initialize() -> void:
	debug_collisions_hint = true # Before any collision node enters the tree.
	_run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800,600)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var player = load("res://game/player/player.tscn").instantiate()
	viewport.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3(0,0,0.8)
	var items = load("res://game/items/loose_items.gd").new()
	viewport.add_child(items)
	items.set_physics_process(false)
	items.world = {"player":player,"transitioning":false}
	items.catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	items.field_cells.resize(1125)
	items.records[0] = []
	items.set_area(0)
	for index in 3:
		for initial in [true,false]:
			var point := Vector3(index*0.8-0.8,0,-0.8 if initial else 0.6)
			var record := {"id":ITEMS[index],"position":point,"active":true,"cell":index,"free_position":not initial}
			items.records[0].append(record)
			items._add_record(record)
			var collision: CollisionShape3D = record.node.get_node("Obstruction").get_child(0)
			if collision.debug_color!=COLOURS[index] or collision.debug_fill or not collision.shape.size.is_equal_approx(Vector3.ONE*0.4) or not collision.global_position.is_equal_approx(point+Vector3.UP*0.2):
				push_error("Item debug style changed its physical box or did not reach the native collider")
				quit(1)
				return
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = rad_to_deg(2*atan(120.0/1000.0))
	camera.position = Vector3(6.363,4.5,6.363)*1.44
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	for frame in 6: await RenderingServer.frame_post_draw
	var picture := viewport.get_texture().get_image()
	var counts := [0,0,0]
	for y in picture.get_height():
		for x in picture.get_width():
			var pixel := picture.get_pixel(x,y)
			for index in 3:
				var colour: Color = COLOURS[index]
				if Vector3(pixel.r-colour.r,pixel.g-colour.g,pixel.b-colour.b).length()<0.08:
					counts[index] += 1
	for index in 3:
		if counts[index]<40:
			push_error("Native item wireframe is not clearly visible: "+str([ITEMS[index],counts]))
			quit(1)
			return
	var collision: CollisionShape3D = player.get_node("CollisionShape3D")
	var wire: MeshInstance3D = collision.get_node_or_null("DebugFootprint")
	if wire==null or wire.mesh!=player.footprint.get_debug_mesh() or not wire.global_transform.is_equal_approx(collision.global_transform) or not is_equal_approx(player.footprint.radius,0.09) or not is_equal_approx(player.footprint.height,0.24):
		push_error("Player debug wire does not match the actual widened capsule")
		quit(1)
		return
	var visible_counts := []
	for facing in 4:
		player.facing = facing
		player._update_animation(Vector2.ZERO,false,0.0)
		player.sprite.show()
		for frame in 3: await RenderingServer.frame_post_draw
		var shown := viewport.get_texture().get_image()
		player.sprite.hide()
		for frame in 3: await RenderingServer.frame_post_draw
		var hidden := viewport.get_texture().get_image()
		var visible_cyan := 0
		var hidden_cyan := 0
		for y in shown.get_height():
			for x in shown.get_width():
				var a := shown.get_pixel(x,y)
				var b := hidden.get_pixel(x,y)
				if a.r<0.1 and a.g>0.9 and a.b>0.9: visible_cyan += 1
				if b.r<0.1 and b.g>0.9 and b.b>0.9: hidden_cyan += 1
		if visible_cyan<30 or absi(visible_cyan-hidden_cyan)>2:
			push_error("Player billboard hides the collision capsule: "+str([facing,visible_cyan,hidden_cyan]))
			quit(1)
			return
		visible_counts.append(visible_cyan)
		if facing==0:
			shown.save_png("res://verification/player_debug_collider.png")
	print("PLAYER_DEBUG_CAPSULE_OK: all four facings keep cyan capsule visible through actual sprite; cyan pixels=",visible_counts,"; engine debug mesh follows actual collider, radius=0.09 height=0.24; bottom remains at ground")
	player.sprite.show()
	picture.save_png("res://verification/item_debug_colliders.png")
	print("ITEM_DEBUG_COLLIDERS_OK: native magenta/yellow/lime wireframes visible; pixel counts=",counts,"; initial and placed full-cell boxes unchanged; actual item batches and player included")
	viewport.queue_free()
	await process_frame
	quit()

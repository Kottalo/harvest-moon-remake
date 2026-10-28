extends SceneTree
## Standalone GPU check entry; run_render_check.py isolates its Windows desktop.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var result: Dictionary = await load("res://tools/verify_actions_gpu.gd").new().run(root)
	var ordering: Dictionary = await load("res://tools/verify_render_order.gd").new().run(root)
	var water: Dictionary = await load("res://tools/verify_water.gd").new().run(root)
	for evidence in [["source-actions-render-order.json",ordering],["source-actions-water.json",water]]:
		var file := FileAccess.open("res://verification/"+evidence[0],FileAccess.WRITE)
		file.store_string(JSON.stringify(evidence[1],"\t"))
	result["existing_render_order"] = ordering.ok
	result["accepted_water_animation"] = water.ok
	result.ok = result.ok and ordering.ok and water.ok
	await process_frame
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,720)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world = ResourceLoader.load("res://game/world/world.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	viewport.add_child(world)
	world.set_physics_process(false)
	world.player.set_physics_process(false)
	for record in world.loose_items.records[0]:
		if record.id==64 and record.position.x>0 and record.position.z>1:
			world.player.position = record.position-Vector3(0,0,0.224)+Vector3.UP*0.001
			world.loose_items._remove(record)
			break
	world.player.facing = 0
	world.player.actions.carried_id = 64
	world.player.actions.play("base",27,"",0)
	world.player.actions.update_held(false)
	var held: Sprite3D = world.player.actions.held_sprite
	result["carried_item_texture_bound"] = held.material_override.get_shader_parameter("albedo_texture").get_rid()==held.texture.get_rid()
	result.ok = result.ok and result.carried_item_texture_bound
	world.camera.current = true
	world._update_camera()
	world._refresh_hud()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("res://verification/source_actions_farm.png")
	viewport.queue_free()
	var summary := FileAccess.open("res://verification/source-actions-gpu.json",FileAccess.WRITE)
	summary.store_string(JSON.stringify(result,"\t"))
	print("ACTIONS_GPU_RESULT: ",JSON.stringify(result))
	await process_frame
	quit(0 if result.ok else 1)

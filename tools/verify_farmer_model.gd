extends RefCounted
## Isolated offscreen review; never changes the active player, camera or input.
func run(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320, 400)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var focus := Vector3(0, 0.22, 0)
	camera.position = focus + Vector3(1, sqrt(0.5), 1)
	camera.look_at(focus)
	camera.set_orthogonal(0.64, 0.01, 10)
	# Read the current native GLB into this separate world, even while the user
	# is playing with the editor's older import cache. No editor reimport needed.
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file("res://game/player/model_3d/farmer.glb", state) != OK:
		viewport.queue_free()
		return {"ok":false,"error":"Could not read farmer GLB"}
	var model := Node3D.new()
	model.set_script(load("res://game/player/model_3d/farmer_visual.gd"))
	var imported := document.generate_scene(state)
	imported.scale = Vector3.ONE * 0.28
	model.add_child(imported)
	viewport.add_child(model)
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	if skeleton.get_bone_count() != 12:
		viewport.queue_free()
		return {"ok":false,"error":"Expected twelve bones"}
	for name in ["idle", "walk", "run"]:
		if not model.animator.has_animation(name) or model.animator.get_animation(name).get_track_count() == 0:
			viewport.queue_free()
			return {"ok":false,"error":"Missing animation: " + name}
	var strip := Image.create(1280, 400, false, Image.FORMAT_RGBA8)
	var bounds := []
	for facing in 4:
		model.rotation.y = [0.0, -PI/2, PI, PI/2][facing]
		model.animator.seek(0.0, true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		bounds.append(picture.get_used_rect())
		strip.blit_rect(picture, Rect2i(0,0,320,400), Vector2i(facing*320,0))
	strip.save_png("res://verification/farmer_3d_views.png")
	model.visible = false
	var sprite := Sprite3D.new()
	sprite.texture = load("res://game/player/player_atlas.png")
	sprite.hframes = 8
	sprite.vframes = 12
	sprite.pixel_size = 0.009827848
	sprite.offset = Vector2(0,53)
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.shaded = false
	viewport.add_child(sprite)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image().get_used_rect()
	sprite.visible = false
	model.visible = true
	model.rotation.y = 0
	var poses := []
	for action in ["walk", "run"]:
		model.animator.play(action)
		model.animator.seek(0, true)
		model.animator.advance(0)
		var bone := skeleton.find_bone("thigh_left")
		var first := skeleton.get_bone_pose_rotation(bone)
		model.animator.seek(model.animator.current_animation_length * 0.25, true)
		model.animator.advance(0)
		var second := skeleton.get_bone_pose_rotation(bone)
		poses.append({"action":action,"thigh_rotation_radians":first.angle_to(second),"ok":first.angle_to(second)>0.1})
	var report := {"ok":poses[0].ok and poses[1].ok,"bones":12,"meshes":model.find_children("*","MeshInstance3D",true,false).size(),"model_bounds":bounds,"sprite_bounds":original,"animations":poses,"offscreen":true}
	var file := FileAccess.open("res://verification/farmer-godot.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	viewport.queue_free()
	return report

extends RefCounted
## Isolated render review. No active-player edits, physical input or window changes.
func run(parent: Node) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(320,320)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var player = ResourceLoader.load("res://game/player/player.tscn","PackedScene",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	player.set_physics_process(false)
	viewport.add_child(player)
	player.set_physics_process(false)
	player.position = Vector3.ZERO
	var camera := Camera3D.new()
	viewport.add_child(camera)
	var focus := Vector3(0,0.25,0)
	camera.position = focus+Vector3(1,sqrt(0.5),1)
	camera.look_at(focus)
	camera.set_orthogonal(0.9,0.01,10)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var original := viewport.get_texture().get_image().get_used_rect()
	player.actions.play("base",0,"")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var packed := viewport.get_texture().get_image().get_used_rect()
	var aligned: bool = original.position.distance_to(packed.position)<=1.5 and original.size.distance_to(packed.size)<=1.5
	var canvas := CanvasLayer.new()
	viewport.add_child(canvas)
	var label := Label.new()
	label.add_theme_font_size_override("font_size",18)
	label.position = Vector2(8,8)
	canvas.add_child(label)
	var samples := [["镰刀","tool_0",72,1],["铜锄头","tool_1",93,2],["秘银斧头","tool_4",116,6],["金锤子","tool_3",135,5],["秘银水壶","tool_4",156,10],["挤奶器","milker",0,2],["剪毛器","clippers",0,1],["刷子","brush",0,2],["铃铛","bell",0,2],["钓竿","fishing",0,2],["拿起","base",11,1],["抱持行走","base",15,2]]
	var gallery := Image.create(1280,960,false,Image.FORMAT_RGBA8)
	for i in samples.size():
		var sample: Array = samples[i]
		label.text = sample[0]
		var count: int = player.actions.data.banks[sample[1]].ranges[str(sample[2])].size()
		player.actions.play(sample[1],sample[2],"",mini(sample[3],count-1))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var picture := viewport.get_texture().get_image()
		gallery.blit_rect(picture,Rect2i(0,0,320,320),Vector2i(i%4*320,i/4 as int*320))
	gallery.save_png("res://verification/source_actions_gallery.png")
	player.hide()
	label.hide()
	for i in 2:
		var layer := Sprite3D.new()
		var color_image := Image.create(8,8,false,Image.FORMAT_RGBA8)
		color_image.fill(Color(0.1,0.2,0.9) if i==0 else Color(0.9,0.1,0.1))
		layer.texture = ImageTexture.create_from_image(color_image)
		layer.pixel_size = 0.05
		layer.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		layer.position = focus
		var material := ShaderMaterial.new()
		material.shader = load("res://game/rendering/player_sprite.gdshader")
		material.set_shader_parameter("albedo_texture",layer.texture)
		material.set_shader_parameter("sort_bias",0.0 if i==0 else 0.005)
		layer.material_override = material
		viewport.add_child(layer)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var overlap := viewport.get_texture().get_image().get_pixel(160,160)
	var held_behind: bool = overlap.b>0.85 and overlap.r<0.15
	# Check actual subtractive pixels, independently of gameplay timing.
	var transition = load("res://game/world/location_transition.gd").new()
	viewport.add_child(transition)
	transition.set_process(false)
	var source := Image.create(1,1,false,Image.FORMAT_RGBA8)
	source.fill(Color(0.8,0.5,0.25,1))
	transition.rect.material.set_shader_parameter("old_frame",ImageTexture.create_from_image(source))
	transition.rect.material.set_shader_parameter("frozen",true)
	transition.rect.show()
	transition._set_shade(0.2)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var pixel := viewport.get_texture().get_image().get_pixel(160,160)
	var subtractive: bool = absf(pixel.r-0.6)<0.02 and absf(pixel.g-0.3)<0.02 and absf(pixel.b-0.05)<0.02
	var report := {"ok":aligned and subtractive and held_behind,"held_layer_behind_body":held_behind,"overlap_pixel":overlap,"player_position":player.position,"physics_processing":player.is_physics_processing(),"legacy_bounds":original,"packed_bounds":packed,"common_canvas_aligned":aligned,"subtractive_pixel":pixel,"source_subtractive_blend":subtractive,"offscreen":true,"gallery_samples":samples.size()}
	var file := FileAccess.open("res://verification/source-actions-gpu.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	viewport.queue_free()
	return report

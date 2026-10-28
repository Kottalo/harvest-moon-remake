extends SceneTree
## Compare cropped ground batches with the original ANI canvas at its source projection point.

func _initialize() -> void:
	_run.call_deferred()

func _picture() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_node("ItemOffsetViewport").get_texture().get_image()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.name = "ItemOffsetViewport"
	viewport.size = Vector2i(320,240)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var player = load("res://game/player/player.tscn").instantiate()
	viewport.add_child(player)
	player.set_physics_process(false)
	player.hide()
	var items = load("res://game/items/loose_items.gd").new()
	viewport.add_child(items)
	items.set_physics_process(false)
	items.world = {"player":player}
	items.catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/items/item_catalog.json"))
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = rad_to_deg(2*atan(120.0/1000.0))
	camera.make_current()
	var actual := MultiMeshInstance3D.new()
	actual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	actual.multimesh = MultiMesh.new()
	actual.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	actual.multimesh.mesh = items._item_mesh(58)
	actual.multimesh.instance_count = 1
	viewport.add_child(actual)
	var reference := Sprite3D.new()
	viewport.add_child(reference)
	reference.offset = Vector2(0,48)
	reference.pixel_size = player.sprite.pixel_size
	reference.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	reference.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	material.shader = load("res://game/rendering/player_sprite.gdshader")
	reference.material_override = material
	var cases := 0
	for item in [58,62,64]:
		actual.multimesh.mesh = items._item_mesh(item)
		reference.texture = load(items.catalogue.pictures[str(item)].ground_texture)
		material.set_shader_parameter("albedo_texture",reference.texture)
		for point in [Vector3(-4.2,0,-1.4),Vector3(0.2,0,0.2),Vector3(13.4,0,8.2)]:
			actual.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,point))
			# field_draw_grid / estate_draw_records: (+150,-100,-150) in PS1 space.
			reference.position = point+Vector3(0.15,0.1,0.15)
			for distance in [1.0,1.44]:
				camera.position = point+Vector3(6.363,4.5,6.363)*distance
				camera.look_at(point)
				reference.hide()
				actual.show()
				var drawn := await _picture()
				actual.hide()
				reference.show()
				var expected := await _picture()
				var error := 0
				for y in 240:
					for x in 320:
						var a := drawn.get_pixel(x,y)
						var b := expected.get_pixel(x,y)
						if absf(a.a-b.a)>0.02 or (a.a>0.5 and Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>0.04):
							error += 1
				if error>2 or not drawn.get_used_rect().has_area():
					push_error("Ground ANI projection/batch offset differs from source canvas: "+str([item,point,distance,error,drawn.get_used_rect(),expected.get_used_rect()]))
					quit(1)
					return
				cases += 1
	print("GROUND_ITEM_GPU_OK: ",cases," stone/branch/weeds cases; original ANI canvas and (+150,-100,-150) anchor match cropped batches across farm corners and 1x/1.44x cameras")
	viewport.queue_free()
	await process_frame
	quit()

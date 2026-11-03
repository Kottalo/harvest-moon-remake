extends SceneTree
## Exercise actual frame caches, including shared crop pixels with different ANI margins.
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var player = load("res://game/player/player.tscn").instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var checked := 0
	for bank_name in player.actions.data.banks:
		var bank: Dictionary = player.actions.data.banks[bank_name]
		for range_id in bank.ranges:
			for frame in bank.ranges[range_id].size():
				var pose: Dictionary = bank.ranges[range_id][frame]
				player.actions.bank = bank_name
				player.actions.range_id = int(range_id)
				player.actions.frame = frame
				player.actions._draw()
				var texture: AtlasTexture = player.sprite.texture
				var expected_region := Rect2(pose.rect[0],pose.rect[1],pose.rect[2],pose.rect[3])
				var expected_margin := Rect2(pose.margin[0],pose.margin[1],pose.margin[2],pose.margin[3])
				if texture.region!=expected_region or texture.margin!=expected_margin or texture.atlas.resource_path!=bank.pages[pose.page] or texture.get_size()!=Vector2(256,256) or player.sprite.offset!=Vector2(0,49) or not is_same(player.sprite.material_override.get_shader_parameter("albedo_texture"),texture):
					push_error("Packed frame cache lost original canvas/offset: "+str([bank_name,range_id,frame]))
					quit(1)
					return
				checked += 1
	player.free()
	print("PACKED_FRAMES_OK: ",checked," actual action draws retain per-pose margins, source pivot and shader texture, including deduplicated crop regions")
	quit()

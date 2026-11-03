extends SceneTree
func _initialize() -> void:
	var data=JSON.parse_string(FileAccess.get_file_as_string("res://tools/generated/backdrop_fields.json"))
	var catalogue := {}
	for map in data.maps:
		var folder: String = "res://game/rendering/outdoor_backdrops/"+map.name+"/"
		DirAccess.make_dir_recursive_absolute(folder)
		var material := ShaderMaterial.new()
		material.shader=load("res://game/rendering/outdoor_backdrop.gdshader")
		material.resource_name=map.name+"_edge_continuation"
		material.set_shader_parameter("view_right",Vector3(1,0,-1).normalized())
		material.set_shader_parameter("view_up",Vector3(-1,sqrt(8.0),-1).normalized())
		material.set_meta("source_geometry_sha256",data.source_sha256)
		material.set_shader_parameter("field_rect",Vector4(map.rect[0],map.rect[1],map.rect[2],map.rect[3]))
		for label in ["uv","axes","bounds","tint"]:
			var bytes=FileAccess.get_file_as_bytes("res://tools/generated/"+map.name+"_edge_"+label+".float32")
			var image=Image.create_from_data(map.size,map.size,false,Image.FORMAT_RGBAF,bytes)
			var texture=ImageTexture.create_from_image(image)
			var path: String = folder+map.name+"_edge_"+label+".res"
			assert(ResourceSaver.save(texture,path,ResourceSaver.FLAG_COMPRESS)==OK)
			material.set_shader_parameter("patch_"+label,load(path))
		for i in 3:
			material.set_shader_parameter("scene_atlas_"+str(i),load(map.atlases[mini(i,map.atlases.size()-1)]))
		assert(ResourceSaver.save(material,folder+map.name+"_edge_material.tres")==OK)
		catalogue[map.name] = folder+map.name+"_edge_material.tres"
		print("BACKDROP_RESOURCE_OK: ",map.name," source triangles=",map.triangles)
	var file=FileAccess.open("res://game/rendering/outdoor_backdrops/catalog.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(catalogue,"\t"));file.close()
	quit()

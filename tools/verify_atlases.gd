extends SceneTree
## Native dependencies/regions and original geometry checks after atlas packing.
func require_ok(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition

func _initialize() -> void:
	var packed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/texture_packer/atlas_manifest.json"))
	var scenes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/texture_dedup_manifest.json")).scenes
	var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://verification/texture-dedup-baseline.json"))
	var inspector = load("res://tools/consolidate_scene_textures.gd").new()
	var bindings := 0
	var atlases := {}
	var imported_sizes := {}
	for entry in packed.entries.values(): imported_sizes[entry.atlas] = Vector2(entry.atlas_size[0],entry.atlas_size[1])
	for path: String in imported_sizes:
		var image: Texture2D = load(path)
		if not require_ok(image!=null and image.get_size()==imported_sizes[path],"Packed PNG is not freshly imported: "+path): return
	var views := 0
	for old: String in packed.aliases:
		if not packed.images[old].has("entry"): continue
		var entry: Dictionary = packed.entries[packed.images[old].entry]
		var texture: AtlasTexture = load(packed.aliases[old])
		var rect := Rect2(entry.rect[0],entry.rect[1],entry.rect[2],entry.rect[3])
		if not require_ok(texture!=null and texture.region==rect and texture.margin==Rect2() and texture.atlas.resource_path==entry.atlas,"Incorrect packed texture view: "+old): return
		views += 1
	for path: String in scenes:
		for dependency in ResourceLoader.get_dependencies(path):
			for part in str(dependency).split("::"):
				if not require_ok(not packed.images.has(part),"Unpacked native dependency: "+part): return
		var scene: Node = load(path).instantiate()
		if not require_ok(inspector.digest(inspector.snapshot(scene))==baseline[path],"Original geometry/UV/collision/source animation changed: "+path):
			scene.free()
			return
		for node in [scene]+scene.find_children("*","",true,false):
			if not node is MeshInstance3D: continue
			for surface in node.mesh.get_surface_count():
				var material: Material = node.mesh.surface_get_material(surface)
				if material is ShaderMaterial:
					for uniform in ["albedo_texture","motion_texture"]:
						var texture: Texture2D = material.get_shader_parameter(uniform)
						if texture==null: continue
						if not require_ok(texture is AtlasTexture,"Unpacked texture in "+path+": "+texture.resource_path): return
						var region: Vector4 = load("res://game/rendering/atlas_binding.gd").region(texture)
						if not require_ok(material.get_shader_parameter(uniform+"_region")==region,"Incorrect atlas sampling region in "+path): return
						var atlas: Texture2D = texture.atlas
						if atlases.has(atlas.resource_path):
							if not require_ok(is_same(atlases[atlas.resource_path],atlas),"Atlas loaded more than once: "+atlas.resource_path): return
						else: atlases[atlas.resource_path] = atlas
						bindings += 1
				elif material is BaseMaterial3D and material.albedo_texture!=null:
					var texture: Texture2D = material.albedo_texture
					if not require_ok(texture is AtlasTexture,"Legacy material still uses original PNG"): return
					var region: Vector4 = load("res://game/rendering/atlas_binding.gd").region(texture)
					if not require_ok(material.uv1_scale==Vector3(region.z,region.w,1) and material.uv1_offset==Vector3(region.x,region.y,0),"Incorrect legacy material UV region"): return
		scene.free()
	print("NATIVE_ATLAS_CHECK_OK: ",scenes.size()," native scenes; ",views," packed views; ",bindings," packed shader bindings share ",atlases.size()," imported map atlases; original geometry/UV/collision/source animation unchanged")
	quit()

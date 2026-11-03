extends SceneTree
## Audit every native scene against pre-migration fingerprints and canonical bindings.
func _initialize() -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/texture_dedup_manifest.json"))
	var baseline := {}
	var output := {}
	var canonical := {}
	var shared := 0
	var mode := OS.get_cmdline_user_args().has("--baseline")
	if not mode:
		baseline = JSON.parse_string(FileAccess.get_file_as_string("res://verification/texture-dedup-baseline.json"))
	var inspector = load("res://tools/consolidate_scene_textures.gd").new()
	for path in plan.scenes:
		var source: String = "res://tools/generated/texture_before/"+path.trim_prefix("res://") if mode else path
		var packed: PackedScene = load(source)
		if packed==null:
			push_error("Missing native scene: "+source)
			quit(1)
			return
		var scene := packed.instantiate()
		var fingerprint: String = inspector.digest(inspector.snapshot(scene))
		output[path] = fingerprint
		if not mode and fingerprint!=baseline[path]:
			push_error("Geometry/UV/collision/source uniforms changed: "+path)
			quit(1)
			return
		if not mode:
			for dependency in ResourceLoader.get_dependencies(path):
				for part in str(dependency).split("::"):
					if plan.aliases.has(part):
						push_error("Stale native dependency: "+path+" -> "+part)
						quit(1)
						return
			for node in [scene]+scene.find_children("*","",true,false):
				if not node is MeshInstance3D: continue
				for surface in node.mesh.get_surface_count():
					var material: Material = node.mesh.surface_get_material(surface)
					var textures := []
					if material is ShaderMaterial:
						for name in ["albedo_texture","motion_texture"]: textures.append(material.get_shader_parameter(name))
					elif material is BaseMaterial3D:
						for slot in BaseMaterial3D.TEXTURE_MAX: textures.append(material.get_texture(slot))
					for texture: Texture2D in textures:
						if texture==null: continue
						var texture_path: String = texture.resource_path
						if plan.aliases.has(texture_path) or (texture is ImageTexture and plan.motion.has(texture.resource_name)):
							push_error("Duplicate native texture binding: "+texture_path)
							quit(1)
							return
						if not texture_path.ends_with(".png"): continue
						if canonical.has(texture_path):
							if not is_same(canonical[texture_path],texture):
								push_error("Canonical texture was loaded twice: "+texture_path)
								quit(1)
								return
							shared += 1
						else: canonical[texture_path] = texture
		scene.free()
	if mode:
		var file := FileAccess.open("res://verification/texture-dedup-baseline.json",FileAccess.WRITE)
		if file==null:
			push_error("Cannot write native baseline")
			quit(1)
			return
		file.store_string(JSON.stringify(output,"\t"))
	print("TEXTURE_SCENE_BASELINE_OK: " if mode else "TEXTURE_SCENE_CHECK_OK: ",output.size()," native scenes; geometry/UV/collision/source uniforms preserved; shared bindings=",shared,"; unique imported Texture2D resources=",canonical.size())
	quit()

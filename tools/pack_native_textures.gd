extends SceneTree
## Offline migration/rebind: native scene resources only, never the user's active game.
func _initialize() -> void:
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/texture_packer/atlas_manifest.json"))
	plan.pack_regions = true
	var scenes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/texture_dedup_manifest.json")).scenes
	for path: String in scenes:
		var result: Dictionary = load("res://tools/consolidate_scene_textures.gd").new().rewrite(path,plan)
		if result.before!=result.after:
			push_error("Atlas migration changed source scene state: "+JSON.stringify(result))
			quit(1)
			return
		print("NATIVE_ATLAS_OK: ",path)
	print("NATIVE_ATLASES_OK: ",scenes.size()," native scenes; original geometry, UVs, collision and animation records preserved")
	quit()

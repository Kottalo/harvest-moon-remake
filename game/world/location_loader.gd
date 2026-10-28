extends RefCounted
## Keep the current map and its neighbours warm; Godot's native threaded loader.
var catalogue: Dictionary
var ready := {}
var requested := {}
var wanted := {}

func path_for(area: int) -> String:
	return "res://game/world/coast.tscn" if area in [52,56] else catalogue[str(area)].scene

func get_scene(area: int) -> PackedScene:
	var path := path_for(area)
	if not ready.has(path):
		ready[path] = ResourceLoader.load_threaded_get(path) if requested.has(path) else load(path)
		requested.erase(path)
	return ready[path]

func warm(area: int) -> void:
	wanted = {path_for(area):true}
	for source in ([52,56] if area in [52,56] else [area]):
		for exit in catalogue[str(source)].exits:
			wanted[path_for(int(exit.target))] = true
	for path in ready.keys():
		if not wanted.has(path): ready.erase(path)
	if DisplayServer.get_name() == "headless": return
	for path in wanted:
		if not ready.has(path) and not requested.has(path):
			if ResourceLoader.load_threaded_request(path,"PackedScene") == OK:
				requested[path] = true

func poll() -> void:
	for path in requested.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var scene := ResourceLoader.load_threaded_get(path)
			if wanted.has(path): ready[path] = scene
			requested.erase(path)
		elif status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			requested.erase(path)

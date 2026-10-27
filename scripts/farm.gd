extends Node3D
## Compatibility entry for the original editor tab. Runtime code lives under game/.
func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://game/world/world.tscn")

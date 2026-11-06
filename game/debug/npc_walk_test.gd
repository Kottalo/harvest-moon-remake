extends Node3D
## Thomas walks between two markers. The real player and the test wall can interrupt him.
const SpriteLibrary := preload("res://game/original_sprites/sprite_library.gd")
const Villager := preload("res://game/npc/villager.tscn")

@onready var obstacle: StaticBody3D = $Obstacle
var npc: CharacterBody3D


func _ready() -> void:
	var library := SpriteLibrary.new("res://game/npc/npc_catalogue.json")
	npc = Villager.instantiate()
	npc.name = "Thomas"
	npc.art = library
	npc.poses = library.catalogue.actors.mayor_thomas.art["6"]
	npc.speed = 1.44
	npc.set_itinerary([[$Start.position,3,0.4],[$Goal.position,1,0.4]],0)
	add_child(npc)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_B:
		obstacle.visible = not obstacle.visible
		obstacle.collision_layer = 1 if obstacle.visible else 0
		get_viewport().set_input_as_handled()

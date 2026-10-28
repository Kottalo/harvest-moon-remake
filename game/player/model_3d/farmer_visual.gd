extends Node3D
## Optional model study: shares the existing body's movement and visible-ground offset.
var player
var animator: AnimationPlayer

func _ready() -> void:
	var palette := ShaderMaterial.new()
	palette.shader = load("res://game/player/model_3d/farmer_palette.gdshader")
	for mesh: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(surface, palette)
	animator = find_children("*", "AnimationPlayer", true, false)[0]
	for name in animator.get_animation_list():
		if name != "RESET":
			animator.get_animation(name).loop_mode = Animation.LOOP_LINEAR
	animator.play("idle")
	if get_parent() is CharacterBody3D:
		player = get_parent()
		player.get_node("Sprite3D").visible = not visible
		animator.active = visible

func _unhandled_key_input(event: InputEvent) -> void:
	if player != null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		visible = not visible
		player.sprite.visible = not visible
		animator.active = visible
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if player == null or not visible:
		return
	position.y = player.sprite.position.y
	rotation.y = [0.0, -PI / 2.0, PI, PI / 2.0][player.facing]
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	var action := "idle" if speed < 0.01 else ("run" if speed > player.WALK_SPEED * 1.1 else "walk")
	if animator.current_animation != action:
		animator.play(action, 0.08)

extends Control
## Real toolbox and item art, with stock that belongs only to this fixture.
const ToolPicker := preload("res://game/player/tool_picker.gd")
const Rucksack := preload("res://game/items/rucksack.gd")
const CropArt := preload("res://game/field/farm_crops.gd")
const SoundEffects := preload("res://game/audio/sound_effects.gd")

@onready var player: CharacterBody3D = $Player
@onready var open_button: Button = $Center/OpenButton
var picker: CanvasLayer
var bag := Rucksack.new()


func _ready() -> void:
	player.set_physics_process(false)
	var crops := CropArt.new()
	add_child(crops)
	crops.configure_seed_art(player.actions)
	var sound := SoundEffects.new()
	add_child(sound)
	player.actions.sound_requested.connect(sound.cue)
	player.actions.equipment_available = func(_tool: int): return true
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei"])
	open_button.add_theme_font_override("font",font)
	bag.tools.assign([1,34,39,0,0,0,0,0])
	bag.capacity = 4
	picker = ToolPicker.new()
	add_child(picker)
	picker.setup(player.actions,font,_seed_count,_choose_tool,open_button.get_node("Status"),$Hint,bag,sound.cue)
	open_button.pressed.connect(picker.open)
	picker.open.call_deferred()


func _seed_count(item: int) -> int:
	return 1 if item==34 else 12 if item==39 else 0


func _choose_tool(item: int) -> bool:
	return bag.choose_tool(player.actions,item)


func _physics_process(delta: float) -> void:
	if player.actions.busy():
		player.actions.advance(delta)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_I:
		picker.open()
		get_viewport().set_input_as_handled()

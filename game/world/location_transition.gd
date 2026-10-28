extends CanvasLayer
## farm_main.c: fade_start_blend(20), then fade_start_in(10,0,2).
var rect: ColorRect
var shade := 0.0
var phase := "idle"
var clock := 0.0
var step := 0
var frozen: Texture2D
var skip_frame := false
var half_step := false

func _ready() -> void:
	layer = 100
	rect = ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://game/world/location_transition.gdshader")
	rect.material = material
	add_child(rect)
	rect.hide()

func start_out() -> void:
	phase = "out"
	step = 0
	clock = 0
	skip_frame = true
	half_step = false
	if DisplayServer.get_name() != "headless":
		var image := get_viewport().get_texture().get_image()
		if image != null and not image.is_empty():
			frozen = ImageTexture.create_from_image(image)
			rect.material.set_shader_parameter("old_frame",frozen)
	rect.material.set_shader_parameter("frozen",frozen != null)
	rect.show()
	_set_shade(0)

func start_in() -> void:
	phase = "in"
	step = 9
	clock = 0
	rect.material.set_shader_parameter("frozen",false)
	_set_shade(0.9)

func reset() -> void:
	phase = "idle"
	shade = 0
	frozen = null
	if rect != null:
		rect.hide()
		rect.material.set_shader_parameter("old_frame",null)

func _set_shade(value: float) -> void:
	shade = value
	rect.material.set_shader_parameter("shade",value)

func _process(delta: float) -> void:
	# screen_fade_frame runs at display rate. Only BLEND halves its stepping
	# in MAIN_SPEED_HALF; the new-scene IN fade still advances at 60 Hz.
	clock += delta*60.0
	while clock >= 1:
		clock -= 1
		match phase:
			"out":
				if skip_frame:
					skip_frame = false
					continue
				half_step = not half_step
				if not half_step:
					continue
				step += 1
				# Original subtractive blend accumulates floor(255/21)=12 per step.
				_set_shade(minf(step*12.0/255.0,1.0))
				if step >= 21:
					_set_shade(1)
					phase = "black"
			"in":
				step -= 1
				_set_shade(maxf(step/10.0,0))
				if step <= 0:
					phase = "idle"
					rect.hide()
					frozen = null
					rect.material.set_shader_parameter("old_frame",null)

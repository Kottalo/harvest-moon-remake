extends Control
## Screen-space text follows its world-space speaker without scaling with distance.
var label: Label
var body: PanelContainer
var actor: Node3D
var remaining := 0.0
var fade_duration := 0.65
var streaming := false
var tint := Color("#fff2d6")
var _tail := Vector2.ZERO
var _tail_base := 0.0

func setup(speaker: Node3D, font: Font, player: bool) -> void:
	actor = speaker
	mouse_filter = MOUSE_FILTER_IGNORE
	if player:
		tint = Color("#e3f2ff")
		fade_duration = 0.0
	body = PanelContainer.new()
	body.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = Color("#4a382c")
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0,0,0,0.26)
	style.shadow_size = 3
	body.add_theme_stylebox_override("panel",style)
	add_child(body)
	label = Label.new()
	label.mouse_filter = MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_override("font",font)
	label.add_theme_font_size_override("font_size",18)
	label.add_theme_color_override("font_color",Color("#35271d"))
	body.add_child(label)

func say(text: String, is_streaming: bool) -> void:
	label.text = text
	var font := label.get_theme_font("font")
	label.custom_minimum_size.x = clampf(ceilf(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)+2,24,216)
	body.reset_size()
	body.reset_size.call_deferred()
	streaming = is_streaming
	modulate.a = 1.0
	if fade_duration>0.0:
		remaining = clampf(7.0+text.length()*0.10,8.0,16.0)+fade_duration
	else:
		remaining = clampf(3.5+text.length()*0.08,4.0,12.0)

func advance(delta: float) -> bool:
	if streaming:
		return true
	remaining = maxf(0.0,remaining-delta)
	if fade_duration>0.0:
		modulate.a = minf(1.0,remaining/fade_duration)
	return remaining>0.0

func follow(camera: Camera3D, bounds: Vector2, used: Array[Rect2]) -> void:
	var transform_on_screen := actor.get_global_transform_interpolated()
	var head := transform_on_screen.origin+Vector3.UP*0.84
	if camera.is_position_behind(head):
		hide()
		return
	var tip := camera.unproject_position(head)
	visible = Rect2(Vector2.ZERO,bounds).grow(24).has_point(tip)
	if not visible:
		return
	var extent := body.size
	var top_left := Vector2(clampf(tip.x-extent.x*0.5,5,maxf(5,bounds.x-extent.x-5)),
		clampf(tip.y-extent.y-9,4,maxf(4,bounds.y-extent.y-4)))
	var rect := Rect2(top_left,extent)
	for previous in used:
		if rect.grow(3).intersects(previous) and previous.position.y-extent.y-6>=4:
			rect.position.y = previous.position.y-extent.y-6
	position = rect.position
	used.append(rect)
	var tail := tip-position
	tail.x = clampf(tail.x,12,extent.x-12)
	tail.y = clampf(tail.y,extent.y,extent.y+10)
	if tail != _tail or extent.y != _tail_base:
		_tail = tail
		_tail_base = extent.y
		queue_redraw()

func _draw() -> void:
	if _tail.y<=_tail_base:
		return
	var left := Vector2(_tail.x-6,_tail_base-2)
	var right := Vector2(_tail.x+6,_tail_base-2)
	draw_colored_polygon(PackedVector2Array([left,_tail,right]),tint)

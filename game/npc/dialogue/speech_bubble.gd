extends Control
## Screen-space text follows its world-space speaker without scaling with distance.
const CHARACTER_SECONDS := 0.09
const COMMA_SECONDS := 0.16

var label: Label
var body: PanelContainer
var actor: Node3D
var remaining := 0.0
var fade_duration := 0.65
var streaming := false
var reveal_elapsed := 0.0
var speech := ""
var sentences := PackedStringArray()
var sentence_index := 0

func setup(speaker: Node3D, font: Font, player: bool) -> void:
	actor = speaker
	mouse_filter = MOUSE_FILTER_IGNORE
	if player:
		fade_duration = 0.0
	body = PanelContainer.new()
	body.mouse_filter = MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#e3f2ff") if player else Color("#fff2d6")
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
	speech = text
	if fade_duration>0.0:
		sentences = text.split("\n",false)
		if not streaming:
			sentence_index = 0
			label.visible_characters = 1
			reveal_elapsed = 0.0
		sentence_index = mini(sentence_index,sentences.size()-1)
		_set_line(sentences[sentence_index])
	else:
		_set_line(text)
	streaming = is_streaming
	modulate.a = 1.0
	if fade_duration>0.0:
		var last := sentences[-1]
		var hold := _reading_hold(last)
		if last.ends_with("？") or last.ends_with("?"):
			hold = clampf(6.0+last.length()*0.14,8.0,14.0)
		remaining = hold+fade_duration
	else:
		remaining = clampf(3.5+text.length()*0.08,4.0,12.0)

func _reading_hold(text: String) -> float:
	return clampf(1.8+text.length()*0.17,3.5,12.0)

func _set_line(text: String) -> void:
	if label.text==text:
		return
	label.text = text
	var font := label.get_theme_font("font")
	label.custom_minimum_size.x = clampf(ceilf(font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,18).x)+2,24,216)
	body.reset_size()
	body.reset_size.call_deferred()

func revealing() -> bool:
	return fade_duration>0.0 and (
		label.visible_characters<label.text.length() or sentence_index+1<sentences.size())

func advance(delta: float) -> bool:
	while revealing():
		var next_char := label.visible_characters<label.text.length()
		var interval := CHARACTER_SECONDS if next_char else _reading_hold(label.text)
		if next_char and label.visible_characters>0 and "，、；：,;:".contains(label.text[label.visible_characters-1]):
			interval = COMMA_SECONDS
		var needed := interval-reveal_elapsed
		if delta+0.000000001<needed:
			reveal_elapsed += delta
			return true
		delta = maxf(0.0,delta-needed)
		reveal_elapsed = 0.0
		if next_char:
			label.visible_characters += 1
		else:
			sentence_index += 1
			label.visible_characters = 1
			_set_line(sentences[sentence_index])
	if streaming:
		return true
	remaining = maxf(0.0,remaining-delta)
	if fade_duration>0.0:
		modulate.a = minf(1.0,remaining/fade_duration)
	return remaining>0.0

func follow(camera: Camera3D, bounds: Vector2, used: Array[Rect2]) -> void:
	var transform_on_screen := actor.get_global_transform_interpolated()
	var head := transform_on_screen.origin+Vector3.UP*0.84
	var projected_head := camera.unproject_position(head)
	if fade_duration==0.0 and (camera.is_position_behind(head) or not Rect2(Vector2.ZERO,bounds).grow(24).has_point(projected_head)):
		hide()
		return
	show()
	var extent := body.size
	var max_top := maxf(8,bounds.y-extent.y-14)
	var top := projected_head.y-extent.y-10
	if top<8 and projected_head.y+10<=max_top:
		top = projected_head.y+10
	var rect := Rect2(Vector2(clampf(projected_head.x-extent.x*0.5,8,maxf(8,bounds.x-extent.x-8)),
		clampf(top,8,max_top)),extent)
	if used.any(func(previous): return rect.grow(4).intersects(previous)):
		var best_offset := INF
		var original_y := rect.position.y
		for previous in used:
			for candidate_y: float in [previous.position.y-extent.y-12,previous.end.y+12]:
				var offset := absf(candidate_y-original_y)
				if candidate_y<8 or candidate_y>max_top or offset>=best_offset:
					continue
				var candidate := Rect2(Vector2(rect.position.x,candidate_y),extent)
				if not used.any(func(placed): return candidate.grow(4).intersects(placed)):
					rect = candidate
					best_offset = offset
	position = rect.position
	used.append(rect)

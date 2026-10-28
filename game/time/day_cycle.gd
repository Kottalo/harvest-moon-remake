extends Node
## Source clock.c/calendar and weather.c drift; independent of rendering FPS.
signal sleep_requested(automatic: bool)
var catalogue: Dictionary
var world
var year := 0
var season := 0
var day := 1 # Source clock_reset: spring 2, Monday (stored days are zero-based).
var weekday := 1
var minute := 360
var elapsed := 0.0
var sleeping := false
var menu_open := false
var menu: PanelContainer
var clock_label: Label
var tint: ColorRect
var tint_from := Vector3.ZERO
var tint_to := Vector3.ZERO
var tint_rgb := Vector3.ZERO
var tint_elapsed := 256.0/30.0
var period := 0
var menu_selection := 0
var menu_text: Label

func setup(owner_world) -> void:
	world = owner_world
	catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/time/day_cycle_catalog.json"))
	var canvas := CanvasLayer.new()
	canvas.layer = 1 # Above 3D, below the clock/prompts and transition overlay.
	add_child(canvas)
	tint = ColorRect.new()
	tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://game/time/day_cycle.gdshader")
	tint.material = material
	canvas.add_child(tint)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	clock_label = Label.new()
	clock_label.add_theme_font_override("font",world.hud.get_theme_font("font"))
	clock_label.position = Vector2(18,18)
	clock_label.add_theme_font_size_override("font_size",20)
	clock_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	clock_label.add_theme_constant_override("shadow_offset_x",2)
	clock_label.add_theme_constant_override("shadow_offset_y",2)
	ui.add_child(clock_label)
	menu = PanelContainer.new()
	menu.position = Vector2(24,90)
	menu.custom_minimum_size = Vector2(300,130)
	menu_text = Label.new()
	menu_text.add_theme_font_override("font",world.hud.get_theme_font("font"))
	menu_text.add_theme_font_size_override("font_size",20)
	menu.add_child(menu_text)
	ui.add_child(menu)
	menu.hide()
	period = time_period()
	tint_rgb = _period_rgb(period)
	tint_from = tint_rgb
	tint_to = tint_rgb
	refresh()

func time_period() -> int:
	var hour := minute/60 as int
	if hour>=5 and hour<7: return 0
	if hour>=7 and hour<15: return 1
	if hour>=15 and hour<17: return 2
	return 3

func _period_rgb(index: int) -> Vector3:
	var rgb: Array = catalogue.tint_rgb[index]
	return Vector3(rgb[0],rgb[1],rgb[2])

func advance(delta: float, paused: bool) -> void:
	if paused or menu_open or sleeping:
		return
	if catalogue.areas[str(world.current_area)].tint_enabled and tint_elapsed < 256.0/30.0:
		tint_elapsed = minf(tint_elapsed+delta,256.0/30.0)
		tint_rgb = tint_from.lerp(tint_to,tint_elapsed/(256.0/30.0))
		_apply_tint()
	if catalogue.areas[str(world.current_area)].clock_paused:
		return
	elapsed += delta
	var previous_minute := minute
	while elapsed+0.00000001 >= 0.5:
		elapsed -= 0.5
		_tick_minute()
		if minute == 360:
			sleeping = true
			sleep_requested.emit(true)
			break
	if previous_minute != minute:
		refresh()

func _tick_minute() -> void:
	minute = (minute+1)%1440
	if minute == 360:
		day += 1
		weekday = (weekday+1)%7
		if day >= 30:
			day = 0
			season += 1
		if season >= 4:
			season = 0
			year = mini(year+1,98)
	var next := time_period()
	if next != period:
		period = next
		tint_from = tint_rgb
		tint_to = _period_rgb(period)
		tint_elapsed = 0

func wake_next_morning(automatic := false) -> void:
	if not automatic:
		var remaining := (360-minute+1440)%1440
		if remaining == 0: remaining = 1440
		for i in remaining: _tick_minute()
	elapsed = 0
	period = time_period()
	tint_rgb = _period_rgb(period)
	tint_from = tint_rgb
	tint_to = tint_rgb
	tint_elapsed = 256.0/30.0
	refresh()

func nearby_bed() -> bool:
	if world.player.actions.carried_id != 0 or world.player.actions.busy():
		return false
	var point := Vector2(world.player.position.x,world.player.position.z)
	var direction: Vector3 = world.player.actions.DIRECTIONS[world.player.facing]
	var ahead := point+Vector2(direction.x,direction.z)*0.224
	for bed in catalogue.beds:
		if world.current_area != int(bed.area) or world.player.facing != int(bed.facing):
			continue
		var bounds := Rect2(Vector2(bed.min[0],bed.min[1]),Vector2(bed.max[0]-bed.min[0],bed.max[1]-bed.min[1]))
		if bounds.has_point(point) or bounds.has_point(ahead): return true
	return false

func interact() -> void:
	if not world.transitioning and not menu_open and nearby_bed():
		menu_open = true
		menu_selection = 0
		world.player.input_locked = true
		_draw_menu()
		menu.show()

func _draw_menu() -> void:
	menu_text.text = "今天就休息吗？\n"+("▶ " if menu_selection==0 else "   ")+"睡觉到明天\n"+("▶ " if menu_selection==1 else "   ")+"继续活动\n↑↓ 选择 · E 确定 · Esc 返回"

func _unhandled_key_input(event: InputEvent) -> void:
	if not menu_open or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_UP,KEY_DOWN,KEY_W,KEY_S]:
		menu_selection = 1-menu_selection
		_draw_menu()
	elif event.physical_keycode == KEY_ESCAPE:
		close_menu()
	elif event.physical_keycode in [KEY_E,KEY_ENTER,KEY_SPACE]:
		if menu_selection==1:
			close_menu()
		else:
			menu_open = false
			menu.hide()
			sleeping = true
			sleep_requested.emit(false)
	world.get_viewport().set_input_as_handled()

func close_menu() -> void:
	menu_open = false
	menu.hide()
	world.player.input_locked = false

func _apply_tint() -> void:
	tint.visible = catalogue.areas[str(world.current_area)].tint_enabled and tint_rgb.length_squared()>0.0001
	tint.material.set_shader_parameter("subtract_rgb",tint_rgb/255.0)

func refresh() -> void:
	clock_label.text = "第 %d 年 · %s %d 日 · 周%s  %02d:%02d" % [year+1,["春","夏","秋","冬"][season],day+1,["日","一","二","三","四","五","六"][weekday],minute/60 as int,minute%60/10 as int*10]
	_apply_tint()

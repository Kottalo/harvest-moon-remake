extends VBoxContainer
## Read-only map view for the F1 debug panel.
signal back_requested
signal live_requested(enabled: bool)

const ATLAS := "res://game/npc/npc_map_atlas.png"
const SHAPES := "res://game/npc/npc_map_shapes.json"
const LIVE_INK := Color("#f5d48a")
const SCHEDULE_INK := Color("#a9c4c8")

var world
var area_choice: OptionButton
var actor_choice: OptionButton
var plot: Control
var summary: Label
var roster: Label
var live_button: CheckButton
var selected_area := -1
var selected_actor := ""
var geometry: Dictionary
var atlas: Texture2D
var positions := {}
var elapsed := 0.0


func setup(owner_world, font: Font) -> void:
	world = owner_world
	name = "NpcMap"
	custom_minimum_size.x = 710
	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	add_theme_constant_override("separation",10)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	add_child(controls)
	var back := Button.new()
	back.text = "返回调试面板"
	back.pressed.connect(func(): back_requested.emit())
	controls.add_child(back)
	area_choice = OptionButton.new()
	area_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area_choice.item_selected.connect(_select_area)
	controls.add_child(area_choice)
	actor_choice = OptionButton.new()
	actor_choice.custom_minimum_size.x = 154
	actor_choice.item_selected.connect(_select_actor)
	controls.add_child(actor_choice)
	live_button = CheckButton.new()
	live_button.text = "实时追踪"
	live_button.toggled.connect(func(enabled: bool): live_requested.emit(enabled))
	controls.add_child(live_button)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	add_child(content)
	plot = Control.new()
	plot.custom_minimum_size = Vector2(418,370)
	plot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plot.draw.connect(_draw_plot)
	content.add_child(plot)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 255
	side.add_theme_constant_override("separation",8)
	content.add_child(side)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(scroll)
	roster = Label.new()
	roster.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roster.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scroll.add_child(roster)
	var legend := Label.new()
	legend.text = "● 实际位置    ○ 日程参考点    ◇ 玩家    □ 地图出口"
	add_child(legend)
	set_process(false)
	hide()


func open(allow_live: bool) -> void:
	if atlas==null:
		geometry = JSON.parse_string(FileAccess.get_file_as_string(SHAPES))
		atlas = load(ATLAS) if ResourceLoader.exists(ATLAS) else ImageTexture.create_from_image(Image.load_from_file(ATLAS))
		for area in world.world:
			area_choice.add_item(world.world[area].name,int(area))
		actor_choice.add_item("追踪角色…")
		for id in world.npcs.NAMES:
			actor_choice.add_item(world.npcs.NAMES[id])
			actor_choice.set_item_metadata(actor_choice.item_count-1,id)
	live_button.disabled = not allow_live
	selected_actor = ""
	actor_choice.select(0)
	_show_area(world.current_area)
	show()
	_refresh()


func _show_area(area: int) -> void:
	selected_area = area
	var index := area_choice.get_item_index(area)
	if index>=0:
		area_choice.select(index)


func _select_area(index: int) -> void:
	selected_actor = ""
	actor_choice.select(0)
	_show_area(area_choice.get_item_id(index))
	_refresh()


func _select_actor(index: int) -> void:
	selected_actor = str(actor_choice.get_item_metadata(index)) if index>0 else ""
	_refresh()


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed>=0.2:
		elapsed = 0.0
		_refresh()


func set_live(enabled: bool) -> void:
	live_button.set_pressed_no_signal(enabled)
	set_process(enabled)
	_refresh()


func _refresh() -> void:
	positions.clear()
	for id in world.npcs.NAMES:
		positions[id] = world.npcs.presence(id)
	if not selected_actor.is_empty():
		var followed: Dictionary = positions[selected_actor]
		if followed.area>=0:
			_show_area(followed.area)
	var place: Dictionary = world.world[str(selected_area)]
	var clock = world.day_cycle
	summary.text = "%s   %02d:%02d" % [place.name,int(clock.minute)/60,int(clock.minute)%60]
	if not selected_actor.is_empty():
		var entry: Dictionary = positions[selected_actor]
		summary.text += "\n追踪 %s · %s" % [world.npcs.NAMES[selected_actor],entry.activity]
		if entry.point.is_finite():
			summary.text += "\nX %.2f   Y %.2f   Z %.2f" % [entry.point.x,entry.point.y,entry.point.z]
	var names := PackedStringArray()
	for id in positions:
		var entry: Dictionary = positions[id]
		if entry.area==selected_area:
			names.append("%s %s · %s" % ["●" if entry.live else "○",world.npcs.NAMES[id],entry.activity])
	roster.text = "该区域角色 · %d\n%s" % [names.size(),"暂无角色" if names.is_empty() else "\n".join(names)]
	plot.queue_redraw()


func _draw_plot() -> void:
	if selected_area<0:
		return
	plot.draw_rect(Rect2(Vector2.ZERO,plot.size),Color("#172823"))
	var shape: Dictionary = geometry[str(selected_area)]
	var square := minf(plot.size.x,plot.size.y)-24.0
	if square<=0:
		return
	var canvas := Rect2((plot.size-Vector2.ONE*square)*0.5,Vector2.ONE*square)
	var tile: Array = shape.tile
	var bounds: Array = shape.bounds
	plot.draw_texture_rect_region(atlas,canvas,Rect2(tile[0],tile[1],tile[2],tile[3]))
	var place: Dictionary = world.world[str(selected_area)]
	for exit in place.exits:
		var point := Vector3((exit.min[0]+exit.max[0])*0.5,0,(exit.min[1]+exit.max[1])*0.5)
		plot.draw_rect(Rect2(_screen_point(point,canvas,bounds)-Vector2(3,3),Vector2(6,6)),SCHEDULE_INK,false)
	if world.current_area==selected_area:
		var player: Vector3 = world.world_to_area(selected_area,world.player.global_position)
		var at := _screen_point(player,canvas,bounds)
		plot.draw_colored_polygon(PackedVector2Array([at+Vector2(0,-6),at+Vector2(6,0),
			at+Vector2(0,6),at+Vector2(-6,0)]),Color("#80d7f0"))
	for id in positions:
		var entry: Dictionary = positions[id]
		if entry.area!=selected_area or not entry.point.is_finite():
			continue
		var at := _screen_point(entry.point,canvas,bounds)
		var radius := 6.0 if id==selected_actor else 4.0
		plot.draw_circle(at,radius,LIVE_INK if entry.live else SCHEDULE_INK,entry.live,1.6,true)
		if id==selected_actor:
			plot.draw_string(theme.default_font,at+Vector2(9,-6),world.npcs.NAMES[id],
				HORIZONTAL_ALIGNMENT_LEFT,-1,16,LIVE_INK)


func _screen_point(point: Vector3, canvas: Rect2, bounds: Array) -> Vector2:
	var local := (Vector2(point.x,point.z)-Vector2(bounds[0],bounds[1]))/float(bounds[2])
	return canvas.position+local.clamp(Vector2.ZERO,Vector2.ONE)*canvas.size

extends CanvasLayer
## Purchase lists for counters and displays. FarmEconomy commits the purchase.
const Wood := preload("res://game/items/toolbox_style.gd")
const ROW_HEIGHT := 54
const ROW_GAP := 6
const PRICE_INK := Color("#f7d58d")
const REFUSAL_INK := Color("#e9b4a0")

var economy
var overlay: ColorRect
var panel: PanelContainer
var heading: Label
var balance: Label
var scroll: ScrollContainer
var rows: VBoxContainer
var feedback: Label
var back_button: Button
var strong_font: Font
var row_style: StyleBoxFlat
var hover_style: StyleBoxFlat
var focus_style: StyleBoxFlat
var products: Dictionary = {}
var seller := ""
var goods: Array = []
var return_to_counter: Callable
var hud_visible := false
var clock_visible := false


func setup(owner_economy, font: Font) -> void:
	economy = owner_economy
	name = "ShopMenu"
	layer = 25
	process_mode = Node.PROCESS_MODE_ALWAYS
	strong_font = Wood.font(font,700)
	row_style = Wood.box(Color("#54382a"),7,Color("#76503a"),1)
	hover_style = Wood.box(Color("#684830"),7,Color("#a7764e"),1)
	focus_style = Wood.box(Color.TRANSPARENT,7,PRICE_INK,2)

	overlay = ColorRect.new()
	overlay.color = Color(0.09,0.07,0.06,0.28)
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme = Theme.new()
	overlay.theme.default_font = Wood.font(font)

	var dock := VBoxContainer.new()
	overlay.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock.offset_bottom = -24
	dock.alignment = BoxContainer.ALIGNMENT_END
	dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel",Wood.box(Color("#38251b"),12,Color("#c18550"),2,16))
	dock.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	panel.add_child(body)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	body.add_child(header)
	heading = _label("",25,Wood.HEADING,true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel",Wood.box(Color("#69452c"),7,Color("#ae7d50"),1,7))
	header.add_child(wallet)
	balance = _label("",18,PRICE_INK,true)
	wallet.add_child(balance)

	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	body.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation",ROW_GAP)
	scroll.add_child(rows)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",12)
	body.add_child(footer)
	feedback = _label("",16,Wood.MUTED_INK)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(feedback)
	back_button = Button.new()
	back_button.name = "Back"
	back_button.custom_minimum_size = Vector2(82,34)
	back_button.add_theme_font_override("font",strong_font)
	back_button.add_theme_font_size_override("font_size",16)
	_style_button(back_button)
	back_button.pressed.connect(_back)
	footer.add_child(back_button)

	overlay.resized.connect(_layout)
	overlay.hide()
	set_process_input(false)


func open(shopkeeper: String, items: Array, back := Callable()) -> void:
	var world = economy.world
	seller = shopkeeper
	goods = items.duplicate()
	return_to_counter = back
	heading.text = world.world[str(world.current_area)].name
	back_button.text = "返回" if back.is_valid() else "关闭"
	hud_visible = world.hud.visible
	clock_visible = world.day_cycle.clock_label.visible
	world.hud.hide()
	world.day_cycle.clock_label.hide()
	get_tree().paused = true
	overlay.show()
	set_process_input(true)
	world.sound.cue("menu")
	_refresh()


func close() -> void:
	if not overlay.visible:
		return
	var world = economy.world
	if Input.is_action_pressed("interact"):
		world.awaiting_interact_release = true
	overlay.hide()
	set_process_input(false)
	return_to_counter = Callable()
	world.hud.visible = hud_visible
	world.day_cycle.clock_label.visible = clock_visible
	get_tree().paused = false


func _back() -> void:
	var back := return_to_counter
	economy.world.sound.cue("cancel")
	close()
	if back.is_valid():
		back.call()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_back()
	elif event is InputEventKey and event.physical_keycode==KEY_F1:
		get_viewport().set_input_as_handled()


func _layout() -> void:
	panel.custom_minimum_size.x = clampf(overlay.size.x-48,1,548)
	var content_height := maxi(rows.get_child_count(),1)*(ROW_HEIGHT+ROW_GAP)-ROW_GAP
	scroll.custom_minimum_size.y = minf(content_height,minf(294,maxf(ROW_HEIGHT,overlay.size.y-166)))


func _refresh(result := "", selected := 0) -> void:
	balance.text = "余额  %d G" % economy.gold
	feedback.text = result
	feedback.add_theme_color_override("font_color",Wood.INK if result.begins_with("已购买") else REFUSAL_INK)
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	products.clear()
	for raw in goods:
		var item := int(raw)
		var owned: bool = item in economy.SINGLE_PURCHASE and economy.count(item)>0
		if owned and not return_to_counter.is_valid():
			continue
		var price: int = economy.buy_price(item)
		var note := "已拥有" if owned else "余额不足" if price>economy.gold else ""
		var button := _product(item,price,note)
		products[item] = button
		rows.add_child(button)
	if products.is_empty():
		var empty := _label("这里暂时没有商品。",17,Wood.MUTED_INK)
		empty.custom_minimum_size.y = ROW_HEIGHT
		rows.add_child(empty)
	_layout()
	var focus: Button = products.get(selected)
	if focus==null:
		focus = back_button if products.is_empty() else rows.get_child(0)
	focus.grab_focus()


func _product(item: int, price: int, note: String) -> Button:
	var title: String = economy.item_name(item)
	var button := Button.new()
	button.name = "Product%d" % item
	button.accessibility_name = "%s，%d G" % [title,price]
	button.custom_minimum_size.y = ROW_HEIGHT
	_style_button(button)
	button.pressed.connect(_buy.bind(item))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left",12)
	margin.add_theme_constant_override("margin_right",14)
	button.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation",12)
	margin.add_child(line)
	var art := TextureRect.new()
	art.name = "Icon"
	art.custom_minimum_size = Vector2(36,36)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var actions = economy.world.player.actions
	var picture: Texture2D = actions.tool_picture(34,item) if actions.seed_catalogue.has(str(item)) else actions.item_picture(item)
	art.texture = actions.menu_icon(picture)
	line.add_child(art)
	var caption := _label(title,19,Wood.INK)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(caption)
	if not note.is_empty():
		line.add_child(_label(note,14,REFUSAL_INK))
	var cost := _label("%d G" % price,20,PRICE_INK if note.is_empty() else REFUSAL_INK,true)
	cost.name = "Price"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost.custom_minimum_size.x = 86
	line.add_child(cost)
	return button


func _buy(item: int) -> void:
	_refresh(economy._purchase_from_menu(seller,item),item)


func _label(value: String, points: int, ink: Color, bold := false) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",points)
	label.add_theme_color_override("font_color",ink)
	if bold:
		label.add_theme_font_override("font",strong_font)
	return label


func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal",row_style)
	button.add_theme_stylebox_override("hover",hover_style)
	button.add_theme_stylebox_override("pressed",hover_style)
	button.add_theme_stylebox_override("focus",focus_style)
	for shade in ["font_color","font_focus_color","font_hover_color","font_pressed_color"]:
		button.add_theme_color_override(shade,Wood.INK)

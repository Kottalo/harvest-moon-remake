extends RefCounted
## Materials and typography shared by the farmhouse toolbox and carried rucksack.
const INK := Color("#fff0d7")
const MUTED_INK := Color("#eac7a1")
const DARK_INK := Color("#352419")
const HEADING := Color("#fff1ce")
const PIN_PATH := "res://game/items/toolbox_brass_pin.svg"
const FRAME_SIZE := Vector2(472,335)
const SLOT_SIZE := Vector2(52,52)
const SLOT_PITCH := 62
const SLOT_COLUMNS := 4
const ICON_EDGE := 32.0
const QUANTITY_ORIGIN := Vector2(3,37)

static func icon_rect(texture: Texture2D) -> Rect2:
	var source := texture.get_size()
	var fitted := source * (ICON_EDGE / maxf(source.x,source.y))
	return Rect2(Vector2((SLOT_SIZE.x-fitted.x)*0.5,4+(ICON_EDGE-fitted.y)*0.5),fitted)

static func box(fill: Color, radius: int, edge := Color.TRANSPARENT, width := 0, padding := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_corner_radius_all(radius)
	style.set_border_width_all(width)
	style.set_content_margin_all(padding)
	return style

static func materials() -> Dictionary:
	return {
		"shell": box(Color("#38251b"),12),
		"rim": box(Color.TRANSPARENT,12,Color("#c18550"),2),
		"wood": box(Color("#9b603b"),8,Color("#75462d"),1),
		"header": box(Color("#67402a"),6,Color("#d39760"),1),
		"badge": box(Color("#d6a66a"),4,Color("#69462f"),1),
		"tray": box(Color("#4c3024"),6,Color("#c99565"),1),
		"filled": box(Color("#b78357"),5,Color("#d19d68"),1),
		"empty": box(Color("#80543a"),5,Color("#ac7955"),1),
		"focus": box(Color.TRANSPARENT,5,Color("#ffe1a2"),2),
		"marked": box(Color.TRANSPARENT,4,Color("#ecac64"),2),
		"help": box(Color("#68412b"),4),
		"key": box(Color("#d4a471"),4),
	}

static func font(base: Font, weight := 400) -> SystemFont:
	var result := SystemFont.new()
	var families := PackedStringArray(["Noto Sans SC"])
	if base is SystemFont:
		families.append_array(base.font_names)
	result.font_names = families
	result.font_weight = weight
	return result

static func brass_pin() -> Texture2D:
	if ResourceLoader.exists(PIN_PATH):
		return load(PIN_PATH)
	var pin := Image.new()
	if pin.load_svg_from_buffer(FileAccess.get_file_as_bytes(PIN_PATH))==OK:
		return ImageTexture.create_from_image(pin)
	return null

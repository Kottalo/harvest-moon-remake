extends RefCounted
## Lazily resolves the original ANI frames as fixed-pivot Godot textures.

const CATALOGUE_PATH := "res://game/original_sprites/catalogue.json"

var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
var pages: Dictionary = {}


func frame_texture(frame: Dictionary) -> AtlasTexture:
	var image = frame["image"]
	if image == null:
		return null
	var texture := image_texture(image)
	var offset: Array = frame["offset"]
	var origin: Array = catalogue["origin"]
	var margin_start := Vector2(offset[0] + origin[0], offset[1] + origin[1])
	var canvas := Vector2.ONE * float(catalogue["canvas"])
	texture.margin = Rect2(margin_start, canvas - texture.region.size)
	return texture


func image_texture(key: String) -> AtlasTexture:
	var packed: Array = catalogue["images"][key]
	var page := int(packed[0])
	if not pages.has(page):
		pages[page] = load(catalogue["pages"][page])
	var texture := AtlasTexture.new()
	texture.atlas = pages[page]
	texture.region = Rect2(packed[1], packed[2], packed[3], packed[4])
	texture.filter_clip = true
	return texture

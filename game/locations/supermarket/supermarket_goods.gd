extends Node3D
## Source run 10 estate records. Display poses are from farm art set 8.

const AREA := 180
const ART := "res://game/locations/supermarket/merchandise.png"
const CATALOGUE := "res://game/locations/supermarket/merchandise.json"
const DRAW_OFFSET := Vector3(0.15,0.1,0.15)
const SEED_STANDS := 3
var economy
var rows: Array
var sprites: Array[Sprite3D] = []
var atlas: Texture2D

func setup(owner) -> void:
	economy = owner
	rows = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE))

func bind_location() -> void:
	for sprite in sprites:
		sprite.queue_free()
	sprites.clear()
	if economy.world.current_area!=AREA:
		return
	if atlas==null:
		atlas = load(ART) if ResourceLoader.exists(ART) else ImageTexture.create_from_image(Image.load_from_file(ART))
	for row in rows:
		var sprite := Sprite3D.new()
		sprite.texture = atlas
		sprite.hframes = 8
		sprite.vframes = atlas.get_height()/128
		sprite.offset = Vector2(0,48)
		sprite.frame = int(row.tile)
		sprite.pixel_size = economy.world.player.sprite.pixel_size
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sprite.position = _point(row)+DRAW_OFFSET
		add_child(sprite)
		sprites.append(sprite)
	refresh()

func refresh() -> void:
	if sprites.is_empty():
		return
	var goods := PackedInt32Array(economy.goods_for("jeff"))
	for i in sprites.size():
		var row: Dictionary = rows[i]
		var choices := _available(i,goods)
		sprites[i].visible = not choices.is_empty() or row.items.is_empty()
		if i==3:
			# Backpack slot shows the medium or large bag, depending on the upgrade.
			sprites[i].frame = int(row.tile)+(1 if choices.has(110) else 0)

func _point(row: Dictionary) -> Vector3:
	var xyz: Array = row.position
	return Vector3(xyz[0],xyz[1],xyz[2])

func _available(index: int, goods: PackedInt32Array) -> Array[int]:
	if index<SEED_STANDS and economy.world.day_cycle.season!=index:
		return []
	var choices: Array[int] = []
	for raw in rows[index].items:
		var item := int(raw)
		if goods.has(item) and (item not in economy.SINGLE_PURCHASE or economy.count(item)==0):
			choices.append(item)
	return choices

func interact() -> bool:
	if sprites.is_empty() or economy.world.player.actions.carried_id!=0 or economy.world.player.actions.busy():
		return false
	if not economy._zone_ahead(economy.data.counters[str(AREA)]):
		return false
	var world = economy.world
	var direction: Vector3 = world.player.actions.DIRECTIONS[world.player.facing]
	var ahead: Vector3 = world.world_to_area(AREA,world.player.global_position)+direction*0.25
	var goods := PackedInt32Array(economy.goods_for("jeff"))
	for index in rows.size():
		var delta := ahead-_point(rows[index])
		if absf(delta.x)>=0.15 or absf(delta.z)>=0.15:
			continue
		var choices := _available(index,goods)
		if choices.is_empty():
			continue
		economy.show_shelf(choices)
		return true
	return false

extends Node
## Purchased animals occupy stable slots in the coop or barn.
const NAMES := {"calf":"小牛","cow":"牛","sheep":"羊","chicken":"鸡"}
const VILLAGER := preload("res://game/npc/villager.tscn")
var economy
var library
var visible_animals: Array[Dictionary] = []

func bind_location() -> void:
	visible_animals.clear()
	var world = economy.world
	if world.current_area not in [96,112] or economy.animals.is_empty():
		return
	if library==null:
		library = preload("res://game/original_sprites/sprite_library.gd").new()
	var location: Node3D = world.get_node("Location")
	var previous := location.get_node_or_null("Livestock")
	if previous != null:
		previous.free()
	var container := Node3D.new()
	container.name = "Livestock"
	location.add_child(container)
	for record in economy.animals:
		var chicken: bool = record.kind=="chicken"
		if chicken != (world.current_area==112):
			continue
		var slot := visible_animals.size()
		var point := Vector3(-0.85+slot*0.4,0,0.6) if chicken else Vector3(0.75+1.4*(slot/5),0,-1.2+0.6*(slot%5))
		var actor: CharacterBody3D = VILLAGER.instantiate()
		actor.set_script(null)
		actor.collision_layer = 2
		actor.position = point
		var sprite: Sprite3D = actor.get_node("Sprite3D")
		var frame: Dictionary = library.catalogue.animals[record.kind]["0"][0][0]
		sprite.texture = library.frame_texture(frame)
		sprite.offset.y = float(frame.foot_y)-float(library.catalogue.canvas)*0.5
		sprite.material_override.set_shader_parameter("albedo_texture",sprite.texture)
		container.add_child(actor)
		actor.get_node("GroundShadow").show()
		visible_animals.append({"actor":actor,"record":record})

func _nearby() -> Dictionary:
	var player = economy.world.player
	var origin: Vector3 = player.global_position
	var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
	var nearest := 0.65*0.65
	var result := {}
	for entry in visible_animals:
		var offset: Vector3 = entry.actor.global_position-origin
		if offset.dot(direction)<0.08 or offset.length_squared()>nearest:
			continue
		nearest = offset.length_squared()
		result = entry.record
	return result

func prompt() -> String:
	var record := _nearby()
	return "E 照料"+NAMES[record.kind] if not record.is_empty() else ""

func interact() -> bool:
	var record := _nearby()
	if record.is_empty() or economy.world.player.actions.carried_id!=0:
		return false
	var options: Array = []
	if not record.fed:
		options.append(["喂食",_feed.bind(record)])
	if record.product and record.kind=="chicken":
		options.append(["捡鸡蛋",_collect.bind(record,134)])
	options.append(["结束",economy.dialogue.close])
	var message := "今天已喂食。" if record.fed else "今天还没喂食。"
	if record.product and record.kind in ["cow","sheep"]:
		message += " 可以使用"+("挤奶器。" if record.kind=="cow" else "剪毛器。")
	economy.dialogue.show_choices(NAMES[record.kind],message,options)
	return true

func _feed(record: Dictionary) -> void:
	var feed := 105 if record.kind=="chicken" else 104
	if not economy.take(feed):
		var harvest: Dictionary = economy.world.farm_field.crops.harvest
		if feed!=104 or int(harvest.get(feed,0))==0:
			economy.dialogue.show_choices(NAMES[record.kind],"饲料不足。",[["结束",economy.dialogue.close]])
			return
		harvest[feed] -= 1
	record.fed = true
	economy.world.record_player_action("喂了"+NAMES[record.kind])
	interact()

func use_tool(tool: int) -> void:
	if tool not in [26,27]:
		return
	var record := _nearby()
	if record.is_empty() or not record.product or record.kind!=("cow" if tool==26 else "sheep"):
		return
	if economy.count(tool)==0:
		economy.message = "请先购买"+economy.item_name(tool)
		return
	_collect(record,139 if tool==26 else 145)

func _collect(record: Dictionary, item: int) -> void:
	if not record.product:
		return
	record.product = false
	if item==145:
		record.cooldown = 7
	economy._add(item)
	economy.message = "获得"+economy.item_name(item)
	economy.world.record_player_action("获得了"+economy.item_name(item))
	if economy.dialogue.overlay.visible:
		interact()

extends Node
## Selects the original ordinary-day rows for the currently loaded location.
const SpriteLibrary := preload("res://game/original_sprites/sprite_library.gd")
const Villager := preload("res://game/npc/villager.tscn")
const CATALOGUE_PATH := "res://game/npc/npc_catalogue.json"
const DAY_START := 360
# Original 16.16 movement uses 768/256 times a 4096-scale trig value at 30 Hz.
const OUTDOOR_SPEED := 1.44
const INDOOR_SPEED := 0.48
const COAST := [52,56]
const NAMES := {
	"jeff":"杰夫", "sasha":"莎夏", "karen":"卡莲", "saibara":"赛巴拉", "gray":"格雷",
	"doug":"达特", "ann":"兰", "doctor":"多特", "elli":"艾丽", "pastor_carter":"卡特",
	"cliff":"克里夫", "basil":"巴吉尔", "anna":"安娜", "mary":"玛丽", "barley":"穆奇",
	"may":"梅", "mayor_thomas":"托马斯", "lillia":"莉莉雅", "rick":"里克", "popuri":"珀布莉",
	"duke":"迪克", "manna":"玛娜", "ellen":"艾莲", "gotz":"哥茨", "kai":"凯", "zack":"扎克",
	"harris":"哈里斯", "kano":"凯诺", "louis":"路易斯", "greg":"格雷格", "stu":"优", "won":"霍安",
	"chef":"切夫", "nappy":"纳皮", "timid":"提米德", "hoggy":"霍格", "staid":"斯泰德",
	"bold":"博尔德", "aqua":"阿库亚",
}

var world
var library
var location: Node3D
var active := {}
var scheduled_areas := {}
var clock_key := Vector4i(-1,-1,-1,-1)
var dialogue


func enter_location(next_location: Node3D) -> void:
	location = next_location
	active.clear()
	dialogue.close()
	clock_key = Vector4i(-1,-1,-1,-1)
	update(0.0)


func update(_delta: float) -> void:
	var clock = world.day_cycle
	var key := Vector4i(clock.year,clock.season,clock.weekday,clock.minute)
	if key == clock_key:
		return
	clock_key = key
	if library == null:
		library = SpriteLibrary.new(CATALOGUE_PATH)
	var day_index: int = (0 if clock.year==0 else 28)+clock.season*7+clock.weekday
	var minute := posmod(clock.minute-DAY_START,1440)
	var areas: Array = COAST if world.current_area in COAST else [world.current_area]
	for name in library.catalogue.actors:
		var record: Dictionary = library.catalogue.actors[name]
		var variant := int(record.days[day_index])
		var step: Array = _current_step(record.schedules[variant],minute) if variant>=0 else []
		var scheduled_area := -1 if step.is_empty() else int(step[1])
		scheduled_areas[name] = scheduled_area
		if scheduled_area not in areas:
			_remove(name)
			continue
		var area := str(scheduled_area)
		var row := str(int(step[2]))
		var itinerary: Array = library.catalogue.routes[area][row]
		if itinerary[0].is_empty():
			_remove(name)
			continue
		var pack := str(int(record.area_art.get(area,record.default_art)))
		_place(name,int(area),row,record.art[pack],itinerary,(minute-float(step[0]))*0.5)
	if world.current_area==200:
		for name in library.catalogue.helpers:
			var helper: Dictionary = library.catalogue.helpers[name]
			_place(name,200,"home",helper.poses,[[helper.spot],-1,false],0.0)


func _current_step(schedule: Array, minute: int) -> Array:
	var result: Array = []
	for step: Array in schedule:
		if int(step[0])>minute:
			break
		result = step
	return result


func _remove(name: String) -> void:
	if not active.has(name):
		return
	var actor: Node = active[name]
	location.remove_child(actor)
	actor.queue_free()
	active.erase(name)


func _place(name: String, area: int, row: String, poses: Array, route: Array, elapsed: float) -> void:
	var actor = active.get(name)
	var route_key := str(area)+"/"+row
	if actor != null and actor.get_meta("route")==route_key:
		return
	var points := []
	for cell: Array in route[0]:
		var point: Vector3 = world.area_to_world(area,Vector3(cell[0],cell[1],cell[2])*0.001)
		points.append([point,int(cell[3]),float(cell[4])/30.0])
	if actor == null:
		actor = Villager.instantiate()
		actor.name = name
		actor.world = world
		actor.display_name = NAMES[name]
		actor.art = library
		actor.poses = poses
		var flags: int = world.day_cycle.catalogue.areas[str(area)].source_flags
		actor.speed = INDOOR_SPEED if flags&0x1000 else OUTDOOR_SPEED
		actor.set_itinerary(points,int(route[1]),elapsed)
		location.add_child(actor)
		active[name] = actor
	else:
		actor.set_itinerary(points,int(route[1]),0.0,bool(route[2]))
	actor.set_meta("route",route_key)


func _nearby():
	var best = null
	var distance := 0.53*0.53
	var player: CharacterBody3D = world.player
	var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
	for actor in active.values():
		if not actor.placed:
			continue
		var offset: Vector3 = actor.global_position-player.global_position
		if absf(offset.y)>0.2 or offset.dot(direction)<0.12:
			continue
		var squared := Vector2(offset.x,offset.z).length_squared()
		if squared < distance:
			best = actor
			distance = squared
	return best


func people_near(observer: CharacterBody3D) -> PackedStringArray:
	var result := PackedStringArray()
	var origin := observer.global_position
	var space := observer.get_world_3d().direct_space_state
	var eye := Vector3.UP*0.35
	for id in active:
		var actor = active[id]
		if actor == observer or not actor.placed or not actor.is_visible_in_tree():
			continue
		var position: Vector3 = actor.global_position
		var offset := position-origin
		if absf(offset.y)>0.4 or offset.length_squared()>4.0:
			continue
		# Solid props, ground and closed doorway stops can block sight.
		var query := PhysicsRayQueryParameters3D.create(
			origin+eye,position+eye,1|2|16,[observer.get_rid(),actor.get_rid()])
		if space.intersect_ray(query).is_empty():
			result.append(id)
	return result


func greet() -> void:
	if world.transitioning or world.day_cycle.menu_open or world.player.actions.busy() or world.player.actions.carried_id!=0:
		return
	if not world.nearby_exit.is_empty():
		return
	var counter = world.economy.counter_actor()
	if counter!=null and world.economy.shop_interact(counter):
		return
	var actor = _nearby()
	if actor != null and not world.economy.shop_interact(actor):
		dialogue.begin(actor)


func prompt() -> String:
	var counter = world.economy.counter_actor()
	if counter!=null:
		return "Z 在柜台购物"
	var actor = _nearby()
	if actor==null:
		return ""
	return "Z 与%s%s" % [actor.display_name,"交谈" if world.economy.offer_for(str(actor.name)).is_empty() else "互动"]

extends Node
## Selects the original ordinary-day rows for the currently loaded location.
const SpriteLibrary := preload("res://game/original_sprites/sprite_library.gd")
const Travel := preload("res://game/npc/npc_travel.gd")
const Villager := preload("res://game/npc/villager.tscn")
const CATALOGUE_PATH := "res://game/npc/npc_catalogue.json"
const DAY_START := 360
# Original 16.16 movement uses 768/256 times a 4096-scale trig value at 30 Hz.
const OUTDOOR_SPEED := 1.44
const INDOOR_SPEED := 0.48
const COAST := [52,56]
const CONVERSATION_RANGE := 2.4
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
var travel := Travel.new()
var location: Node3D
var active := {}
var scheduled_areas := {}
var scheduled_spots := {}
var clock_key := Vector4i(-1,-1,-1,-1)
var dialogue
var player_arrivals := {}
var awareness_elapsed := 0.0


func enter_location(next_location: Node3D) -> void:
	location = next_location
	travel.setup(self)
	active.clear()
	player_arrivals.clear()
	awareness_elapsed = 0.0
	dialogue.close()
	clock_key = Vector4i(-1,-1,-1,-1)
	update(0.0,true)


func update(delta: float, loading := false) -> void:
	travel.tick(delta)
	awareness_elapsed += delta
	if awareness_elapsed>=0.2:
		awareness_elapsed = 0.0
		_notice_player()
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
	var previous_spots := scheduled_spots.duplicate()
	scheduled_spots.clear()
	for name in library.catalogue.actors:
		var record: Dictionary = library.catalogue.actors[name]
		var variant := int(record.days[day_index])
		var step: Array = _current_step(record.schedules[variant],minute) if variant>=0 else []
		var scheduled_area := -1 if step.is_empty() else int(step[1])
		var prior_area: int = scheduled_areas.get(name,-1)
		scheduled_areas[name] = scheduled_area
		if scheduled_area<0:
			_depart_for_schedule(name,-1)
			continue
		var area := str(scheduled_area)
		var row := str(int(step[2]))
		var itinerary: Array = library.catalogue.routes[area][row]
		if not itinerary[0].is_empty():
			scheduled_spots[name] = _local_point(itinerary[0][0])
		if travel.trips.has(name):
			continue
		if scheduled_area not in areas or itinerary[0].is_empty():
			_depart_for_schedule(name,scheduled_area if scheduled_area not in areas else -1)
			continue
		if not loading and not active.has(name) and prior_area!=scheduled_area:
			if travel.arrive_for_schedule(name,prior_area,previous_spots.get(name,Vector3.INF),
					scheduled_area,scheduled_spots[name]):
				continue
		var pack := str(int(record.area_art.get(area,record.default_art)))
		_place(name,int(area),row,record.art[pack],itinerary,(minute-float(step[0]))*clock.SECONDS_PER_MINUTE)
	for name in library.catalogue.helpers:
		var helper: Dictionary = library.catalogue.helpers[name]
		scheduled_areas[name] = 200
		scheduled_spots[name] = _local_point(helper.spot)
		if world.current_area==200 and not travel.trips.has(name):
			_place(name,200,"home",helper.poses,[[helper.spot],-1,false],0.0)


func _local_point(cell: Array) -> Vector3:
	return Vector3(cell[0],cell[1],cell[2])*0.001


func presence(id: String) -> Dictionary:
	var actor = active.get(id)
	if actor!=null and actor.placed:
		var area: int = world.area_at(actor.global_position)
		return {"area":area,"point":world.world_to_area(area,actor.global_position),"live":true,
			"activity":"前往%s" % world.world[str(travel.trips[id].destination)].name
				if travel.trips.has(id) and travel.trips[id].requested and travel.trips[id].phase!="visit"
				else ("走动" if actor.walking else "停留")}
	if travel.trips.has(id):
		var trip: Dictionary = travel.trips[id]
		return {"area":trip.area,"point":trip.point,"live":false,
			"activity":"临时到访" if trip.phase=="visit" else "在路上"}
	return {"area":scheduled_areas.get(id,-1),"point":scheduled_spots.get(id,Vector3.INF),"live":false,
		"activity":"日程位置" if scheduled_spots.has(id) else "暂无定位"}


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
	player_arrivals.erase(name)


func _depart_for_schedule(id: String, destination: int) -> void:
	if travel.trips.has(id) or not active.has(id):
		return
	var actor = active[id]
	if actor.placed:
		travel.start(actor,destination,false)
	else:
		_remove(id)


func _scheduled_point(area: int, cell: Array) -> Vector3:
	var point: Vector3 = world.area_to_world(area,_local_point(cell))
	for exit in world.world[str(area)].exits:
		if not exit.has("door"):
			continue
		var stop := location.get_node_or_null("DoorStop_%02d" % int(exit.index)) as StaticBody3D
		if stop==null:
			continue
		var inward: Vector3 = stop.get_meta("inward")
		var across := Vector3(inward.z,0,-inward.x)
		var offset := point-stop.global_position
		var depth := offset.dot(inward)
		var side := offset.dot(across)
		var half_width: float = stop.get_meta("half_width")
		if depth>=-0.28 and depth<=0.35 and absf(side)<=half_width and absf(offset.y)<0.8:
			# Regular schedule stops must leave the doorway available for travellers.
			var clear := stop.global_position-inward*0.48+across*(half_width+0.23)*(-1.0 if side<0.0 else 1.0)
			return Vector3(clear.x,point.y,clear.z)
	return point


func _place(name: String, area: int, row: String, poses: Array, route: Array, elapsed: float) -> void:
	var actor = active.get(name)
	var route_key := str(area)+"/"+row
	if actor != null and actor.get_meta("route","")==route_key:
		return
	var points := []
	for cell: Array in route[0]:
		points.append([_scheduled_point(area,cell),int(cell[3]),float(cell[4])/30.0])
	actor = _install_route(name,area,poses,points,int(route[1]),elapsed,bool(route[2]))
	actor.set_meta("route",route_key)


func place_traveller(id: String, area: int, points: Array):
	var poses: Array
	if library.catalogue.helpers.has(id):
		poses = library.catalogue.helpers[id].poses
	else:
		var record: Dictionary = library.catalogue.actors[id]
		var pack := str(int(record.area_art.get(str(area),record.default_art)))
		poses = record.art[pack]
	var actor = _install_route(id,area,poses,points,-1,0.0,false)
	if actor.has_meta("route"):
		actor.remove_meta("route")
	return actor


func _install_route(id: String, area: int, poses: Array, points: Array, repeat_from: int,
		elapsed: float, keep_position: bool):
	var actor = active.get(id)
	var flags: int = world.day_cycle.catalogue.areas[str(area)].source_flags
	var speed := INDOOR_SPEED if flags&0x1000 else OUTDOOR_SPEED
	if actor==null:
		actor = Villager.instantiate()
		actor.name = id
		actor.world = world
		actor.display_name = NAMES[id]
		actor.art = library
		actor.poses = poses
		actor.speed = speed
		actor.set_itinerary(points,repeat_from,elapsed)
		location.add_child(actor)
		active[id] = actor
	else:
		actor.speed = speed
		actor.set_itinerary(points,repeat_from,0.0,keep_position)
	return actor


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


func people_near(observer: CharacterBody3D, conversation := false) -> PackedStringArray:
	var result := PackedStringArray()
	var origin := observer.global_position
	var radius := CONVERSATION_RANGE if conversation else 2.0
	for id in active:
		var actor = active[id]
		if actor == observer or not actor.placed or not actor.is_visible_in_tree():
			continue
		var position: Vector3 = actor.global_position
		var offset := position-origin
		if absf(offset.y)>0.4 or offset.length_squared()>radius*radius:
			continue
		if _clear_sight(observer,actor,0.35) or (conversation and _clear_sight(observer,actor,0.55)):
			result.append(id)
	return result


func _notice_player() -> void:
	var visible := people_near(world.player)
	for id in player_arrivals.keys():
		if not visible.has(id):
			player_arrivals.erase(id)
	for id in visible:
		if player_arrivals.has(id):
			continue
		player_arrivals[id] = Time.get_ticks_msec()
		var actor = active[id]
		if not actor.walking:
			actor.greet(world.player.global_position,0.35)
	dialogue.consider_proactive(visible)


func _clear_sight(observer: CharacterBody3D, actor: CharacterBody3D, height: float) -> bool:
	var eye := Vector3.UP*height
	var query := PhysicsRayQueryParameters3D.create(observer.global_position+eye,actor.global_position+eye,
		1|2|16,[observer.get_rid(),actor.get_rid()])
	return observer.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func known_people(observer: CharacterBody3D) -> Dictionary:
	# Spatial awareness is wider than the radius for hearing a conversation.
	var result := {"near":PackedStringArray(),"elsewhere":PackedStringArray(),"same_shop":PackedStringArray()}
	var origin := observer.global_position
	var area: int = world.area_at(origin)
	var indoors: bool = int(world.day_cycle.catalogue.areas[str(area)].source_flags)&0x1000!=0
	for id in active:
		var actor = active[id]
		if actor==observer or not actor.placed or not actor.is_visible_in_tree():
			continue
		var offset: Vector3 = actor.global_position-origin
		var distance := Vector2(offset.x,offset.z).length()
		var same_area: bool = world.area_at(actor.global_position)==area
		if absf(offset.y)>0.4 or distance>6.0 or (distance>2.5 and not (indoors and same_area)):
			continue
		# A second sight line clears low counters while solid walls and floors still occlude.
		if not _clear_sight(observer,actor,0.35) and not _clear_sight(observer,actor,0.55):
			# The supermarket floor is one public room. Know who is in it,
			# but do not claim a precise position through an obstruction.
			if same_area and world.world[str(area)].slug=="supermarket":
				result.same_shop.append(NAMES[id])
			continue
		var relation := "就在你旁边" if distance<=0.8 else ("就在附近" if distance<=2.5 else "在同一处，隔着一段距离")
		var group := "near" if distance<=2.5 else "elsewhere"
		result[group].append("%s（%s）" % [NAMES[id],relation])
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

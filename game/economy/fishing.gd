extends Node
## A bite is timed on the source 30 Hz clock; releasing before it reels in empty.
const SPOT_KIND := {56:0,68:1,72:2,245:3}
const BITE_RANGE := [
	[0,479,[15,60,60,150,30]], [480,1079,[60,180,180,210,90]],
	[1080,1319,[30,120,120,210,60]], [1320,1439,[15,60,60,150,30]]
]
var economy
var source: Dictionary
var cast_point := Vector3.INF
var spot := 4
var wait := 0.0
var pull := 0.0
var started := false
var unique_catches := {}

func _physics_process(delta: float) -> void:
	var actions = economy.world.player.actions
	if actions.state!="fishing_wait":
		if actions.state not in ["cast","reel"]:
			started = false
			pull = 0.0
		return
	if not started:
		started = true
		cast_point = _water_ahead()
		if cast_point==Vector3.INF:
			economy.message = "鱼漂没有落在可钓鱼的水面。"
			return
		spot = SPOT_KIND.get(economy.world.current_area,4)
		economy.message = "按住工具键等鱼咬钩。"
		_reset_wait()
	if cast_point==Vector3.INF:
		return
	if pull>0:
		pull -= delta
		if pull<=0:
			economy.message = "鱼脱钩了，继续等下一次。"
			_reset_wait()
		return
	wait -= delta
	if wait>0:
		return
	if randi_range(0,99)<(40 if actions.equipped==57 else 20):
		pull = (5+randi_range(0,9 if spot==3 else 24))/30.0
		economy.message = "鱼咬钩了！松开工具键"
	else:
		_reset_wait()

func finish() -> void:
	var landed := pull>0.0
	started = false
	pull = 0.0
	var item := _roll() if landed else 0
	if item==0:
		economy.message = "没有钓到东西。"
		return
	economy._add(item)
	economy.message = "钓到了"+economy.item_name(item)
	economy.world.record_player_action(economy.message)

func _reset_wait() -> void:
	var minute: int = economy.world.day_cycle.minute
	for row in BITE_RANGE:
		if minute>=row[0] and minute<=row[1]:
			wait = float(row[2][spot])/30.0
			return

func _roll() -> int:
	var table: Array = source.seasonal[economy.world.day_cycle.season] if spot==0 else source.catches[str(spot)]
	var roll := randi_range(0,99)
	for index in range(0,table.size(),2):
		roll -= int(table[index])
		if roll>=0:
			continue
		var item := int(table[index+1])
		if item in [62,103,234,237,238,239,240,241,242]:
			if unique_catches.has(item):
				continue
			unique_catches[item] = true
		return item
	return 0

func _water_ahead() -> Vector3:
	if source.is_empty():
		source = JSON.parse_string(FileAccess.get_file_as_string("res://game/economy/source_fishing.json"))
	var world = economy.world
	var player = world.player
	var polygons: Array = source.water.get(str(world.current_area),[])
	if polygons.is_empty():
		return Vector3.INF
	var origin: Vector3 = world.world_to_area(world.current_area,player.global_position)
	var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
	for distance in [1.4,1.2,1.0,0.8,0.6]:
		var point: Vector3 = origin+direction*distance
		var target := Vector2(point.x,point.z)*1000.0
		for index in range(0,polygons.size(),8):
			var a := Vector2(polygons[index],polygons[index+1])
			var b := Vector2(polygons[index+2],polygons[index+3])
			var c := Vector2(polygons[index+4],polygons[index+5])
			var d := Vector2(polygons[index+6],polygons[index+7])
			if Geometry2D.point_is_inside_triangle(target,a,b,c) or (c!=d and Geometry2D.point_is_inside_triangle(target,b,d,c)):
				return point
	return Vector3.INF

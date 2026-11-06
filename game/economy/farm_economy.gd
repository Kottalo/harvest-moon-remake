extends Node
## Farm cash, stock, shipping and blacksmith orders belong to the current game.
const TOOL_BASES := [1,6,11,16,21]
const ORES := [124,123,122,96]
const UPGRADE_COST := [1000,2000,3000,5000]
const UPGRADE_EXP := [6000,18000,36000,65535]
const ANIMALS := {353:"calf",357:"sheep",265:"chicken"}
const GOODS_NAMES := {
	26:"挤奶器",27:"剪毛器",28:"刷子",29:"铃铛",30:"动物药",31:"牛孕药",32:"羊孕药",
	33:"青之羽毛",63:"木材",96:"秘银",97:"奥里哈钢",98:"精金",99:"番茄酱食谱",100:"篮子",104:"牧草饲料",105:"鸡饲料",
	109:"中背包",110:"大背包",103:"力量果实",122:"金矿石",123:"银矿石",124:"铜矿石",
	153:"饭团",154:"面包",155:"体力药",156:"高级体力药",157:"消疲劳药",158:"高级消疲劳药",
	132:"鱼饲料",159:"葡萄酒",160:"葡萄汁",161:"大鱼",162:"中鱼",163:"小鱼",165:"油",166:"面粉",167:"咖喱粉",168:"套餐",
	169:"山葡萄酒",170:"牛奶",171:"水",172:"刨冰",265:"鸡",304:"沙拉",305:"苹果派",
	306:"芝士蛋糕",307:"饼干",309:"烤玉米",310:"意大利面",311:"披萨",312:"废矿石",319:"蛋黄酱机",
	353:"小牛",357:"羊",134:"鸡蛋",139:"牛奶",145:"羊毛",
}
# The source farm has no active shipping-box zone. The remake exposes a farm drop-off.
const FARM_BOX := [1,-5.266,-3.108,-4.733,-2.944]
const SINGLE_PURCHASE := [26,27,28,29,33,100,109,110,319]

var world
var data: Dictionary
var shops: Dictionary
var gold := 500
var rucksack_delivery := 0
# Ownership, seeds and farm supply counters use their own native categories.
var stock := {34:1}
var rucksack := preload("res://game/items/rucksack.gd").new()
var shipped_value := 0
var last_income := 0
var levels := {}
var experience := {}
var order := {}
var animals: Array[Dictionary] = []
var dialogue
var livestock
var fishing
var supermarket
var message := ""

func setup(owner_world) -> void:
	world = owner_world
	name = "FarmEconomy"
	data = JSON.parse_string(FileAccess.get_file_as_string("res://game/economy/source_economy.json"))
	shops = JSON.parse_string(FileAccess.get_file_as_string("res://game/economy/shops.json"))
	world.day_cycle.minute_changed.connect(_minute_changed)
	world.day_cycle.day_started.connect(_new_day)
	world.player.actions.tool_used.connect(_gain_experience)
	world.player.actions.equipment_selected.connect(_equip)
	world.mine_field.found.connect(_mined)
	livestock = preload("res://game/economy/farm_animals.gd").new()
	livestock.economy = self
	add_child(livestock)
	fishing = preload("res://game/economy/fishing.gd").new()
	fishing.economy = self
	add_child(fishing)
	supermarket = preload("res://game/locations/supermarket/supermarket_goods.gd").new()
	supermarket.name = "SupermarketGoods"
	add_child(supermarket)
	supermarket.setup(self)
	world.player.actions.equipment_available = can_equip
	world.player.actions.quick_switch = rucksack.cycle_tool.bind(world.player.actions)
	world.player.actions.quick_seed_switch = rucksack.cycle_tool.bind(world.player.actions,true)

func buy_price(item: int) -> int:
	return int(data.prices.get(str(item),[0,0])[0])

func sell_price(item: int) -> int:
	return int(data.prices.get(str(item),[0,0])[1])

func item_name(item: int) -> String:
	if world.loose_items.HISTORY_NAMES.has(item):
		return world.loose_items.HISTORY_NAMES[item]
	var seeds: Dictionary = world.player.actions.seed_catalogue
	if seeds.has(str(item)):
		return seeds[str(item)].name+"种子"
	if GOODS_NAMES.has(item):
		return GOODS_NAMES[item]
	for seed in world.farm_field.crops.data.crops:
		var crop: Dictionary = world.farm_field.crops.data.crops[seed]
		if int(crop.get("harvest",0))==item and seeds.has(seed):
			return seeds[seed].name
	return "物品 %d" % item

func offer_for(id: String) -> Dictionary:
	var offer: Dictionary = shops.get(id,{})
	if offer.is_empty() or int(offer.area)!=world.current_area or (offer.get("summer",false) and world.day_cycle.season!=1):
		return {}
	return offer

func goods_for(id: String) -> Array:
	var offer := offer_for(id)
	var goods: Array = offer.get("goods",[]).duplicate()
	if id=="jeff":
		if rucksack.capacity!=2:
			goods.erase(109.0)
		if rucksack.capacity!=4 or rucksack_delivery>0:
			goods.erase(110.0)
	if offer.get("seasonal_seeds",false):
		var seasonal := [[34,35,36],[39,40,41],[44,45,46],[]]
		goods.append_array(seasonal[world.day_cycle.season])
		if world.day_cycle.season!=3:
			goods.append(54)
	return goods

func buy(id: String, item: int) -> String:
	if not goods_for(id).any(func(raw): return int(raw)==item):
		return "这家店现在没有这件商品。"
	var price := buy_price(item)
	if price<=0 and item!=171:
		return "这件商品暂时无法购买。"
	if item in SINGLE_PURCHASE and (count(item)>0 or world.player.actions.carried_id==item):
		return "你已经拥有这件物品。"
	if item==319 and not _has_animal("chicken"):
		return "鸡舍有鸡后才能订购。"
	if ANIMALS.has(item):
		var coop := item==265
		var occupied := animals.filter(func(record): return (record.kind=="chicken")==coop).size()
		if occupied >= (5 if coop else 10):
			return "已经没有空畜栏。"
	if gold<price:
		return "钱不够，需要 %d G。" % price
	if item!=171 and not ANIMALS.has(item) and not _add(item):
		return "背包已满。"
	gold -= price
	if world.player.actions.seed_catalogue.has(str(item)) and not rucksack.has_tool(world.player.actions,item):
		var slot := rucksack.tools.find(0)
		if slot>=0 and slot<rucksack.capacity:
			rucksack.tools[slot] = item
	if ANIMALS.has(item):
		animals.append({"kind":ANIMALS[item],"age":0,"fed":false,"product":false,"cooldown":0})
	elif item in [109,110]:
		rucksack.capacity = 4 if item==109 else 8
		if item==109:
			rucksack_delivery = 10
	supermarket.refresh()
	world.sound.cue("confirm")
	world.record_player_action("购买了"+item_name(item))
	return "已购买%s。剩余 %d G。" % [item_name(item),gold]

func can_equip(tool: int) -> bool:
	return tool in TOOL_BASES or tool==34 or count(tool)>0

func count(item: int) -> int:
	return int(stock.get(item,0))+rucksack.items.count(item)

func _add(item: int) -> bool:
	if item in [26,27,28,29,30,31,32,56,57,63,100,104,105,109,110,132,319] or world.player.actions.seed_catalogue.has(str(item)):
		stock[item] = int(stock.get(item,0))+1
		return true
	return rucksack.add_item(item)

func take(item: int) -> bool:
	if int(stock.get(item,0))>0:
		stock[item] -= 1
		return true
	return rucksack.take_item(item)

func receive(item: int) -> bool:
	if _add(item):
		return true
	var actions = world.player.actions
	if actions.carried_id!=0:
		return false
	actions.carried_id = item
	actions.update_held(false)
	return true

func _mined(item: int) -> void:
	if item==102:
		var amount := sell_price(item)
		gold += amount
		message = "挖到 %d G" % amount
	elif world.player.actions.start_pickup(item,false):
		message = "挖到"+item_name(item)

func _has_animal(kind: String) -> bool:
	return animals.any(func(record): return record.kind==kind)

func _gain_experience(tool: int, charge: int) -> void:
	livestock.use_tool(tool)
	if tool in [56,57]:
		fishing.finish()
	if tool<1 or tool>25:
		return
	var base: int = TOOL_BASES[(tool-1)/5]
	experience[base] = mini(65535,int(experience.get(base,0))+(150 if charge>0 else 40))

func _equip(tool: int) -> void:
	world.player.actions.upgrade = int(levels.get(tool,0))

func upgrade_tool(tool: int, tier: int) -> String:
	if not offer_for("saibara").get("upgrade",false) or tool not in TOOL_BASES or tier<1 or tier>4:
		return "请在锻冶屋选择要升级的农具。"
	if not order.is_empty():
		return "赛巴拉还在处理上一件农具。"
	if tier<=int(levels.get(tool,0)):
		return "这件农具已经达到这个等级。"
	if int(experience.get(tool,0))<UPGRADE_EXP[tier-1]:
		return "熟练度不足（%d / %d）。" % [experience.get(tool,0),UPGRADE_EXP[tier-1]]
	var ore: int = ORES[tier-1]
	if count(ore)==0 or gold<UPGRADE_COST[tier-1]:
		return "需要%s和 %d G。" % [item_name(ore),UPGRADE_COST[tier-1]]
	gold -= UPGRADE_COST[tier-1]
	take(ore)
	order = {"tool":tool,"tier":tier,"days":2}
	world.player.actions.service_tool = tool
	world.record_player_action("委托赛巴拉升级农具")
	return "赛巴拉收下了农具和矿石，两天后可来取。"

func collect_upgrade() -> String:
	if offer_for("saibara").is_empty():
		return "请到锻冶屋取回农具。"
	if order.is_empty() or order.days>0:
		return "农具还没有完成。"
	var tool: int = order.tool
	levels[tool] = order.tier
	order.clear()
	world.player.actions.service_tool = 0
	if world.player.actions.equipped==tool:
		_equip(tool)
	world.record_player_action("取回了升级后的农具")
	return "升级完成。"

func _new_day(_previous_season: int) -> void:
	rucksack_delivery = maxi(0,rucksack_delivery-1)
	if not order.is_empty():
		order.days = maxi(0,int(order.days)-1)
	for animal in animals:
		animal.age += 1
		if animal.kind=="calf" and animal.age>=14:
			animal.kind = "cow"
		animal.cooldown = maxi(0,int(animal.cooldown)-1)
		if animal.fed and animal.kind!="calf" and animal.cooldown==0:
			animal.product = true
		animal.fed = false
	livestock.bind_location()
	supermarket.refresh()

func _minute_changed(minute: int) -> void:
	if minute!=17*60+58 or shipped_value==0:
		return
	last_income = shipped_value
	gold += shipped_value
	shipped_value = 0

func shipping_near() -> bool:
	var rows: Array = data.shipping.get(str(world.current_area),[])
	if world.current_area==0:
		rows = [FARM_BOX]
	return _zone_ahead(rows)

func counter_actor():
	if world.current_area!=180 or world.player.actions.carried_id!=0 or not _zone_ahead(data.counters["180"]):
		return null
	var actor = world.npcs.active.get("jeff")
	return actor if actor!=null and actor.placed else null

func _zone_ahead(rows: Array) -> bool:
	var player = world.player
	var direction: Vector3 = player.actions.DIRECTIONS[player.facing]
	var point: Vector3 = world.world_to_area(world.current_area,player.global_position)+direction*0.25
	for row in rows:
		if int(row[0]) in [player.facing,999] and Rect2(row[1],row[2],row[3]-row[1],row[4]-row[2]).has_point(Vector2(point.x,point.z)):
			return true
	return false

func ship(item: int) -> String:
	var price := sell_price(item)
	if price<=0:
		return "这个物品不能出货。"
	var actions = world.player.actions
	if actions.carried_id==item:
		actions.carried_id = 0
		actions.held_sprite.hide()
	elif not take(item):
		return "没有这件物品。"
	shipped_value += price
	world.sound.cue("ship")
	world.record_player_action("出货了"+item_name(item))
	return "已出货，预计收入 %d G。" % shipped_value

func shop_interact(actor) -> bool:
	var id := str(actor.name)
	var offer := offer_for(id)
	if offer.is_empty():
		return false
	var options: Array = []
	if not goods_for(id).is_empty():
		options.append(["购买商品",_show_goods.bind(actor,false)])
	if offer.get("livestock",false):
		options.append(["购买动物",_show_goods.bind(actor,true)])
	if offer.get("upgrade",false):
		options.append(["升级工具",_show_upgrades.bind(actor)])
		if not order.is_empty():
			options.append(["取回工具",_shop_result.bind(actor,collect_upgrade)])
	if offer.get("exam",false):
		options.append(["检查身体 · 10 G",_shop_result.bind(actor,_exam)])
	if offer.get("fishing_rod",false) and count(56)==0:
		options.append(["领取钓竿",_shop_result.bind(actor,_fishing_rod)])
	if options.is_empty():
		return false
	options.append(["交谈",_chat.bind(actor)])
	dialogue.show_choices(actor.display_name,"持有 %d G" % gold,options)
	return true

func show_shelf(items: Array, result := "") -> void:
	var choices: Array = []
	for item in items:
		var id := int(item)
		var purchase := func(): show_shelf(items,_purchase_from_menu("jeff",id))
		if id not in SINGLE_PURCHASE or count(id)==0:
			choices.append(["%s · %d G" % [item_name(id),buy_price(id)],purchase])
	choices.append(["返回",dialogue.close])
	var balance := "持有 %d G" % gold
	dialogue.show_choices("杂货店",balance if result.is_empty() else result+"\n"+balance,choices)


func _chat(actor) -> void:
	dialogue.close()
	dialogue.begin(actor)

func _show_goods(actor, animals_only: bool, result := "") -> void:
	var options: Array = []
	for raw in goods_for(str(actor.name)):
		var item := int(raw)
		if ANIMALS.has(item)==animals_only:
			options.append(["%s · %d G" % [item_name(item),buy_price(item)],_buy_choice.bind(actor,item,animals_only)])
	options.append(["返回",shop_interact.bind(actor)])
	dialogue.show_choices(actor.display_name,"%s\n持有 %d G" % [result,gold],options)

func _buy_choice(actor, item: int, animals_only: bool) -> void:
	_show_goods(actor,animals_only,_purchase_from_menu(str(actor.name),item))


func _purchase_from_menu(seller: String, item: int) -> String:
	var result := buy(seller,item)
	if not result.begins_with("已购买"):
		world.sound.cue("refuse")
	return result

func _show_upgrades(actor) -> void:
	var options: Array = []
	var actions = world.player.actions
	for tool in TOOL_BASES:
		options.append([actions.TOOL_NAMES[actions.TOOL_IDS.find(tool)],_show_tiers.bind(actor,tool)])
	options.append(["返回",shop_interact.bind(actor)])
	dialogue.show_choices(actor.display_name,"选择要升级的农具",options)

func _show_tiers(actor, tool: int) -> void:
	var options: Array = []
	for tier in range(int(levels.get(tool,0))+1,5):
		options.append(["%s · %d G + %s" % [world.player.actions.LEVEL_NAMES[tier],UPGRADE_COST[tier-1],item_name(ORES[tier-1])],
			_shop_result.bind(actor,upgrade_tool.bind(tool,tier))])
	options.append(["返回",_show_upgrades.bind(actor)])
	dialogue.show_choices(actor.display_name,"请选择等级",options)

func _shop_result(actor, operation: Callable) -> void:
	dialogue.show_choices(actor.display_name,operation.call(),[["返回",shop_interact.bind(actor)]])

func _exam() -> String:
	if gold<10:
		return "检查需要 10 G。"
	gold -= 10
	return "检查结束。"

func _fishing_rod() -> String:
	_add(56)
	return "收下了钓竿。"

func show_shipping() -> void:
	var actions = world.player.actions
	if actions.carried_id!=0:
		dialogue.show_notice("出货箱",ship(actions.carried_id))
		return
	var options: Array = []
	var available := stock.duplicate()
	for item in rucksack.items:
		if item!=0:
			available[item] = count(item)
	for item in available:
		if int(available[item])>0 and sell_price(item)>0:
			options.append(["%s × %d · %d G" % [item_name(item),available[item],sell_price(item)],_ship_choice.bind(item)])
	options.append(["结束",dialogue.close])
	dialogue.show_choices("出货箱","待结算 %d G。把收成带到这里即可出货。" % shipped_value,options)

func _ship_choice(item: int) -> void:
	ship(item)
	show_shipping()

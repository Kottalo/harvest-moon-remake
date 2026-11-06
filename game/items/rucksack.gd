extends RefCounted
## The original has one held item plus 2, 4 or 8 slots per row.
const TOOLBOX_PAGES := 8
const TOOLBOX_PAGE_SIZE := 8
const TOOLBOX_FIRST_SLOT := 9
# title_new_game_toolbox: sickle, axe, hoe, hammer, watering can.
const STARTER_TOOLS := [1,11,6,16,21]

var toolbox: Array[int] = []
var items: Array[int] = [0,0,0,0,0,0,0,0]
var tools: Array[int] = [1,34,0,0,0,0,0,0]
var capacity := 2
var next_tool := 0

func _init() -> void:
	toolbox.resize(TOOLBOX_PAGES*TOOLBOX_PAGE_SIZE)
	toolbox.fill(0)


func has_tool(actions, item: int) -> bool:
	return active_tool(actions)==item or tools.has(item) or toolbox.has(item)


func sync_toolbox(actions, seed_count: Callable) -> void:
	var held := active_tool(actions)
	for index in toolbox.size():
		var item := toolbox[index]
		if item!=0 and (item==held or tools.has(item)):
			toolbox[index] = 0
	var catalogue: Array = STARTER_TOOLS.duplicate()
	for tool: int in actions.TOOL_IDS:
		if tool!=34 and tool not in STARTER_TOOLS:
			catalogue.append(tool)
	for key: String in actions.seed_catalogue:
		if seed_count.call(int(key))>0:
			catalogue.append(int(key))
	for item: int in catalogue:
		if not has_tool(actions,item) and (actions.seed_catalogue.has(str(item)) or actions.owns_tool(item)):
			var free := toolbox.find(0)
			if free>=0:
				toolbox[free] = item


func tool_at(actions, slot: int) -> int:
	if slot==0:
		return active_tool(actions)
	return tools[slot-1] if slot<TOOLBOX_FIRST_SLOT else toolbox[slot-TOOLBOX_FIRST_SLOT]


func put_tool(actions, slot: int, item: int) -> void:
	if slot==0:
		actions.set_bag_tool(item)
	elif slot<TOOLBOX_FIRST_SLOT:
		tools[slot-1] = item
	else:
		toolbox[slot-TOOLBOX_FIRST_SLOT] = item


func free_item_slot() -> int:
	var slot := items.find(0)
	return slot if slot<capacity else -1

func add_item(item: int) -> bool:
	var slot := free_item_slot()
	if slot<0:
		return false
	items[slot] = item
	return true

func compact_items() -> void:
	var occupied := items.slice(0,capacity).filter(func(item: int): return item!=0)
	for index in capacity:
		items[index] = occupied[index] if index<occupied.size() else 0

func take_item(item: int) -> bool:
	var slot := items.find(item)
	if slot<0:
		return false
	items[slot] = 0
	return true

func active_tool(actions) -> int:
	return actions.selected_seed if actions.equipped==34 else actions.equipped

func choose_tool(actions, item: int) -> bool:
	var previous := active_tool(actions)
	var tool := 34 if actions.seed_catalogue.has(str(item)) else item
	if not actions.select_tool(tool,item if tool==34 else -1):
		return false
	if previous==item:
		return true
	var slot := tools.find(item)
	if slot<0 and previous!=0:
		slot = tools.find(0)
	if slot>=0 and slot<capacity:
		tools[slot] = previous
	return true

func cycle_tool(actions, seeds_only := false) -> bool:
	for offset in capacity:
		var slot := (next_tool+offset)%capacity
		var item := tools[slot]
		if item!=0 and (not seeds_only or actions.seed_catalogue.has(str(item))) and choose_tool(actions,item):
			next_tool = (slot+1)%capacity
			return true
	return false

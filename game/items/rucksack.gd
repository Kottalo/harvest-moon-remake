extends RefCounted
## The original has one held item plus 2, 4 or 8 slots per row.
var items: Array[int] = [0,0,0,0,0,0,0,0]
var tools: Array[int] = [1,34,0,0,0,0,0,0]
var capacity := 2
var next_tool := 0

func add_item(item: int) -> bool:
	var slot := items.find(0)
	if slot<0 or slot>=capacity:
		return false
	items[slot] = item
	return true

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

func cycle_tool(actions) -> bool:
	for offset in capacity:
		var slot := (next_tool+offset)%capacity
		if tools[slot]!=0 and choose_tool(actions,tools[slot]):
			next_tool = (slot+1)%capacity
			return true
	return false

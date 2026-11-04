extends RefCounted
## One chronological journal for this world. Actor IDs also identify witnesses.
const RECENT_LIMIT := 8
const RELATED_LIMIT := 3

var entries: Array[Dictionary] = []

func record(kind: String, actor: String, content: String, witnesses: PackedStringArray,
		place: String, date: String) -> int:
	var known_by := PackedStringArray([actor])
	for witness in witnesses:
		if not known_by.has(witness):
			known_by.append(witness)
	entries.append({"kind":kind,"actor":actor,"content":content,
		"known_by":known_by,"place":place,"date":date})
	return entries.size()-1

func memory_for(npc_id: String, query: String, excluded := -1,
		conversation_group := PackedStringArray()) -> Array[Dictionary]:
	var memory: Array[Dictionary] = []
	var related := 0
	var words := _query_fragments(query)
	for index in range(entries.size()-1,-1,-1):
		var event := entries[index]
		if index == excluded or not event.known_by.has(npc_id):
			continue
		# A group reply may quote a past conversation only if the group heard it.
		if event.kind=="speech" and not _shared_with(event,conversation_group):
			continue
		if memory.size() >= RECENT_LIMIT:
			if words.is_empty() or related >= RELATED_LIMIT:
				break
			if not _matches(event.content,words):
				continue
			related += 1
		var detail := event.duplicate()
		detail.erase("known_by")
		memory.push_front(detail)
	return memory

func _shared_with(event: Dictionary, group: PackedStringArray) -> bool:
	for id in group:
		if not event.known_by.has(id):
			return false
	return true

func _query_fragments(query: String) -> PackedStringArray:
	var fragments := PackedStringArray()
	# Overlapping pairs also work for Chinese queries without word separators.
	var lower := query.to_lower()
	for index in range(lower.length()-1):
		var fragment := lower.substr(index,2)
		if not fragments.has(fragment) and fragment.strip_edges().length()==2:
			fragments.append(fragment)
	return fragments

func _matches(content: String, fragments: PackedStringArray) -> bool:
	var lower := content.to_lower()
	for fragment in fragments:
		if lower.contains(fragment):
			return true
	return false

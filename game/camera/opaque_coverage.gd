extends RefCounted
## Continuous camera centres inside the baked opaque projection. No runtime image.
const CELLS_PER_UNIT := 16.0
var _catalogue := {}
var _origin := Vector2.ZERO
var _coverage: Array[PackedInt32Array] = []
var _safe: Array[PackedVector2Array] = []


func set_area(area: int) -> void:
	_coverage.clear()
	_safe.clear()
	if area<0:
		return
	if _catalogue.is_empty():
		_catalogue = JSON.parse_string(FileAccess.get_file_as_string("res://game/camera/outdoor_coverage.json"))
	var data: Array = _catalogue[str(52 if area==56 else area)]
	_origin = Vector2(data[0][0],data[0][1])/CELLS_PER_UNIT
	for row: Array in data[1]:
		_coverage.append(PackedInt32Array(row))


func enabled() -> bool:
	return not _coverage.is_empty()


func fit(half: Vector2) -> bool:
	_safe.clear()
	if not enabled():
		return true
	_safe.resize(_coverage.size())
	var vertical := ceili(half.y*CELLS_PER_UNIT)
	var has_centre := false
	for row in range(vertical,_coverage.size()-vertical):
		var spans := _coverage[row]
		for sample in range(row-vertical,row+vertical+1):
			if spans.is_empty():
				break
			if sample!=row:
				spans = _intersect(spans,_coverage[sample])
		var safe := PackedVector2Array()
		for i in range(0,spans.size(),2):
			var low := _origin.x+spans[i]/CELLS_PER_UNIT+half.x
			var high := _origin.x+spans[i+1]/CELLS_PER_UNIT-half.x
			if low<=high:
				safe.append(Vector2(low,high))
		_safe[row] = safe
		has_centre = has_centre or not safe.is_empty()
	return has_centre


func nearest(point: Vector2, subject_centres := Rect2()) -> Vector2:
	var restricted := subject_centres.has_area()
	var row := floori((point.y-_origin.y)*CELLS_PER_UNIT)
	if row>=0 and row<_safe.size() and (not restricted or subject_centres.has_point(point)):
		for span in _safe[row]:
			if point.x>=span.x and point.x<=span.y:
				return point
	var best := INF
	var chosen := Vector2.INF
	for i in _safe.size():
		var bottom := _origin.y+i/CELLS_PER_UNIT
		var top := bottom+1.0/CELLS_PER_UNIT
		if restricted:
			bottom = maxf(bottom,subject_centres.position.y)
			top = minf(top,subject_centres.end.y)
			if bottom>top:
				continue
		var y := clampf(point.y,bottom,top)
		if (y-point.y)*(y-point.y)>=best:
			continue
		for span in _safe[i]:
			var low := span.x
			var high := span.y
			if restricted:
				low = maxf(low,subject_centres.position.x)
				high = minf(high,subject_centres.end.x)
				if low>high:
					continue
			var candidate := Vector2(clampf(point.x,low,high),y)
			var distance := candidate.distance_squared_to(point)
			if distance<best:
				chosen = candidate
				best = distance
	return chosen


func _intersect(a: PackedInt32Array, b: PackedInt32Array) -> PackedInt32Array:
	var result := PackedInt32Array()
	var i := 0
	var j := 0
	while i<a.size() and j<b.size():
		var low := maxi(a[i],b[j])
		var high := mini(a[i+1],b[j+1])
		if low<high:
			result.append(low)
			result.append(high)
		if a[i+1]<b[j+1]:
			i += 2
		else:
			j += 2
	return result

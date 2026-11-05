extends Control
# window_frame.c gives the PS1 bevel and the two fill colours in BGR.
func _draw() -> void:
	var w := size.x
	var h := size.y
	var light := Color("#d2ecfd")
	var dark := Color("#478bba")
	var top := Color("#bddff4")
	var bottom := Color("#8fcff9")
	draw_polygon(PackedVector2Array([Vector2(4,4),Vector2(w-4,4),Vector2(w-4,h-4),Vector2(4,h-4)]),
		PackedColorArray([top,top,bottom,bottom]))
	draw_rect(Rect2(4,0,w-8,4),light)
	draw_rect(Rect2(0,4,4,h-8),light)
	draw_rect(Rect2(w-4,4,4,h-8),dark)
	draw_rect(Rect2(4,h-4,w-8,4),dark)
	for corner in [Vector2(2,2),Vector2(w-4,2),Vector2(2,h-4),Vector2(w-4,h-4)]:
		draw_rect(Rect2(corner,Vector2(2,2)),Color("#609fc8"))

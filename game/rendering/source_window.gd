extends Control
## Native bevel colours and corner pixels from window_frame.c.
@export var source_pixel := 2.0

func _draw() -> void:
	var p := source_pixel
	var w := size.x
	var h := size.y
	var light := Color("#d2ecfd")
	var dark := Color("#478bba")
	var top := Color("#bddff4")
	var bottom := Color("#8fcff9")
	draw_polygon(PackedVector2Array([Vector2(2*p,2*p),Vector2(w-2*p,2*p),
		Vector2(w-2*p,h-2*p),Vector2(2*p,h-2*p)]),PackedColorArray([top,top,bottom,bottom]))
	draw_rect(Rect2(p,0,w-2*p,2*p),light)
	draw_rect(Rect2(0,p,2*p,h-2*p),light)
	draw_rect(Rect2(w-2*p,p,2*p,h-2*p),dark)
	draw_rect(Rect2(p,h-2*p,w-2*p,2*p),dark)
	draw_rect(Rect2(w-2*p,0,p,p),Color("#afdbf8"))
	draw_rect(Rect2(w-2*p,p,p,p),Color("#84bbde"))
	draw_rect(Rect2(w-p,p,p,p),Color("#609fc8"))
	draw_rect(Rect2(p,h-2*p,p,p),Color("#8bc0e2"))
	draw_rect(Rect2(p,h-p,p,p),Color("#609fc8"))
	draw_rect(Rect2(0,h-2*p,p,p),Color("#afdbf8"))

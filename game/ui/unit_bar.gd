class_name UnitBar
extends Control
## A bar on a unit frame: a dark track with a pointed far end that runs out
## from under the round portrait, filled from the portrait's side with a
## gradient (top `hi`, foot `lo`). `mirror` puts the portrait on the right,
## as on the target frame. The text sits in a Label child.

var hi := Color.RED
var lo := Color.DARK_RED
var mirror := false
var k := 1.0:
	set(v):
		v = clampf(v, 0, 1)
		if not is_equal_approx(v, k):
			k = v
			queue_redraw()

const TIP := 0.55 ## the point's length, as a share of the bar's height
const TRACK := Color("0c0a08", 0.9)
const EDGE := Color("6a5232")


func _init(h: Color, l: Color, height: int, mirrored := false) -> void:
	hi = h
	lo = l
	mirror = mirrored
	custom_minimum_size = Vector2(0, height)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func tint(h: Color, l: Color) -> void:
	hi = h
	lo = l
	queue_redraw()


## the track's outline: square at the portrait end, pointed at the other
func shape(grow := 0.0) -> PackedVector2Array:
	var w := size.x
	var h := size.y
	var t := h * TIP
	var pts := PackedVector2Array([
		Vector2(-grow, -grow), Vector2(w - t, -grow), Vector2(w + grow, h * 0.5),
		Vector2(w - t, h + grow), Vector2(-grow, h + grow)])
	if mirror:
		for i in pts.size():
			pts[i].x = w - pts[i].x
	return pts


func _draw() -> void:
	if size.x < 4:
		return
	draw_colored_polygon(shape(1.0), EDGE)
	draw_colored_polygon(shape(), TRACK)
	if k <= 0:
		return
	var cut := size.x * k
	var x0 := size.x - cut if mirror else 0.0
	var box := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + cut, 0), Vector2(x0 + cut, size.y), Vector2(x0, size.y)])
	for poly in Geometry2D.intersect_polygons(shape(-1.0), box):
		var cols := PackedColorArray()
		for p in poly:
			cols.append(hi.lerp(lo, clampf(p.y / size.y, 0, 1)))
		draw_polygon(poly, cols)
	# a thin light along the top edge, so the bar reads as glossy
	var y := 1.5
	var a := x0 + 1.0
	var b := minf(x0 + cut, size.x - size.y * TIP) - 1.0 if not mirror else x0 + cut - 1.0
	if mirror:
		a = maxf(x0, size.y * TIP) + 1.0
	if b > a:
		draw_line(Vector2(a, y), Vector2(b, y), Color(1, 1, 1, 0.22), 1.0)

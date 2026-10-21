class_name Canvas2D
extends RefCounted
## A small part of the browser's 2D canvas (CanvasRenderingContext2D),
## drawing onto a CanvasItem from inside its draw callback. The painted spell
## glyphs (src/ui/icons.js) and the minimap (src/ui/minimap.js) are written
## against the browser's canvas, so with this they port line for line.
##
## Paths are flattened to points as they are built (arcs, ellipses and
## curves included), in the current transform. Strokes are polylines with
## round ends; fills are polygons. A radial gradient fills a disc around its
## centre in rings.

var ci: CanvasItem
var line_width := 1.0
var global_alpha := 1.0
var font_size := 12
var round_caps := true
var _stroke = Color.BLACK
var _fill = Color.BLACK
var _dash: Array = []
var _paths: Array = [] ## [{pts: PackedVector2Array, closed: bool}]
var _xf := Transform2D.IDENTITY
var _stack: Array = []

## a colour, a CSS colour string ('#c8c4b8', 'rgba(230,200,140,0.6)') or a gradient
var stroke_style:
	get:
		return _stroke
	set(v):
		_stroke = css(v) if v is String else v
var fill_style:
	get:
		return _fill
	set(v):
		_fill = css(v) if v is String else v


func _init(item: CanvasItem) -> void:
	ci = item


static func css(s: String) -> Color:
	s = s.strip_edges()
	if s.begins_with("#"):
		return Color.html(s)
	if s.begins_with("rgb"):
		var inner := s.substr(s.find("(") + 1, s.rfind(")") - s.find("(") - 1).split(",")
		var a := float(inner[3]) if inner.size() > 3 else 1.0
		return Color8(int(inner[0]), int(inner[1]), int(inner[2]), int(roundf(a * 255)))
	return Color.html(s)


# ------------------------------------------------------------------ state
func save() -> void:
	_stack.append([_xf, _stroke, _fill, line_width, global_alpha, _dash.duplicate()])


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Array = _stack.pop_back()
	_xf = s[0]
	_stroke = s[1]
	_fill = s[2]
	line_width = s[3]
	global_alpha = s[4]
	_dash = s[5]


func translate(x: float, y: float) -> void:
	_xf = _xf.translated_local(Vector2(x, y))


func rotate(a: float) -> void:
	_xf = _xf.rotated_local(a)


func set_line_dash(d: Array) -> void:
	_dash = d.duplicate()


# ------------------------------------------------------------------ paths
func begin_path() -> void:
	_paths = []


func _current() -> Dictionary:
	if _paths.is_empty():
		_paths.append({"pts": PackedVector2Array(), "closed": false})
	return _paths[-1]


func move_to(x: float, y: float) -> void:
	_paths.append({"pts": PackedVector2Array([_xf * Vector2(x, y)]), "closed": false})


func line_to(x: float, y: float) -> void:
	var c := _current()
	c.pts.append(_xf * Vector2(x, y))


func close_path() -> void:
	if _paths.is_empty():
		return
	var c: Dictionary = _paths[-1]
	c.closed = true
	# the next segment starts where this one began, as a new piece
	if c.pts.size():
		_paths.append({"pts": PackedVector2Array([c.pts[0]]), "closed": false})


func arc(cx: float, cy: float, r: float, a0: float, a1: float) -> void:
	ellipse(cx, cy, r, r, 0.0, a0, a1)


func ellipse(cx: float, cy: float, rx: float, ry: float, rot: float, a0: float, a1: float) -> void:
	while a1 < a0:
		a1 += TAU
	var span := minf(a1 - a0, TAU)
	var n := maxi(6, int(ceil(span * maxf(rx, ry) / 1.5)))
	var c := _current()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n + 1:
		var a := a0 + span * i / n
		var ex := cos(a) * rx
		var ey := sin(a) * ry
		c.pts.append(_xf * Vector2(cx + ex * cr - ey * sr, cy + ex * sr + ey * cr))


func quadratic_curve_to(cpx: float, cpy: float, x: float, y: float) -> void:
	var c := _current()
	var inv := _xf.affine_inverse()
	var p0: Vector2 = inv * c.pts[-1] if c.pts.size() else Vector2(cpx, cpy)
	for i in range(1, 13):
		var t := i / 12.0
		var p := p0 * (1 - t) * (1 - t) + Vector2(cpx, cpy) * 2 * (1 - t) * t + Vector2(x, y) * t * t
		c.pts.append(_xf * p)


func rect_path(x: float, y: float, w: float, h: float) -> void:
	move_to(x, y)
	line_to(x + w, y)
	line_to(x + w, y + h)
	line_to(x, y + h)
	close_path()


# ------------------------------------------------------------------ drawing
func _tint(c: Color) -> Color:
	return Color(c, c.a * global_alpha)


func stroke() -> void:
	if not (_stroke is Color):
		return
	var col := _tint(_stroke)
	for p in _paths:
		var pts: PackedVector2Array = p.pts
		if pts.size() < 2:
			continue
		if p.closed:
			pts = pts.duplicate()
			pts.append(pts[0])
		if not _dash.is_empty():
			_dashed(pts, col)
			continue
		ci.draw_polyline(pts, col, line_width, true)
		# round ends and corners (lineCap / lineJoin 'round'), for solid strokes
		if round_caps and col.a > 0.98 and line_width >= 2.5:
			for i in pts.size():
				var corner: bool = i == 0 or i == pts.size() - 1
				if not corner:
					var d0 := (pts[i] - pts[i - 1]).normalized()
					var d1 := (pts[i + 1] - pts[i]).normalized()
					corner = d0.dot(d1) < 0.94
				if corner and not (p.closed and (i == 0 or i == pts.size() - 1) and false):
					ci.draw_circle(pts[i], line_width / 2.0, col)


func _dashed(pts: PackedVector2Array, col: Color) -> void:
	var on := true
	var k := 0
	var left: float = _dash[0]
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		var at := 0.0
		while at < seg:
			var step := minf(left, seg - at)
			if on:
				ci.draw_line(a.lerp(b, at / seg), a.lerp(b, (at + step) / seg), col, line_width, true)
			at += step
			left -= step
			if left <= 0.0001:
				k = (k + 1) % _dash.size()
				left = _dash[k]
				on = not on


func fill() -> void:
	for p in _paths:
		var pts: PackedVector2Array = p.pts
		if pts.size() < 3:
			continue
		if _fill is Dictionary:
			_gradient_fill(pts, _fill)
			continue
		var clean := PackedVector2Array()
		for q in pts:
			if clean.is_empty() or clean[-1].distance_to(q) > 0.01:
				clean.append(q)
		if clean.size() > 2 and clean[0].distance_to(clean[-1]) < 0.01:
			clean.remove_at(clean.size() - 1)
		if clean.size() < 3 or Geometry2D.triangulate_polygon(clean).is_empty():
			continue
		ci.draw_colored_polygon(clean, _tint(_fill))


func fill_rect(x: float, y: float, w: float, h: float) -> void:
	var saved := _paths
	begin_path()
	rect_path(x, y, w, h)
	fill()
	_paths = saved


func clear_rect(_x: float, _y: float, _w: float, _h: float) -> void:
	pass # draws start clear


# ------------------------------------------------------------------ gradients
func create_radial_gradient(x0: float, y0: float, r0: float, x1: float, y1: float, r1: float) -> Dictionary:
	return {"kind": "radial", "c": _xf * Vector2(x1, y1), "c0": _xf * Vector2(x0, y0), "r0": r0, "r1": r1, "stops": []}


func create_linear_gradient(x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	return {"kind": "linear", "a": _xf * Vector2(x0, y0), "b": _xf * Vector2(x1, y1), "stops": []}


static func add_color_stop(g: Dictionary, at: float, colour) -> void:
	g.stops.append([at, css(colour) if colour is String else colour])


## a gradient's colour at t (0..1), mixed with premultiplied alpha as browsers do
static func gradient_at(g: Dictionary, t: float) -> Color:
	var s: Array = g.stops
	if s.is_empty():
		return Color(0, 0, 0, 0)
	if t <= s[0][0]:
		return s[0][1]
	for i in range(1, s.size()):
		if t <= s[i][0]:
			var a: Color = s[i - 1][1]
			var b: Color = s[i][1]
			var k: float = (t - s[i - 1][0]) / maxf(0.0001, s[i][0] - s[i - 1][0])
			var pa := Color(a.r * a.a, a.g * a.a, a.b * a.a, a.a)
			var pb := Color(b.r * b.a, b.g * b.a, b.b * b.a, b.a)
			var m := pa.lerp(pb, k)
			return Color(m.r / m.a, m.g / m.a, m.b / m.a, m.a) if m.a > 0.0001 else Color(b, 0)
	return s[-1][1]


func _gradient_fill(pts: PackedVector2Array, g: Dictionary) -> void:
	if g.kind == "linear":
		_linear_fill(pts, g)
		return
	# beyond the outer ring the last colour holds: fill the shape with it,
	# then lay the rings over it out from the centre
	var outer := _tint(gradient_at(g, 1.0))
	if outer.a > 0.001:
		ci.draw_colored_polygon(pts, outer)
	var c: Vector2 = g.c
	var reach := 0.0
	for q in pts:
		reach = maxf(reach, q.distance_to(c))
	var r1: float = minf(g.r1, reach)
	var rings := 18
	var segs := 40
	for k in rings:
		var ra := r1 * k / rings
		var rb := r1 * (k + 1) / rings
		var ca := _tint(gradient_at(g, clampf((ra - g.r0) / (g.r1 - g.r0), 0, 1)))
		var cb := _tint(gradient_at(g, clampf((rb - g.r0) / (g.r1 - g.r0), 0, 1)))
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var u0 := Vector2(cos(a0), sin(a0))
			var u1 := Vector2(cos(a1), sin(a1))
			ci.draw_polygon(PackedVector2Array([c + u0 * ra, c + u1 * ra, c + u1 * rb, c + u0 * rb]), PackedColorArray([ca, ca, cb, cb]))


## a linear gradient across a rectangle (only axis-aligned rectangles are used)
func _linear_fill(pts: PackedVector2Array, g: Dictionary) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts:
		r = r.expand(q)
	var a: Vector2 = g.a
	var b: Vector2 = g.b
	var vertical := absf(b.y - a.y) >= absf(b.x - a.x)
	var stops: Array = g.stops
	# the colour before the first and after the last stop
	var lo := a.y if vertical else a.x
	var hi := b.y if vertical else b.x
	var bands := [[r.position.y if vertical else r.position.x, lo, 0.0, 0.0]]
	for i in stops.size() - 1:
		bands.append([lo + (hi - lo) * stops[i][0], lo + (hi - lo) * stops[i + 1][0], stops[i][0], stops[i + 1][0]])
	bands.append([hi, r.end.y if vertical else r.end.x, 1.0, 1.0])
	for band in bands:
		var from: float = clampf(band[0], r.position.y if vertical else r.position.x, r.end.y if vertical else r.end.x)
		var to: float = clampf(band[1], r.position.y if vertical else r.position.x, r.end.y if vertical else r.end.x)
		if to <= from:
			continue
		var c0 := _tint(gradient_at(g, band[2]))
		var c1 := _tint(gradient_at(g, band[3]))
		var quad: PackedVector2Array
		if vertical:
			quad = PackedVector2Array([Vector2(r.position.x, from), Vector2(r.end.x, from), Vector2(r.end.x, to), Vector2(r.position.x, to)])
		else:
			quad = PackedVector2Array([Vector2(from, r.position.y), Vector2(to, r.position.y), Vector2(to, r.end.y), Vector2(from, r.end.y)])
		var cols := PackedColorArray([c0, c0, c1, c1]) if vertical else PackedColorArray([c0, c1, c1, c0])
		ci.draw_polygon(quad, cols)


# ------------------------------------------------------------------ text and images
## centred on (x, y), as with textAlign 'center' and textBaseline 'middle'
func fill_text(text: String, x: float, y: float, use_font: Font = null) -> void:
	var f := use_font if use_font else UI.bold
	var col := _tint(_fill) if _fill is Color else Color.WHITE
	ci.draw_string(f, _text_pos(f, text, x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func stroke_text(text: String, x: float, y: float, use_font: Font = null) -> void:
	var f := use_font if use_font else UI.bold
	var col := _tint(_stroke) if _stroke is Color else Color.BLACK
	ci.draw_string_outline(f, _text_pos(f, text, x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, int(line_width * 2), col)


func _text_pos(f: Font, text: String, x: float, y: float) -> Vector2:
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var asc := f.get_ascent(font_size)
	var desc := f.get_descent(font_size)
	return _xf * Vector2(x - w / 2.0, y + (asc - desc) / 2.0)


func draw_image(tex: Texture2D, x: float, y: float, w: float, h: float) -> void:
	ci.draw_set_transform_matrix(_xf)
	ci.draw_texture_rect(tex, Rect2(x, y, w, h), false, Color(1, 1, 1, global_alpha))
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

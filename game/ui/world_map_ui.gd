class_name WorldMapUI
extends Control
## The world map (M): the whole world as Dan painted it (data/world_map.json):
## coast, zones with their names and levels, mountains, rivers, the roads
## and boat routes, Act 1 in detail, the places you have discovered and where
## you are. Scroll to zoom, drag to pan; it opens centred on you.

const SEA := Color("1c3440")
const LAND := Color("50603a")
const BIOME := {
	"temperate": Color("50603a"), "shore": Color("7a7458"), "farmland": Color("6a6a3c"), "forest": Color("34482c"),
	"marsh": Color("4a5640"), "swamp": Color("3a4632"), "moor": Color("5a4a4e"), "haunted": Color("3c3644"),
	"rocky": Color("66605a"), "desert": Color("9a7c50"), "sandy": Color("a89a6c"), "jungle": Color("2e5028"),
	"snow": Color("b8bec4"), "volcanic": Color("4a2c26"),
}
const KIND_COLOUR := {"town": Color("f0d890"), "village": Color("e0c880"), "dock": Color("9fd0ff"), "inn": Color("e0b070"),
	"fort": Color("c0a080"), "camp": Color("d09060"), "hut": Color("c8b890"), "ruin": Color("a09890"), "landmark": Color("d0d0e0"),
	"gate": Color("e08060"), "trainer": Color("a0e0a0"), "dungeon": Color("e06050"), "secret": Color("c090ff")}

var game
var center := Vector2.ZERO
var scale_px := 0.25 ## screen pixels per metre
var _drag := false
var _font: Font
var _coast := PackedVector2Array()
var _islands: Array = []
var _zones: Array = [] ## {poly, colour, name, levels, label}
var _rock: Array = []
var _snow: Array = []
var _forest: Array = []


func _init(g) -> void:
	game = g
	name = "WorldMap"
	visible = false
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UI.bold if UI.bold else ThemeDB.fallback_font
	var w: Dictionary = DB.world_map.get("world", {})
	if w.is_empty():
		return
	_coast = _pts(w.coast)
	for i in w.islands:
		_islands.append(_pts(i.poly) if i.has("poly") else _circle(i.at, i.r))
	for z in w.zones:
		var poly := _pts(z.poly) if z.has("poly") else PackedVector2Array()
		_zones.append({"poly": poly, "colour": BIOME.get(z.biome, LAND), "name": z.name, "levels": z.get("levels", ""), "label": Vector2(z.label[0], z.label[1]), "act": z.get("act", "")})
	var t: Dictionary = DB.world_map.get("terrain", {}).get("terrain", {})
	for p in t.get("rock", []) + t.get("volcanic", []):
		_rock.append(_pts(p))
	for p in t.get("snow", []):
		_snow.append(_pts(p))
	for p in t.get("forest", []):
		_forest.append(_pts(p))


static func _pts(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in list:
		out.append(Vector2(p[0], p[1]))
	return out


static func _circle(at: Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 20:
		var a := TAU * k / 20.0
		out.append(Vector2(at[0], at[1]) + Vector2(cos(a), sin(a)) * r)
	return out


func open() -> void:
	var p: Vector3 = game.player.position
	center = Vector2(p.x, p.z)
	scale_px = 0.35
	visible = true
	layout()
	queue_redraw()


func layout() -> void:
	var vp := get_viewport_rect().size
	size = (vp * Vector2(0.84, 0.86)).round()
	position = ((vp - size) / 2).round()


func _to_screen(v: Vector2) -> Vector2:
	return size / 2 + (v - center) * scale_px


func _xf(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(poly.size())
	for i in poly.size():
		out[i] = _to_screen(poly[i])
	return out


func _poly(poly: PackedVector2Array, c: Color) -> void:
	if poly.size() < 3:
		return
	var pts := _xf(poly)
	# a concave outline can fail to triangulate: draw its edge instead
	if Geometry2D.triangulate_polygon(pts).is_empty():
		pts.append(pts[0])
		draw_polyline(pts, c, 2.0)
		return
	draw_colored_polygon(pts, c)


func _line(line: Array, c: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for p in line:
		pts.append(_to_screen(Vector2(p[0], p[1])))
	if pts.size() > 1:
		draw_polyline(pts, c, width, true)


func _text(at: Vector2, text: String, size_px: int, c: Color) -> void:
	var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	var p := at - Vector2(w / 2, -size_px * 0.35)
	draw_string_outline(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 4, Color(0, 0, 0, 0.8))
	draw_string(_font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, c)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	_poly(_coast, LAND)
	for i in _islands:
		_poly(i, LAND)
	for z in _zones:
		_poly(z.poly, z.colour)
	for p in _forest:
		_poly(p, Color(0.12, 0.2, 0.1, 0.45))
	for p in _rock:
		_poly(p, Color(0.42, 0.4, 0.38, 0.9))
	for p in _snow:
		_poly(p, Color(0.85, 0.87, 0.9, 0.9))
	var w: Dictionary = DB.world_map.world
	# zone borders
	for z in _zones:
		if z.poly.size() > 2:
			var pts := _xf(z.poly)
			pts.append(pts[0])
			draw_polyline(pts, Color(0, 0, 0, 0.35), 1.5)
	# rivers, lakes, the roads and the boats
	for r in DB.water.get("rivers", []):
		_line(r.points, Color("3a6a78"), maxf(1.5, r.width * scale_px))
	for l in DB.water.get("lakes", []):
		var pts := PackedVector2Array()
		for k in 32:
			var a := TAU * k / 32.0
			pts.append(Vector2(l.center[0] + cos(a) * l.rx, l.center[1] + sin(a) * l.rz))
		_poly(pts, Color("2c5056"))
	for road in Terrain.roads():
		if road.half > 0:
			_line(road.points, Color("c8a870") if road.kind == "road" else Color("a08860", 0.9), 2.0 if road.kind == "road" else 1.2)
	for r in w.routes:
		if r.kind == "boat":
			var pts := PackedVector2Array()
			for p in r.line:
				pts.append(_to_screen(Vector2(p[0], p[1])))
			for k in pts.size() - 1:
				draw_dashed_line(pts[k], pts[k + 1], Color("9fd0ff", 0.8), 1.5, 6.0)
	# zone names
	for z in _zones:
		_text(_to_screen(z.label), z.name.to_upper(), 15 if scale_px < 0.6 else 18, Color("f0e0b0"))
		if z.levels != "":
			_text(_to_screen(z.label) + Vector2(0, 16), "%s  ·  levels %s" % [z.act, z.levels] if z.act != "" else "levels %s" % z.levels, 11, Color("d0c0a0"))
	# Act 1's regions, close up
	if scale_px >= 0.5:
		for r in DB.world_map.act1.regions:
			var c := Vector2.ZERO
			for p in r.poly:
				c += Vector2(p[0], p[1])
			c = c / r.poly.size() + WorldMap.offset
			_text(_to_screen(c), r.name, 12, Color("e8d8b0", 0.85))
	# discovered places
	for p in WorldMap.pois:
		if not game.discovery.is_discovered(p.id):
			continue
		var s := _to_screen(Vector2(p.at[0], p.at[1]))
		if s.x < 0 or s.y < 0 or s.x > size.x or s.y > size.y:
			continue
		var c: Color = KIND_COLOUR.get(p.kind, Color("e8d8b0"))
		draw_circle(s, 4.0, Color.BLACK)
		draw_circle(s, 3.0, c)
		if scale_px >= 0.45 or p.kind in ["town", "dock", "landmark"]:
			_text(s + Vector2(0, -12), p.name, 11, c)
	for d in game.discovery.docks:
		var s := _to_screen(d.at)
		draw_rect(Rect2(s - Vector2(3, 3), Vector2(6, 6)), Color("9fd0ff"))
	# you
	var me: Vector3 = game.player.position
	var s := _to_screen(Vector2(me.x, me.z))
	var f: float = game.player.facing
	var dir := Vector2(sin(f), cos(f))
	var side := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([s + dir * 10, s - dir * 6 + side * 6, s - dir * 3, s - dir * 6 - side * 6]), Color("ffe080"))
	# frame and help
	draw_rect(Rect2(Vector2.ZERO, size), UI.BORDER, false, 2.0)
	_text(Vector2(90, 26), "THE WORLD", 18, UI.GOLD)
	_text(Vector2(size.x / 2, size.y - 14), "Scroll to zoom  ·  drag to move  ·  M or Esc to close", 11, UI.TEXT_DIM)
	var here := DB.region_at(me.x, me.z)
	_text(Vector2(size.x / 2, size.y - 34), "%s%s" % [here.get("name", ""), ("  ·  " + game.subzone) if game.subzone != "" else ""], 12, UI.TEXT)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var k := 1.25 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 0.8
			# zoom about the cursor
			var at: Vector2 = center + (e.position - size / 2) / scale_px
			scale_px = clampf(scale_px * k, 0.08, 4.0)
			center = at - (e.position - size / 2) / scale_px
			queue_redraw()
		elif e.button_index == MOUSE_BUTTON_LEFT:
			_drag = e.pressed
		accept_event()
	elif e is InputEventMouseMotion and _drag:
		center -= e.relative / scale_px
		queue_redraw()
		accept_event()

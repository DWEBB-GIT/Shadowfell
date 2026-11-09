class_name WorldMapUI
extends Control
## The world map (M): the whole world as Dan painted it (data/world/world_map.json):
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
var _survey: Texture2D


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
	if Terrain.is_new_map():
		layout()
		var rect := Terrain.map_rect()
		center = rect.get_center()
		scale_px = minf(size.x / rect.size.x, (size.y - 100) / rect.size.y)
	else:
		scale_px = 0.35
	if Terrain.is_new_map() and _survey == null:
		_build_survey()
	visible = true
	layout()
	queue_redraw()


## Redrawn while open: you walk on with it up, and the ring round you pulses.
func _process(_dt: float) -> void:
	if visible:
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
	var art := Terrain.map_picture()
	if Terrain.is_new_map() and _survey != null:
		var r := Terrain.map_rect()
		draw_texture_rect(_survey, Rect2(_to_screen(r.position), r.size * scale_px), false)
		for road in Terrain.roads():
			_line(road.points, Color("d1b581"), maxf(1.5, road.half * 2.0 * scale_px))
		for region in DB.world.regions:
			if not region.get("campaign", false):
				continue
			var zone_rect: Array = region.rect
			draw_rect(Rect2(_to_screen(Vector2(zone_rect[0], zone_rect[1])), Vector2(zone_rect[2], zone_rect[3]) * scale_px), Color(0.9, 0.85, 0.65, 0.25), false, 1.0)
			if scale_px < 0.5:
				_text(_to_screen(Vector2(region.label[0], region.label[1])), region.name, 12, UI.TEXT)
		for p in WorldMap.pois:
			var dungeon: bool = p.kind == "dungeon"
			var hub: bool = p.get("hub", "") != "" or p.kind == "town" or p.get("returnPocket", false)
			if not dungeon and not hub and scale_px < 0.7:
				continue
			var at := _to_screen(Vector2(p.at[0], p.at[1]))
			draw_circle(at, 4.0 if dungeon else 3.0, Color("e98272") if dungeon else Color("e5c886"))
			if dungeon and scale_px < 0.35:
				_text(at + Vector2(0, -8), str(int(p.get("dungeonNumber", 0))), 11, Color("ffd7b1"))
			if scale_px >= (0.35 if dungeon else 0.5):
				var label: String = p.name + ("  " + str(p.levels) if p.has("levels") else "")
				_text(at + Vector2(0, -12), label, 12, UI.TEXT)
		if scale_px < 0.3:
			_draw_campaign_key()
	elif art:
		var r := Terrain.map_rect()
		var tl := _to_screen(r.position)
		draw_texture_rect(art, Rect2(tl, r.size * scale_px), false)
	elif not DB.world_map.is_empty():
		_draw_design_map()
	var ql = game.quests
	var followed: Array = ql.active.duplicate()
	if ql.focus != "" and ql.status(ql.focus) == "available":
		followed.append(ql.focus)
	for id in followed:
		if not ql.tracked.has(id) and id != ql.focus:
			continue
		var at: Dictionary = ql.goal(id)
		if at.is_empty():
			continue
		var gs := _to_screen(Vector2(at.x, at.z))
		var gc := Color("fff0a0") if id == ql.focus else Color("d8b058")
		var k := 7.0 if id == ql.focus else 5.0
		var diamond := PackedVector2Array([gs + Vector2(0, -k), gs + Vector2(k, 0), gs + Vector2(0, k), gs + Vector2(-k, 0)])
		draw_colored_polygon(diamond, Color.BLACK)
		draw_colored_polygon(PackedVector2Array(Array(diamond).map(func(v): return gs + (v - gs) * 0.7)), gc)
		if id == ql.focus:
			_text(gs + Vector2(0, -14), DB.quests[id].name, 11, gc)
	# you
	var me: Vector3 = game.player.position
	var s := _to_screen(Vector2(me.x, me.z))
	var f: float = game.player.facing
	var dir := Vector2(sin(f), cos(f))
	var side := Vector2(-dir.y, dir.x)
	# a pulsing ring and a dark disc, so you stand out on Dan's busy painting
	var beat := fmod(Time.get_ticks_msec() / 1200.0, 1.0)
	draw_arc(s, 12 + beat * 18, 0, TAU, 32, Color(1, 0.88, 0.5, 1 - beat), 2.0, true)
	draw_circle(s, 12, Color(0, 0, 0, 0.55))
	dir *= 1.4
	side *= 1.4
	draw_colored_polygon(PackedVector2Array([s + dir * 10, s - dir * 6 + side * 6, s - dir * 3, s - dir * 6 - side * 6]), Color("ffe080"))
	# frame and help
	draw_rect(Rect2(Vector2.ZERO, size), UI.BORDER, false, 2.0)
	_text(Vector2(105, 26), "REGION MAP" if Terrain.is_new_map() else "THE WORLD", 18, UI.GOLD)
	_text(Vector2(size.x / 2, size.y - 14), "Scroll to zoom  ·  drag to move  ·  M or Esc to close", 11, UI.TEXT_DIM)
	var here := DB.region_at(me.x, me.z)
	_text(Vector2(size.x / 2, size.y - 34), "%s%s" % [here.get("name", ""), ("  ·  " + game.subzone) if game.subzone != "" else ""], 12, UI.TEXT)


## Survey the actual saved terrain; the illustrated atlas is concept art,
## so it cannot guide somebody through newly sculpted roads and hills.
func _build_survey() -> void:
	var r := Terrain.map_rect()
	var step := 8.0
	var img := Image.create(ceili(r.size.x / step), ceili(r.size.y / step), false, Image.FORMAT_RGB8)
	for y in img.get_height():
		for x in img.get_width():
			var wx := r.position.x + (x + 0.5) * step
			var wz := r.position.y + (y + 0.5) * step
			var h := Terrain.height_at(wx, wz)
			var col := SEA
			if h > 0.3:
				var painted = Terrain.ground_colour(wx, wz)
				col = painted if painted is Color else Color(Land.GROUND.get(Terrain.surface_at(wx, wz), Land.GROUND[Terrain.MEADOW])[0]).lightened(0.18)
				var slope := Terrain.height_at(wx - step, wz - step) - h
				col = col.lightened(clampf(slope * 0.025, 0, 0.18)).darkened(clampf(-slope * 0.025, 0, 0.3))
			var pond = Terrain.water_at(wx, wz)
			if pond != null:
				col = Color(pond.get("color", "#416e78"))
			img.set_pixel(x, y, col)
	_survey = ImageTexture.create_from_image(img)


## The old world's map, drawn from world_map.json.
func _draw_design_map() -> void:
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
		# Dan's map pictogram (assets/icons/map/place_<kind>.png), else a dot
		var art := Icons.art("map", "place_" + str(p.kind))
		if art:
			draw_texture_rect(art, Rect2(s - Vector2(12, 12), Vector2(24, 24)), false)
		else:
			draw_circle(s, 4.0, Color.BLACK)
			draw_circle(s, 3.0, c)
		if scale_px >= 0.45 or p.kind in ["town", "dock", "landmark"]:
			_text(s + Vector2(0, -18 if art else -12), p.name, 11, c)
	for d in game.discovery.docks:
		var s := _to_screen(d.at)
		draw_rect(Rect2(s - Vector2(3, 3), Vector2(6, 6)), Color("9fd0ff"))
	# where tracked quests lead (the followed one brightest)


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


## Use the wide map margin for readable brackets and the seven-layout key.
func _draw_campaign_key() -> void:
	var y := 65.0
	_text(Vector2(155, y), "REGIONS AND LEVELS", 13, UI.GOLD)
	for region in DB.world.regions:
		if not region.get("campaign", false):
			continue
		y += 22
		_text(Vector2(155, y), str(region.name) + "  " + str(region.levels), 12, UI.TEXT)
	y += 34
	_text(Vector2(155, y), "DUNGEON ENTRANCES", 13, UI.GOLD)
	var seen := {}
	for entrance in DB.world.get("dungeonEntrances", []):
		if seen.has(entrance.dungeon):
			continue
		seen[entrance.dungeon] = true
		y += 24
		var label: String = "%d. %s  %d–%d" % [int(entrance.number), entrance.name, int(entrance.levels[0]), int(entrance.levels[1])]
		_text(Vector2(155, y), label, 11, UI.TEXT)
	y += 26
	_text(Vector2(155, y), "Entrances are sealed", 10, UI.TEXT_DIM)
	_text(Vector2(155, y + 18), "Zoom in for individual hub brackets", 10, UI.TEXT_DIM)

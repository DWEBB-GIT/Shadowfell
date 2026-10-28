class_name Minimap
extends Control
## A round minimap in the top-right corner, north up (src/ui/minimap.js; the
## camera never turns, so up on the map is up on the screen). The ground,
## roads, water and props round the Warden are painted into a picture (again
## when they walk out of it); each frame draws the part around them, then the markers on
## top: townsfolk with their quest marks, shrines, the places current
## objectives point to, and the Warden as an arrow. Quest marks out of range
## sit on the rim, pointing the way, but only within
## `CONFIG.minimap.questRange` metres: quests far off stay hidden until you
## come nearer. Townsfolk with a trade (npcs.json `mapIcon`) show its icon;
## enemies fighting you show as red dots.

const SIZE := 168.0 ## pixels across
const PX := 3.0 ## picture pixels per metre
const ZOOMS := [2.2, 3.2, 4.6] ## screen pixels per metre
## The new map's minimap shows Dan's painting (2 m a pixel) itself, so it
## stands further back: zoomed in as close as the old map it is a blur.
const PAINTING_ZOOMS := [0.35, 0.6, 1.0]
const PROP_STYLE := {
	"watch_post": ["rect", "#8a6a44", 4.5],
	"forge": ["rect", "#8a6a44", 3],
	"awning": ["rect", "#7a5c3a", 3],
	"palisade": ["rect", "#5e4a32", 2.4],
	"fence": ["rect", "#5e4a32", 1.4],
	"ruin_wall": ["rect", "#77736a", 2],
	"cart": ["rect", "#9a7a4a", 1.8],
	"standing_stone": ["dot", "#a8a89c", 0.9],
	"grave0": ["dot", "#8c877a", 0.55],
	"grave1": ["dot", "#8c877a", 0.55],
	"rock0": ["dot", "#6c6a62", 1],
	"rock1": ["dot", "#6c6a62", 0.8],
	"bone_pile": ["dot", "#b0a890", 0.6],
}
const SEGMENTS := 72 ## sides of the round window the map is shown through

var game
var zoom := 1
var picture: Texture2D
var origin := Vector2.ZERO
var map: Control
var view: SubViewport ## the square map is drawn here, then shown through a circle
var location: Label ## where you are, on a bar across the foot of the map
var coords: Label ## X / Y in world metres, under the map
var _circle := PackedVector2Array()
var _circle_uv := PackedVector2Array()
var zoom_buttons: Array = [] ## + and −, for the HUD to give them tips


func _init(g) -> void:
	game = g
	name = "Minimap"
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	# the map is drawn square, off screen, and shown through a true circle
	# (a polygon), so nothing outside the circle can ever show
	view = SubViewport.new()
	view.size = Vector2i(int(SIZE), int(SIZE))
	view.disable_3d = true
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	map = Control.new()
	map.size = size
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.draw.connect(_draw_map)
	view.add_child(map)
	var r := SIZE / 2
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var v := Vector2(cos(a), sin(a))
		_circle.append(Vector2(r, r) + v * (r - 1))
		_circle_uv.append(Vector2(0.5, 0.5) + v * (r - 1) / SIZE)
	# where you are: a bar across the foot of the circle
	location = UI.label(self, "", 11, UI.GOLD)
	location.add_theme_stylebox_override("normal", _round_box(4))
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	location.clip_text = true
	location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	location.size = Vector2(124, 18)
	location.position = Vector2(SIZE / 2 - 62, SIZE - 9)
	coords = UI.label(self, "", 11, UI.TEXT_DIM, 3)
	coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coords.size = Vector2(124, 14)
	coords.position = Vector2(SIZE / 2 - 62, SIZE + 17)
	# the N badge and the zoom buttons
	# a small orb at the top of the rim, styled like the menu orbs round it
	var north := orb(270.0, 10.0)
	north.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var north_art := Icons.art("ui", "minimap_north")
	if north_art:
		north.draw.connect(func(): north.draw_texture_rect(north_art, Rect2(Vector2(2, 2), north.size - Vector2(4, 4)), false))
	var n := UI.label(north, "" if north_art else "N", 12, UI.GOLD)
	n.add_theme_font_override("font", UI.bold)
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.grow_vertical = Control.GROW_DIRECTION_BOTH
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# zoom: two small round buttons on the rim, right side, clear of the place
	# bar (the HUD sets its menu orbs round the left side the same way)
	for z in [[1, 22.0], [-1, 48.0]]:
		var b := orb(z[1], ZOOM_R)
		var step: int = z[0]
		b.pressed.connect(func():
			game.audio.sfx("quest_log", 0.6)
			set_zoom(zoom + step))
		b.draw.connect(func(): _draw_zoom(b, step))
		zoom_buttons.append(b)


const ZOOM_R := 11.0


## A round button sat on the rim at `angle` degrees (0 = east, 90 = south),
## RuneScape style: drawn as a true circle, a bronze ring on dark stone
func orb(angle: float, radius: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(radius * 2, radius * 2)
	b.size = b.custom_minimum_size
	var a := deg_to_rad(angle)
	var r := SIZE / 2
	b.position = Vector2(r, r) + Vector2(cos(a), sin(a)) * (r - 2) - Vector2(radius, radius)
	b.draw.connect(func(): _draw_orb(b, radius))
	add_child(b)
	return b


func _draw_orb(b: Button, radius: float) -> void:
	var c := Vector2(radius, radius)
	var lit := b.is_hovered() or b.is_pressed()
	b.draw_circle(c, radius, Color(0, 0, 0, 0.5), true, -1, true)
	b.draw_circle(c, radius - 1.5, UI.PANEL_SOLID, true, -1, true)
	b.draw_circle(c, radius - 1.5, UI.GOLD if lit else UI.BORDER, false, 1.5, true)


func _draw_zoom(b: Button, step: int) -> void:
	var c := Vector2(ZOOM_R, ZOOM_R)
	var col := UI.GOLD if b.is_hovered() or b.is_pressed() else Color("e2d3ae")
	var art := Icons.art("ui", "minimap_zoom_in" if step > 0 else "minimap_zoom_out")
	if art:
		b.draw_texture_rect(art, Rect2(Vector2(2, 2), b.size - Vector2(4, 4)), false, Color(1.25, 1.2, 1.1) if b.is_hovered() or b.is_pressed() else Color.WHITE)
		return
	b.draw_line(c - Vector2(4.5, 0), c + Vector2(4.5, 0), col, 2.0, true)
	if step > 0:
		b.draw_line(c - Vector2(0, 4.5), c + Vector2(0, 4.5), col, 2.0, true)


func _round_box(r: int, border := UI.BORDER) -> StyleBoxFlat:
	var s := UI.box(UI.PANEL_SOLID, border, 0)
	s.set_corner_radius_all(r)
	s.corner_detail = 12
	s.anti_aliasing = true
	s.set_content_margin_all(0)
	return s


func set_zoom(z: int) -> void:
	zoom = clampi(z, 0, ZOOMS.size() - 1)


# ------------------------------------------- the land around you, painted
## The world is far too big to paint whole, so a square WINDOW metres across
## around the Warden is painted once, and painted again round the new spot
## when they walk more than REPAINT metres from its middle.
const WINDOW := 384.0
const REPAINT := 96.0
var _paint_vp: SubViewport
var _paint_canvas: Control
var _painted_at := Vector2(INF, INF)
var _ground_tex: ImageTexture ## kept: the paint pass draws it after _paint_world returns


func _paint(at: Vector2) -> void:
	_painted_at = at
	origin = at - Vector2(WINDOW, WINDOW) / 2
	var w := int(WINDOW * PX)
	if _paint_vp == null:
		_paint_vp = SubViewport.new()
		_paint_vp.size = Vector2i(w, w)
		_paint_vp.disable_3d = true
		_paint_canvas = Control.new()
		_paint_canvas.size = Vector2(w, w)
		_paint_canvas.draw.connect(func(): _paint_world(Canvas2D.new(_paint_canvas), w, w))
		_paint_vp.add_child(_paint_canvas)
		add_child(_paint_vp)
		picture = _paint_vp.get_texture()
	_paint_canvas.queue_redraw()
	_paint_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## The ground's colour on the map: open ground by what it is, high ground
## dark, water blue.
const MAP_GROUND := {
	Terrain.SEA: "#22404a", Terrain.MEADOW: "#4a4634", Terrain.MARSH: "#3e4a38", Terrain.DOWNS: "#5c5c40",
	Terrain.BLACKWOOD: "#26302a", Terrain.ROCK: "#5a5650", Terrain.MOOR: "#4e4240", Terrain.SAND: "#8a7c5a",
	Terrain.FARMLAND: "#525030", Terrain.FOREST: "#2e3a28", Terrain.SNOW: "#b8bcc0", Terrain.DESERT: "#8a6c44",
	Terrain.ASH: "#3a302c", Terrain.SWAMP: "#30382a", Terrain.JUNGLE: "#2a4224", Terrain.HAUNTED: "#2c2a32",
}


func _ground_picture() -> ImageTexture:
	var c := Terrain.cell()
	var n := int(WINDOW / c) + 1
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var o := Terrain.grid_origin()
	var a0 := roundi((origin.x - o.x) / c)
	var b0 := roundi((origin.y - o.y) / c)
	for j in n:
		for i in n:
			var s := Terrain.grid(a0 + i, b0 + j)
			var col := Color(MAP_GROUND.get(s[2], "#4a4634"))
			if s[0] < 0.3:
				col = Color(MAP_GROUND[Terrain.SEA])
			elif s[1] < 0.5:
				col = col.darkened(0.55 - s[1] * 0.4)
			img.set_pixel(i, j, col)
	return ImageTexture.create_from_image(img)


func _paint_world(g: Canvas2D, w: float, h: float) -> void:
	var X := func(x: float) -> float: return (x - origin.x) * PX
	var Z := func(z: float) -> float: return (z - origin.y) * PX
	g.round_caps = true
	# the ground, a pixel per 4 m sample, smoothed (the new map: Dan's picture)
	var c := Terrain.cell()
	var art := Terrain.map_picture()
	if art:
		var r := Terrain.map_rect()
		g.fill_style = "#0a3c6e"
		g.fill_rect(0, 0, w, h)
		g.draw_image(art, X.call(r.position.x), Z.call(r.position.y), r.size.x * PX, r.size.y * PX)
	_ground_tex = _ground_picture() if art == null else null
	var ground := _ground_tex
	var gs := ground.get_size() if ground else Vector2.ZERO
	if ground:
		g.draw_image(ground, X.call(Terrain.grid_origin().x + roundi((origin.x - Terrain.grid_origin().x) / c) * c) - c * PX / 2, Z.call(Terrain.grid_origin().y + roundi((origin.y - Terrain.grid_origin().y) / c) * c) - c * PX / 2, gs.x * c * PX, gs.y * c * PX)
	# clearings read a little lighter
	g.fill_style = "rgba(160, 150, 110, 0.10)"
	for cl in Layout.clearings:
		g.begin_path()
		g.arc(X.call(cl[0]), Z.call(cl[1]), cl[2] * PX, 0, TAU)
		g.fill()
	# rivers and lakes
	g.stroke_style = "#2c5056"
	for r in DB.water.get("rivers", []):
		g.line_width = (r.width + 2.0) * PX
		g.begin_path()
		for i in r.points.size():
			var q: Array = r.points[i]
			if i:
				g.line_to(X.call(q[0]), Z.call(q[1]))
			else:
				g.move_to(X.call(q[0]), Z.call(q[1]))
		g.stroke()
	for l in DB.water.get("lakes", []):
		g.fill_style = "#2c5056"
		g.begin_path()
		g.ellipse(X.call(l.center[0]), Z.call(l.center[1]), l.rx * PX, l.rz * PX, 0, 0, TAU)
		g.fill()
	# roads
	for road in Terrain.roads():
		if road.half <= 0:
			continue
		g.stroke_style = "#9c8358" if road.kind == "road" else "#7a6848"
		g.line_width = maxf(road.half * 1.6, 2.2) * PX
		g.begin_path()
		for i in road.points.size():
			var q: Array = road.points[i]
			if i:
				g.line_to(X.call(q[0]), Z.call(q[1]))
			else:
				g.move_to(X.call(q[0]), Z.call(q[1]))
		g.stroke()
	# props
	for p in Layout.props:
		var style = PROP_STYLE.get(p.get("model", ""))
		if style == null:
			continue
		g.fill_style = style[1]
		var sz: float = style[2]
		var x: float = p.position[0]
		var z: float = p.position[1]
		if style[0] == "dot":
			g.begin_path()
			g.arc(X.call(x), Z.call(z), sz * PX, 0, TAU)
			g.fill()
		else:
			g.save()
			g.translate(X.call(x), Z.call(z))
			g.rotate(-deg_to_rad(p.get("rotation", 0)))
			g.fill_rect(-sz * PX, -sz * 0.6 * PX, sz * 2 * PX, sz * 1.2 * PX)
			g.restore()
	# houses (roof colour) and palisades
	for hs in Layout.houses:
		g.fill_style = "#" + Town.ROOF.get(hs.get("roof", "thatch"), Town.ROOF.thatch).to_html(false)
		g.save()
		g.translate(X.call(hs.position[0]), Z.call(hs.position[1]))
		g.rotate(-deg_to_rad(hs.get("rotation", 0)))
		g.fill_rect(-hs.size[0] / 2.0 * PX, -hs.size[1] / 2.0 * PX, hs.size[0] * PX, hs.size[1] * PX)
		g.restore()
	g.stroke_style = "#5a4630"
	g.line_width = 1.6 * PX
	for tw in Layout.town_walls:
		for line in tw.lines:
			g.begin_path()
			for i in line.size():
				if i:
					g.line_to(X.call(line[i][0]), Z.call(line[i][1]))
				else:
					g.move_to(X.call(line[i][0]), Z.call(line[i][1]))
			g.stroke()
	# ponds, and the places too dark to see into
	for wt in Layout.water:
		if wt.get("carved"):
			continue
		g.fill_style = "#2c5056"
		g.begin_path()
		g.arc(X.call(wt.position[0]), Z.call(wt.position[1]), wt.radius * PX, 0, TAU)
		g.fill()
	for o in Layout.obscured:
		g.fill_style = "rgba(0, 0, 0, 0.85)"
		g.begin_path()
		g.arc(X.call(o.position[0]), Z.call(o.position[1]), o.radius * PX, 0, TAU)
		g.fill()


# ------------------------------------------------------------ markers
## Every marker for the current state, in world metres:
## { x, z, kind: 'npc' | 'shrine' | 'area' | 'ready' | 'available' | 'active' | 'foe' | ..., r?, label? }
func markers() -> Array:
	var quests = game.quests
	var out := []
	for s in Layout.shrines:
		out.append({"x": s.position[0], "z": s.position[1], "kind": "shrine"})
	# where open objectives point
	var areas := {}
	for id in quests.active:
		if quests.status(id) != "active":
			continue
		for o in quests.objectives(id):
			if o.done or not o.get("location") or areas.has(o.location):
				continue
			var l: Dictionary = DB.locations[o.location]
			# tracked quests show however far off they are
			if not quests.tracked.has(id) and _far(l.position[0], l.position[1], l.radius):
				continue
			areas[o.location] = {"x": l.position[0], "z": l.position[1], "r": l.radius, "kind": "area", "label": l.name, "tracked": quests.tracked.has(id)}
	out.append_array(areas.values())
	# the next step of each tracked quest, at any distance; the followed one
	# brightest
	for id in quests.active:
		if not quests.tracked.has(id):
			continue
		var at: Dictionary = quests.goal(id)
		if not at.is_empty():
			out.append({"x": at.x, "z": at.z, "r": at.r, "kind": "goal", "label": at.label, "npc": at.has("npc"), "focus": id == quests.focus})
	for n in game.npcs.list:
		var status: String = quests.marker_for(n.id)
		var quest: String = status if status != "" and not _far(n.position.x, n.position.z) else ""
		# a trade (the inn's tankard) shows even while its keeper has a quest:
		# the quest mark then sits just above it
		if quest == "" or n.def.get("mapIcon"):
			out.append({"x": n.position.x, "z": n.position.z, "kind": "npc", "icon": n.def.get("mapIcon"), "label": n.name})
		if quest != "":
			out.append({"x": n.position.x, "z": n.position.z, "kind": quest, "icon": n.def.get("mapIcon"), "label": n.name})
	# a miner sees where the live veins glint (WoW's Find Minerals)
	if game.skills.has("mining"):
		for v in game.mining.veins():
			out.append({"x": v.x, "z": v.z, "kind": "vein", "label": v.name})
	# a herbalist sees the herbs they can pick (WoW's Find Herbs)
	for v in game.gathering.live():
		if game.skills.has(v.skill):
			out.append({"x": v.x, "z": v.z, "kind": "herb", "label": v.name})
	for e in game.enemies.list:
		if Targeting.in_combat_with_player(e):
			out.append({"x": e.position.x, "z": e.position.z, "kind": "foe", "label": e.cfg.name})
	# the enemy that killed you, and your body while you walk as a spirit
	var ws = game.world_state
	if ws.nemesis != null:
		for e in game.enemies.list:
			if e.id == ws.nemesis and e.alive:
				out.append({"x": e.position.x, "z": e.position.z, "kind": "nemesis", "label": e.cfg.name})
	var corpse = game.afterlife.corpse
	if corpse != null:
		out.append({"x": corpse.x, "z": corpse.z, "kind": "corpse", "label": "Your body"})
	if ws.camp != null:
		out.append({"x": ws.camp.x, "z": ws.camp.z, "kind": "camp", "label": "Your camp"})
	return out


## is (x, z) beyond the range quest marks show at? (`r`: an area's radius)
func _far(x: float, z: float, r := 0.0) -> bool:
	var p: Vector3 = game.player.position
	return U.hyp(x - p.x, z - p.z) - r > DB.CONFIG.minimap.questRange


# ---------------------------------------------------------------- draw
func _draw() -> void:
	# the frame: a dark ring and the warm border (style.css #minimap)
	var c := Vector2(SIZE, SIZE) / 2
	draw_circle(c, SIZE / 2 + 3, Color.BLACK)
	draw_circle(c, SIZE / 2 + 1, UI.BORDER)
	draw_polygon(_circle, PackedColorArray([Color.WHITE]), _circle_uv, view.get_texture())
	# a smooth rim over the polygon's edge
	draw_arc(c, SIZE / 2 - 0.5, 0, TAU, SEGMENTS, UI.BORDER, 1.5, true)


## Redrawn when the Warden moves or turns, and a few times a second for the
## markers (enemies, quests); every frame cost several milliseconds.
var _drawn_at := Vector4(INF, 0, 0, 0)
var _since := 0.0


func _process(dt: float) -> void:
	if not is_visible_in_tree() or game.player == null:
		return
	_since += dt
	var p: Vector3 = game.player.position
	var now := Vector4(p.x, p.z, game.player.facing, zoom)
	if _since >= 0.2 or _moved(now):
		_since = 0.0
		var here := place_name()
		if location.text != here:
			location.text = here
		var xy := "X: %d   Y: %d" % [roundi(p.x), roundi(p.z)]
		if coords.text != xy:
			coords.text = xy
		_drawn_at = now
		map.queue_redraw()


## The name of where you stand: the building you are in, else the region.
func place_name() -> String:
	var inside = game.world.indoors if game.world else null
	if inside is Dictionary and inside.get("def", {}).get("name"):
		return inside.def.name
	return game.region.get("name", "") if game.region is Dictionary else ""


func _moved(now: Vector4) -> bool:
	var d := (now - _drawn_at).abs()
	return d.x > 0.05 or d.y > 0.05 or d.z > 0.02 or d.w > 0


func _draw_map() -> void:
	if game.player == null or not game.started and not game.hud.showcase:
		map.draw_circle(Vector2(SIZE, SIZE) / 2, SIZE / 2, Color.BLACK)
		return
	var p: Vector3 = game.player.position
	var art := Terrain.map_picture()
	if art == null and (picture == null or Vector2(p.x, p.z).distance_to(_painted_at) > REPAINT):
		_paint(Vector2(p.x, p.z))
	var g := Canvas2D.new(map)
	var scale: float = (ZOOMS if art == null else PAINTING_ZOOMS)[zoom]
	var R := SIZE / 2
	g.fill_style = "#000" if art == null else "#0a3c6e"
	g.fill_rect(0, 0, SIZE, SIZE)
	if art:
		# the new map: Dan's painting, drawn straight in at this zoom
		var r := Terrain.map_rect()
		g.draw_image(art, R + (r.position.x - p.x) * scale, R + (r.position.y - p.z) * scale, r.size.x * scale, r.size.y * scale)
	else:
		# the painted world around the Warden
		var k := scale / PX
		var ps := picture.get_size()
		g.draw_image(picture, R - (p.x - origin.x) * scale, R - (p.z - origin.y) * scale, ps.x * k, ps.y * k)
	var to_map := func(x: float, z: float) -> Vector2: return Vector2(R + (x - p.x) * scale, R + (z - p.z) * scale)
	var all := markers()
	# objective areas first, under everything else
	for m in all:
		if m.kind != "area":
			continue
		var s: Vector2 = to_map.call(m.x, m.z)
		g.begin_path()
		g.arc(s.x, s.y, maxf(5, m.r * scale), 0, TAU)
		g.fill_style = "rgba(240, 200, 80, 0.16)"
		g.fill()
		g.stroke_style = "rgba(240, 200, 80, 0.7)"
		g.line_width = 1
		g.set_line_dash([3, 3])
		g.stroke()
		g.set_line_dash([])
	for m in all:
		var s: Vector2 = to_map.call(m.x, m.z)
		var inside := s.distance_to(Vector2(R, R)) <= R - 4
		if m.kind == "shrine" and inside:
			if _art(g, "shrine", s.x, s.y, 14):
				continue
			g.fill_style = "#9fd0ff"
			g.begin_path()
			g.move_to(s.x, s.y - 4)
			g.line_to(s.x + 3, s.y)
			g.line_to(s.x, s.y + 4)
			g.line_to(s.x - 3, s.y)
			g.fill()
		elif m.kind == "npc" and inside:
			if m.icon:
				if not _art(g, "npc_" + m.icon, s.x, s.y, 15):
					_trade_icon(g, s.x, s.y, m.icon)
				continue
			g.fill_style = "#e8d8a0"
			g.begin_path()
			g.arc(s.x, s.y, 2.6, 0, TAU)
			g.fill()
		elif m.kind == "vein" and inside:
			if _art(g, "vein", s.x, s.y, 13):
				continue
			g.fill_style = "#f0d890"
			g.stroke_style = "#000"
			g.line_width = 1
			g.begin_path()
			g.move_to(s.x, s.y - 3)
			g.line_to(s.x + 3, s.y)
			g.line_to(s.x, s.y + 3)
			g.line_to(s.x - 3, s.y)
			g.fill()
			g.stroke()
		elif m.kind == "herb" and inside:
			g.fill_style = "#9fe07a"
			g.stroke_style = "#000"
			g.line_width = 1
			g.begin_path()
			g.arc(s.x, s.y, 2.5, 0, TAU)
			g.fill()
			g.stroke()
		elif m.kind == "foe" and inside:
			g.fill_style = "#ff3a2a"
			g.stroke_style = "#000"
			g.line_width = 1
			g.begin_path()
			g.arc(s.x, s.y, 3, 0, TAU)
			g.fill()
			g.stroke()
	# where tracked quests lead: a diamond on the map, a pointer on the rim
	# when off it (the followed quest's last, so it sits on top)
	for pass_focus in [false, true]:
		for m in all:
			if m.kind != "goal" or m.focus != pass_focus:
				continue
			var s: Vector2 = to_map.call(m.x, m.z)
			var colour := "#fff0a0" if m.focus else "#d8b058"
			if s.distance_to(Vector2(R, R)) > R - 4 - m.r * scale:
				_rim(g, s, R, colour, "", m.r * scale, 1.5 if m.focus else 1.0)
			elif not m.npc and not _art(g, "quest_goal", s.x, s.y, 15 if m.focus else 12):
				_glyph(g, s.x, s.y, "◆", colour, 13 if m.focus else 10)
	# quest marks last, so they sit on top; out of range ones on the rim
	for m in all:
		if m.kind != "ready" and m.kind != "available" and m.kind != "active":
			continue
		var s: Vector2 = to_map.call(m.x, m.z)
		var glyph := "!" if m.kind == "available" else "?"
		var colour := "#a8a8a8" if m.kind == "active" else "#ffd23c"
		if s.distance_to(Vector2(R, R)) <= R - 8:
			if m.get("icon"):
				s.y -= 11
			if not _art(g, "quest_" + m.kind, s.x, s.y, 16):
				_glyph(g, s.x, s.y, glyph, colour, 15)
		else:
			_rim(g, s, R, colour, glyph)
	# your camp, your killer and your body: always shown, on the rim when far
	for m in all:
		var s: Vector2 = to_map.call(m.x, m.z)
		var inside := s.distance_to(Vector2(R, R)) <= R - 8
		if m.kind == "camp":
			if inside and not _art(g, "camp", s.x, s.y, 14):
				_glyph(g, s.x, s.y, "▲", "#ff9a40", 11)
		elif m.kind == "nemesis":
			if inside:
				if not _art(g, "nemesis", s.x, s.y, 16):
					_glyph(g, s.x, s.y, "☠", "#ff4a3a", 15)
			else:
				_rim(g, s, R, "#ff4a3a", "☠")
		elif m.kind == "corpse":
			if inside:
				if not _art(g, "corpse", s.x, s.y, 16):
					_glyph(g, s.x, s.y, "✝", "#cfe6ff", 15)
			else:
				_rim(g, s, R, "#cfe6ff", "")
	# the Warden, at the centre, pointing the way they face
	g.save()
	g.translate(R, R)
	if art:
		# a dark disc under the arrow: it is lost on a busy painting otherwise
		g.begin_path()
		g.arc(0, 0, 10, 0, TAU)
		g.fill_style = "rgba(0, 0, 0, 0.55)"
		g.fill()
	g.rotate(PI - game.player.facing)
	var arrow := Icons.art("map", "player")
	if arrow:
		g.draw_image(arrow, -8, -8, 16, 16)
		g.restore()
		return
	g.begin_path()
	g.move_to(0, -7)
	g.line_to(5, 6)
	g.line_to(0, 3)
	g.line_to(-5, 6)
	g.close_path()
	g.fill_style = "#ffffff"
	g.stroke_style = "#000"
	g.line_width = 1.5
	g.stroke()
	g.fill()
	g.restore()


## A townsperson's trade: a small pictogram on a dark disc.
func _trade_icon(g: Canvas2D, x: float, y: float, icon: String) -> void:
	g.save()
	g.translate(x, y)
	g.begin_path()
	g.arc(0, 0, 6.5, 0, TAU)
	g.fill_style = "rgba(12, 10, 8, 0.9)"
	g.fill()
	g.stroke_style = "#c8a860"
	g.line_width = 1
	g.stroke()
	g.fill_style = "#f0dca0"
	g.stroke_style = "#f0dca0"
	g.line_width = 1.3
	g.begin_path()
	match icon:
		"vendor":
			# a coin purse
			g.arc(0, 1.2, 3, 0, TAU)
			g.fill()
			g.begin_path()
			g.move_to(-1.6, -3.4)
			g.line_to(1.6, -3.4)
			g.line_to(0, -1.4)
			g.fill()
		"blacksmith":
			# an anvil
			g.move_to(-4, -2)
			g.line_to(4, -2)
			g.line_to(2, 0.5)
			g.line_to(1.2, 0.5)
			g.line_to(2.4, 3)
			g.line_to(-2.4, 3)
			g.line_to(-1.2, 0.5)
			g.line_to(-2.5, 0.5)
			g.close_path()
			g.fill()
		"fishing":
			# a fish
			g.ellipse(-0.6, 0, 3, 1.8, 0, 0, TAU)
			g.fill()
			g.begin_path()
			g.move_to(1.8, 0)
			g.line_to(4.2, -2.2)
			g.line_to(4.2, 2.2)
			g.fill()
		"cooking":
			# a cooking pot
			g.arc(0, 0, 3.2, 0, PI)
			g.fill()
			g.begin_path()
			g.move_to(-4.4, -0.2)
			g.line_to(4.4, -0.2)
			g.stroke()
			g.begin_path()
			g.move_to(-1.2, -2.6)
			g.line_to(1.2, -2.6)
			g.stroke()
		"tanner":
			# a hide stretched on a frame
			g.move_to(-3.6, -3.4)
			for pt in [[-1.2, -2.2], [1.2, -2.2], [3.6, -3.4], [2.6, 0], [3.6, 3.4], [1, 2.4], [-1, 2.4], [-3.6, 3.4], [-2.6, 0]]:
				g.line_to(pt[0], pt[1])
			g.close_path()
			g.fill()
		"innkeeper":
			# a tankard
			g.fill_rect(-3, -2.8, 4.4, 6)
			g.begin_path()
			g.arc(1.6, 0.2, 1.8, -PI / 2, PI / 2)
			g.stroke()
		_:
			# a class trainer: crossed swords
			for sgn in [1, -1]:
				g.begin_path()
				g.move_to(-3.6 * sgn, -3.6)
				g.line_to(3.2 * sgn, 3.2)
				g.stroke()
				g.begin_path()
				g.move_to(1.4 * sgn, 3.6)
				g.line_to(3.6 * sgn, 1.4)
				g.stroke()
	g.restore()


## Dan's painted marker (assets/icons/map/<id>.png) centred on x, y; false
## when there is none, so the caller draws its own
func _art(g: Canvas2D, id: String, x: float, y: float, px: float) -> bool:
	var tex := Icons.art("map", id)
	if tex == null:
		return false
	g.draw_image(tex, x - px / 2, y - px / 2, px, px)
	return true


func _glyph(g: Canvas2D, x: float, y: float, glyph: String, colour: String, px: int) -> void:
	g.font_size = px
	g.line_width = 3
	g.stroke_style = "#000"
	g.stroke_text(glyph, x, y)
	g.fill_style = colour
	g.fill_text(glyph, x, y)


## A marker beyond the edge: a small arrow on the rim pointing at it.
func _rim(g: Canvas2D, s: Vector2, R: float, colour: String, glyph: String, reach := 0.0, big := 1.0) -> void:
	var dx := s.x - R
	var dy := s.y - R
	var d := Vector2(dx, dy).length()
	if d - reach <= R - 4:
		return
	var a := atan2(dy, dx)
	var r := R - 9
	var x := R + cos(a) * r
	var y := R + sin(a) * r
	if glyph != "":
		_glyph(g, x, y, glyph, colour, 12)
		return
	g.save()
	g.translate(x, y)
	g.rotate(a)
	g.scale(big, big)
	g.begin_path()
	g.move_to(5, 0)
	g.line_to(-3, -4)
	g.line_to(-3, 4)
	g.close_path()
	g.fill_style = colour
	g.stroke_style = "#000"
	g.line_width = 1
	g.stroke()
	g.fill()
	g.restore()

class_name Minimap
extends Control
## A round minimap in the top-right corner, north up (src/ui/minimap.js; the
## camera never turns, so up on the map is up on the screen). The ground,
## roads, trees and props are painted once into a picture of the whole
## world; each frame draws the part around the Warden, then the markers on
## top: townsfolk with their quest marks, shrines, the places current
## objectives point to, and the Warden as an arrow. Quest marks out of range
## sit on the rim, pointing the way, but only within
## `CONFIG.minimap.questRange` metres: quests far off stay hidden until you
## come nearer. Townsfolk with a trade (npcs.json `mapIcon`) show its icon;
## enemies fighting you show as red dots.

const SIZE := 168.0 ## pixels across
const PX := 4.0 ## picture pixels per metre
const ZOOMS := [2.2, 3.2, 4.6] ## screen pixels per metre
const PAD := 24.0 ## metres painted beyond the world's edge (the woods go on)
const GROUND := {"fallen_road": "#4a4634", "blackwood": "#26302a"}
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
## keeps every draw inside the round map
const MASK := """
shader_type canvas_item;
varying vec2 local;
void vertex() { local = VERTEX; }
void fragment() { if (distance(local, vec2(84.0)) > 83.0) { discard; } }
"""

var game
var zoom := 1
var picture: Texture2D
var origin := Vector2.ZERO
var map: Control
var zoom_buttons: Array = [] ## + and −, for the HUD to give them tips


func _init(g) -> void:
	game = g
	name = "Minimap"
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	map = Control.new()
	map.size = size
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = MASK
	var mat := ShaderMaterial.new()
	mat.shader = sh
	map.material = mat
	map.draw.connect(_draw_map)
	add_child(map)
	# the N badge and the zoom buttons
	var north := UI.label(self, "N", 11, UI.GOLD)
	north.add_theme_stylebox_override("normal", _round_box(8))
	north.position = Vector2(SIZE / 2 - 8, -7)
	north.size = Vector2(16, 14)
	north.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	north.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	for z in [["+", -18, 1], ["−", 4, -1]]:
		var b := UI.button(self, z[0], Callable(), 14)
		var step: int = z[2]
		b.pressed.connect(func(): set_zoom(zoom + step))
		b.add_theme_stylebox_override("normal", _round_box(10))
		b.add_theme_stylebox_override("hover", _round_box(10, UI.GOLD))
		b.add_theme_stylebox_override("pressed", _round_box(10, UI.GOLD))
		b.add_theme_font_override("font", UI.bold)
		b.size = Vector2(20, 20)
		b.custom_minimum_size = Vector2(20, 20)
		b.position = Vector2(SIZE - 16, SIZE - 20 + z[1])
		zoom_buttons.append(b)


func _round_box(r: int, border := UI.BORDER) -> StyleBoxFlat:
	var s := UI.box(UI.PANEL_SOLID, border, 0)
	s.set_corner_radius_all(r)
	return s


func set_zoom(z: int) -> void:
	zoom = clampi(z, 0, ZOOMS.size() - 1)


# ------------------------------------------------- the world, painted once
func _paint() -> void:
	var b: Dictionary = Layout.bounds
	origin = Vector2(b.minX - PAD, b.minZ - PAD)
	var w := int((b.maxX - b.minX + PAD * 2) * PX)
	var h := int((b.maxZ - b.minZ + PAD * 2) * PX)
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Control.new()
	c.size = Vector2(w, h)
	c.draw.connect(func(): _paint_world(Canvas2D.new(c), w, h))
	vp.add_child(c)
	add_child(vp)
	picture = vp.get_texture()


func _paint_world(g: Canvas2D, w: float, h: float) -> void:
	var b: Dictionary = Layout.bounds
	var X := func(x: float) -> float: return (x - origin.x) * PX
	var Z := func(z: float) -> float: return (z - origin.y) * PX
	g.round_caps = true
	# ground by region, blended across the border
	var border: float = DB.region_by_id("fallen_road").minZ
	var grad := g.create_linear_gradient(0, Z.call(border - 6), 0, Z.call(border + 6))
	Canvas2D.add_color_stop(grad, 0, GROUND.blackwood)
	Canvas2D.add_color_stop(grad, 1, GROUND.fallen_road)
	g.fill_style = grad
	g.fill_rect(0, 0, w, h)
	# clearings read a little lighter
	g.fill_style = "rgba(160, 150, 110, 0.10)"
	for cl in Layout.clearings:
		g.begin_path()
		g.arc(X.call(cl[0]), Z.call(cl[1]), cl[2] * PX, 0, TAU)
		g.fill()
	# trees: dark dots, darker in the Blackwood
	for t in game.world.map_trees:
		g.fill_style = "rgba(8, 14, 10, 0.75)" if t.y < border else "rgba(22, 30, 18, 0.7)"
		g.begin_path()
		g.arc(X.call(t.x), Z.call(t.y), 1.3 * PX, 0, TAU)
		g.fill()
	# roads
	for road in DB.world.roads:
		g.stroke_style = "#9c8358" if road.id == "fallen_road" else "#7a6848"
		g.line_width = road.halfWidth * 1.6 * PX
		g.begin_path()
		for i in road.points.size():
			var p: Array = road.points[i]
			if i:
				g.line_to(X.call(p[0]), Z.call(p[1]))
			else:
				g.move_to(X.call(p[0]), Z.call(p[1]))
		g.stroke()
		# round joins on a wide road
		g.fill_style = g.stroke_style
		for p in road.points:
			g.begin_path()
			g.arc(X.call(p[0]), Z.call(p[1]), g.line_width / 2, 0, TAU)
			g.fill()
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
	# ponds, and the places too dark to see into
	for wt in Layout.water:
		g.fill_style = "#2c5056"
		g.begin_path()
		g.arc(X.call(wt.position[0]), Z.call(wt.position[1]), wt.radius * PX, 0, TAU)
		g.fill()
	for o in Layout.obscured:
		g.fill_style = "rgba(0, 0, 0, 0.85)"
		g.begin_path()
		g.arc(X.call(o.position[0]), Z.call(o.position[1]), o.radius * PX, 0, TAU)
		g.fill()
	# beyond the world's edge: darkness
	g.fill_style = "rgba(0, 0, 0, 0.55)"
	var top: float = Z.call(b.minZ)
	var bot: float = Z.call(b.maxZ)
	g.fill_rect(0, 0, w, top)
	g.fill_rect(0, bot, w, h - bot)
	g.fill_rect(0, top, X.call(b.minX), bot - top)
	g.fill_rect(X.call(b.maxX), top, w - X.call(b.maxX), bot - top)


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
			if _far(l.position[0], l.position[1], l.radius):
				continue
			areas[o.location] = {"x": l.position[0], "z": l.position[1], "r": l.radius, "kind": "area", "label": l.name, "tracked": quests.tracked.has(id)}
	out.append_array(areas.values())
	for n in game.npcs.list:
		var status: String = quests.marker_for(n.id)
		var quest: String = status if status != "" and not _far(n.position.x, n.position.z) else ""
		out.append({"x": n.position.x, "z": n.position.z, "kind": quest if quest != "" else "npc", "icon": n.def.get("mapIcon"), "label": n.name})
	# a miner sees where the live veins glint (WoW's Find Minerals)
	if game.skills.has("mining"):
		for v in game.mining.veins():
			out.append({"x": v.x, "z": v.z, "kind": "vein", "label": v.name})
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
	draw_circle(Vector2(SIZE, SIZE) / 2, SIZE / 2 + 3, Color.BLACK)
	draw_circle(Vector2(SIZE, SIZE) / 2, SIZE / 2 + 1, UI.BORDER)


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
		_drawn_at = now
		map.queue_redraw()


func _moved(now: Vector4) -> bool:
	var d := (now - _drawn_at).abs()
	return d.x > 0.05 or d.y > 0.05 or d.z > 0.02 or d.w > 0


func _draw_map() -> void:
	if game.player == null or not game.started and not game.hud.showcase:
		map.draw_circle(Vector2(SIZE, SIZE) / 2, SIZE / 2, Color.BLACK)
		return
	if picture == null:
		_paint()
	var g := Canvas2D.new(map)
	var p: Vector3 = game.player.position
	var scale: float = ZOOMS[zoom]
	var R := SIZE / 2
	g.fill_style = "#000"
	g.fill_rect(0, 0, SIZE, SIZE)
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
			g.fill_style = "#9fd0ff"
			g.begin_path()
			g.move_to(s.x, s.y - 4)
			g.line_to(s.x + 3, s.y)
			g.line_to(s.x, s.y + 4)
			g.line_to(s.x - 3, s.y)
			g.fill()
		elif m.kind == "npc" and inside:
			if m.icon:
				_trade_icon(g, s.x, s.y, m.icon)
				continue
			g.fill_style = "#e8d8a0"
			g.begin_path()
			g.arc(s.x, s.y, 2.6, 0, TAU)
			g.fill()
		elif m.kind == "vein" and inside:
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
		elif m.kind == "foe" and inside:
			g.fill_style = "#ff3a2a"
			g.stroke_style = "#000"
			g.line_width = 1
			g.begin_path()
			g.arc(s.x, s.y, 3, 0, TAU)
			g.fill()
			g.stroke()
	# the areas that are off the map get a pointer on the rim
	for m in all:
		if m.kind == "area" and m.tracked:
			_rim(g, to_map.call(m.x, m.z), R, "#f0c850", "", m.r * scale)
	# quest marks last, so they sit on top; out of range ones on the rim
	for m in all:
		if m.kind != "ready" and m.kind != "available" and m.kind != "active":
			continue
		var s: Vector2 = to_map.call(m.x, m.z)
		var glyph := "!" if m.kind == "available" else "?"
		var colour := "#a8a8a8" if m.kind == "active" else "#ffd23c"
		if s.distance_to(Vector2(R, R)) <= R - 8:
			_glyph(g, s.x, s.y, glyph, colour, 15)
		else:
			_rim(g, s, R, colour, glyph)
	# your camp, your killer and your body: always shown, on the rim when far
	for m in all:
		var s: Vector2 = to_map.call(m.x, m.z)
		var inside := s.distance_to(Vector2(R, R)) <= R - 8
		if m.kind == "camp":
			if inside:
				_glyph(g, s.x, s.y, "▲", "#ff9a40", 11)
		elif m.kind == "nemesis":
			if inside:
				_glyph(g, s.x, s.y, "☠", "#ff4a3a", 15)
			else:
				_rim(g, s, R, "#ff4a3a", "☠")
		elif m.kind == "corpse":
			if inside:
				_glyph(g, s.x, s.y, "✝", "#cfe6ff", 15)
			else:
				_rim(g, s, R, "#cfe6ff", "")
	# the Warden, at the centre, pointing the way they face
	g.save()
	g.translate(R, R)
	g.rotate(PI - game.player.facing)
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


func _glyph(g: Canvas2D, x: float, y: float, glyph: String, colour: String, px: int) -> void:
	g.font_size = px
	g.line_width = 3
	g.stroke_style = "#000"
	g.stroke_text(glyph, x, y)
	g.fill_style = colour
	g.fill_text(glyph, x, y)


## A marker beyond the edge: a small arrow on the rim pointing at it.
func _rim(g: Canvas2D, s: Vector2, R: float, colour: String, glyph: String, reach := 0.0) -> void:
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

class_name Minimap
extends Control
## A round north-up minimap, rendered from the actual gameplay World3D.
## A throttled orthographic camera shows the real terrain, water, buildings
## and placed assets, with the navigation markers drawn on
## top: townsfolk with their quest marks, shrines, the places current
## objectives point to, and the Warden as an arrow. Quest marks out of range
## sit on the rim, pointing the way, but only within
## `CONFIG.minimap.questRange` metres: quests far off stay hidden until you
## come nearer. Townsfolk with a trade (npcs.json `mapIcon`) show its icon;
## enemies fighting you show as red dots.

const SIZE := 168.0 ## pixels across
const ZOOMS := [0.9, 1.5, 2.4] ## screen pixels per metre; visible radius stays within Land.RADIUS
const SEGMENTS := 72 ## sides of the round window the map is shown through

var game
var zoom := 1
var map: Control
var view: SubViewport ## the square map is drawn here, then shown through a circle
var location: Label ## where you are, on a bar across the foot of the map
var coords: Label ## X / Y in world metres, under the map
var _circle := PackedVector2Array()
var _circle_uv := PackedVector2Array()
var zoom_buttons: Array = [] ## + and −, for the HUD to give them tips
var _tip: Label ## a quest mark's name and how far off it is, at the cursor
var _marks: Array = [] ## the markers last drawn, for the hover tip
## marker kinds that are not quest places (no distance tip)
const NOT_QUEST := ["shrine", "npc", "vein", "herb", "foe", "nemesis", "corpse", "camp"]


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
	# where you are: a bar above the circle (Dan, 2026-11-02), the map
	# moved down by NAME_ROOM to make room for it
	location = UI.label(self, "", 13, UI.GOLD)
	location.add_theme_stylebox_override("normal", _round_box(4))
	location.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	location.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	location.clip_text = true
	location.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	location.size = Vector2(150, 20)
	location.position = Vector2(SIZE / 2 - 75, -OUT_TOP)
	coords = UI.label(self, "", 11, UI.TEXT_DIM, 3)
	coords.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	coords.size = Vector2(180, 14)
	coords.position = Vector2(SIZE / 2 - 90, SIZE + 4)
	# the N badge and the zoom buttons
	# a small orb at the top of the rim, styled like the menu orbs round it
	var north := orb(270.0, NORTH_R, ON_RIM)
	_north = north
	north.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# a plain gold N, so north reads at a glance (Dan, 2026-11-04); the arrow
	# art is kept for the player marker and the tracker's way pointer
	var n := UI.label(north, "N", 12, UI.GOLD)
	n.add_theme_font_override("font", UI.bold)
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	n.grow_vertical = Control.GROW_DIRECTION_BOTH
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# zoom: two small round buttons on the rim, right side, clear of the place
	# bar (the HUD sets its menu orbs round the left side the same way)
	for z in [[1, 22.0], [-1, 48.0]]:
		var b := orb(z[1], ZOOM_R, ON_RIM)
		var step: int = z[0]
		b.pressed.connect(func():
			game.audio.sfx("quest_log", 0.6)
			set_zoom(zoom + step))
		b.draw.connect(func(): _draw_zoom(b, step))
		zoom_buttons.append(b)
	_tip = UI.label(self, "", 12, UI.TEXT)
	_tip.add_theme_stylebox_override("normal", UI.frame(Vector4(8, 4, 8, 4)))
	_tip.top_level = true
	_tip.z_index = 30
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false


const ZOOM_R := 11.0
const NORTH_R := 9.0
## the N and the zoom buttons sit ON the map's rim, centred on its edge
## (Dan, 2026-11-02), not outside it as the menu orbs once did
const ON_RIM := 0.0
## room the rim buttons need outside SIZE: right for zoom, top for north
const OUT_RIGHT := 4.0
const NAME_ROOM := 22.0 ## the place name's bar above the north badge
const OUT_TOP := 9.0 + NAME_ROOM


## A round button sat on the rim at `angle` degrees (0 = east, 90 = south),
## RuneScape style: drawn as a true circle, a bronze ring on dark stone.
## It sits just outside the map, its inner edge on the dark frame, so it
## never hides the quest arrows drawn round the inside of the rim (Dan,
## 2026-11-02: the orbs covered the waypoint arrows).
## `out` is how far the orb's centre stands out from the rim (-1: just
## outside, its inner edge on the frame).
func orb(angle: float, radius: float, out := -1.0) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(radius * 2, radius * 2)
	b.size = b.custom_minimum_size
	var a := deg_to_rad(angle)
	var r := SIZE / 2
	var dist := r + radius - 1 if out < 0 else r + out
	b.position = Vector2(r, r) + Vector2(cos(a), sin(a)) * dist - Vector2(radius, radius)
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


# ----------------------------------------------- actual overhead world
## The same World3D as gameplay, seen by an independent north-up camera.
## Each 64 m patch of ground (one Land chunk) is photographed ONCE, the first
## time its chunk is built, and kept as a still image; the minimap then just
## slides those stills under the markers as the player moves (Dan,
## 2026-11-04: capture once, no live re-rendering). Moving bodies are left
## out of the photo so nobody is frozen into the ground.
const TILE_M := 64.0 ## metres per still (matches Land.CHUNK, so a built chunk is a finished tile)
const TILE_PX := 192 ## pixels per still: 3 px/m, as sharp as the closest zoom
const KEEP_TILES := 4 ## stills further than this many tiles away are dropped (memory)
var terrain_view: SubViewport
var overhead_camera: Camera3D
var _tiles := {} ## Vector2i -> ImageTexture
var _capturing := false


func _ensure_overhead() -> void:
	if terrain_view != null or not game.is_inside_tree():
		return
	terrain_view = SubViewport.new()
	terrain_view.name = "WorldOverhead"
	terrain_view.size = Vector2i(TILE_PX, TILE_PX)
	terrain_view.own_world_3d = false
	terrain_view.world_3d = game.get_world_3d()
	terrain_view.gui_disable_input = true
	terrain_view.audio_listener_enable_3d = false
	terrain_view.positional_shadow_atlas_size = 0
	terrain_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(terrain_view)
	overhead_camera = Camera3D.new()
	overhead_camera.name = "NorthUpCamera"
	overhead_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	overhead_camera.rotation = Vector3(-PI / 2.0, 0, 0)
	overhead_camera.cull_mask = 0xFFFFF ^ World.MOVING_LAYER
	overhead_camera.size = TILE_M
	# A separate environment prevents the gameplay camera's depth fog from
	# hiding the ground when viewed from above.
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("15242b")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c4be")
	environment.ambient_light_energy = 0.8
	environment.ambient_light_sky_contribution = 0
	environment.fog_enabled = false
	environment.glow_enabled = false
	overhead_camera.environment = environment
	terrain_view.add_child(overhead_camera)
	overhead_camera.make_current()


## Photograph the nearest built chunk that has no still yet (one per frame at
## most, usually one per 64 m walked), and drop stills far behind.
func _refresh_overhead(_force := false) -> void:
	_ensure_overhead()
	if overhead_camera == null or game.player == null or _capturing:
		return
	var land = game.world.land if game.get("world") else null
	if land == null:
		return
	var p: Vector3 = game.player.position
	var here := Vector2i(floori(p.x / TILE_M), floori(p.z / TILE_M))
	for k in _tiles.keys():
		if maxi(absi(k.x - here.x), absi(k.y - here.y)) > KEEP_TILES:
			_tiles.erase(k)
	var best = null
	var best_d := INF
	for k in land.chunks:
		if _tiles.has(k) or maxi(absi(k.x - here.x), absi(k.y - here.y)) > 2:
			continue
		# wait until the streamed props on it are built too (WorldStream)
		var stream = game.world.stream
		if stream and not stream.covers(k.x * TILE_M, k.y * TILE_M, (k.x + 1) * TILE_M, (k.y + 1) * TILE_M):
			continue
		var d := Vector2(k - here).length_squared()
		if d < best_d:
			best_d = d
			best = k
	if best != null:
		_capture(best)


func _capture(k: Vector2i) -> void:
	_capturing = true
	var c := (Vector2(k) + Vector2(0.5, 0.5)) * TILE_M
	var peak := -INF
	for x in [0.0, 0.5, 1.0]:
		for z in [0.0, 0.5, 1.0]:
			peak = maxf(peak, Terrain.height_at(k.x * TILE_M + x * TILE_M, k.y * TILE_M + z * TILE_M))
	overhead_camera.position = Vector3(c.x, peak + 64.0, c.y)
	overhead_camera.near = 0.1
	overhead_camera.far = maxf(1024.0, peak + 320.0)
	terrain_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if is_instance_valid(terrain_view):
		_tiles[k] = ImageTexture.create_from_image(terrain_view.get_texture().get_image())
		map.queue_redraw()
	_capturing = false


## Shared coordinates for overlay markers: east right, north up.
func world_to_map(at: Vector2) -> Vector2:
	var p: Vector3 = game.player.position
	return Vector2.ONE * SIZE * 0.5 + ((at - Vector2(p.x, p.z)) * float(ZOOMS[zoom])).rotated(_yaw)


## The map turns with the camera, so the screen's up (W) is the map's up
## (Dan, 2026-11-10: with the 45° camera, map-north needed W+D). _yaw is the
## camera's turn; the N badge slides round the rim to where north now is.
var _yaw := 0.0
var _north: Button


func _camera_yaw() -> float:
	var o: Vector3 = game._camera_offset(1.0)
	return atan2(o.x, o.z)


func _place_north() -> void:
	if _north == null:
		return
	var a := deg_to_rad(270.0) + _yaw
	var r := SIZE / 2
	var half := _north.size / 2
	_north.position = Vector2(r, r) + Vector2(cos(a), sin(a)) * (r + ON_RIM) - half


# ------------------------------------------------------------ markers
## Every marker for the current state, in world metres:
## { x, z, kind: 'npc' | 'shrine' | 'area' | 'ready' | 'available' | 'active' | 'foe' | ..., r?, label? }
func markers() -> Array:
	var quests = game.quests
	var out := []
	for s in Layout.shrines:
		out.append({"x": s.position[0], "z": s.position[1], "kind": "shrine"})
	for st in Layout.stations:
		out.append({"x": st.position[0], "z": st.position[1], "kind": "station", "station": st.kind, "label": Interaction.title(st.name)})
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
	if quests.focus != "" and quests.status(quests.focus) == "available":
		var at: Dictionary = quests.goal(quests.focus)
		if not at.is_empty():
			out.append({"x": at.x, "z": at.z, "r": 0, "kind": "goal", "label": at.label, "npc": true, "focus": true})
	for n in game.npcs.here:
		if n.def.get("ambient"):
			continue # background folk (town life) would bury the people you look for
		var status: String = quests.marker_for(n.id) if not _far(n.position.x, n.position.z) else ""
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
	if not game.started and not game.hud.showcase:
		return
	_refresh_overhead()
	_hover_tip()
	_since += dt
	var p: Vector3 = game.player.position
	var yaw := _camera_yaw()
	if not is_equal_approx(yaw, _yaw):
		_yaw = yaw
		_place_north()
		_drawn_at = Vector4(INF, 0, 0, 0)
	var now := Vector4(p.x, p.z, game.player.facing, zoom)
	if _since >= 0.2 or _moved(now):
		_since = 0.0
		var here := place_name()
		if location.text != here:
			location.text = here
		# the world clock (WorldState.hour) beside where you stand
		var xy := "%s   X: %d   Y: %d" % [DayNight.clock_text(game.world_state.hour), roundi(p.x), roundi(p.z)]
		if coords.text != xy:
			coords.text = xy
		_drawn_at = now
		map.queue_redraw()


## Over a quest mark (an objective's area, a tracked goal, a quest giver):
## its name and how far off it is, in metres, at the cursor (Dan, 2026-10-29).
## Marks past the rim are found on the rim, where they are drawn.
func _hover_tip() -> void:
	var R := SIZE / 2
	var c := Vector2(R, R)
	var mp := get_local_mouse_position()
	var best = null
	if game.started and mp.distance_to(c) <= R:
		var scale: float = ZOOMS[zoom]
		var p: Vector3 = game.player.position
		var near := 8.0
		for m in _marks:
			if m.kind in NOT_QUEST:
				continue
			var s := world_to_map(Vector2(m.x, m.z))
			var reach: float = m.get("r", 0.0) * scale
			if s.distance_to(c) - reach > R - 4:
				s = c + (s - c).normalized() * (R - 9)
				reach = 0.0
			var d := maxf(0.0, mp.distance_to(s) - reach)
			if d <= near:
				near = d
				best = m
	if best == null:
		_tip.visible = false
		return
	var pl: Vector3 = game.player.position
	var metres := maxi(0, roundi(U.hyp(best.x - pl.x, best.z - pl.z) - best.get("r", 0.0)))
	var label: String = best.get("label", "")
	_tip.text = ("%s\n%d m" % [label, metres]) if label != "" else "%d m" % metres
	_tip.size = _tip.get_combined_minimum_size()
	var at := get_global_mouse_position() + Vector2(14, 10)
	if at.x + _tip.size.x > get_viewport_rect().size.x - 4:
		at.x -= _tip.size.x + 24 # the map sits at the right edge
	_tip.global_position = at
	_tip.visible = true


## The name of where you stand: the building you are in, else the region.
func place_name() -> String:
	var inside = game.world.indoors if game.world else null
	if inside is Dictionary and inside.get("def", {}).get("name"):
		return inside.def.name
	return game.region.get("name", "") if game.region is Dictionary else ""


const MARKS_MS := 80
var _marks_at := -100000


func _moved(now: Vector4) -> bool:
	var d := (now - _drawn_at).abs()
	return d.x > 0.05 or d.y > 0.05 or d.z > 0.02 or d.w > 0


func _draw_map() -> void:
	if game.player == null or not game.started and not game.hud.showcase:
		map.draw_circle(Vector2(SIZE, SIZE) / 2, SIZE / 2, Color.BLACK)
		return
	var p: Vector3 = game.player.position
	_refresh_overhead()
	var g := Canvas2D.new(map)
	var scale: float = ZOOMS[zoom]
	var R := SIZE / 2
	g.fill_style = "#15242b"
	g.fill_rect(0, 0, SIZE, SIZE)
	var tile_px := TILE_M * scale
	# the stills are drawn turned with the camera, about the map's centre
	map.draw_set_transform(Vector2(R, R), _yaw)
	var reach := R * 1.42 + tile_px
	for k in _tiles:
		var at := (Vector2(k) * TILE_M - Vector2(p.x, p.z)) * scale
		if (at + Vector2.ONE * tile_px / 2).length() > reach:
			continue
		# a hair of overlap hides seams between neighbouring stills
		map.draw_texture_rect(_tiles[k], Rect2(at, Vector2.ONE * (tile_px + 0.5)), false)
	map.draw_set_transform(Vector2.ZERO)
	var to_map := func(x: float, z: float) -> Vector2: return world_to_map(Vector2(x, z))
	# the map redraws every frame while you walk (smooth scrolling); the
	# list of what is on it is rebuilt about 12 times a second (it walks every
	# quest, npc and enemy: ~0.5 ms)
	var now_ms := Time.get_ticks_msec()
	if now_ms - _marks_at >= MARKS_MS or _marks.is_empty():
		_marks_at = now_ms
		_marks = markers()
	var all: Array = _marks
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
		elif m.kind == "station" and inside:
			# Dan's art when painted (assets/icons/map/station_<kind>.png),
			# else a coloured disc with the station's letter
			if _art(g, "station_" + m.station, s.x, s.y, 14):
				continue
			var lk := Interaction.look(m.station)
			g.fill_style = "#000"
			g.begin_path()
			g.arc(s.x, s.y, 5.5, 0, TAU)
			g.fill()
			g.fill_style = lk.colour
			g.begin_path()
			g.arc(s.x, s.y, 4.5, 0, TAU)
			g.fill()
			g.font_size = 8
			g.fill_style = "#000"
			g.fill_text(lk.letter, s.x, s.y + 0.5)
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
	g.begin_path()
	g.arc(0, 0, 10, 0, TAU)
	g.fill_style = "rgba(0, 0, 0, 0.55)"
	g.fill()
	g.rotate(PI - game.player.facing + _yaw)
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
		"banker":
			# a strongbox with its lock
			g.fill_rect(-3.6, -2.4, 7.2, 5.4)
			g.fill_style = "rgba(12, 10, 8, 0.9)"
			g.fill_rect(-0.8, -0.6, 1.6, 1.8)
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
	var r := R - 18 ## in from the rim, clear of the zoom buttons (Dan, 2026-11-02)
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

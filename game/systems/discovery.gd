class_name Discovery
extends RefCounted
## Exploring the world: every point of interest (WorldMap.pois: Act 1's
## places, the world's settlements and landmarks) has a marker you can
## examine for its story note, and walking near one discovers it: its name
## across the screen, a little experience, and it shows on the world map
## from then on. Hidden places (`secret`) have no marker until found. The
## boat routes are ferries: Space at a jetty sails you to the other end.

const REACH := 30.0 ## metres from a POI that discover it
const XP_PER_LEVEL := 6 ## experience for a discovery, per zone level (WoW-style)
const MARKERS := {
	"town": ["cottage", 1.0], "village": ["cottage", 1.0], "hut": ["cottage", 0.8], "inn": ["cottage", 1.1],
	"dock": ["crate", 1.4], "fort": ["watch_post", 1.0], "camp": ["camp", 1.0], "ruin": ["ruin_wall", 1.4],
	"landmark": ["standing_stone", 1.8], "gate": ["palisade", 1.0], "trainer": ["awning", 1.0],
	"tale": ["waymarker", 1.0], "hunt": ["bone_pile", 1.4], "story": ["waymarker", 1.0],
	"dungeon": ["rock1", 3.0], "place": ["waymarker", 1.0],
}

var game
var markers := {} ## poi id -> Node3D
var docks: Array = [] ## {name, at: Vector2, to: Vector2, to_name}
var _check := 0.0


func _init(g) -> void:
	game = g


func build() -> Discovery:
	for p in WorldMap.pois:
		if p.kind == "secret":
			continue
		var x: float = p.at[0]
		var z: float = p.at[1]
		game.world.examine_points.append({"id": "poi:" + p.id, "x": x, "z": z})
		if _built_up(x, z):
			continue # something already stands here (the town, the cart...)
		var m: Array = MARKERS.get(p.kind, ["waymarker", 1.0])
		if not Assets.has(m[0]):
			continue
		var obj := Assets.instance(m[0])
		obj.scale = Vector3.ONE * m[1]
		obj.position = Vector3(x, Terrain.height_at(x, z), z)
		obj.rotation.y = hash(p.id) % 360
		obj.name = "Poi_" + p.id
		game.world.group.add_child(obj)
		markers[p.id] = obj
		game.collision.add(x, z, 0.6 * m[1])
	for b in WorldMap.boats:
		var a := _shore(b.from, b.line)
		var c := _shore(b.to, b.line.duplicate())
		if a == Vector2.INF or c == Vector2.INF:
			continue
		var from_name := _place_name(a)
		var to_name := _place_name(c)
		docks.append({"name": b.name, "at": a, "to": c, "to_name": to_name})
		docks.append({"name": b.name, "at": c, "to": a, "to_name": from_name})
	for d in docks:
		if Assets.has("signpost"):
			var s := Assets.instance("signpost")
			s.position = Vector3(d.at.x, Terrain.height_at(d.at.x, d.at.y), d.at.y)
			s.name = "Jetty"
			game.world.group.add_child(s)
	return self


static func _built_up(x: float, z: float) -> bool:
	for p in Layout.props:
		if Vector2(x - p.position[0], z - p.position[1]).length() < 22.0:
			return true
	for b in Layout.buildings:
		if Vector2(x - b.position[0], z - b.position[1]).length() < 40.0:
			return true
	return false


## The open ground nearest a boat route's end (routes end out on the water).
static func _shore(end: Array, line: Array) -> Vector2:
	var at := Vector2(end[0], end[1])
	for r in range(0, 260, 6):
		for k in 16:
			var a := TAU * k / 16.0
			var p := at + Vector2(cos(a), sin(a)) * r
			if Terrain.walk_at(p.x, p.y) >= 0.75:
				return p
	return Vector2.INF


static func _place_name(at: Vector2) -> String:
	var p := WorldMap.poi_near(at.x, at.y, 400.0)
	return p.name if not p.is_empty() else "the far shore"


# ------------------------------------------------------------- discovering
func update(dt: float) -> void:
	_check -= dt
	if _check > 0 or game.player == null or game.player.dead:
		return
	_check = 0.5
	var pos: Vector3 = game.player.position
	var ws = game.world_state
	for p in WorldMap.pois:
		if ws.discovered.has(p.id):
			continue
		if Vector2(pos.x - p.at[0], pos.z - p.at[1]).length() <= (REACH * 0.5 if p.kind == "secret" else REACH):
			discover(p)


func discover(p: Dictionary) -> void:
	game.world_state.discovered[p.id] = true
	var lv := _zone_level(p)
	var xp := XP_PER_LEVEL * lv
	game.hud.show_zone(p.name, "Discovered" if p.kind != "secret" else "A hidden place", 3.0)
	game.events.emit("log", {"text": "Discovered: %s." % p.name, "kind": "lore"})
	game.events.emit("poiDiscovered", {"poi": p})
	if game.started:
		game.progression.add_xp(xp)


## The low end of the levels of the region a POI is in (1 when unknown).
func _zone_level(p: Dictionary) -> int:
	var r := DB.region_at(p.at[0], p.at[1])
	var lv := str(r.get("levels", "1"))
	var n := lv.get_slice("-", 0).strip_edges()
	return maxi(1, int(n)) if n.is_valid_int() else 1


func is_discovered(id: String) -> bool:
	return game.world_state.discovered.has(id)


# ------------------------------------------------------------- boats
func interactions() -> Array:
	var out := []
	for d in docks:
		out.append({"key": "boat:%s:%d:%d" % [d.name, int(d.at.x), int(d.at.y)], "x": d.at.x, "z": d.at.y, "bias": 0.2, "reach": 3.0,
			"prompt": "Take the boat to %s (%s)" % [d.to_name, d.name], "run": func(): sail(d)})
	return out


func sail(d: Dictionary) -> void:
	if game.resources.in_combat or game.targeting.attacking:
		game.hud.error("You can't do that while fighting")
		return
	game.player.place_at(d.to.x, d.to.y)
	game._snap_camera()
	game.events.emit("log", {"text": "The boat takes you over the water to %s." % d.to_name, "kind": "lore"})

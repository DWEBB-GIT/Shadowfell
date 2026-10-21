class_name Layout
extends RefCounted
## The world's layout from data/world.json and data/scenery.json, under the
## names the world code uses (src/world/layout.js). Positions are [x, z] in
## metres, rotations in degrees around the vertical axis. North is -z.

static var bounds: Dictionary
static var player_start: Dictionary
static var shrines: Array
static var npcs: Array ## townsfolk where they stand, merged with who they are
static var enemies: Array ## { id, type, position }
static var props: Array
static var clearings: Array
static var lights: Array
static var witchlights: Array
static var water: Array
static var obscured: Array
static var buildings: Array
static var stations: Array
static var signposts: Array
static var pads: Array
static var danger_zones: Array
static var road: Array
static var road_half_width: float
static var track: Array


static func setup(w: Dictionary, s: Dictionary) -> void:
	bounds = w.bounds
	player_start = w.playerStart
	shrines = w.shrines
	npcs = []
	for sp in w.npcSpawns:
		var n: Dictionary = DB.npcs[sp.npc]
		var m := U.merged(n, sp)
		m.id = n.id
		npcs.append(m)
	enemies = []
	for sp in w.enemySpawns:
		enemies.append({"id": sp.id, "type": sp.enemy, "position": sp.position})
	for r in w.roads:
		if r.id == "fallen_road":
			road = r.points
			road_half_width = r.halfWidth
		elif r.id == "forest_track":
			track = r.points
	props = s.props
	clearings = s.clearings
	lights = s.lights
	witchlights = s.witchlights
	water = w.get("water", [])
	obscured = w.get("obscured", [])
	buildings = w.get("buildings", [])
	stations = w.get("stations", [])
	signposts = w.get("signposts", [])
	pads = w.get("pads", [])
	danger_zones = []
	for z in w.dangerZones:
		danger_zones.append({"position": z.position, "radius": z.radius, "enemy": z.enemySpawn})


static func enemy_spawn(id: String):
	for s in enemies:
		if s.id == id:
			return s
	return null


const DIRS := [["north", "↑"], ["north-east", "↗"], ["east", "→"], ["south-east", "↘"], ["south", "↓"], ["south-west", "↙"], ["west", "←"], ["north-west", "↖"]]


## [{ label, dir, arrow, metres, angle }] for one signpost; north is -z
static func signpost_lines(sp: Dictionary) -> Array:
	var x: float = sp.position[0]
	var z: float = sp.position[1]
	var out := []
	for p in sp.points:
		var loc: Dictionary = DB.locations[p.to]
		var dx: float = loc.position[0] - x
		var dz: float = loc.position[1] - z
		var bearing := fmod(rad_to_deg(atan2(dx, -dz)) + 360.0, 360.0)
		var d: Array = DIRS[U.jround(bearing / 45.0) % 8]
		out.append({"label": p.get("label", loc.name), "dir": d[0], "arrow": d[1], "metres": maxi(10, U.jround(U.hyp(dx, dz) / 10.0) * 10), "angle": atan2(dx, dz)})
	return out

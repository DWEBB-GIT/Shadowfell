class_name WorldMap
extends RefCounted
## The world's design map (data/world_map.json) as the game uses it: which
## region and subzone a place is in, and every point of interest (Act 1's
## POIs, the world's settlements and landmarks) with its story note. World
## positions throughout; Act 1's layout is shifted by world.act1Offset.

static var offset := Vector2.ZERO
static var act1_box := Rect2()
static var act1_regions: Array = [] ## {id, poly: PackedVector2Array}
static var pockets: Array = [] ## Act 1's walkable valleys: {name, poly | at + r | ellipse}
static var zones: Array = [] ## the world's zones, in world_map.json order
static var pois: Array = [] ## {id, name, kind, at: [x, z], note, region, act}
static var boats: Array = [] ## {name, from: [x, z], to: [x, z], line}
static var _by_id := {}


static func setup() -> void:
	var m: Dictionary = DB.world_map
	act1_regions = []
	pockets = []
	pois = []
	boats = []
	_by_id.clear()
	if m.is_empty():
		return
	var w: Dictionary = m.world
	var a: Dictionary = m.act1
	offset = Vector2(w.act1Offset[0], w.act1Offset[1])
	act1_box = Rect2(w.act1Box[0], w.act1Box[1], w.act1Box[2], w.act1Box[3])
	zones = w.zones
	for r in a.regions:
		act1_regions.append({"id": r.id, "poly": _poly(r.poly, offset)})
	for p in a.pockets:
		var q := {"name": p.name}
		if p.has("poly"):
			q.poly = _poly(p.poly, offset)
		elif p.has("ellipse"):
			q.ellipse = [p.ellipse[0] + offset.x, p.ellipse[1] + offset.y, p.ellipse[2], p.ellipse[3]]
		else:
			q.at = Vector2(p.at[0], p.at[1]) + offset
			q.r = p.r
		pockets.append(q)
	for p in a.pois:
		_add({"id": p.id, "name": p.name, "kind": p.kind, "at": [p.at[0] + offset.x, p.at[1] + offset.y], "note": p.get("note", ""), "region": p.region, "act": "Act 1"})
	var zone_act := {}
	for z in zones:
		zone_act[z.id] = z.get("act", "")
	for s in w.settlements:
		if s.zone == "bracken":
			continue # Act 1's own POIs stand for these
		_add({"id": str(s.name).to_snake_case().replace("'", ""), "name": s.name, "kind": s.kind, "at": s.at, "note": s.get("note", ""), "region": s.zone, "act": zone_act.get(s.zone, "")})
	for l in w.landmarks:
		_add({"id": "landmark_" + str(l.name).to_snake_case().replace("'", ""), "name": l.name, "kind": "landmark", "at": l.at, "note": l.get("note", ""), "region": "", "act": ""})
	for r in w.routes:
		if r.kind == "boat":
			boats.append({"name": r.name, "from": r.line[0], "to": r.line[-1], "line": r.line})


static func _add(p: Dictionary) -> void:
	if _by_id.has(p.id):
		p.id = "%s_%d" % [p.id, pois.size()]
	pois.append(p)
	_by_id[p.id] = p


static func poi(id: String) -> Dictionary:
	return _by_id.get(id, {})


static func _poly(pts: Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p[0], p[1]) + off)
	return out


## The region at a place (a record of world.json `regions`): Brackenford
## itself, one of Act 1's regions, or the world zone the ground belongs to.
static func region_at(x: float, z: float) -> Dictionary:
	var regions: Array = DB.world.regions
	if regions.is_empty():
		return {}
	var id := ""
	for r in regions:
		if r.has("town") and Vector2(x - r.town[0], z - r.town[1]).length() <= r.town[2]:
			return r
	var p := Vector2(x, z)
	if act1_box.has_point(p):
		var best := INF
		for r in act1_regions:
			if Geometry2D.is_point_in_polygon(p, r.poly):
				id = r.id
				break
		if id == "":
			for r in act1_regions:
				for v in r.poly:
					var d: float = v.distance_to(p)
					if d < best:
						best = d
						id = r.id
	elif not zones.is_empty():
		var k := Terrain.zone_index_at(x, z)
		id = zones[clampi(k, 0, zones.size() - 1)].id
	for r in regions:
		if r.id == id:
			return r
	return regions[0]


## The named valley or place you stand in, or "" between them.
static func subzone_at(x: float, z: float) -> String:
	var p := Vector2(x, z)
	if act1_box.has_point(p):
		for q in pockets:
			if q.has("poly"):
				if Geometry2D.is_point_in_polygon(p, q.poly):
					return q.name
			elif q.has("ellipse"):
				var e: Array = q.ellipse
				if pow((x - e[0]) / e[2], 2) + pow((z - e[1]) / e[3], 2) <= 1.0:
					return q.name
			elif p.distance_to(q.at) <= q.r:
				return q.name
		return ""
	for s in pois:
		if s.kind != "landmark" and p.distance_to(Vector2(s.at[0], s.at[1])) < 90:
			return s.name
	return ""


## The POI nearest a place within `reach` metres, or {}.
static func poi_near(x: float, z: float, reach: float) -> Dictionary:
	var best := {}
	var bd := reach
	for p in pois:
		var d := Vector2(x - p.at[0], z - p.at[1]).length()
		if d < bd:
			bd = d
			best = p
	return best

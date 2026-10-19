class_name Terrain
extends RefCounted
## The ground's height anywhere, worked out from world.json (roads, pads,
## ponds) with the same formula as src/world/terrain.js, so both builds stand
## things at the same height. Gameplay asks height_at() instead of raycasting.

static var _bounds: Dictionary
static var _road: Array
static var _track: Array
static var _road_half_width := 2.2
static var _pads: Array
static var _water: Array
static var _pad_level := {}
static var _water_level := {}


static func setup(world: Dictionary) -> void:
	_bounds = world.bounds
	for r in world.roads:
		if r.id == "fallen_road":
			_road = r.points
			_road_half_width = r.halfWidth
		elif r.id == "forest_track":
			_track = r.points
	_pads = world.get("pads", [])
	_water = world.get("water", [])
	_pad_level.clear()
	_water_level.clear()


static func _dist_to_segment(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var len2 := dx * dx + dz * dz
	var t := clampf(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	return Vector2(px - (ax + dx * t), pz - (az + dz * t)).length()


static func _dist_to_line(line: Array, x: float, z: float) -> float:
	var best := INF
	for i in line.size() - 1:
		best = minf(best, _dist_to_segment(x, z, line[i][0], line[i][1], line[i + 1][0], line[i + 1][1]))
	return best


static func distance_to_main_road(x: float, z: float) -> float:
	return _dist_to_line(_road, x, z)


static func distance_to_road(x: float, z: float) -> float:
	return minf(_dist_to_line(_road, x, z), _dist_to_line(_track, x, z))


## 0 on the Fallen Road, rising to 1 a little way into the Blackwood.
static func blackwoodness(z: float) -> float:
	return smoothstep(52.0, 66.0, -z)


static func _raw_height(x: float, z: float) -> float:
	var h := sin(x * 0.11) * cos(z * 0.09) * 0.9 \
		+ sin(x * 0.27 + 1.3) * sin(z * 0.23 + 0.7) * 0.35 \
		+ cos(x * 0.6 + z * 0.4) * 0.08
	# the land climbs towards the watch post, then sinks into the Blackwood
	h += maxf(0.0, (minf(-z, 56.0) - 20.0) * 0.06) * maxf(0.0, (x + 10.0) / 40.0)
	h -= smoothstep(56.0, 76.0, -z) * 1.4
	# hills rise outside the playable area
	var ex := maxf(0.0, maxf(_bounds.minX + 4.0 - x, x - (_bounds.maxX - 4.0)))
	var ez := maxf(0.0, maxf(_bounds.minZ + 4.0 - z, z - (_bounds.maxZ - 4.0)))
	var e := Vector2(ex, ez).length()
	return h + e * e * 0.05


static func _land_height(x: float, z: float) -> float:
	var h := _raw_height(x, z)
	var k := smoothstep(_road_half_width * 0.6, _road_half_width * 2.5, distance_to_road(x, z))
	return lerpf(h * 0.55 - 0.05, h, k)


static func water_level(w: Dictionary) -> float:
	if not _water_level.has(w.id):
		_water_level[w.id] = w.get("level", _land_height(w.position[0], w.position[1]) - 0.25)
	return _water_level[w.id]


static func height_at(x: float, z: float) -> float:
	var h := _land_height(x, z)
	for p in _pads:
		var d := Vector2(x - p[0], z - p[1]).length()
		if d > p[2] + 3.0:
			continue
		var key := "%s,%s" % [p[0], p[1]]
		if not _pad_level.has(key):
			_pad_level[key] = _land_height(p[0], p[1])
		h = lerpf(_pad_level[key], h, smoothstep(p[2], p[2] + 3.0, d))
	for w in _water:
		var d := Vector2(x - w.position[0], z - w.position[1]).length()
		if d > w.radius + 1.0:
			continue
		var k := 1.0 - smoothstep(w.radius - 1.6, w.radius + 0.6, d)
		h = lerpf(h, water_level(w) - 1.1, k)
	return h

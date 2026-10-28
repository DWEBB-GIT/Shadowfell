class_name Terrain
extends RefCounted
## The ground anywhere in the world: height, whether it can be walked on,
## what it is (surface) and which zone it belongs to. Baked from
## data/world_map.json by tools/world/bake_world.py into data/terrain/world.bin:
## a 4 m grid cut into 128 m tiles, each packed on its own, so only the tiles
## somebody stands near are ever unpacked (a server would do the same for
## every player). Gameplay asks height_at() and walk_at() instead of
## raycasting. Building pads and the old small ponds are worked in on top.

## Which map the ground is: "act1" (data/terrain/, baked from world_map.json)
## or "new" (data/terrain/new_map/, Dan's 2026-10-28 map, baked from his
## heightmap by tools/world/new_map/bake_new_map.py). Project Settings >
## shadowfell/world/map picks it; the World dock's Map picker sets it.
const MAPS := {"act1": "res://data/terrain/", "new": "res://data/terrain/new_map/"}
const MAP_SETTING := "shadowfell/world/map"
static var dir := "res://data/terrain/" ## the map's folder: world.bin, water.json, sculpt.json
static var _ground_img: Image ## new map: the ground's colours (ground.png), or null
static var _ground_scale := 2.0 ## metres per ground.png pixel
static var _map_tex: Texture2D ## map_picture(), made once
const N := 33 ## samples per tile side (32 cells, edges shared)

## surfaces, the low 4 bits of a sample's info byte (bake_world.py SURF)
enum { SEA, MEADOW, MARSH, DOWNS, BLACKWOOD, ROCK, MOOR, SAND, FARMLAND, FOREST, SNOW, DESERT, ASH, SWAMP, JUNGLE, HAUNTED }

static var _bounds: Dictionary
static var _x0 := 0.0
static var _z0 := 0.0
static var _cell := 4.0
static var _sea_floor := -12.0
static var _tile := 32
static var _tx := 0
static var _tz := 0
static var _index := PackedInt64Array() ## offset << 32 | length, per tile
static var _file: PackedByteArray
static var _tiles := {} ## tile key -> [heights (PackedFloat32Array), walk, info] or null
static var _pads: Array
static var _water: Array
static var _pad_level := {}
static var _water_level := {}
static var _roads: Array = [] ## [{ id, name, kind, half, points }]
static var _road_cells := {} ## 32 m cell -> [[ax, az, bx, bz, half], ...]
const ROAD_CELL := 32.0
## the visible road surface's half width by kind (the walkable corridor is wider)
const ROAD_HALF := {"road": 2.6, "lane": 2.2, "track": 1.6, "hidden": 0.9, "tunnel": 2.0, "intro": 0.0}
static var tiles_unpacked := 0


## The map Project Settings picks ("act1" unless set).
static func chosen_map() -> String:
	var m := str(ProjectSettings.get_setting(MAP_SETTING, "act1"))
	return m if MAPS.has(m) else "act1"


static func is_new_map() -> bool:
	return dir == MAPS.new


## Switch to a map's folder (drops what was loaded from the other one).
static func use_map(map: String) -> void:
	var d: String = MAPS.get(map, MAPS.act1)
	if d == dir and not _file.is_empty():
		return
	dir = d
	_file = PackedByteArray()
	_tiles.clear()
	_pad_level.clear()
	_water_level.clear()
	_ground_img = null
	_map_tex = null
	if is_new_map() and ResourceLoader.exists(dir + "ground.png"):
		var tex: Texture2D = load(dir + "ground.png")
		_ground_img = tex.get_image()
		if _ground_img.is_compressed():
			_ground_img.decompress()


static func path() -> String:
	return dir + "world.bin"


## The new map's painted picture (map.jpg: Dan's top-down map) for the world
## map and the minimap, or null on the old map (they draw the ground instead).
static func map_picture() -> Texture2D:
	if not is_new_map() or not ResourceLoader.exists(dir + "map.jpg"):
		return null
	if _map_tex == null:
		_map_tex = ImageTexture.create_from_image((load(dir + "map.jpg") as Texture2D).get_image())
	return _map_tex


## The ground the map covers, in metres (x, z, width, depth).
static func map_rect() -> Rect2:
	return Rect2(_x0, _z0, _tx * _tile * _cell, _tz * _tile * _cell)


## The new map's painted ground colour at a point, or null on the old map.
static func ground_colour(x: float, z: float):
	if _ground_img == null:
		return null
	var px := clampi(int((x - _x0) / _ground_scale), 0, _ground_img.get_width() - 1)
	var pz := clampi(int((z - _z0) / _ground_scale), 0, _ground_img.get_height() - 1)
	return _ground_img.get_pixel(px, pz)


static func setup(world: Dictionary) -> void:
	_bounds = world.bounds
	_pads = world.get("pads", [])
	_water = world.get("water", [])
	_pad_level.clear()
	_water_level.clear()
	_load_tiles()
	_index_roads(world)


static func _load_tiles() -> void:
	if not _file.is_empty():
		return
	_file = FileAccess.get_file_as_bytes(path())
	if _file.size() < 36:
		push_error("Terrain: %s is missing; run tools/world/bake_world.py" % path())
		return
	_x0 = _file.decode_float(8)
	_z0 = _file.decode_float(12)
	_cell = _file.decode_float(16)
	_sea_floor = _file.decode_float(20)
	_tile = _file.decode_u32(24)
	_tx = _file.decode_u32(28)
	_tz = _file.decode_u32(32)
	_index.resize(_tx * _tz)
	for k in _tx * _tz:
		_index[k] = (_file.decode_u32(36 + k * 8) << 32) | _file.decode_u32(40 + k * 8)
	if _ground_img:
		_ground_scale = _tx * _tile * _cell / _ground_img.get_width()


## The roads drawn on the ground: Act 1's lanes and tracks, the world's routes
## and any extra in world.json `roads`, cut into a grid for quick lookups.
static func _index_roads(world: Dictionary) -> void:
	_roads = []
	_road_cells.clear()
	var wm: Dictionary = DB.world_map if not DB.world_map.is_empty() else {}
	if not wm.is_empty():
		var off: Array = wm.world.act1Offset
		for r in wm.act1.roads:
			var pts := []
			for p in r.line:
				pts.append([p[0] + off[0], p[1] + off[1]])
			_roads.append({"id": r.id, "name": r.name, "kind": r.kind, "half": ROAD_HALF.get(r.kind, 1.6), "points": pts})
		for r in wm.world.routes:
			if r.kind != "boat":
				_roads.append({"id": str(r.name).to_snake_case(), "name": r.name, "kind": r.kind, "half": ROAD_HALF.get(r.kind, 1.6), "points": r.line})
	for r in world.get("roads", []):
		_roads.append({"id": r.id, "name": r.name, "kind": r.get("kind", "road"), "half": r.get("halfWidth", 2.2), "points": r.points})
	for r in _roads:
		if r.half <= 0:
			continue
		var pts: Array = r.points
		for i in pts.size() - 1:
			var seg := [float(pts[i][0]), float(pts[i][1]), float(pts[i + 1][0]), float(pts[i + 1][1]), float(r.half)]
			var pad := 12.0
			for cx in range(floori((minf(seg[0], seg[2]) - pad) / ROAD_CELL), floori((maxf(seg[0], seg[2]) + pad) / ROAD_CELL) + 1):
				for cz in range(floori((minf(seg[1], seg[3]) - pad) / ROAD_CELL), floori((maxf(seg[1], seg[3]) + pad) / ROAD_CELL) + 1):
					var k := Vector2i(cx, cz)
					if not _road_cells.has(k):
						_road_cells[k] = []
					_road_cells[k].append(seg)


static func roads() -> Array:
	return _roads


# ------------------------------------------------------------------ tiles
## One tile's samples, unpacked the first time anything asks: [heights,
## walk, info], or null for open sea.
static func _tile_at(i: int, j: int):
	var key := j * 65536 + i
	if _tiles.has(key):
		return _tiles[key]
	var t = null
	if i >= 0 and j >= 0 and i < _tx and j < _tz:
		var e: int = _index[j * _tx + i]
		var length := e & 0xffffffff
		if length > 0:
			var blob := _file.slice(e >> 32, (e >> 32) + length)
			var raw := blob.decompress(N * N * 4, FileAccess.COMPRESSION_DEFLATE)
			var h := PackedFloat32Array()
			h.resize(N * N)
			# heights are stored as differences along x, then along z
			var col := PackedInt32Array()
			col.resize(N)
			for b in N:
				var run := 0
				for a in N:
					col[a] += raw.decode_s16((b * N + a) * 2)
					run += col[a]
					h[b * N + a] = run * 0.05 - 50.0
			t = [h, raw.slice(N * N * 2, N * N * 3), raw.slice(N * N * 3, N * N * 4)]
			tiles_unpacked += 1
	_tiles[key] = t
	return t


## How many tiles are unpacked (the rest of the world costs nothing).
static func tiles_loaded() -> int:
	return tiles_unpacked


## sample (a, b) of the 4 m grid: [height, walk 0..255, info]
static func _sample(a: int, b: int) -> Array:
	var i := floori(float(a) / _tile)
	var j := floori(float(b) / _tile)
	var t = _tile_at(i, j)
	if t == null:
		return [_sea_floor, 0, 0]
	var k := (b - j * _tile) * N + (a - i * _tile)
	return [t[0][k], t[1][k], t[2][k]]


static func _grid_height(a: int, b: int) -> float:
	var i := floori(float(a) / _tile)
	var j := floori(float(b) / _tile)
	var t = _tile_at(i, j)
	if t == null:
		return _sea_floor
	return t[0][(b - j * _tile) * N + (a - i * _tile)]


static func _grid_walk(a: int, b: int) -> float:
	var i := floori(float(a) / _tile)
	var j := floori(float(b) / _tile)
	var t = _tile_at(i, j)
	if t == null:
		return 0.0
	return t[1][(b - j * _tile) * N + (a - i * _tile)] / 255.0


## The baked ground's height, on the same two triangles per 4 m square as the
## drawn terrain (split from (x+4, z) to (x, z+4)), so feet meet the ground.
static func base_height(x: float, z: float) -> float:
	var fx := (x - _x0) / _cell
	var fz := (z - _z0) / _cell
	var a := floori(fx)
	var b := floori(fz)
	fx -= a
	fz -= b
	if fx + fz <= 1.0:
		var h00 := _grid_height(a, b)
		return h00 + (_grid_height(a + 1, b) - h00) * fx + (_grid_height(a, b + 1) - h00) * fz
	var h11 := _grid_height(a + 1, b + 1)
	return h11 + (_grid_height(a, b + 1) - h11) * (1.0 - fx) + (_grid_height(a + 1, b) - h11) * (1.0 - fz)


## 1 on open ground, 0 deep in high ground, the sea or a river; below 0.5
## cannot be walked on. Smooth, so its slope points back to open ground.
static func walk_at(x: float, z: float) -> float:
	var fx := (x - _x0) / _cell
	var fz := (z - _z0) / _cell
	var a := floori(fx)
	var b := floori(fz)
	fx -= a
	fz -= b
	var top := lerpf(_grid_walk(a, b), _grid_walk(a + 1, b), fx)
	var bottom := lerpf(_grid_walk(a, b + 1), _grid_walk(a + 1, b + 1), fx)
	return lerpf(top, bottom, fz)


static func walkable(x: float, z: float) -> bool:
	return walk_at(x, z) >= 0.5 and water_at(x, z) == null


## Which way open ground lies (a unit vector, x/z), or zero on flat ground.
static func walk_gradient(x: float, z: float) -> Vector2:
	var e := 1.0
	var g := Vector2(walk_at(x + e, z) - walk_at(x - e, z), walk_at(x, z + e) - walk_at(x, z - e))
	return g.normalized() if g.length() > 1e-5 else Vector2.ZERO


## The nearest sample's surface (MEADOW, BLACKWOOD, ...).
static func surface_at(x: float, z: float) -> int:
	var s := _sample(roundi((x - _x0) / _cell), roundi((z - _z0) / _cell))
	return s[2] & 15


## The nearest sample's zone, an index into world_map.json world.zones.
static func zone_index_at(x: float, z: float) -> int:
	var s := _sample(roundi((x - _x0) / _cell), roundi((z - _z0) / _cell))
	return s[2] >> 4


## Sample info for drawing: [height, walk 0..1, surface, zone] at grid (a, b).
static func grid(a: int, b: int) -> Array:
	var s := _sample(a, b)
	return [s[0], s[1] / 255.0, s[2] & 15, s[2] >> 4]


static func grid_origin() -> Vector2:
	return Vector2(_x0, _z0)


static func cell() -> float:
	return _cell


## How dark and close the woods are here: 1 in the Blackwood and haunted
## places, 0 in the open (eases over a few metres).
static func gloom(x: float, z: float) -> float:
	var k := 0.0
	for o in [Vector2(0, 0), Vector2(6, 0), Vector2(-6, 0), Vector2(0, 6), Vector2(0, -6)]:
		var s := surface_at(x + o.x, z + o.y)
		if s == BLACKWOOD or s == HAUNTED:
			k += 0.2
	return k


# ------------------------------------------------------------------ editing
## For the World editor's sculpt brushes: grid sample (a, b) as
## [height, walk 0..255, info], and setting one (every tile that shares it
## along an edge gets the change; open sea grows a tile).
static func sample(a: int, b: int) -> Array:
	return _sample(a, b)


static func set_sample(a: int, b: int, h: float, walk: int, info: int) -> Array:
	var touched := []
	for i: int in ([a / _tile - 1, a / _tile] if a % _tile == 0 else [floori(float(a) / _tile)]):
		for j: int in ([b / _tile - 1, b / _tile] if b % _tile == 0 else [floori(float(b) / _tile)]):
			if i < 0 or j < 0 or i >= _tx or j >= _tz:
				continue
			var t = _tile_at(i, j)
			if t == null:
				t = _new_tile()
				_tiles[j * 65536 + i] = t
			var k: int = (b - j * _tile) * N + (a - i * _tile)
			var hs: PackedFloat32Array = t[0]
			var ws: PackedByteArray = t[1]
			var fs: PackedByteArray = t[2]
			hs[k] = h
			ws[k] = clampi(walk, 0, 255)
			fs[k] = info
			t[0] = hs
			t[1] = ws
			t[2] = fs
			touched.append(Vector2i(i, j))
	return touched


static func _new_tile() -> Array:
	var h := PackedFloat32Array()
	h.resize(N * N)
	h.fill(_sea_floor)
	var w := PackedByteArray()
	w.resize(N * N)
	var f := PackedByteArray()
	f.resize(N * N)
	return [h, w, f]


## Write world.bin again with these tiles (Vector2i) packed from what is
## unpacked now; every other tile is copied as it was.
static func save_tiles(edited: Dictionary, to := "") -> Error:
	var live := to == "" or to == path()
	if to == "":
		to = path()
	var head := _file.slice(0, 36)
	var blobs := PackedByteArray()
	var index := PackedByteArray()
	index.resize(_tx * _tz * 8)
	var head_len := 36 + index.size()
	for j in _tz:
		for i in _tx:
			var k := j * _tx + i
			var blob := PackedByteArray()
			if edited.has(Vector2i(i, j)) and _tiles.get(j * 65536 + i) != null:
				blob = _pack(_tiles[j * 65536 + i])
			elif (_index[k] & 0xffffffff) > 0:
				blob = _file.slice(_index[k] >> 32, (_index[k] >> 32) + (_index[k] & 0xffffffff))
			if blob.size():
				index.encode_u32(k * 8, head_len + blobs.size())
				index.encode_u32(k * 8 + 4, blob.size())
				blobs.append_array(blob)
	var f := FileAccess.open(to, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	var out := head + index + blobs
	f.store_buffer(out)
	f.close()
	if live:
		_file = out
		for k in _tx * _tz:
			_index[k] = (_file.decode_u32(36 + k * 8) << 32) | _file.decode_u32(40 + k * 8)
	return OK


## One tile packed as bake_world.py packs it: heights in 5 cm steps as
## differences along x then along z, then walk and info bytes, zlib.
static func _pack(t: Array) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(N * N * 4)
	var q := PackedInt32Array()
	q.resize(N * N)
	for k in N * N:
		q[k] = clampi(roundi((t[0][k] + 50.0) * 20.0), 0, 65535)
	for b in N:
		for a in N:
			var dx: int = q[b * N + a] - (q[b * N + a - 1] if a > 0 else 0)
			var up: int = (q[(b - 1) * N + a] - (q[(b - 1) * N + a - 1] if a > 0 else 0)) if b > 0 else 0
			raw.encode_s16((b * N + a) * 2, dx - up)
	for k in N * N:
		raw[N * N * 2 + k] = t[1][k]
		raw[N * N * 3 + k] = t[2][k]
	return raw.compress(FileAccess.COMPRESSION_DEFLATE)


## Tile (i, j) as stored in world.bin, unpacked bytes (empty for open sea).
static func stored_tile(i: int, j: int) -> PackedByteArray:
	var e: int = _index[j * _tx + i]
	if (e & 0xffffffff) == 0:
		return PackedByteArray()
	return _file.slice(e >> 32, (e >> 32) + (e & 0xffffffff)).decompress(N * N * 4, FileAccess.COMPRESSION_DEFLATE)


## Forget every unpacked tile and read world.bin again (drops unsaved edits).
static func reload_tiles() -> void:
	_tiles.clear()
	_file = PackedByteArray()
	_pad_level.clear()
	_water_level.clear()
	_load_tiles()


# ------------------------------------------------------------------ roads
static func _dist_to_segment(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var len2 := dx * dx + dz * dz
	var t := clampf(((px - ax) * dx + (pz - az) * dz) / len2, 0.0, 1.0) if len2 > 0.0 else 0.0
	return Vector2(px - (ax + dx * t), pz - (az + dz * t)).length()


## Metres to the nearest road's surface edge (negative on the road), or 99
## when no road is near.
static func road_edge(x: float, z: float) -> float:
	var best := 99.0
	for seg in _road_cells.get(Vector2i(floori(x / ROAD_CELL), floori(z / ROAD_CELL)), []):
		best = minf(best, _dist_to_segment(x, z, seg[0], seg[1], seg[2], seg[3]) - seg[4])
	return best


## Metres to the nearest road's middle (as the old roads measured), at most 99.
static func distance_to_road(x: float, z: float) -> float:
	var best := 99.0
	for seg in _road_cells.get(Vector2i(floori(x / ROAD_CELL), floori(z / ROAD_CELL)), []):
		best = minf(best, _dist_to_segment(x, z, seg[0], seg[1], seg[2], seg[3]))
	return best


static func distance_to_main_road(x: float, z: float) -> float:
	return distance_to_road(x, z)


# ------------------------------------------------------------------ height
static func water_level(w: Dictionary) -> float:
	if not _water_level.has(w.id):
		if w.has("level"):
			_water_level[w.id] = w.level
		elif w.get("carved"):
			_water_level[w.id] = _lake_level(w.id, base_height(w.position[0], w.position[1]) + 2.4)
		else:
			_water_level[w.id] = base_height(w.position[0], w.position[1]) - 0.25
	return _water_level[w.id]


static func _lake_level(id: String, fallback: float) -> float:
	for l in DB.water.get("lakes", []):
		if l.id == id:
			return l.level
	return fallback


static func height_at(x: float, z: float) -> float:
	var h := base_height(x, z)
	for i in _pads.size():
		var p: Array = _pads[i]
		var d := Vector2(x - p[0], z - p[1]).length()
		if d > p[2] + 3.0:
			continue
		if not _pad_level.has(i):
			_pad_level[i] = base_height(p[0], p[1])
		h = lerpf(_pad_level[i], h, smoothstep(p[2], p[2] + 3.0, d))
	for w in _water:
		if w.get("carved"):
			continue # the land already dips under it
		var d := Vector2(x - w.position[0], z - w.position[1]).length()
		if d > w.radius + 1.0:
			continue
		var k := 1.0 - smoothstep(w.radius - 1.6, w.radius + 0.6, d)
		h = lerpf(h, water_level(w) - 1.1, k)
	return h


## The fishing water at a point, if any: a pond (a circle) or a lake (an
## ellipse, `rx` by `rz`).
static func water_at(x: float, z: float, margin := 0.0):
	for w in _water:
		var dx: float = x - w.position[0]
		var dz: float = z - w.position[1]
		if w.has("rx"):
			var rx: float = w.rx - margin
			var rz: float = w.rz - margin
			if rx > 0 and rz > 0 and (dx * dx) / (rx * rx) + (dz * dz) / (rz * rz) <= 1.0:
				return w
		elif Vector2(dx, dz).length() <= w.radius - margin:
			return w
	return null

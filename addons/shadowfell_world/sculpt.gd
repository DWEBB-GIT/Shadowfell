@tool
extends RefCounted
## The sculpt brushes' hand edits, kept as a layer on top of the baked ground:
## data/terrain/sculpt.json holds, per 128 m tile, 32 x 32 samples of height
## change (5 cm steps), a walk override (-1 none, 0 blocked .. 255 open) and a
## surface override (-1 none). Brushes change the unpacked terrain at once,
## so the ground redraws as you paint; saving writes sculpt.json and packs the
## edited tiles into world.bin, so the game needs no bake. bake_world.py puts
## sculpt.json back on top whenever the map is baked again.

## the sculpt layer of the map being edited (see Terrain.dir)
static func path() -> String:
	return Terrain.dir + "sculpt.json"
const T := 32 ## samples per tile side, as bake_world.py's TILE
const RATE := 6.0 ## metres a second the raise and lower brushes move at full strength

enum { OFF, RAISE, LOWER, SMOOTH, FLATTEN, OPEN, BLOCK, PAINT }
const MODES := ["Off", "Raise", "Lower", "Smooth", "Flatten", "Walkable", "Blocked", "Paint ground"]

var _layer := {} ## Vector2i tile -> {h: PackedFloat32Array (metres), w: PackedInt32Array, s: PackedInt32Array}
var _dirty := {} ## world.bin tiles changed since the last save
var _stroke := {} ## Vector2i sample -> its state before this stroke
var dirty := false


func _init() -> void:
	load_layer()


func load_layer() -> void:
	_layer.clear()
	_dirty.clear()
	dirty = false
	if not FileAccess.file_exists(path()):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path()))
	if typeof(d) != TYPE_DICTIONARY:
		push_error("Sculpt: cannot read %s" % path())
		return
	for key in d.tiles:
		var ij: PackedStringArray = key.split(",")
		var t: Dictionary = d.tiles[key]
		var h := PackedFloat32Array()
		h.resize(T * T)
		var raw := _unpack(t.h)
		for k in T * T:
			h[k] = raw.decode_s16(k * 2) * 0.05
		_layer[Vector2i(int(ij[0]), int(ij[1]))] = {"h": h, "w": _ints(_unpack(t.w)), "s": _ints(_unpack(t.s))}


static func _unpack(b64: String) -> PackedByteArray:
	return Marshalls.base64_to_raw(b64).decompress(T * T * 2, FileAccess.COMPRESSION_DEFLATE)


static func _ints(raw: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(T * T)
	for k in T * T:
		out[k] = raw.decode_s16(k * 2)
	return out


static func _pack(values) -> String:
	var raw := PackedByteArray()
	raw.resize(T * T * 2)
	for k in T * T:
		raw.encode_s16(k * 2, values[k])
	return Marshalls.raw_to_base64(raw.compress(FileAccess.COMPRESSION_DEFLATE))


func _cell(a: int, b: int) -> Dictionary:
	var key := Vector2i(floori(float(a) / T), floori(float(b) / T))
	if not _layer.has(key):
		var h := PackedFloat32Array()
		h.resize(T * T)
		var w := PackedInt32Array()
		w.resize(T * T)
		w.fill(-1)
		var s := PackedInt32Array()
		s.resize(T * T)
		s.fill(-1)
		_layer[key] = {"h": h, "w": w, "s": s}
	return _layer[key]


static func _k(a: int, b: int) -> int:
	return posmod(b, T) * T + posmod(a, T)


## The ground under the mouse: where a ray from the camera first meets it.
static func ray_hit(from: Vector3, dir: Vector3):
	var t := 0.0
	var last := 0.0
	while t < 4000.0:
		var p := from + dir * t
		if p.y <= Terrain.height_at(p.x, p.z):
			var lo := last
			var hi := t
			for i in 12:
				var mid := (lo + hi) * 0.5
				var q := from + dir * mid
				if q.y <= Terrain.height_at(q.x, q.z):
					hi = mid
				else:
					lo = mid
			return from + dir * hi
		last = t
		t += clampf(t * 0.01, 0.5, 8.0)
	return null


func begin_stroke() -> void:
	_stroke = {}


## One brush step at (x, z): radius in metres, strength 0..1, dt seconds.
## `target` is the flatten height, `surface` the ground to paint. Returns
## the 64 m ground chunks to draw again.
func apply(mode: int, x: float, z: float, radius: float, strength: float, dt: float, target := 0.0, surface := 1) -> Dictionary:
	var o := Terrain.grid_origin()
	var c := Terrain.cell()
	var a0 := floori((x - radius - o.x) / c)
	var a1 := ceili((x + radius - o.x) / c)
	var b0 := floori((z - radius - o.y) / c)
	var b1 := ceili((z + radius - o.y) / c)
	var before := {}
	if mode == SMOOTH:
		for b in range(b0 - 1, b1 + 2):
			for a in range(a0 - 1, a1 + 2):
				before[Vector2i(a, b)] = Terrain.sample(a, b)[0]
	var chunks := {}
	for b in range(b0, b1 + 1):
		for a in range(a0, a1 + 1):
			var sx := o.x + a * c
			var sz := o.y + b * c
			var d := Vector2(sx - x, sz - z).length()
			if d > radius:
				continue
			var f := 1.0 - smoothstep(0.0, 1.0, d / radius)
			var s := Terrain.sample(a, b)
			var h: float = s[0]
			var walk: int = s[1]
			var info: int = s[2]
			var layer := _cell(a, b)
			var k := _k(a, b)
			var key := Vector2i(a, b)
			if not _stroke.has(key):
				_stroke[key] = [h, walk, info, layer.h[k], layer.w[k], layer.s[k]]
			var nh := h
			match mode:
				RAISE:
					nh = h + RATE * strength * f * dt
				LOWER:
					nh = h - RATE * strength * f * dt
				SMOOTH:
					var avg := 0.0
					for v in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
						avg += before[key + v]
					nh = lerpf(h, avg / 8.0, clampf(f * strength * dt * 8.0, 0.0, 1.0))
				FLATTEN:
					nh = lerpf(h, target, clampf(f * strength * dt * 8.0, 0.0, 1.0))
				OPEN:
					walk = maxi(walk, roundi(255 * clampf(f * 1.6, 0.0, 1.0)))
					layer.w[k] = walk
				BLOCK:
					walk = mini(walk, roundi(255 * (1.0 - clampf(f * 1.6, 0.0, 1.0))))
					layer.w[k] = walk
				PAINT:
					if f > 0.3:
						info = (info & 0xf0) | (surface & 15)
						layer.s[k] = surface & 15
			layer.h[k] += nh - h
			for t in Terrain.set_sample(a, b, nh, walk, info):
				_dirty[t] = true
			chunks[Vector2i(floori(sx / Land.CHUNK), floori(sz / Land.CHUNK))] = true
			# a sample on a chunk's edge is drawn by its neighbours too
			chunks[Vector2i(floori((sx - 1) / Land.CHUNK), floori((sz - 1) / Land.CHUNK))] = true
	dirty = true
	return chunks


## The stroke just finished, as [before, after] for undo and redo.
func end_stroke() -> Array:
	var before := _stroke
	var after := {}
	for key in before:
		var s: Array = Terrain.sample(key.x, key.y)
		var layer: Dictionary = _cell(key.x, key.y)
		var k: int = _k(key.x, key.y)
		after[key] = [s[0], s[1], s[2], layer.h[k], layer.w[k], layer.s[k]]
	_stroke = {}
	return [before, after]


## Put samples back as a stroke's before or after recorded them.
func restore(state: Dictionary) -> Dictionary:
	var chunks := {}
	var o := Terrain.grid_origin()
	var c := Terrain.cell()
	for key in state:
		var v: Array = state[key]
		var layer: Dictionary = _cell(key.x, key.y)
		var k: int = _k(key.x, key.y)
		layer.h[k] = v[3]
		layer.w[k] = v[4]
		layer.s[k] = v[5]
		for t in Terrain.set_sample(key.x, key.y, v[0], v[1], v[2]):
			_dirty[t] = true
		var sx: float = o.x + key.x * c
		var sz: float = o.y + key.y * c
		chunks[Vector2i(floori(sx / Land.CHUNK), floori(sz / Land.CHUNK))] = true
		chunks[Vector2i(floori((sx - 1) / Land.CHUNK), floori((sz - 1) / Land.CHUNK))] = true
	dirty = true
	return chunks


## Write sculpt.json and the edited tiles into world.bin.
func save() -> Error:
	if not dirty:
		return OK
	var o := Terrain.grid_origin()
	var tiles := {}
	var keys := _layer.keys()
	keys.sort()
	for key in keys:
		var t: Dictionary = _layer[key]
		var hq := PackedInt32Array()
		hq.resize(T * T)
		var used := false
		for k in T * T:
			hq[k] = roundi(t.h[k] * 20.0)
			used = used or hq[k] != 0 or t.w[k] >= 0 or t.s[k] >= 0
		if used:
			tiles["%d,%d" % [key.x, key.y]] = {"h": _pack(hq), "w": _pack(t.w), "s": _pack(t.s)}
	var d := {
		"_about": "Hand edits from the World editor's sculpt brushes, on top of the baked ground (see addons/shadowfell_world/sculpt.gd). Per 128 m tile 'i,j': 32 x 32 samples, base64 zlib int16: h = height change in 5 cm steps, w = walk override (-1 none, 0 blocked .. 255 open), s = surface override (-1 none). bake_world.py applies it after baking.",
		"version": 1, "x0": o.x, "z0": o.y, "cell": Terrain.cell(), "tiles": tiles,
	}
	var f := FileAccess.open(path(), FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(d, "  ", false) + "\n")
	f.close()
	var err := Terrain.save_tiles(_dirty)
	if err == OK:
		_dirty.clear()
		dirty = false
	return err

@tool
extends RefCounted
## Sparse, editable paint on the shared half-metre road grid. RGB is
## premultiplied dirt, cobbles, and coverage over the baked pigments.

const Land := preload("res://game/world/lantern_coast/land.gd")
const TARGETS := [Color(1, 0, 1), Color(1, 1, 1), Color(0, 0, 1)]
const BORDER := 2
const BORDER_METRES := BORDER / Land.PATH_PIXELS_PER_METRE

var land: Node3D
var radius: float
var _colour: Color
var _at: Vector2
var _tiles := {}
var _dirty := {}
var _coverage := {}
var _strength: float


func _init(terrain: Node3D, mode: int, width: float, start: Vector2, strength := 1.0) -> void:
	land = terrain
	radius = width * 0.5
	_colour = TARGETS[mode - 1]
	_strength = clampf(strength, 0.0, 1.0)
	_at = start
	_stamp(start)


func move_to(at: Vector2) -> void:
	var distance := _at.distance_to(at)
	if distance < .03:
		return
	# A jump over water, or a camera jump across the map, starts a fresh mark.
	if distance > 80.0:
		_at = at
		_stamp(at)
		return
	var steps := ceili(distance / maxf(.30, radius * .45))
	for i in range(1, steps + 1):
		_stamp(_at.lerp(at, float(i) / steps))
	_at = at


func preview() -> void:
	for key in _dirty:
		land.preview_path_tile(key, _tiles[key])
	_dirty.clear()


func states(current: Dictionary) -> Array[Dictionary]:
	var before := {}
	var after := {}
	for key in _tiles:
		var image: Image = _tiles[key]
		var compressed := image.get_data().compress(FileAccess.COMPRESSION_DEFLATE)
		var encoded := Marshalls.raw_to_base64(compressed)
		if encoded != current.get(key, ""):
			before[key] = current.get(key, "")
			after[key] = encoded
	return [before, after]


func _stamp(at: Vector2) -> void:
	var pad := Vector2.ONE * (radius + BORDER_METRES)
	var low := Vector2i(((at - pad) / Land.CELL_SIZE).floor())
	var high := Vector2i(((at + pad) / Land.CELL_SIZE).floor())
	for z in range(low.y, high.y + 1):
		for x in range(low.x, high.x + 1):
			var key := Vector2i(x, z)
			if land.has_cell(key):
				_paint_tile(key, at)


func _paint_tile(key: Vector2i, at: Vector2) -> void:
	var center := (at - Vector2(key) * Land.CELL_SIZE) * Land.PATH_PIXELS_PER_METRE + Vector2.ONE * BORDER
	var extent := radius * Land.PATH_PIXELS_PER_METRE
	var from := (center - Vector2.ONE * extent).ceil().max(Vector2.ZERO)
	var to := (center + Vector2.ONE * extent).floor().min(Vector2.ONE * (Land.ROAD_SIDE - 1))
	if from.x > to.x or from.y > to.y:
		return
	if not _tiles.has(key):
		var prior: Image = land.path_tile(key)
		_tiles[key] = prior.duplicate() if prior != null else Image.create_empty(Land.ROAD_SIDE, Land.ROAD_SIDE, false, Image.FORMAT_RGB8)
		_coverage[key] = Image.create_empty(Land.ROAD_SIDE, Land.ROAD_SIDE, false, Image.FORMAT_L8)
	var image: Image = _tiles[key]
	var coverage: Image = _coverage[key]
	var previous: Image = land.path_tile(key)
	_dirty[key] = true
	for y in range(int(from.y), int(to.y) + 1):
		for x in range(int(from.x), int(to.x) + 1):
			# A single stroke has a consistent opacity even if stamps overlap.
			var weight := _strength * (1.0 - smoothstep(extent * .61, extent, center.distance_to(Vector2(x, y))))
			if weight > coverage.get_pixel(x, y).r:
				coverage.set_pixel(x, y, Color(weight, 0, 0))
				var base := previous.get_pixel(x, y) if previous != null else Color.BLACK
				image.set_pixel(x, y, base.lerp(_colour, weight))

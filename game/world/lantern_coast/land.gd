@tool
extends Node3D
## Loads only nearby 64 m cells. All cells share a sampling grid and UV padding.

const CELL_SIZE := 64.0
const STEP := 2.0
const CLIFF_GRADE := 0.78
const INTERVALS := 32
const SIDE := 35
const HEIGHT_BYTES := SIDE * SIDE * 2
const PAVING_OFFSET := SIDE * SIDE * 6
const ROAD_OFFSET := SIDE * SIDE * 7
const ROAD_SIDE := 133
const PATH_PIXELS_PER_METRE := 2.0
const RAW_BYTES := ROAD_OFFSET + ROAD_SIDE * ROAD_SIDE
const ACTIVE_RADIUS := 49.0
const VIEW_RADIUS := 128.0
const KEEP_RADIUS := 150.0
const FALLBACK_HEIGHT := -5.0
const MATERIAL := preload("surface.gdshader")
const GROUND := preload("ground_detail.png")
const ROCK := preload("rock_detail.png")
const BRUSHWORK := preload("biome_brushwork.png")
const BANK_DETAIL := preload("bank_detail.png")
const COVER := preload("cover.gd")
const DIRECTORY := "res://game/world/lantern_coast/terrain/"

var _regions: Dictionary
var _packs := {}
var _samples := {}
var chunks := {}
var _path_tiles: Dictionary
var _path_cache := {}
var editor_placement_collision := false
static var _no_paving: Texture2D
static var _cobbles: Texture2D
static var _accents: Texture2D


func configure(regions: Dictionary, path_tiles: Dictionary = {}) -> void:
	_regions = regions
	_path_tiles = path_tiles.duplicate()


func stream_near(focus: Vector3, immediate := false) -> void:
	var p := Vector2(focus.x, focus.z)
	var centre := _cell_key(p)
	var candidates: Array[Vector2i] = []
	var loaded_packs := {}
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var key := centre + Vector2i(dx, dz)
			if not _regions.has(Vector2(key)):
				continue
			var distance := _distance_to_cell(p, key)
			if distance <= VIEW_RADIUS and not chunks.has(key):
				candidates.append(key)
			if distance <= KEEP_RADIUS:
				loaded_packs[_regions[Vector2(key)]] = true
	candidates.sort_custom(func(a, b): return _distance_to_cell(p, a) < _distance_to_cell(p, b))
	for key in candidates:
		var distance := _distance_to_cell(p, key)
		if immediate and distance > ACTIVE_RADIUS:
			break
		var node := _build_cell(key, not Engine.is_editor_hint() or editor_placement_collision)
		if node:
			chunks[key] = node
			add_child(node)
		if not immediate:
			break

	for key in chunks.keys():
		if _distance_to_cell(p, key) > KEEP_RADIUS:
			chunks[key].queue_free()
			chunks.erase(key)
	for key in _samples.keys():
		if _distance_to_cell(p, key) > KEEP_RADIUS:
			_samples.erase(key)
	for key in _path_cache.keys():
		if _distance_to_cell(p, key) > KEEP_RADIUS:
			_path_cache.erase(key)
	for pack in _packs.keys():
		if not loaded_packs.has(pack):
			_packs.erase(pack)


func floor_height(p: Vector2) -> float:
	return floor_sample(p).x


## Height and rise/run of the exact mesh triangle under the point.
func floor_sample(p: Vector2) -> Vector2:
	var key := _cell_key(p)
	var raw := _cell_data(key)
	if raw.is_empty():
		return Vector2(FALLBACK_HEIGHT, 0.0)
	var local := (p - Vector2(key) * CELL_SIZE) / STEP
	var x := clampi(floori(local.x), 0, INTERVALS - 1)
	var z := clampi(floori(local.y), 0, INTERVALS - 1)
	var uv := local - Vector2(x, z)
	var a := _height(raw, x, z)
	var b := _height(raw, x + 1, z)
	var c := _height(raw, x, z + 1)
	if uv.x + uv.y <= 1.0:
		return Vector2(a + (b - a) * uv.x + (c - a) * uv.y, Vector2(b - a, c - a).length() / STEP)
	var d := _height(raw, x + 1, z + 1)
	return Vector2(d + (b - d) * (1.0 - uv.y) + (c - d) * (1.0 - uv.x), Vector2(c - d, b - d).length() / STEP)


func colour_at(p: Vector2):
	var key := _cell_key(p)
	var raw := _cell_data(key)
	if raw.is_empty():
		return null
	var local := (p - Vector2(key) * CELL_SIZE) / STEP
	var index := (roundi(local.y) + 1) * SIDE + roundi(local.x) + 1
	var i := HEIGHT_BYTES + index * 4
	return Color8(raw[i], raw[i + 1], raw[i + 2])


func road_at(p: Vector2, baked := false) -> float:
	var key := _cell_key(p)
	var raw := _cell_data(key)
	if raw.is_empty():
		return 0.0
	var local := (p - Vector2(key) * CELL_SIZE) / STEP
	var index := (roundi(local.y) + 1) * SIDE + roundi(local.x) + 1
	var base := raw[HEIGHT_BYTES + index * 4 + 3] / 255.0
	if baked:
		return base
	var edit := _path_at(key, local)
	if edit.b > 0.0 and raw.size() == RAW_BYTES:
		var fine := Vector2i((local * 4.0 + Vector2(2, 2)).round())
		base = raw[ROAD_OFFSET + fine.y * ROAD_SIDE + fine.x] / 255.0
	return base * (1.0 - edit.b) + edit.r


func paving_at(p: Vector2, baked := false) -> float:
	var key := _cell_key(p)
	var raw := _cell_data(key)
	if raw.is_empty():
		return 0.0
	var local := (p - Vector2(key) * CELL_SIZE) / STEP
	var index := (roundi(local.y) + 1) * SIDE + roundi(local.x) + 1
	var base := raw[PAVING_OFFSET + index] / 255.0 if raw.size() >= ROAD_OFFSET else 0.0
	if baked:
		return base
	var edit := _path_at(key, local)
	return base * (1.0 - edit.b) + edit.g


func _path_at(key: Vector2i, local: Vector2) -> Color:
	var image := path_tile(key)
	return image.get_pixelv(Vector2i((local * 4.0 + Vector2(2, 2)).round())) if image != null else Color.BLACK


func has_cell(key: Vector2i) -> bool:
	return _regions.has(Vector2(key))


func path_tile(key: Vector2i) -> Image:
	if not _path_tiles.has(key):
		return null
	if not _path_cache.has(key):
		var encoded := Marshalls.base64_to_raw(str(_path_tiles[key]))
		var pixels := encoded.decompress(ROAD_SIDE * ROAD_SIDE * 3, FileAccess.COMPRESSION_DEFLATE)
		if pixels.size() != ROAD_SIDE * ROAD_SIDE * 3:
			return null
		_path_cache[key] = Image.create_from_data(ROAD_SIDE, ROAD_SIDE, false, Image.FORMAT_RGB8, pixels)
	return _path_cache[key]


## Show the stroke without recreating terrain geometry while the mouse is down.
func preview_path_tile(key: Vector2i, image: Image) -> void:
	if chunks.has(key):
		_set_path_material(chunks[key].material_override, image)


func apply_path_tiles(changes: Dictionary) -> void:
	for key in changes:
		if changes[key].is_empty():
			_path_tiles.erase(key)
		else:
			_path_tiles[key] = changes[key]
		_path_cache.erase(key)
		if chunks.has(key):
			var old: MeshInstance3D = chunks[key]
			var cell := _build_cell(key, editor_placement_collision)
			remove_child(old)
			old.queue_free()
			chunks[key] = cell
			add_child(cell)


static func _set_path_material(material: ShaderMaterial, image: Image) -> void:
	material.set_shader_parameter("has_path_edits", image != null)
	if image == null:
		return
	var texture := material.get_shader_parameter("path_edits") as ImageTexture
	if texture == null:
		texture = ImageTexture.create_from_image(image)
		material.set_shader_parameter("path_edits", texture)
	else:
		texture.update(image)


func _cell_key(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL_SIZE), floori(p.y / CELL_SIZE))


func _distance_to_cell(p: Vector2, key: Vector2i) -> float:
	var lo := Vector2(key) * CELL_SIZE
	var hi := lo + Vector2.ONE * CELL_SIZE
	return p.distance_to(p.clamp(lo, hi))


func _cell_data(key: Vector2i) -> PackedByteArray:
	if _samples.has(key):
		return _samples[key]
	var index := Vector2(key)
	if not _regions.has(index):
		return PackedByteArray()
	var pack: String = _regions[index]
	if not _packs.has(pack):
		var resource := ResourceLoader.load(DIRECTORY + pack + ".tres")
		if not resource:
			return PackedByteArray()
		_packs[pack] = resource.get_meta("cells")
	var encoded: PackedByteArray = _packs[pack].get(index, PackedByteArray())
	if encoded.is_empty():
		return encoded
	var raw := encoded.decompress(RAW_BYTES, FileAccess.COMPRESSION_DEFLATE)
	if raw.size() not in [PAVING_OFFSET, ROAD_OFFSET, RAW_BYTES]:
		push_error("Lantern Coast terrain cell %s has invalid sample data." % key)
		return PackedByteArray()
	_samples[key] = raw
	return raw


func _height(raw: PackedByteArray, x: int, z: int) -> float:
	return raw.decode_s16(((z + 1) * SIDE + x + 1) * 2) * 0.01


func _build_cell(key: Vector2i, physical: bool) -> MeshInstance3D:
	var raw := _cell_data(key)
	if raw.is_empty():
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var triangles := PackedInt32Array()
	var steep := false
	var width := INTERVALS + 1
	for z in width:
		for x in width:
			vertices.append(Vector3(x * STEP, _height(raw, x, z), z * STEP))
			var dx := _height(raw, x - 1, z) - _height(raw, x + 1, z)
			var dz := _height(raw, x, z - 1) - _height(raw, x, z + 1)
			var normal := Vector3(dx, STEP * 2.0, dz).normalized()
			normals.append(normal)
			steep = steep or normal.y < 0.82
			uvs.append(Vector2(x + 1.5, z + 1.5) / float(SIDE))
	triangles = _indices(INTERVALS)
	var mesh_data := []
	mesh_data.resize(Mesh.ARRAY_MAX)
	mesh_data[Mesh.ARRAY_VERTEX] = vertices
	mesh_data[Mesh.ARRAY_NORMAL] = normals
	mesh_data[Mesh.ARRAY_TEX_UV] = uvs
	mesh_data[Mesh.ARRAY_INDEX] = triangles
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_data)

	var material := ShaderMaterial.new()
	material.shader = MATERIAL
	var paint := Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_RGBA8, raw.slice(HEIGHT_BYTES, PAVING_OFFSET))
	material.set_shader_parameter("terrain_control", ImageTexture.create_from_image(paint))
	if _no_paving == null:
		var blank := Image.create_empty(1, 1, false, Image.FORMAT_L8)
		blank.fill(Color.BLACK)
		_no_paving = ImageTexture.create_from_image(blank)
	var paving := _no_paving
	var paving_mask: Image
	if raw.size() >= ROAD_OFFSET:
		paving_mask = Image.create_from_data(SIDE, SIDE, false, Image.FORMAT_L8, raw.slice(PAVING_OFFSET, ROAD_OFFSET))
		paving = ImageTexture.create_from_image(paving_mask)
	material.set_shader_parameter("paving_control", paving)
	var road: Image
	if raw.size() == RAW_BYTES:
		road = Image.create_from_data(ROAD_SIDE, ROAD_SIDE, false, Image.FORMAT_L8, raw.slice(ROAD_OFFSET))
		material.set_shader_parameter("road_control", ImageTexture.create_from_image(road))
		material.set_shader_parameter("fine_roads", true)
	if _cobbles == null:
		_cobbles = load("res://game/world/lantern_coast/cobble_detail.png")
	material.set_shader_parameter("cobble_detail", _cobbles)
	if _accents == null:
		_accents = load("res://game/world/lantern_coast/terrain_accents.png")
	material.set_shader_parameter("terrain_accents", _accents)
	material.set_shader_parameter("biome_brushwork", BRUSHWORK)
	material.set_shader_parameter("bank_detail", BANK_DETAIL)
	material.set_shader_parameter("ground_detail", GROUND)
	material.set_shader_parameter("cliff_detail", ROCK)
	material.set_shader_parameter("cliff_normal_y", 1.0 / sqrt(1.0 + CLIFF_GRADE * CLIFF_GRADE))
	var path := path_tile(key)
	_set_path_material(material, path)
	var cell := MeshInstance3D.new()
	cell.name = "Cell_%d_%d" % [key.x, key.y]
	cell.position = Vector3(key.x * CELL_SIZE, 0.0, key.y * CELL_SIZE)
	# The controller and ray picks retain the original height grid. A
	# subdivided visual mesh gives banks and shoreline a softer profile.
	cell.mesh = _visual_mesh(raw) if steep and not Engine.is_editor_hint() else mesh
	cell.material_override = material
	COVER.dress(cell, key, vertices, normals, paint, road, paving_mask, CLIFF_GRADE, path)
	if physical:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		body.add_child(shape)
		cell.add_child(body)
	return cell


static var _index_cache := {}


static func _indices(count: int) -> PackedInt32Array:
	if _index_cache.has(count):
		return _index_cache[count]
	var indices := PackedInt32Array()
	var width := count + 1
	for z in count:
		for x in count:
			var a := z * width + x
			indices.append(a)
			indices.append(a + 1)
			indices.append(a + width)
			indices.append(a + 1)
			indices.append(a + width + 1)
			indices.append(a + width)
	_index_cache[count] = indices
	return indices


func _visual_mesh(raw: PackedByteArray) -> ArrayMesh:
	var count := INTERVALS * 2
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	for row in count + 1:
		for column in count + 1:
			var x := column * 0.5
			var z := row * 0.5
			var a := mini(floori(x), INTERVALS - 1)
			var b := mini(floori(z), INTERVALS - 1)
			var u := x - a
			var v := z - b
			var y00 := _height(raw, a, b)
			var y10 := _height(raw, a + 1, b)
			var y01 := _height(raw, a, b + 1)
			var y11 := _height(raw, a + 1, b + 1)
			var original := y00 + (y10-y00)*u + (y01-y00)*v if u+v <= 1 else y11 + (y01-y11)*(1-u) + (y10-y11)*(1-v)
			var softened := lerpf(lerpf(y00, y10, u), lerpf(y01, y11, u), v)
			var y := original + clampf(softened - original, -0.23, 0.23)
			vertices.append(Vector3(x * STEP, y, z * STEP))
			# Interpolate the same shared normals across each metre subcell.
			var dx := lerpf(_height(raw, a - 1, b) - y10, y00 - _height(raw, a + 2, b), u)
			dx = lerpf(dx, lerpf(_height(raw, a - 1, b + 1) - y11, y01 - _height(raw, a + 2, b + 1), u), v)
			var dz := lerpf(_height(raw, a, b - 1) - y01, y00 - _height(raw, a, b + 2), v)
			dz = lerpf(dz, lerpf(_height(raw, a + 1, b - 1) - y11, y10 - _height(raw, a + 1, b + 2), v), u)
			normals.append(Vector3(dx, STEP * 2.0, dz).normalized())
			uvs.append(Vector2(x + 1.5, z + 1.5) / float(SIDE))
	var data := []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_NORMAL] = normals
	data[Mesh.ARRAY_TEX_UV] = uvs
	data[Mesh.ARRAY_INDEX] = _indices(count)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	return mesh

class_name Land
extends RefCounted
## The ground, woodland, grass and water near the camera, built in 64 m
## chunks as they come into range and freed when they fall far behind, so
## only what this player can see is ever drawn (a 5 x 7.7 km world costs the
## same as a small one). What a chunk holds is worked out from the terrain
## data alone, the same every time, so a server or another player's client
## would place the same trees (Collision registers the solid ones from
## chunk_trees() wherever anything moves, drawn or not).

const CUTAWAY := preload("res://game/render/cutaway.gdshader")
const CHUNK := 64.0
const RADIUS := 112.0 ## metres around the camera's focus that are drawn
const KEEP := 176.0 ## chunks further than this are freed
const BUDGET_MS := 5.0 ## chunk building per frame, once playing

## ground colours by surface (sRGB), [open ground, high ground]
const GROUND := {
	Terrain.SEA: ["3a4a44", "3a4a44"], Terrain.MEADOW: ["44552e", "34422a"],
	Terrain.MARSH: ["3a4630", "2f3a2a"], Terrain.DOWNS: ["5d6640", "4e5638"],
	Terrain.BLACKWOOD: ["1f2419", "1a2016"], Terrain.ROCK: ["5a5650", "4e4a46"],
	Terrain.MOOR: ["4a4038", "3e3630"], Terrain.SAND: ["9a8c64", "807458"],
	Terrain.FARMLAND: ["4e5230", "40462a"], Terrain.FOREST: ["2e3c24", "26321e"],
	Terrain.SNOW: ["c8ccd0", "b4b8bc"], Terrain.DESERT: ["9a7a4e", "86683f"],
	Terrain.ASH: ["3a302c", "2e2624"], Terrain.SWAMP: ["2e3628", "262e22"],
	Terrain.JUNGLE: ["2a4a22", "223e1c"], Terrain.HAUNTED: ["2a2830", "222028"],
}
## trees per 4 m square by surface: [on open ground, on high ground], and
## the models they are drawn from
const WOODS := {
	Terrain.MEADOW: [0.012, 0.6, ["pine"]], Terrain.MARSH: [0.01, 0.16, ["dead_tree", "pine"]],
	Terrain.DOWNS: [0.006, 0.12, ["pine"]], Terrain.BLACKWOOD: [0.06, 0.8, ["black_pine", "black_pine", "dead_tree"]],
	Terrain.ROCK: [0.002, 0.03, ["dead_tree"]], Terrain.MOOR: [0.004, 0.05, ["dead_tree"]],
	Terrain.FARMLAND: [0.01, 0.3, ["pine"]], Terrain.FOREST: [0.07, 0.75, ["pine", "pine", "black_pine"]],
	Terrain.SNOW: [0.0, 0.03, ["pine"]], Terrain.ASH: [0.0, 0.02, ["dead_tree"]],
	Terrain.SWAMP: [0.03, 0.4, ["dead_tree", "black_pine"]], Terrain.JUNGLE: [0.08, 0.8, ["pine", "black_pine"]],
	Terrain.HAUNTED: [0.05, 0.6, ["dead_tree", "black_pine"]],
}
## rocks per 4 m square of high ground
const ROCKS := {Terrain.ROCK: 0.16, Terrain.SNOW: 0.1, Terrain.MOOR: 0.06, Terrain.ASH: 0.12, Terrain.DOWNS: 0.03, Terrain.DESERT: 0.06}
const GRASSY := [Terrain.MEADOW, Terrain.FARMLAND, Terrain.DOWNS, Terrain.FOREST, Terrain.BLACKWOOD, Terrain.MARSH, Terrain.MOOR, Terrain.JUNGLE, Terrain.SWAMP]

var game
var group: Node3D
var chunks := {} ## Vector2i -> Node3D
var focus := Vector3.ZERO
var built := 0 ## chunks built so far (for the perf tools)
var _ground_mat: StandardMaterial3D
var _sea_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _blade: ArrayMesh
var _models := {} ## model -> [mesh, cutaway material]
var _cutaways: Array = []
static var _clear_cells := {} ## 32 m cell -> [[x, z, r]]: ground kept free of trees


func _init(g, parent: Node3D) -> void:
	game = g
	group = Node3D.new()
	group.name = "Land"
	parent.add_child(group)
	_ground_mat = ground_material()
	_sea_mat = StandardMaterial3D.new()
	_sea_mat.albedo_color = Color(Color.hex(0x22404aff), 0.9)
	_sea_mat.emission_enabled = true
	_sea_mat.emission = Color.hex(0x0a1618ff)
	_sea_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_sea_mat.roughness = 0.4
	_grass_mat = StandardMaterial3D.new()
	_grass_mat.albedo_color = Color("4a5a32")
	_grass_mat.vertex_color_use_as_albedo = true
	_grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_grass_mat.roughness = 1.0
	_blade = _grass_blade()
	index_clearings()
	_build_rivers_and_lakes()


static func ground_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = Tex.ground_detail()
	mat.roughness = 1.0
	return mat


# ------------------------------------------------------------- streaming
## Build the chunks around `at` that are missing (nearest first, within a
## time budget unless `all`) and free the far ones.
func update(at: Vector3, all := false) -> void:
	focus = at
	var c := Vector2i(floori(at.x / CHUNK), floori(at.z / CHUNK))
	# arriving somewhere new (loading in, a portal, a boat): build it all now
	all = all or not chunks.has(c)
	var reach := int(ceil(RADIUS / CHUNK)) + 1
	var want := []
	for i in range(c.x - reach, c.x + reach + 1):
		for j in range(c.y - reach, c.y + reach + 1):
			var k := Vector2i(i, j)
			if chunks.has(k):
				continue
			var d := _chunk_distance(k, at)
			if d <= RADIUS:
				want.append([d, k])
	want.sort_custom(func(a, b): return a[0] < b[0])
	var t0 := Time.get_ticks_usec()
	for w in want:
		chunks[w[1]] = _build_chunk(w[1])
		if not all and (Time.get_ticks_usec() - t0) / 1000.0 > BUDGET_MS:
			break
	for k in chunks.keys():
		if _chunk_distance(k, at) > KEEP:
			chunks[k].queue_free()
			chunks.erase(k)


static func _chunk_distance(k: Vector2i, at: Vector3) -> float:
	var cx := clampf(at.x, k.x * CHUNK, (k.x + 1) * CHUNK)
	var cz := clampf(at.z, k.y * CHUNK, (k.y + 1) * CHUNK)
	return Vector2(at.x - cx, at.z - cz).length()


func _build_chunk(k: Vector2i) -> Node3D:
	var n := Node3D.new()
	n.name = "Chunk_%d_%d" % [k.x, k.y]
	group.add_child(n)
	var ground := chunk_ground(k, _ground_mat)
	n.add_child(ground)
	if ground.get_meta("sea", false):
		var sea := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(CHUNK, CHUNK)
		sea.mesh = pm
		sea.material_override = _sea_mat
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sea.position = Vector3((k.x + 0.5) * CHUNK, DB.water.get("sea", 0.0), (k.y + 0.5) * CHUNK)
		n.add_child(sea)
	var trees := chunk_trees(k)
	_plant(n, trees + chunk_rocks(k))
	var shaft := World.sun_shaft(k, trees)
	if shaft:
		n.add_child(shaft)
	_grass(n, k)
	built += 1
	return n


# ------------------------------------------------------------- the ground
## One chunk of ground: 4 m squares (2 m where buildings or ponds need the
## detail), flat shaded, coloured by surface, roads and high ground.
static func chunk_ground(k: Vector2i, mat: Material) -> MeshInstance3D:
	var x0 := k.x * CHUNK
	var z0 := k.y * CHUNK
	var step := 2.0 if _needs_detail(x0, z0) else Terrain.cell()
	var n := int(CHUNK / step)
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	pos.resize((n + 1) * (n + 1))
	cols.resize((n + 1) * (n + 1))
	var sea := false
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(k)
	var road_col := Color("6a5c48")
	var rock_col := Color("5a5650")
	var snow_col := Color("c8ccd0")
	var o := Terrain.grid_origin()
	for j in n + 1:
		for i in n + 1:
			var x := x0 + i * step
			var z := z0 + j * step
			var h := Terrain.height_at(x, z)
			pos[j * (n + 1) + i] = Vector3(x, h, z)
			if h < 0.3:
				sea = true
			var g := Terrain.grid(roundi((x - o.x) / Terrain.cell()), roundi((z - o.y) / Terrain.cell()))
			var slope := absf(Terrain.base_height(x + 2, z) - Terrain.base_height(x - 2, z)) + absf(Terrain.base_height(x, z + 2) - Terrain.base_height(x, z - 2))
			var painted = Terrain.ground_colour(x, z)
			var c: Color
			if painted != null:
				# the new map: Dan's painted ground, darker where it cannot be walked
				# and on steep sides, so open ground still reads at a glance
				c = (painted as Color).lerp((painted as Color).darkened(0.18), clampf(1.4 - g[1] * 2.0, 0.0, 1.0))
				c = c.lerp(c.darkened(0.1), rand.randf() * 0.5)
				c = c.darkened(clampf((slope - 2.5) / 12.0, 0.0, 0.2))
			else:
				var pal: Array = GROUND.get(g[2], GROUND[Terrain.MEADOW])
				# open ground a shade lighter, high ground darker: where you can walk
				# reads at a glance from the iso camera (Dan's readability rule)
				c = Color(pal[0]).lightened(0.07).lerp(Color(pal[1]).darkened(0.3), clampf(1.4 - g[1] * 2.0, 0.0, 1.0))
				c = c.lerp(c.darkened(0.25), rand.randf() * 0.6)
				if rand.randf() < 0.1:
					c = c.lerp(Color("5a4a36"), 0.35)
				# steep high ground shows its rock, the tops their snow
				c = c.lerp(rock_col, clampf((slope - 2.5) / 4.0, 0.0, 0.9))
			if h > 75 and g[2] != Terrain.DESERT and g[2] != Terrain.ASH:
				c = c.lerp(snow_col, clampf((h - 75) / 20.0, 0.0, 1.0))
			var road := Terrain.road_edge(x, z)
			if road < 1.0:
				c = c.lerp(road_col, (1.0 - smoothstep(-0.8, 1.0, road)) * (0.75 + rand.randf() * 0.25))
			if h < 1.2 and g[2] != Terrain.SEA:
				c = c.lerp(Color("8a8060"), clampf((1.2 - h) / 0.9, 0.0, 0.6))
			cols[j * (n + 1) + i] = c
	var verts := PackedVector3Array()
	var vcols := PackedColorArray()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(n * n * 6)
	vcols.resize(n * n * 6)
	norms.resize(n * n * 6)
	uvs.resize(n * n * 6)
	var v := 0
	var w := n + 1
	for j in n:
		for i in n:
			var a := j * w + i
			var b := (j + 1) * w + i
			var c := (j + 1) * w + i + 1
			var d := j * w + i + 1
			# two triangles split from (x+1, z) to (x, z+1), as Terrain.base_height
			for tri in [[a, d, b], [b, d, c]]:
				var nrm := (pos[tri[2]] - pos[tri[0]]).cross(pos[tri[1]] - pos[tri[0]]).normalized()
				for idx in tri:
					verts[v] = pos[idx]
					vcols[v] = cols[idx]
					norms[v] = nrm
					uvs[v] = Vector2(pos[idx].x, pos[idx].z) / 6.0
					v += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = vcols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = mesh
	mi.material_override = mat
	# the ground only receives shadows
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("sea", sea)
	return mi


static func _needs_detail(x0: float, z0: float) -> bool:
	var pad := 6.0
	for p in Layout.pads:
		if p[0] > x0 - p[2] - pad and p[0] < x0 + CHUNK + p[2] + pad and p[1] > z0 - p[2] - pad and p[1] < z0 + CHUNK + p[2] + pad:
			return true
	for wt in Layout.water:
		if not wt.get("carved") and wt.position[0] > x0 - 12 and wt.position[0] < x0 + CHUNK + 12 and wt.position[1] > z0 - 12 and wt.position[1] < z0 + CHUNK + 12:
			return true
	return false


## Ground the whole of a rectangle (for the World editor).
static func build_area(min_x: float, min_z: float, max_x: float, max_z: float) -> Node3D:
	var n := Node3D.new()
	n.name = "Terrain"
	var mat := ground_material()
	for i in range(floori(min_x / CHUNK), floori(max_x / CHUNK) + 1):
		for j in range(floori(min_z / CHUNK), floori(max_z / CHUNK) + 1):
			n.add_child(chunk_ground(Vector2i(i, j), mat))
	return n


# ------------------------------------------------------------- woodland
## Places kept free of trees: clearings, building pads, props with
## colliders, buildings, stations, chests, townsfolk and POIs.
static func index_clearings() -> void:
	_clear_cells.clear()
	var add := func(x: float, z: float, r: float):
		for i in range(floori((x - r) / 32.0), floori((x + r) / 32.0) + 1):
			for j in range(floori((z - r) / 32.0), floori((z + r) / 32.0) + 1):
				var key := Vector2i(i, j)
				if not _clear_cells.has(key):
					_clear_cells[key] = []
				_clear_cells[key].append([x, z, r])
	for c in Layout.clearings:
		add.call(c[0], c[1], c[2])
	for p in Layout.pads:
		add.call(p[0], p[1], p[2] + 2.0)
	for p in Layout.props:
		add.call(p.position[0], p.position[1], 3.0 if p.get("collider") else 1.5)
	for b in Layout.buildings + Layout.houses:
		add.call(b.position[0], b.position[1], maxf(b.size[0], b.size[1]) * 0.75 + 2.0)
	for tw in Layout.town_walls:
		for line in tw.lines:
			for i in line.size() - 1:
				var a := Vector2(line[i][0], line[i][1])
				var b := Vector2(line[i + 1][0], line[i + 1][1])
				for k in ceili(a.distance_to(b) / 4.0) + 1:
					var p := a.lerp(b, minf(1.0, k * 4.0 / a.distance_to(b)))
					add.call(p.x, p.y, 3.5)
	for gt in Layout.gates:
		add.call((gt.line[0][0] + gt.line[1][0]) / 2.0, (gt.line[0][1] + gt.line[1][1]) / 2.0, 8.0)
	for list in [Layout.stations, Layout.npcs, Layout.shrines, Layout.signposts, DB.world.get("chests", []), DB.world.get("placedLoot", [])]:
		for s in list:
			add.call(s.position[0], s.position[1], 2.5)
	for p in WorldMap.pois:
		add.call(p.at[0], p.at[1], 12.0)


static func is_clear(x: float, z: float) -> bool:
	for c in _clear_cells.get(Vector2i(floori(x / 32.0), floori(z / 32.0)), []):
		if Vector2(x - c[0], z - c[1]).length() < c[2]:
			return false
	return true


## Every tree in a chunk as {model, x, z, s (scale), r (turn), solid}: the
## same list every time for the same chunk. Trees on open ground are solid.
static func chunk_trees(k: Vector2i) -> Array:
	if Terrain.is_new_map():
		return [] # Dan places the new map's trees himself
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(Vector3i(k.x, k.y, 7))
	var out := []
	var cells := int(CHUNK / 4.0)
	for gj in cells:
		for gi in cells:
			var x := k.x * CHUNK + (gi + rand.randf()) * 4.0
			var z := k.y * CHUNK + (gj + rand.randf()) * 4.0
			var roll := rand.randf()
			var pick := rand.randf()
			var s := 0.8 + rand.randf() * 0.7
			var r := rand.randf() * TAU
			var surf := Terrain.surface_at(x, z)
			var woods = WOODS.get(surf)
			if woods == null:
				continue
			var walk := Terrain.walk_at(x, z)
			var open := walk >= 0.45
			# open ground has copses and lone trees here and there, not an even sprinkle
			if roll > (minf(0.6, woods[0] * (0.3 + 40.0 * grove(x, z))) if open else woods[1]):
				continue
			if Terrain.base_height(x, z) < 1.0:
				continue
			if open and (Terrain.road_edge(x, z) < 2.5 or not is_clear(x, z) or Terrain.water_at(x, z, -2.0) != null):
				continue
			var models: Array = woods[2]
			out.append({"model": models[int(pick * models.size()) % models.size()], "x": x, "z": z, "s": s * (1.0 if open else 1.15), "r": r, "solid": open})
	return out


## 0..1, high in the copses: smooth noise on a 48 m lattice, the same everywhere.
static func grove(x: float, z: float) -> float:
	var fx := x / 48.0
	var fz := z / 48.0
	var i := floori(fx)
	var j := floori(fz)
	fx -= i
	fz -= j
	var r := func(a: int, b: int) -> float: return float(hash(Vector2i(a, b)) % 1000) / 1000.0
	var v := lerpf(lerpf(r.call(i, j), r.call(i + 1, j), fx), lerpf(r.call(i, j + 1), r.call(i + 1, j + 1), fx), fz)
	return clampf((v - 0.62) * 3.0, 0.0, 1.0)


## Big rocks on bare high ground (never solid: the high ground blocks anyway).
static func chunk_rocks(k: Vector2i) -> Array:
	if Terrain.is_new_map():
		return []
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(Vector3i(k.x, k.y, 11))
	var out := []
	var cells := int(CHUNK / 8.0)
	for gj in cells:
		for gi in cells:
			var x := k.x * CHUNK + (gi + rand.randf()) * 8.0
			var z := k.y * CHUNK + (gj + rand.randf()) * 8.0
			var roll := rand.randf()
			var s := 1.6 + rand.randf() * 2.6
			var r := rand.randf() * TAU
			var m := "rock0" if rand.randf() < 0.5 else "rock1"
			var d: float = ROCKS.get(Terrain.surface_at(x, z), 0.0) * 4.0
			if roll > d or Terrain.walk_at(x, z) >= 0.4 or Terrain.base_height(x, z) < 1.0:
				continue
			out.append({"model": m, "x": x, "z": z, "s": s, "r": r})
	return out


func _plant(n: Node3D, list_all: Array) -> void:
	var by_model := {}
	for t in list_all:
		if not by_model.has(t.model):
			by_model[t.model] = []
		by_model[t.model].append(t)
	for model in by_model:
		var src = _model(model)
		if src == null:
			continue
		var list: Array = by_model[model]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = src[0]
		mm.instance_count = list.size()
		for i in list.size():
			var t: Dictionary = list[i]
			var basis := Basis(Vector3.UP, t.r).scaled(Vector3.ONE * t.s)
			mm.set_instance_transform(i, Transform3D(basis, Vector3(t.x, Terrain.height_at(t.x, t.z) - 0.1, t.z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Woodland_" + model
		mmi.material_override = src[1]
		n.add_child(mmi)


## A model's first mesh and a cutaway material for it (trees between the
## camera and the player dissolve).
func _model(model: String):
	if _models.has(model):
		return _models[model]
	var out = null
	if Assets.has(model):
		var src := Assets.instance(model)
		var meshes := src.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			var mi: MeshInstance3D = meshes[0]
			var m := ShaderMaterial.new()
			m.shader = CUTAWAY
			var base := mi.get_active_material(0)
			m.set_shader_parameter("albedo", base.albedo_color if base is BaseMaterial3D else Color.WHITE)
			_cutaways.append(m)
			out = [mi.mesh, m]
		src.free()
	_models[model] = out
	return out


## another material that dissolves between the camera and the player (Town)
func add_cutaway(m: ShaderMaterial) -> void:
	_cutaways.append(m)


func set_cutaway(camera_pos: Vector3, at: Vector3) -> void:
	for m in _cutaways:
		m.set_shader_parameter("uCamPos", camera_pos)
		m.set_shader_parameter("uFocus", at)


# ------------------------------------------------------------- grass
static func _grass_blade() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k / 3.0 * PI
		var cx := cos(a) * 0.18
		var cz := sin(a) * 0.18
		st.add_vertex(Vector3(-cx, 0, -cz))
		st.add_vertex(Vector3(cx * 0.2 + 0.05, 0.45, cz * 0.2))
		st.add_vertex(Vector3(cx, 0, cz))
	st.generate_normals()
	return st.commit()


## low-poly grass tufts on open grassy ground, only drawn close by
func _grass(n: Node3D, k: Vector2i) -> void:
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(Vector3i(k.x, k.y, 3))
	var xfs := []
	var cols := []
	for i in 900:
		var x := k.x * CHUNK + rand.randf() * CHUNK
		var z := k.y * CHUNK + rand.randf() * CHUNK
		var rot := rand.randf() * PI
		var s := 0.6 + rand.randf() * 0.9
		var sy := s * (0.7 + rand.randf() * 0.8)
		var hue := 0.2 + rand.randf() * 0.06
		var sat := 0.25 + rand.randf() * 0.15
		var lig := 0.34 + rand.randf() * 0.16
		var surf := Terrain.surface_at(x, z)
		if not GRASSY.has(surf) or Terrain.walk_at(x, z) < 0.6:
			continue
		if Terrain.road_edge(x, z) < 0.0 and rand.randf() > 0.15:
			continue # a few tufts break through the road
		if game.world != null and game.world.on_floor(x, z):
			continue
		var y := Terrain.height_at(x, z)
		if y < 1.0:
			continue
		xfs.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, sy, s)), Vector3(x, y - 0.02, z)))
		var dark := 0.4 if surf == Terrain.BLACKWOOD else 0.0
		cols.append(World._hsl(hue, sat, lig * (1 - dark)))
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _blade
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.name = "GroundCover"
	mmi.visibility_range_end = 36.0
	mmi.visibility_range_end_margin = 4.0
	n.add_child(mmi)


# ------------------------------------------------------------- water
## Rivers as ribbons at their water level and lakes as flat ovals, in pieces
## that are only drawn near the camera.
func _build_rivers_and_lakes() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(Color.hex(0x1f3a3cff), 0.88)
	mat.emission_enabled = true
	mat.emission = Color.hex(0x0a1618ff)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for r in DB.water.get("rivers", []):
		var pts: Array = r.points
		var half: float = r.width / 2.0 + 1.0
		var i := 0
		while i < pts.size() - 1:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			st.set_normal(Vector3.UP)
			var end := mini(i + 8, pts.size() - 1)
			for k in range(i, end):
				var a := Vector3(pts[k][0], pts[k][2], pts[k][1])
				var b := Vector3(pts[k + 1][0], pts[k + 1][2], pts[k + 1][1])
				var dir := (b - a)
				dir.y = 0
				var side := Vector3(-dir.z, 0, dir.x).normalized() * half
				for vtx in [a - side, b - side, b + side, a - side, b + side, a + side]:
					st.add_vertex(vtx)
			var mi := MeshInstance3D.new()
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.visibility_range_end = RADIUS + 40.0
			mi.name = "River_" + str(r.id)
			group.add_child(mi)
			i = end
	for l in DB.water.get("lakes", []):
		var mi := MeshInstance3D.new()
		mi.mesh = WaterAndDark.flat_ring(0, 1.0, 64)
		mi.scale = Vector3(l.rx + 2.0, 1, l.rz + 2.0)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(l.center[0], l.level, l.center[1])
		mi.visibility_range_end = maxf(l.rx, l.rz) + RADIUS + 40.0
		mi.name = "Lake_" + str(l.id)
		group.add_child(mi)

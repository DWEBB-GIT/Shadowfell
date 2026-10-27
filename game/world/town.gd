class_name Town
extends RefCounted
## Towns and the gates of the opening, from data/world.json: `houses` (kit
## built from a few boxes under a gabled roof whose colour says what it is
## at a glance from the iso camera: thatch, slate or tile; you cannot go
## in), `townWalls` (palisades along lines) and `gates`. A gate shuts its
## ring of the opening (the lane and town, then Bracken Vale) until any of
## its `opensWhen` conditions holds (Quests.condition_holds), then opens for
## good; `shut` ones never open in this act. Everything is drawn with the
## woodland's cutaway, so nothing here can hide the player.

const ROOF := {"thatch": Color("8c7748"), "slate": Color("4c5866"), "tile": Color("9a4a30")}
const WALL := {"plaster": Color("d2c39c"), "timber": Color("9a7a52"), "stone": Color("8f897c")}
const BEAM := Color("4a3322")
const STONE := Color("6e6a62")
const DOOR := Color("3a2818")
const WINDOW := Color("f0c060")
const STAKE := Color("6e5638")
const BARK := Color("4a3a2a")
const CHECK_EVERY := 0.5 ## seconds between gate condition checks
const NAG_EVERY := 8.0 ## seconds before a shut gate says why again

var game
var world
var group: Node3D
var gates := [] ## {def, open, leaves: [[node, shut_y, open_y]], slide, circles, t}
var _mat: ShaderMaterial
var _check := 0.0
var _settled := false
var _nagged := {}


func _init(g, w, parent: Node3D) -> void:
	game = g
	world = w
	group = Node3D.new()
	group.name = "Town"
	parent.add_child(group)
	_mat = ShaderMaterial.new()
	_mat.shader = Land.CUTAWAY
	_mat.set_shader_parameter("albedo", Color.WHITE)
	w.land.add_cutaway(_mat)


func build() -> Town:
	for h in Layout.houses:
		_build_house(h)
	for tw in Layout.town_walls:
		for line in tw.lines:
			_build_palisade(line)
	for gt in Layout.gates:
		_build_gate(gt)
	return self


# ------------------------------------------------------------- houses
func _build_house(h: Dictionary) -> void:
	var x: float = h.position[0]
	var z: float = h.position[1]
	var w: float = h.size[0]
	var d: float = h.size[1]
	var turn := deg_to_rad(h.get("rotation", 0))
	# the ridge runs along the longer side: build with it along local x
	var across := d > w
	var length := d if across else w
	var span := w if across else d
	var storeys: int = h.get("storeys", 1)
	var top := 0.35 + 2.7 * storeys
	var wall: Color = WALL.get(h.get("walls", "plaster"), WALL.plaster)
	var roof: Color = ROOF.get(h.get("roof", "thatch"), ROOF.thatch)
	var m := Mesher.new()
	var hl := length / 2.0
	var hs := span / 2.0
	m.box(Vector3(0, -0.45, 0), Vector3(length + 0.3, 1.6, span + 0.3), STONE)
	m.box(Vector3(0, (0.35 + top) / 2.0, 0), Vector3(length, top - 0.35, span), wall)
	if h.get("walls") != "stone":
		# timber framing: corner and middle posts, a beam at every floor
		for sx in [-1, 1]:
			for sz in [-1, 1]:
				m.box(Vector3(sx * (hl - 0.08), (0.35 + top) / 2.0, sz * (hs - 0.08)), Vector3(0.26, top - 0.35, 0.26), BEAM)
		var posts := maxi(1, roundi(length / 2.4))
		for i in range(1, posts):
			var px := -hl + length * i / posts
			for sz in [-1, 1]:
				m.box(Vector3(px, (0.35 + top) / 2.0, sz * (hs + 0.03)), Vector3(0.18, top - 0.35, 0.08), BEAM)
		for f in range(1, storeys + 1):
			var by := 0.35 + 2.7 * f - 0.12
			m.box(Vector3(0, by, 0), Vector3(length + 0.08, 0.22, span + 0.08), BEAM)
	else:
		m.box(Vector3(0, top - 0.15, 0), Vector3(length + 0.1, 0.3, span + 0.1), STONE)
	# windows on the long sides, a row per floor
	for f in storeys:
		var wy := 0.35 + 2.7 * f + 1.45
		for k in [-0.28, 0.28]:
			for sz in [-1, 1]:
				m.box(Vector3(length * k, wy, sz * (hs + 0.04)), Vector3(0.75, 0.8, 0.1), WINDOW)
	# the door, on its side
	var door := _door_side(str(h.get("door", "s")), across)
	var dp: Vector3 = Vector3(door.x * (hl + 0.05), 1.45, door.y * (hs + 0.05))
	var dsize := Vector3(0.12, 2.2, 1.3) if door.x != 0 else Vector3(1.3, 2.2, 0.12)
	if door.x == 0:
		dp.x = length * 0.08
	m.box(dp, dsize, DOOR)
	# a steep gabled roof with deep eaves: the shape the iso camera reads
	var pitch := deg_to_rad(48.0)
	var eave := 0.5
	var rise := hs * tan(pitch)
	var ridge := top + rise
	var slope_len := (hs + eave) / cos(pitch)
	for sz in [-1, 1]:
		var mid := Vector3(0, ridge - (hs + eave) * tan(pitch) / 2.0, sz * (hs + eave) / 2.0)
		var b := Basis(Vector3.RIGHT, sz * pitch)
		# the slope facing away from the sun a shade darker, so the gable reads from above
		m.box(mid + b * Vector3(0, 0.14, 0), Vector3(length + eave * 2, 0.28, slope_len), roof if sz > 0 else roof.darkened(0.18), b)
	m.box(Vector3(0, ridge + 0.12, 0), Vector3(length + eave * 2 + 0.1, 0.24, 0.4), roof.darkened(0.3))
	for sx in [-1, 1]:
		m.gable(Vector3(sx * hl, top, -hs), Vector3(sx * hl, top, hs), Vector3(sx * hl, ridge, 0), wall, Vector3(sx, 0, 0))
	if h.get("chimney"):
		m.box(Vector3(hl - 1.1, (top + ridge + 1.2) / 2.0, hs * 0.35), Vector3(0.8, ridge + 1.2 - top, 0.8), STONE)
	if h.get("tower"):
		var tw := minf(span, 3.4)
		var th := top + 5.5
		var tx := -hl - tw / 2.0 + 0.2
		m.box(Vector3(tx, th / 2.0 - 0.6, 0), Vector3(tw, th + 1.2, tw), wall)
		m.box(Vector3(tx, th - 1.2, 0), Vector3(tw + 0.1, 0.6, tw + 0.1), STONE)
		m.pyramid(Vector3(tx, th, 0), tw / 2.0 + 0.3, 3.2, roof)
	var mi := MeshInstance3D.new()
	mi.name = h.id
	mi.mesh = m.mesh()
	mi.material_override = _mat
	mi.position = Vector3(x, Terrain.height_at(x, z), z)
	mi.rotation.y = turn + (PI / 2.0 if across else 0.0)
	group.add_child(mi)
	world._wall_colliders(x, z, turn, [[-w / 2, -d / 2, w / 2, -d / 2], [w / 2, -d / 2, w / 2, d / 2], [-w / 2, d / 2, w / 2, d / 2], [-w / 2, -d / 2, -w / 2, d / 2]], 0.3, true)


## the door's face in the ridge-along-x frame: (±1, 0) a gable end, (0, ±1) a long side
static func _door_side(side: String, across: bool) -> Vector2i:
	var world_dir: Vector2i = {"n": Vector2i(0, -1), "s": Vector2i(0, 1), "e": Vector2i(1, 0), "w": Vector2i(-1, 0)}.get(side, Vector2i(0, 1))
	if not across:
		return world_dir
	# turned a quarter (local +x is world -z, local +z is world +x)
	return Vector2i(-world_dir.y, world_dir.x)


# ------------------------------------------------------------- palisades
func _build_palisade(line: Array) -> void:
	var m := Mesher.new()
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(line)
	for i in line.size() - 1:
		var a := Vector2(line[i][0], line[i][1])
		var b := Vector2(line[i + 1][0], line[i + 1][1])
		var n := maxi(1, ceili(a.distance_to(b) / 0.5))
		for k in n:
			var p := a.lerp(b, (k + rand.randf() * 0.2) / n)
			var y := Terrain.height_at(p.x, p.y)
			var tall := 3.1 + rand.randf() * 0.7
			m.stake(Vector3(p.x, y - 0.6, p.y), 0.2, tall + 0.6, STAKE.darkened(rand.randf() * 0.2))
		# a rail along the inside, so the line reads as one wall
		var dir := (b - a).normalized()
		var mid := (a + b) / 2.0
		var rail_y := Terrain.height_at(mid.x, mid.y) + 2.2
		m.box(Vector3(mid.x, rail_y, mid.y), Vector3(a.distance_to(b), 0.22, 0.18), BEAM, Basis(Vector3.UP, -atan2(dir.y, dir.x)))
		world._wall_colliders(0, 0, 0, [[a.x, a.y, b.x, b.y]], 0.32)
	var mi := MeshInstance3D.new()
	mi.name = "Palisade"
	mi.mesh = m.mesh()
	mi.material_override = _mat
	group.add_child(mi)


# ------------------------------------------------------------- gates
func _build_gate(def: Dictionary) -> void:
	var a := Vector2(def.line[0][0], def.line[0][1])
	var b := Vector2(def.line[1][0], def.line[1][1])
	var mid := (a + b) / 2.0
	var length := a.distance_to(b)
	var ang := -atan2(b.y - a.y, b.x - a.x)
	var root := Node3D.new()
	root.name = def.id
	root.position = Vector3(mid.x, Terrain.height_at(mid.x, mid.y), mid.y)
	root.rotation.y = ang
	group.add_child(root)
	var gate := {"def": def, "open": false, "leaves": [], "slide": null, "circles": [], "t": 0.0}
	var kind: String = def.get("kind", "town_gate")
	var solid := Mesher.new()
	var hl := length / 2.0
	if kind == "town_gate":
		# two posts under a roofed lintel: a gateway you can spot across the town
		for s in [-1, 1]:
			solid.box(Vector3(s * (hl + 0.35), 2.4, 0), Vector3(0.75, 5.6, 0.75), BEAM)
		solid.box(Vector3(0, 5.0, 0), Vector3(length + 1.8, 0.5, 0.9), BEAM)
		solid.box(Vector3(0, 5.35, 0), Vector3(length + 1.2, 0.2, 0.9), ROOF.slate.darkened(0.3))
		for s in [-1, 1]:
			var hinge := Node3D.new()
			hinge.position = Vector3(s * hl, 0, 0)
			root.add_child(hinge)
			var leaf := Mesher.new()
			leaf.box(Vector3(-s * hl / 2.0, 1.9, 0), Vector3(hl - 0.1, 3.6, 0.22), STAKE)
			leaf.box(Vector3(-s * hl / 2.0, 1.0, 0.14), Vector3(hl - 0.3, 0.25, 0.08), BEAM)
			leaf.box(Vector3(-s * hl / 2.0, 2.9, 0.14), Vector3(hl - 0.3, 0.25, 0.08), BEAM)
			hinge.add_child(_instance(leaf))
			gate.leaves.append([hinge, 0.0, s * deg_to_rad(105.0)])
	elif kind == "barricade":
		# a wardens' barricade: spiked logs across the way, dragged aside when it opens
		var slide := Node3D.new()
		root.add_child(slide)
		var bar := Mesher.new()
		bar.trunk(Vector3(-hl, 0.9, 0), Vector3(hl, 0.9, 0), 0.3, BARK)
		var n := maxi(2, roundi(length / 1.6))
		for i in n + 1:
			var px := -hl + length * i / n
			for s in [-1, 1]:
				bar.trunk(Vector3(px, 0.05, -1.1 * s), Vector3(px, 1.9, 1.1 * s), 0.13, STAKE)
		slide.add_child(_instance(bar))
		gate.slide = [slide, Vector3.ZERO, Vector3(length * 0.85, 0, 1.6)]
	elif kind == "felled_oak":
		var oak := Mesher.new()
		oak.trunk(Vector3(-hl - 2.0, 0.85, 0.2), Vector3(hl + 1.0, 0.75, -0.3), 0.85, BARK)
		oak.disc(Vector3(hl + 1.1, 1.2, -0.3), Vector3(1, 0, 0), 2.1, Color("4a3c2c"))
		oak.trunk(Vector3(-hl * 0.3, 1.0, 0.0), Vector3(-hl * 0.6, 2.8, 2.6), 0.32, BARK)
		oak.trunk(Vector3(-hl * 0.6, 0.9, 0.2), Vector3(-hl - 1.0, 2.2, -2.4), 0.3, BARK)
		oak.trunk(Vector3(hl * 0.2, 1.0, 0.0), Vector3(hl * 0.1, 2.4, -2.2), 0.28, BARK)
		root.add_child(_instance(oak))
	if not solid.verts.is_empty():
		root.add_child(_instance(solid))
	# the way itself: circles along the line, lifted while the gate stands open
	var steps := maxi(2, ceili(length / 0.35))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		gate.circles.append(game.collision.add(p.x, p.y, 0.4))
	gates.append(gate)


func _instance(m: Mesher) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m.mesh()
	mi.material_override = _mat
	return mi


## true if this gate's way is open now
func _opens(def: Dictionary) -> bool:
	if def.get("shut"):
		return false
	var when = def.get("opensWhen")
	if when == null:
		return true
	if game.quests == null:
		return false
	for c in when:
		if Quests.condition_holds(game, c):
			return true
	return false


func update(dt: float) -> void:
	_check -= dt
	if _check <= 0 and game.started:
		_check = CHECK_EVERY
		for gt in gates:
			var open := _opens(gt.def)
			if open != gt.open:
				gt.open = open
				for c in gt.circles:
					c.off = open
				if _settled and open and gt.def.get("openText"):
					game.events.emit("log", {"text": gt.def.openText, "kind": "quest"})
					game.hud.toast(gt.def.openText)
				if not _settled:
					gt.t = 1.0 if open else 0.0
		_settled = true
		_nag()
	for gt in gates:
		var target := 1.0 if gt.open else 0.0
		if gt.t != target:
			gt.t = move_toward(gt.t, target, dt * 0.6)
		var k: float = smoothstep(0.0, 1.0, gt.t)
		for l in gt.leaves:
			l[0].rotation.y = lerpf(l[1], l[2], k)
		if gt.slide:
			gt.slide[0].position = gt.slide[1].lerp(gt.slide[2], k)


## a shut gate says why when you walk up to it
func _nag() -> void:
	var p: Vector3 = game.player.position
	var now := Time.get_ticks_msec() / 1000.0
	for gt in gates:
		if gt.open or not gt.def.get("closedText"):
			continue
		var a := Vector2(gt.def.line[0][0], gt.def.line[0][1])
		var b := Vector2(gt.def.line[1][0], gt.def.line[1][1])
		var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, b)
		if q.distance_to(Vector2(p.x, p.z)) < 3.0 and now - _nagged.get(gt.def.id, -1000.0) > NAG_EVERY:
			_nagged[gt.def.id] = now
			game.events.emit("log", {"text": gt.def.closedText, "kind": "muted"})
			game.hud.toast(gt.def.closedText)


## is (x, z) on the far side of a shut gate's ring? (for the checks)
func is_open(id: String) -> bool:
	for gt in gates:
		if gt.def.id == id:
			return gt.open
	return false


# ------------------------------------------------------------- meshes
## Flat-shaded, vertex-coloured triangles, front faces wound the way Godot
## draws them (clockwise seen from outside).
class Mesher:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		if (b - a).cross(c - a).dot(out) > 0:
			var t := b
			b = c
			c = t
		verts.append_array([a, b, c])
		cols.append_array([col, col, col])

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out)
		tri(a, c, d, col, out)

	func box(center: Vector3, size: Vector3, col: Color, basis := Basis()) -> void:
		var h := size / 2.0
		var p := func(x: float, y: float, z: float) -> Vector3: return center + basis * Vector3(x * h.x, y * h.y, z * h.z)
		for axis in 3:
			for s in [-1, 1]:
				var n := Vector3.ZERO
				n[axis] = s
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1
				var v := Vector3.ZERO
				v[(axis + 2) % 3] = 1
				var c0: Vector3 = p.call(n.x - u.x - v.x, n.y - u.y - v.y, n.z - u.z - v.z)
				var c1: Vector3 = p.call(n.x + u.x - v.x, n.y + u.y - v.y, n.z + u.z - v.z)
				var c2: Vector3 = p.call(n.x + u.x + v.x, n.y + u.y + v.y, n.z + u.z + v.z)
				var c3: Vector3 = p.call(n.x - u.x + v.x, n.y - u.y + v.y, n.z - u.z + v.z)
				# the top catches the light, the sides a touch darker: reads as a solid from above
				var shade := col if axis == 1 and s > 0 else col.darkened(0.06)
				quad(c0, c1, c2, c3, shade, basis * n)

	## a triangle seen from both sides (a gable end)
	func gable(a: Vector3, b: Vector3, c: Vector3, col: Color, out: Vector3) -> void:
		tri(a, b, c, col, out)
		tri(a, b, c, col.darkened(0.2), -out)

	func pyramid(base: Vector3, r: float, h: float, col: Color) -> void:
		var top := base + Vector3(0, h, 0)
		var c := [base + Vector3(-r, 0, -r), base + Vector3(r, 0, -r), base + Vector3(r, 0, r), base + Vector3(-r, 0, r)]
		for i in 4:
			var a: Vector3 = c[i]
			var b: Vector3 = c[(i + 1) % 4]
			tri(a, b, top, col if i % 2 == 0 else col.darkened(0.1), ((a + b) / 2.0 - base) + Vector3(0, r, 0))

	## a six-sided post with a pointed top, standing at `foot`
	func stake(foot: Vector3, r: float, h: float, col: Color) -> void:
		var tip := foot + Vector3(0, h + r * 2.2, 0)
		for i in 6:
			var a0 := TAU * i / 6.0
			var a1 := TAU * (i + 1) / 6.0
			var d0 := Vector3(cos(a0), 0, sin(a0)) * r
			var d1 := Vector3(cos(a1), 0, sin(a1)) * r
			var out := (d0 + d1) / 2.0
			quad(foot + d0, foot + d1, foot + d1 + Vector3(0, h, 0), foot + d0 + Vector3(0, h, 0), col, out)
			tri(foot + d0 + Vector3(0, h, 0), foot + d1 + Vector3(0, h, 0), tip, col.lightened(0.08), out + Vector3(0, r, 0))

	## an eight-sided log from `a` to `b`
	func trunk(a: Vector3, b: Vector3, r: float, col: Color) -> void:
		var ax := (b - a).normalized()
		var u := ax.cross(Vector3.UP)
		if u.length() < 0.01:
			u = ax.cross(Vector3.RIGHT)
		u = u.normalized()
		var v := ax.cross(u).normalized()
		for i in 8:
			var a0 := TAU * i / 8.0
			var a1 := TAU * (i + 1) / 8.0
			var d0 := (u * cos(a0) + v * sin(a0)) * r
			var d1 := (u * cos(a1) + v * sin(a1)) * r
			quad(a + d0, a + d1, b + d1, b + d0, col if i % 2 == 0 else col.darkened(0.08), (d0 + d1) / 2.0)
			tri(a, a + d0, a + d1, col.lightened(0.15), -ax)
			tri(b, b + d0, b + d1, col.lightened(0.15), ax)

	## a flat round plate facing `n` (the oak's torn-up roots)
	func disc(c: Vector3, n: Vector3, r: float, col: Color) -> void:
		var u := n.cross(Vector3.UP).normalized()
		var v := n.cross(u).normalized()
		for i in 10:
			var a0 := TAU * i / 10.0
			var a1 := TAU * (i + 1) / 10.0
			var p0 := c + (u * cos(a0) + v * sin(a0)) * r * (0.8 + 0.2 * sin(i * 2.3))
			var p1 := c + (u * cos(a1) + v * sin(a1)) * r * (0.8 + 0.2 * sin((i + 1) * 2.3))
			tri(c, p0, p1, col, n)
			tri(c, p0, p1, col.darkened(0.2), -n)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return am

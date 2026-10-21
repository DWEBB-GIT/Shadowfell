class_name Telegraphs
extends RefCounted
## Ground telegraphs, after Final Fantasy XIV (src/systems/telegraphs.js):
## before a big enemy's heavy attack lands, its area is painted on the ground
## and fills up as the wind-up runs. Whoever is still inside when it fills is
## hit. The marked area is fixed when the wind-up starts, so stepping or
## rolling out works.

const SHADER := preload("res://game/render/telegraph.gdshader")


class ConeShape:
	var x: float
	var z: float
	var angle: float ## facing, radians (0 = +z)
	var range: float
	var half: float

	func _init(x_: float, z_: float, angle_: float, range_: float, arc_deg: float) -> void:
		x = x_
		z = z_
		angle = angle_
		range = range_
		half = arc_deg * PI / 360.0

	func contains(px: float, pz: float, radius := 0.0) -> bool:
		var dx := px - x
		var dz := pz - z
		var d := U.hyp(dx, dz)
		if d > range + radius:
			return false
		if d < 0.6:
			return true
		var diff := atan2(dx, dz) - angle
		while diff > PI:
			diff -= TAU
		while diff < -PI:
			diff += TAU
		# allow the player's body to clip the edge of the arc
		return absf(diff) <= half + asin(minf(1, radius / maxf(d, radius)))


## A strip from the caster along a direction: arrows and bolts fly down it.
class LineShape:
	var x: float
	var z: float
	var angle: float
	var length: float
	var width: float

	func _init(x_: float, z_: float, angle_: float, length_: float, width_: float) -> void:
		x = x_
		z = z_
		angle = angle_
		length = length_
		width = width_

	func contains(px: float, pz: float, radius := 0.0) -> bool:
		var dx := px - x
		var dz := pz - z
		var along := dx * sin(angle) + dz * cos(angle)
		var across := dx * cos(angle) - dz * sin(angle)
		return along >= -radius and along <= length + radius and absf(across) <= width / 2 + radius


class CircleShape:
	var x: float
	var z: float
	var range: float
	var angle := 0.0

	func _init(x_: float, z_: float, radius: float) -> void:
		x = x_
		z = z_
		range = radius

	func contains(px: float, pz: float, radius := 0.0) -> bool:
		return U.hyp(px - x, pz - z) <= range + radius


static func _mesh(pos: PackedVector3Array, uv: PackedVector2Array, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A sector mesh that follows the terrain, with per-vertex radial distance.
## A full circle is a sector of 360 degrees with no side edges.
static func sector_mesh(shape, rings := 10, segs := 24) -> ArrayMesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var full: bool = shape is CircleShape
	var half: float = PI if full else shape.half
	var start: float = shape.angle - half
	var step := half * 2 / segs
	for r in rings + 1:
		var k := float(r) / rings
		for s in segs + 1:
			var a := start + step * s
			var x: float = shape.x + sin(a) * shape.range * k
			var z: float = shape.z + cos(a) * shape.range * k
			pos.append(Vector3(x, Terrain.height_at(x, z) + 0.06, z))
			uv.append(Vector2(k, 1.0 if not full and (s == 0 or s == segs) else 0.0))
	for r in rings:
		for s in segs:
			var a := r * (segs + 1) + s
			var b := a + segs + 1
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	return _mesh(pos, uv, idx)


## A strip mesh: the fill runs from the caster to the far end.
static func line_mesh(shape: LineShape, rows := 16) -> ArrayMesh:
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	var fx := sin(shape.angle)
	var fz := cos(shape.angle)
	for r in rows + 1:
		var k := float(r) / rows
		for c in 3:
			var side := (c - 1) * (shape.width / 2)
			var x := shape.x + fx * shape.length * k + fz * side
			var z := shape.z + fz * shape.length * k - fx * side
			pos.append(Vector3(x, Terrain.height_at(x, z) + 0.07, z))
			uv.append(Vector2(k, 0.0 if c == 1 else 1.0))
	for r in rows:
		for c in 2:
			var a := r * 3 + c
			var b := a + 3
			idx.append_array([a, b, a + 1, a + 1, b, b + 1])
	return _mesh(pos, uv, idx)


var game
var active: Array = []


func _init(g) -> void:
	game = g


## Starts a telegraph; `onComplete(shape)` runs when it fills.
## o: angle, range, arc, duration, heavy, onComplete
func cone(owner, o: Dictionary) -> Dictionary:
	var shape := ConeShape.new(owner.position.x, owner.position.z, o.angle, o.range, o.arc)
	return _start(owner, shape, sector_mesh(shape), o)


## An aimed line from the owner: an archer's shot or a seer's bolt.
func line(owner, o: Dictionary) -> Dictionary:
	var shape := LineShape.new(owner.position.x, owner.position.z, o.angle, o.length, o.width)
	var opts := o.duplicate()
	if not opts.has("color"):
		opts.color = Color("e8a040")
	return _start(owner, shape, line_mesh(shape), opts)


## A circle on the ground anywhere (a spell under the player's feet).
func circle(owner, o: Dictionary) -> Dictionary:
	var shape := CircleShape.new(o.x, o.z, o.radius)
	var opts := o.duplicate()
	if not opts.has("color"):
		opts.color = Color("9a5cff")
	if not opts.has("heavy"):
		opts.heavy = true
	return _start(owner, shape, sector_mesh(shape, 10, 32), opts)


func _start(owner, shape, mesh: ArrayMesh, o: Dictionary) -> Dictionary:
	var heavy: bool = o.get("heavy", false)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.render_priority = 2
	var colour = o.get("color")
	mat.set_shader_parameter("uColor", colour if colour != null else (Color("ff6a1a") if heavy else Color("e8a040")))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.scene.add_child(mi)
	var t := {"owner": owner, "shape": shape, "mesh": mi, "t": 0.0, "duration": o.duration, "heavy": heavy, "onComplete": o.get("onComplete"), "done": false}
	active.append(t)
	game.events.emit("telegraph", {"owner": owner, "heavy": heavy})
	return t


func cancel(t) -> void:
	if t == null or t.done:
		return
	t.done = true
	_remove(t)


func cancel_for(owner) -> void:
	for t in active.duplicate():
		if t.owner == owner:
			cancel(t)


func _remove(t: Dictionary) -> void:
	t.mesh.queue_free()
	active.erase(t)


func clear() -> void:
	for t in active.duplicate():
		cancel(t)


func update(dt: float) -> void:
	for t in active.duplicate():
		if t.owner.dead:
			cancel(t)
			continue
		t.t += dt
		var k: float = minf(1, t.t / t.duration)
		t.mesh.material_override.set_shader_parameter("uProgress", k)
		if k >= 1 and not t.done:
			t.done = true
			if t.onComplete:
				t.onComplete.call(t.shape)
			_remove(t)

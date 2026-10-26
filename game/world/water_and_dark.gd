class_name WaterAndDark
extends RefCounted
## Ponds and dark places, both from data/world.json (src/world/waterAndDark.js).
##
## Water: a still surface over a bowl in the ground (Terrain dips the land
## under it), which the Warden cannot walk into. Fishing casts into it.
##
## Obscured areas: a dome of darkness. Without a torch in the off hand the
## Warden cannot enter (the dark pushes them back); with one, the dark thins
## and the torch lights what was hidden inside.

var game
var ponds: Array = []
var domes: Array = []


func _init(g) -> void:
	game = g


## a flat disc or ring lying on the ground, centred on the origin
static func flat_ring(inner: float, outer: float, segs: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var o0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		if inner <= 0:
			for v in [Vector3.ZERO, o1, o0]:
				st.add_vertex(v)
			continue
		var i0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		for v in [i0, o1, o0, i0, i1, o1]:
			st.add_vertex(v)
	return st.commit()


func build() -> WaterAndDark:
	for w in Layout.water:
		if w.get("carved"):
			continue # a lake in the land itself (Land draws it, the ground blocks it)
		var level := Terrain.water_level(w)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(Color.hex(0x1f3a3cff), 0.88)
		mat.emission_enabled = true
		mat.emission = Color.hex(0x0a1618ff)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var surface := MeshInstance3D.new()
		surface.mesh = flat_ring(0, w.radius + 0.4, 48)
		surface.material_override = mat
		surface.position = Vector3(w.position[0], level, w.position[1])
		surface.name = "Water_" + str(w.id)
		game.scene.add_child(surface)
		# a faint ring of light that drifts across the water
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color(Color.hex(0x8fb8b0ff), 0.12)
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		smat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var sheen := MeshInstance3D.new()
		sheen.mesh = flat_ring(w.radius * 0.35, w.radius * 0.42, 40)
		sheen.material_override = smat
		sheen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sheen.position = Vector3(w.position[0], level + 0.02, w.position[1])
		game.scene.add_child(sheen)
		game.collision.add(w.position[0], w.position[1], w.radius - 0.3)
		ponds.append({"def": w, "surface": surface, "sheen": sheen, "mat": smat, "level": level})
	for o in Layout.obscured:
		var x: float = o.position[0]
		var z: float = o.position[1]
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(Color.hex(0x020304ff), 0.94)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.render_priority = 4
		var sphere := SphereMesh.new()
		sphere.radius = o.radius + 0.6
		sphere.height = (o.radius + 0.6) * 2
		sphere.is_hemisphere = true
		sphere.radial_segments = 32
		sphere.rings = 12
		var dome := MeshInstance3D.new()
		dome.mesh = sphere
		dome.material_override = mat
		dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		dome.scale.y = 0.75
		dome.position = Vector3(x, Terrain.height_at(x, z) - 0.4, z)
		dome.name = "Obscured_" + str(o.id)
		game.scene.add_child(dome)
		domes.append({"def": o, "dome": dome, "mat": mat})
	return self


## the Warden carries a light (a torch in the off hand)
var has_light: bool:
	get:
		return game.player.light_radius > 0


func obscured_at(x: float, z: float, margin := 0.0):
	for o in Layout.obscured:
		if U.hyp(x - o.position[0], z - o.position[1]) <= o.radius + margin:
			return o
	return null


func update(dt: float, time: float) -> void:
	var player = game.player
	for p in ponds:
		var k := fmod(time * 0.15, 1.0)
		p.sheen.scale = Vector3.ONE * (0.6 + k * 1.2)
		p.mat.albedo_color.a = 0.14 * sin(k * PI)
	var lit := has_light
	for d in domes:
		var target := 0.35 if lit else 0.94
		d.mat.albedo_color.a += (target - d.mat.albedo_color.a) * minf(1, dt * 3)
		# the dark keeps out anyone without a light
		if lit:
			continue
		var x: float = d.def.position[0]
		var z: float = d.def.position[1]
		var dx: float = player.position.x - x
		var dz: float = player.position.z - z
		var dist := U.hyp(dx, dz)
		var edge: float = d.def.radius + player.radius
		if dist < edge:
			var k := edge / dist if dist > 0.01 else 1.0
			player.position.x = x + (dx if dist > 0.01 else 1.0) * k
			player.position.z = z + (dz if dist > 0.01 else 0.0) * k
			game.events.emit("log", {"text": d.def.get("text", "It is too dark to go on without a light."), "kind": "muted", "throttle": "dark-" + str(d.def.id)})

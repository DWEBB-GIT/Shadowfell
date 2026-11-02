class_name FancyGear
extends Node3D
## Test cosmetics (Dan, 2026-11-02): glowing weapons to preview how
## enchanted weapons could look, and glowing wings, a halo and horns.
## An item opts in with `glow` {colour, strength, pulse, motes} and, for the
## built pieces, `cosmetic` ("wings", "halo" or "horns"). Everything is
## made from primitives here, so no model files are needed, and the glow is
## emission (it blooms past the scene's glow threshold), never a light.

var materials: Array = []
var strength := 2.0
var pulse := 0.0 ## pulses per second; 0 holds it steady
var colour := Color.WHITE
var flap: Array = [] ## wing pivots that beat slowly
var t := 0.0


func _process(dt: float) -> void:
	t += dt
	if pulse > 0.0:
		var k := strength * (0.75 + 0.25 * sin(t * TAU * pulse))
		for m in materials:
			m.emission = colour * k
	for i in flap.size():
		var side := -1.0 if i % 2 == 0 else 1.0
		flap[i].rotation.y = side * (0.35 + 0.12 * sin(t * 1.6))


static func glow_colour(g: Dictionary) -> Color:
	return Color.from_string(String(g.get("colour", "#ffffff")), Color.WHITE)


## Make the given model glow. A FancyGear node is added under it to pulse the
## light and, with `motes`, to drift a few sparks off it.
static func apply(node: Node3D, g: Dictionary) -> void:
	if node == null or g.is_empty():
		return
	var fx := FancyGear.new()
	fx.name = "Glow"
	fx.colour = glow_colour(g)
	fx.strength = float(g.get("strength", 2.0))
	fx.pulse = float(g.get("pulse", 0.0))
	fx.materials = Rig.isolate_materials(node)
	for m in fx.materials:
		if m is BaseMaterial3D:
			# keep the weapon's own colour but wash it towards the glow
			m.albedo_color = m.albedo_color.lerp(fx.colour, 0.35)
	Rig.set_emissive(fx.materials, fx.colour, fx.strength)
	node.add_child(fx)
	if g.get("motes", false):
		fx.add_child(_motes(fx.colour, node))


## The built cosmetics: wings for the back, a halo or horns for the head.
static func build(kind: String, g: Dictionary) -> Node3D:
	var fx := FancyGear.new()
	fx.name = "Cosmetic_" + kind
	fx.colour = glow_colour(g)
	fx.strength = float(g.get("strength", 2.0))
	fx.pulse = float(g.get("pulse", 0.0))
	match kind:
		"halo":
			var ring := TorusMesh.new()
			ring.inner_radius = 0.13
			ring.outer_radius = 0.16
			ring.rings = 24
			ring.ring_segments = 6
			var mi := _mesh(fx, ring, _glow_mat(fx, 1.0))
			mi.position = Vector3(0, 0.48, 0)
			mi.rotation.x = 0.12
		"horns":
			var bone := _lit_mat(Color(0.18, 0.13, 0.11))
			for side in [-1.0, 1.0]:
				var root := Node3D.new()
				root.position = Vector3(0.09 * side, 0.3, 0.02)
				root.rotation = Vector3(-0.35, 0, -0.55 * side)
				fx.add_child(root)
				# three tapering segments, each bent further back: a ram's sweep
				var at := root
				var r := 0.04
				for i in 3:
					var seg := CylinderMesh.new()
					seg.top_radius = r * 0.62
					seg.bottom_radius = r
					seg.height = 0.11
					seg.radial_segments = 6
					seg.rings = 1
					var mi := _mesh(at, seg, bone if i < 2 else _glow_mat(fx, 1.0))
					mi.position.y = 0.055
					var next := Node3D.new()
					next.position.y = 0.11
					next.rotation = Vector3(-0.55, 0, 0.25 * side)
					at.add_child(next)
					at = next
					r *= 0.62
		"wings":
			var mat := _glow_mat(fx, 0.55)
			for side in [-1.0, 1.0]:
				var pivot := Node3D.new()
				pivot.position = Vector3(0.06 * side, 0.22, -0.2)
				fx.add_child(pivot)
				fx.flap.append(pivot)
				# feathers fanning out and down from the shoulder blade
				for i in 5:
					var f := QuadMesh.new()
					f.size = Vector2(0.62 - i * 0.07, 0.11)
					var mi := _mesh(pivot, f, mat)
					var a := 0.55 - i * 0.28
					var reach: float = f.size.x * 0.5
					mi.position = Vector3(side * reach * cos(a), reach * sin(a) - 0.02 * i, 0)
					mi.rotation.z = side * a
			fx.add_child(_motes(fx.colour, fx))
	return fx


static func _mesh(parent: Node3D, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _glow_mat(fx: FancyGear, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(fx.colour, alpha)
	m.emission_enabled = true
	m.emission = fx.colour * fx.strength
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fx.materials.append(m)
	return m


static func _lit_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m


## A handful of sparks drifting up off the thing (CPU particles: light on the web).
static func _motes(c: Color, around: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Motes"
	p.amount = 10
	p.lifetime = 1.1
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.18
	p.position = Vector3(0, 0.35, 0) if around is FancyGear else Vector3(0, 0.45, 0)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.4, 0)
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	p.mesh = q
	var m := Tex.fx_material(Tex.glint(), Color(c, 0.9), true, false)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	p.material_override = m
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p

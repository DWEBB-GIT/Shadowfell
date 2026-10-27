class_name World
extends RefCounted
## Builds the world (src/world/world.js): terrain, hand-placed props,
## buildings you can walk into, signposts, scattered woodland, ground cover,
## warm light sources and mist. Registers obstacles with collision and
## examine points with the interaction system.

var game
var group: Node3D
var flicker_lights: Array = []
var flames: Array = []
var mist: Array = []
var examine_points: Array = []
var buildings: Array = []
var indoors = null
var land: Land ## the ground, woodland, grass and water near the camera
var town: Town ## houses, palisades and the gates of the opening
var see_through: SeeThrough ## fades houses that hide you, shows your silhouette


func _init(g) -> void:
	game = g
	group = Node3D.new()
	group.name = "World"


func build() -> World:
	land = Land.new(game, group)
	for p in Layout.props:
		var obj := Assets.instance(p.model)
		var x: float = p.position[0]
		var z: float = p.position[1]
		obj.position = Vector3(x, Terrain.height_at(x, z), z)
		obj.rotation.y = deg_to_rad(p.get("rotation", 0))
		if p.get("tilt"):
			obj.rotation.z = -deg_to_rad(p.tilt)
		if p.get("scale"):
			obj.scale = Vector3.ONE * p.scale
		group.add_child(obj)
		_add_collider(p, x, z)
		if p.get("examine"):
			var off: Array = p.get("examineOffset", [0, 0])
			var r := deg_to_rad(p.get("rotation", 0))
			var ex: float = x + off[0] * cos(r) + off[1] * sin(r)
			var ez: float = z - off[0] * sin(r) + off[1] * cos(r)
			examine_points.append({"id": p.examine, "x": ex, "z": ez})
	_build_buildings()
	see_through = SeeThrough.new(game)
	town = Town.new(game, self, group).build()
	_build_signposts()
	_add_lights()
	_add_mist()
	_add_motes()
	_add_fairy_rings()
	return self


func _add_collider(p: Dictionary, x: float, z: float) -> void:
	var col = p.get("collider")
	if not col:
		return
	var s: float = p.get("scale", 1.0)
	if typeof(col) == TYPE_FLOAT or typeof(col) == TYPE_INT:
		game.collision.add(x, z, col * s)
		return
	if typeof(col) == TYPE_DICTIONARY and col.has("box"):
		# a closed box (a cottage): its four walls
		var w: float = col.box[0] / 2.0
		var d: float = col.box[1] / 2.0
		_wall_colliders(x, z, deg_to_rad(p.get("rotation", 0)), [[-w, -d, w, -d], [w, -d, w, d], [-w, d, w, d], [-w, -d, -w, d]])
		return
	# compound collider: offsets in the prop's local space
	var r := deg_to_rad(p.get("rotation", 0))
	for c in col:
		game.collision.add(x + (c[0] * cos(r) + c[1] * sin(r)) * s, z + (-c[0] * sin(r) + c[1] * cos(r)) * s, c[2] * s)


## walls as rows of small circles, from [x1, z1, x2, z2] segments in the
## object's own space (rotated by `r` radians)
func _wall_colliders(x: float, z: float, r: float, segments: Array, radius := 0.28, wall := false) -> void:
	for sgm in segments:
		var len := U.hyp(sgm[2] - sgm[0], sgm[3] - sgm[1])
		var n := maxi(1, ceili(len / 0.35))
		for i in n + 1:
			var ox: float = sgm[0] + (sgm[2] - sgm[0]) * i / n
			var oz: float = sgm[1] + (sgm[3] - sgm[1]) * i / n
			game.collision.add(x + ox * cos(r) + oz * sin(r), z - ox * sin(r) + oz * cos(r), radius, wall)


## a post, and an arm turned towards each place it names
func _build_signposts() -> void:
	for sp in Layout.signposts:
		var x: float = sp.position[0]
		var z: float = sp.position[1]
		var y := Terrain.height_at(x, z)
		var post := Assets.instance("signpost")
		post.position = Vector3(x, y, z)
		group.add_child(post)
		var lines := Layout.signpost_lines(sp)
		for i in lines.size():
			var arm := Assets.instance("sign_arm")
			arm.position = Vector3(x, y + 2.05 - i * 0.27, z)
			arm.rotation.y = lines[i].angle
			group.add_child(arm)
		game.collision.add(x, z, 0.3)


## Buildings you can walk into: the shell (floor, back walls, fittings), the
## wall facing the camera and the roof, which fade away while you are inside
## so the fixed camera can see in (see update_indoors).
func _build_buildings() -> void:
	buildings = []
	for b in Layout.buildings:
		var x: float = b.position[0]
		var z: float = b.position[1]
		var g := Node3D.new()
		g.name = b.id
		g.position = Vector3(x, Terrain.height_at(x, z) - 0.1, z)
		g.add_child(Assets.instance(b.shell))
		var fade := []
		for m in [b.front, b.roof]:
			var obj := Assets.instance(m)
			fade.append({"obj": obj, "mats": Rig.isolate_materials(obj)})
			g.add_child(obj)
		if b.get("light"):
			var light := Tex.point_light(Color("ffa050"), 4, 10, 1.4)
			light.position = Vector3(b.light[0], 1.1, b.light[1])
			g.add_child(light)
			flicker_lights.append({"light": light, "base": 4.0, "seed": x})
		group.add_child(g)
		_wall_colliders(x, z, 0, b.walls, 0.28, true) # building walls block sight
		for f in b.get("furniture", []):
			game.collision.add(x + f[0], z + f[1], f[2])
		var w: float = b.size[0]
		var d: float = b.size[1]
		buildings.append({"def": b, "fade": fade, "inside": 0.0, "minX": x - w / 2, "maxX": x + w / 2, "minZ": z - d / 2, "maxZ": z + d / 2})
	indoors = null


## Which building (if any) the player stands in; fade its front wall and
## roof towards hidden while inside, back again outside.
func update_indoors(dt: float, pos: Vector3):
	indoors = null
	for b in buildings:
		var inside: bool = pos.x > b.minX + 0.1 and pos.x < b.maxX - 0.1 and pos.z > b.minZ + 0.1 and pos.z < b.maxZ - 0.1
		if inside:
			indoors = b
		var k := 1 - exp(-8 * dt)
		b.inside += ((1.0 if inside else 0.0) - b.inside) * (k if dt > 0 else 1.0)
		for i in b.fade.size():
			var f: Dictionary = b.fade[i]
			var o: float = 1 - b.inside * (1.0 if i == 1 else 0.85)
			Rig.set_alpha(f.mats, o if o <= 0.95 else 1.0)
			f.obj.visible = o > 0.02
	return indoors


## true if (x, z) is inside a building whose roof is still showing (you are
## not in there), so its labels stay hidden under it
func roof_over(x: float, z: float) -> bool:
	for b in buildings:
		if x > b.minX and x < b.maxX and z > b.minZ and z < b.maxZ:
			return b.inside < 0.5
	return false


## 0 outside, rising to 1 inside a building (the camera closes in)
var indoor_blend: float:
	get:
		var m := 0.0
		for b in buildings:
			m = maxf(m, b.inside)
		return m


## Not on a building (with room to walk round it), a levelled pad, or a
## prop that has a box collider (the cottages).
static func _clear_of_town(x: float, z: float) -> bool:
	for list in [Layout.buildings, Layout.houses]:
		for b in list:
			if absf(x - b.position[0]) < b.size[0] / 2.0 + 3 and absf(z - b.position[1]) < b.size[1] / 2.0 + 3:
				return false
	for p in Layout.pads:
		if U.hyp(x - p[0], z - p[1]) < p[2] + 2:
			return false
	for p in Layout.props:
		var col = p.get("collider")
		if typeof(col) == TYPE_DICTIONARY and col.has("box") and absf(x - p.position[0]) < col.box[0] / 2.0 + 3 and absf(z - p.position[1]) < col.box[1] / 2.0 + 3:
			return false
	return true


static func _clear(x: float, z: float, margin := 0.0) -> bool:
	for c in Layout.clearings:
		if U.hyp(x - c[0], z - c[1]) < c[2] + margin:
			return false
	return true


static func _crowded(list: Array, x: float, z: float, gap: float) -> bool:
	for p in list:
		if U.hyp(p.x - x, p.z - z) < gap:
			return true
	return false


func set_cutaway(camera_pos: Vector3, focus: Vector3) -> void:
	land.set_cutaway(camera_pos, focus)


static func _hsl(h: float, s: float, l: float) -> Color:
	var q := l * (1 + s) if l < 0.5 else l + s - l * s
	var p := 2 * l - q
	var f := func(t: float) -> float:
		t = fposmod(t, 1.0)
		if t < 1.0 / 6:
			return p + (q - p) * 6 * t
		if t < 0.5:
			return q
		if t < 2.0 / 3:
			return p + (q - p) * 6 * (2.0 / 3 - t)
		return p
	return Color(f.call(h + 1.0 / 3), f.call(h), f.call(h - 1.0 / 3))


## true on a building's floor (no grass grows through it)
func on_floor(x: float, z: float) -> bool:
	for bd in buildings:
		if x > bd.minX - 0.3 and x < bd.maxX + 0.3 and z > bd.minZ - 0.3 and z < bd.maxZ + 0.3:
			return true
	return false


func _add_lights() -> void:
	for l in Layout.lights:
		var x: float = l.position[0]
		var z: float = l.position[1]
		var light: OmniLight3D = null
		if not l.get("noLight"):
			light = Tex.point_light(Color(l.color) if l.get("color") is String else Color("ffa860"), l.intensity, l.distance, 1.6)
			light.position = Vector3(x, Terrain.height_at(x, z) + l.height, z)
			group.add_child(light)
		if l.get("lantern"):
			# a fallen lantern, still guttering
			var lantern := Node3D.new()
			lantern.add_child(_box(Vector3(0.16, 0.22, 0.16), Color("1c1a18"), false))
			var flame := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.04
			sm.height = 0.08
			flame.mesh = sm
			flame.material_override = _unshaded(Color("ffb060"))
			lantern.add_child(flame)
			lantern.position = Vector3(x, Terrain.height_at(x, z) + 0.1, z)
			lantern.rotation.z = 1.2
			group.add_child(lantern)
		if l.get("brazier"):
			# an iron bowl on a post, with a flame that ignores the fog a little
			var brazier := Node3D.new()
			brazier.name = "Brazier"
			var iron := StandardMaterial3D.new()
			iron.albedo_color = Color("24201c")
			var post := MeshInstance3D.new()
			var pc := CylinderMesh.new()
			pc.top_radius = 0.07
			pc.bottom_radius = 0.1
			pc.height = 1.0
			pc.radial_segments = 6
			post.mesh = pc
			post.material_override = iron
			post.position.y = 0.5
			var bowl := MeshInstance3D.new()
			var bc := CylinderMesh.new()
			bc.top_radius = 0.34
			bc.bottom_radius = 0.18
			bc.height = 0.22
			bc.radial_segments = 8
			bowl.mesh = bc
			bowl.material_override = iron
			bowl.position.y = 1.08
			var flame := MeshInstance3D.new()
			var fc := CylinderMesh.new()
			fc.top_radius = 0.0
			fc.bottom_radius = 0.22
			fc.height = 0.5
			fc.radial_segments = 6
			flame.mesh = fc
			var fm := _unshaded(Color("ffa040"))
			fm.disable_fog = true
			flame.material_override = fm
			flame.position.y = 1.42
			var gm := Tex.fx_material(Tex.glint(), Color(Color("ffa050"), 0.8), true, true)
			gm.disable_fog = true
			var glow := Tex.sprite(gm)
			glow.scale = Vector3.ONE * 2.2
			glow.position.y = 1.45
			for n in [post, bowl, flame, glow]:
				brazier.add_child(n)
			brazier.position = Vector3(x, Terrain.height_at(x, z), z)
			group.add_child(brazier)
			flames.append({"flame": flame, "glow": glow, "seed": randf() * 10})
			game.collision.add(x, z, 0.35)
		if light and l.get("flicker"):
			flicker_lights.append({"light": light, "base": float(l.intensity), "seed": randf() * 10})
	# witchlight runes on the Blackwood's standing stones glow through the fog
	for wl in Layout.witchlights:
		var x: float = wl[0]
		var z: float = wl[1]
		var r := deg_to_rad(wl[2]) # the rune is on the stone's front face
		var gm := Tex.fx_material(Tex.glint(), Color(Color("80f0c0"), 0.7), true, true)
		gm.disable_fog = true
		var glow := Tex.sprite(gm)
		glow.scale = Vector3.ONE * 1.3
		glow.position = Vector3(x + sin(r) * 0.32, Terrain.height_at(x, z) + 1.2, z + cos(r) * 0.32)
		glow.name = "Witchlight"
		group.add_child(glow)
		flames.append({"flame": null, "glow": glow, "seed": x * 3.1})


## Drifting glowing motes (scenery.json `motes`): fireflies over the mere and
## the hedges, wisps in the Blackwood's glades. One CPU particle cloud per
## spot (works in Compatibility and on the web), only drawn near the camera.
func _add_motes() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.14, 0.14)
	for m in Layout.motes:
		var x: float = m.position[0]
		var z: float = m.position[1]
		var c := Color(m.get("color", "#d8f070"))
		var mat := Tex.fx_material(Tex.glint(), c, true, true)
		mat.disable_fog = true
		var p := CPUParticles3D.new()
		p.name = "Motes"
		p.mesh = mesh
		p.material_override = mat
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.amount = int(m.get("count", 16))
		p.lifetime = 6.0
		p.preprocess = 6.0
		p.randomness = 1.0
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		var r: float = m.get("radius", 5.0)
		p.emission_box_extents = Vector3(r, 0.7, r)
		p.direction = Vector3(0, 1, 0)
		p.spread = 180.0
		p.gravity = Vector3.ZERO
		p.initial_velocity_min = 0.05
		p.initial_velocity_max = 0.3
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.4
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0))
		fade.set_color(1, Color(1, 1, 1, 0))
		fade.add_point(0.3, Color(1, 1, 1, 1))
		fade.add_point(0.55, Color(1, 1, 1, 0.25))
		fade.add_point(0.75, Color(1, 1, 1, 1))
		p.color_ramp = fade
		p.visibility_range_end = 45.0
		p.position = Vector3(x, Terrain.height_at(x, z) + m.get("height", 1.2), z)
		group.add_child(p)


## A ring of glowing toadstools (scenery.json `fairyRings`) with an examine
## point at its middle. The caps pulse slowly, like the witchlights.
func _add_fairy_rings() -> void:
	var cap := SphereMesh.new()
	cap.radius = 0.1
	cap.height = 0.09
	cap.radial_segments = 6
	cap.rings = 2
	for fr in Layout.fairy_rings:
		var x: float = fr.position[0]
		var z: float = fr.position[1]
		var r: float = fr.get("radius", 2.0)
		var n := 13
		for i in n:
			var a := TAU * i / n + sin(i * 2.3) * 0.12
			var cx := x + cos(a) * r * (1 + sin(i * 1.7) * 0.06)
			var cz := z + sin(a) * r * (1 + sin(i * 1.7) * 0.06)
			var y := Terrain.height_at(cx, cz)
			var mi := MeshInstance3D.new()
			mi.mesh = cap
			var cm := _unshaded(Color("e8dcff"))
			cm.disable_fog = true
			mi.material_override = cm
			mi.position = Vector3(cx, y + 0.07, cz)
			mi.scale = Vector3.ONE * (0.8 + fmod(i * 0.37, 0.5))
			group.add_child(mi)
			var gm := Tex.fx_material(Tex.glint(), Color(Color("b090ff"), 0.6), true, true)
			gm.disable_fog = true
			var glow := Tex.sprite(gm)
			glow.scale = Vector3.ONE * 0.7
			glow.position = Vector3(cx, y + 0.15, cz)
			glow.name = "FairyGlow"
			group.add_child(glow)
			flames.append({"flame": null, "glow": glow, "seed": i * 1.9})
		if fr.get("examine"):
			examine_points.append({"id": fr.examine, "x": x, "z": z})


static func _unshaded(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


static func _box(size: Vector3, c: Color, unshaded: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	if unshaded:
		mi.material_override = _unshaded(c)
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		mi.material_override = m
	return mi


## Low drifting mist: a few large soft layers just above the ground, laid
## out on a 96 m pattern that repeats across the world, so the layers near
## the camera are always the same few (each hops to the next repeat well
## inside the fog). In gloomy woods the mist lies thicker and greener.
const MIST_REPEAT := 96.0

func _add_mist() -> void:
	for i in 10:
		var mat := Tex.fx_material(Tex.mist(), Color(Color("b8c4c0"), 0.22), false)
		mat.render_priority = 1
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(30, 30)
		m.mesh = pm
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.rotation.y = i * 1.3
		m.name = "Mist"
		group.add_child(m)
		mist.append({"mesh": m, "mat": mat, "x": fmod(i * 37.0, MIST_REPEAT), "z": fmod(i * 59.0 + 11.0, MIST_REPEAT), "seed": i * 2.1, "lift": 0.5 + (i % 3) * 0.25, "deep": -1.0})


## Sun shafts where the low sun pokes through the canopy: at the edge of
## open ground beside thick woods, at most one per chunk and only in some.
## Cheap additive ribbons (see light_shaft.gdshader), only drawn near the
## camera. In the Blackwood the light is thinner and greener.
const SHAFT_AXIS := Vector3(14, -26, -6) ## the sun's travel, as Game._place_sun aims it

static func sun_shaft(k: Vector2i, trees: Array) -> Node3D:
	var rand := RandomNumberGenerator.new()
	rand.seed = hash(Vector3i(k.x, k.y, 5))
	if rand.randf() > 0.4:
		return null
	var axis := SHAFT_AXIS.normalized()
	for t in trees:
		if t.solid or rand.randf() > 0.3:
			continue
		# open ground a few metres off a high-ground tree
		var a := rand.randf() * TAU
		var x: float = t.x + cos(a) * 5.0
		var z: float = t.z + sin(a) * 5.0
		if Terrain.walk_at(x, z) < 0.7 or Terrain.road_edge(x, z) < 1.0:
			continue
		var deep := Terrain.gloom(x, z) > 0.5
		var length := 10.0 + rand.randf() * 3
		var mat := ShaderMaterial.new()
		mat.shader = load("res://game/render/light_shaft.gdshader")
		mat.set_shader_parameter("uAxis", axis)
		mat.set_shader_parameter("uLength", length)
		mat.set_shader_parameter("uWidth", 1.0 + rand.randf())
		mat.set_shader_parameter("uSeed", rand.randf() * 10)
		mat.set_shader_parameter("uColor", Color(Color("c8e0a0") if deep else Color("ffd08a"), 0.13 + rand.randf() * 0.06))
		var m := Tex.sprite(mat)
		# the origin sits up in the crowns so the shaft lands on (x, z)
		m.position = Vector3(x, Terrain.height_at(x, z), z) - axis * length * 0.95
		# culling uses the quad's own box: give it the shaft's real reach
		var reach := axis * length
		m.custom_aabb = AABB(reach.min(Vector3.ZERO) - Vector3(4, 4, 4), reach.abs() + Vector3(8, 8, 8))
		m.visibility_range_end = 44.0
		m.name = "SunShaft"
		return m
	return null


func update(dt: float, time: float) -> void:
	var focus: Vector3 = game.camera_target
	land.update(focus)
	town.update(dt)
	see_through.update(dt)
	for m in mist:
		var x: float = m.x + MIST_REPEAT * roundf((focus.x - m.x) / MIST_REPEAT) + sin(time * 0.05 + m.seed) * 3
		var z: float = m.z + MIST_REPEAT * roundf((focus.z - m.z) / MIST_REPEAT) + cos(time * 0.04 + m.seed) * 2
		m.mesh.position = Vector3(x, Terrain.height_at(x, z) + m.lift, z)
		m.mesh.rotation.y += dt * 0.01
		var deep := Terrain.gloom(x, z)
		if absf(deep - m.deep) > 0.1:
			m.deep = deep
			m.mat.albedo_color = Color(Color("b8c4c0").lerp(Color("9cb8a8"), deep), 0.22 + 0.06 * deep)
	for f in flames:
		var t: float = time * 9 + f.seed
		var k := 1 + sin(t) * 0.12 + sin(t * 2.3) * 0.08
		if f.flame:
			f.flame.scale = Vector3(1, k, 1)
		f.glow.material_override.albedo_color.a = 0.65 + sin(t * 1.7) * 0.15
	for f in flicker_lights:
		var t: float = time * 7 + f.seed
		f.light.light_energy = f.base * Tex.OMNI_SCALE * (0.82 + sin(t) * 0.06 + sin(t * 2.7) * 0.05 + sin(t * 5.3) * 0.04)

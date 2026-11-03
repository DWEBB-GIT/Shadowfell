class_name World
extends RefCounted
## Builds the world (src/world/world.js): terrain, hand-placed props,
## buildings you can walk into, signposts, scattered woodland, ground cover,
## warm light sources and mist. Registers obstacles with collision and
## examine points with the interaction system.

const Entrance := preload("res://game/world/building_entrance.gd")
const LIGHT_FIXTURE_LAYER := 1 << 19
## Other bodies that move or animate every frame (enemies, NPCs). The
## shadow-casting lamps leave this layer out, so an idling or fighting body
## near a lamp does not make it re-render its shadow map every frame; a
## shadowless twin light lights this layer instead. The player stays off it
## on purpose and keeps a lamp shadow. See Atmosphere.
const MOVING_LAYER := 1 << 18
const MOVING_GROUP := &"moving_body"

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
var see_through: SeeThrough ## houses with the see-through circle


func _init(g) -> void:
	game = g
	group = Node3D.new()
	group.name = "World"


func build() -> World:
	land = Land.new(game, group)
	for p in Layout.props:
		var obj := prop_instance(p)
		budget_prop(obj, str(p.model))
		var x: float = p.position[0]
		var z: float = p.position[1]
		group.add_child(obj)
		_add_collider(p, x, z, obj)
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
	_build_rune_forges()
	_add_lights()
	_add_mist()
	_add_motes()
	_add_fairy_rings()
	return self


## props low enough to jump over: their height in metres (Collision `h`).
## Anything else not listed is measured from its model, and counts as low
## when its top is under JUMPABLE (a crate, a grave, a small rock).
const LOW_PROPS := {"fence": 1.05}
const JUMPABLE := 1.25


## How high a placed prop stands above the ground under it (its meshes'
## bounds, in the prop's own placement), or INF when it has no meshes.
static func prop_height(obj: Node3D, ground: float) -> float:
	var top := -INF
	var stack := [[obj, obj.transform]]
	while stack:
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n is VisualInstance3D:
			top = maxf(top, (xf * (n as VisualInstance3D).get_aabb()).end.y)
		for c in n.get_children():
			if c is Node3D:
				stack.append([c, xf * (c as Node3D).transform])
	return top - ground if top > -INF else INF


## Grass, clover, flowers, ferns and mushrooms: thousands of tiny props whose
## shadows nobody sees. They skip the sun's shadow pass (each one would
## otherwise be drawn again per shadow split) and stop drawing past
## GROUND_COVER_RANGE from the camera (the default view reaches ~67 m).
const GROUND_COVER := ["/nature/grass/", "MeadowGrass", "Flower_", "Fern_", "Mushroom_", "Clover"]
const GROUND_COVER_RANGE := 90.0

static func is_ground_cover(model: String) -> bool:
	for k in GROUND_COVER:
		if model.contains(k):
			return true
	return false


static func budget_prop(obj: Node3D, model: String) -> void:
	if not is_ground_cover(model):
		return
	var meshes: Array = obj.find_children("*", "GeometryInstance3D", true, false)
	if obj is GeometryInstance3D:
		meshes.append(obj)
	for g: GeometryInstance3D in meshes:
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.visibility_range_end = GROUND_COVER_RANGE


## Shared by world construction and authoring round-trip checks.
static func prop_instance(p: Dictionary) -> Node3D:
	var obj := Assets.instance(p.model)
	var x: float = p.position[0]
	var z: float = p.position[1]
	obj.position = Vector3(x, Terrain.height_at(x, z) + p.get("heightOffset", 0.0), z)
	obj.rotation.y = deg_to_rad(p.get("rotation", 0))
	if p.get("tilt"):
		obj.rotation.z = -deg_to_rad(p.tilt)
	if p.get("scale"):
		obj.scale = Vector3.ONE * p.scale
	if p.has("scale3"):
		obj.scale = Vector3(p.scale3[0], p.scale3[1], p.scale3[2])
	if p.has("rotation3"):
		obj.rotation_degrees = Vector3(p.rotation3[0], p.rotation3[1], p.rotation3[2])
	if p.has("tint"):
		Assets.tint_instance(obj, Color(p.tint))
	if str(p.model).get_file().get_basename() in ["lamp_post", "torch"]:
		mark_light_fixture(obj)
	# the nature pack: trees, rocks and plants open a see-through circle
	# around the player instead of hiding them
	if str(p.model).contains("/environment/nature/"):
		Assets.use_cutaway(obj)
	return obj


static func mark_light_fixture(root: Node3D) -> void:
	# A flame must not be enclosed by its own fixture in the local shadow map.
	# The sun still casts the posts' silhouettes; fixture lights skip this layer.
	if root is GeometryInstance3D:
		root.layers = LIGHT_FIXTURE_LAYER
	for mesh in root.find_children("*", "GeometryInstance3D", true, false):
		mesh.layers = LIGHT_FIXTURE_LAYER


func _add_collider(p: Dictionary, x: float, z: float, obj: Node3D = null) -> void:
	var col = p.get("collider")
	# a model with a measured footprint (trees at the trunk, rocks at the
	# base) uses that, whatever the placement says
	var measured = model_collider(str(p.model))
	if measured != null:
		col = measured
	if not col:
		return
	var s: float = p.get("scale", 1.0)
	if p.has("scale3"):
		s = maxf(absf(p.scale3[0]), absf(p.scale3[2]))
	var h: float = LOW_PROPS.get(str(p.get("model", "")).get_file().get_basename(), INF) * s
	if h == INF and obj != null:
		var ph: float = prop_height(obj, Terrain.height_at(x, z))
		if ph <= JUMPABLE:
			h = ph
	if typeof(col) == TYPE_FLOAT or typeof(col) == TYPE_INT:
		game.collision.add(x, z, col * s, false, h)
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
		game.collision.add(x + (c[0] * cos(r) + c[1] * sin(r)) * s, z + (-c[0] * sin(r) + c[1] * cos(r)) * s, c[2] * s, false, h)


static var _model_colliders = null

## the measured footprint of a model, by file name
## (data/world/model_colliders.json), or null
static func model_collider(model: String):
	if _model_colliders == null:
		_model_colliders = {}
		var path := DataPaths.path_for("model_colliders")
		if FileAccess.file_exists(path):
			var d = JSON.parse_string(FileAccess.get_file_as_string(path))
			if d is Dictionary:
				_model_colliders = d.get("models", {})
	return _model_colliders.get(model.get_file().get_basename())


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


## The rune forges (RuneForge, Dan 2026-11-03): an anvil on a dark stone
## plinth with a violet crystal turning over it. The crystal and its glow
## take the rune's colour while it fuses, and flare at the end.
var rune_forges := {} ## station id -> {gem, glow, gem_mat, colour, flare, work}
const RUNE_FORGE_COLOUR := Color("9a6aff")
const REFINING_COLOUR := Color("ffc860")

func _build_rune_forges() -> void:
	for st in Layout.stations:
		if st.kind != RuneForge.KIND and st.kind != Refinery.KIND:
			continue
		# the refining altar's crystal is gold, the rune forge's violet
		var base: Color = REFINING_COLOUR if st.kind == Refinery.KIND else RUNE_FORGE_COLOUR
		var x: float = st.position[0]
		var z: float = st.position[1]
		var root := Node3D.new()
		root.name = "RuneForge"
		root.position = Vector3(x, Terrain.height_at(x, z), z)
		var plinth := _box(Vector3(1.5, 0.9, 1.2), Color("2c2a33"), false)
		plinth.position.y = 0.45
		root.add_child(plinth)
		var lip := _box(Vector3(1.7, 0.14, 1.4), Color("45404f"), false)
		lip.position.y = 0.95
		root.add_child(lip)
		# rune lines cut into the plinth's faces, glowing faintly
		var lines: Array = []
		for side in [-1.0, 1.0]:
			for i in 3:
				var cut := _box(Vector3(0.08, 0.5 - (i % 2) * 0.2, 0.02), base, true)
				cut.position = Vector3(-0.4 + i * 0.4, 0.45, side * 0.61)
				root.add_child(cut)
				lines.append(cut)
				var cut2 := _box(Vector3(0.02, 0.5 - (i % 2) * 0.2, 0.08), base, true)
				cut2.position = Vector3(side * 0.76, 0.45, -0.3 + i * 0.3)
				root.add_child(cut2)
				lines.append(cut2)
		var anvil := Assets.instance("anvil")
		if anvil:
			anvil.position.y = 1.02
			root.add_child(anvil)
		var gem := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.24
		sm.height = 0.8
		sm.radial_segments = 4
		sm.rings = 2
		gem.mesh = sm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = base
		gm.emission_enabled = true
		gm.emission = base
		gm.emission_energy_multiplier = 1.6
		gem.material_override = gm
		gem.position.y = 2.1
		root.add_child(gem)
		var glm := Tex.fx_material(Tex.glint(), Color(base, 0.7), true, true)
		glm.disable_fog = true
		var glow := Tex.sprite(glm)
		glow.scale = Vector3.ONE * 1.2
		glow.position.y = 2.1
		root.add_child(glow)
		group.add_child(root)
		game.collision.add(x, z, 0.75)
		rune_forges[st.id] = {"gem": gem, "glow": glow, "gem_mat": gm, "lines": lines, "colour": base, "base": base, "flare": 0.0, "work": 0.0}


## Tint forge `id` while it works (strength 1), flare it (above 1), or
## settle it back to its own violet (0).
func rune_forge_glow(id: String, colour: Color, strength: float) -> void:
	var f = rune_forges.get(id)
	if f == null:
		return
	if strength <= 0.0:
		f.colour = f.base
		f.work = 0.0
	elif strength <= 1.0:
		f.colour = colour
		f.work = 1.0
	else:
		f.colour = colour
		f.work = 0.0
		f.flare = strength


func _update_rune_forges(dt: float, time: float) -> void:
	for id in rune_forges:
		var f: Dictionary = rune_forges[id]
		var gem: MeshInstance3D = f.gem
		if not gem.is_visible_in_tree():
			continue
		gem.rotation.y += dt * (0.8 + f.work * 5.0 + f.flare * 3.0)
		gem.position.y = 2.1 + sin(time * 1.6) * 0.06 + f.work * 0.2
		var k: float = 1.0 + sin(time * 2.2) * 0.1 + f.work * (0.35 + sin(time * 14.0) * 0.15) + f.flare
		f.glow.scale = Vector3.ONE * 1.2 * k
		f.glow.position.y = gem.position.y
		f.glow.material_override.albedo_color = Color(f.colour, clampf(0.55 + f.work * 0.25 + f.flare * 0.15, 0.0, 1.0))
		f.gem_mat.emission = f.colour
		f.gem_mat.albedo_color = f.colour
		f.gem_mat.emission_energy_multiplier = 1.6 + f.work * 1.5 + f.flare * 2.0
		var lc := Color(f.colour, 0.5 + 0.5 * maxf(f.work, minf(f.flare, 1.0)))
		for l in f.lines:
			l.material_override.albedo_color = lc
		if f.flare > 0.0:
			f.flare = maxf(0.0, f.flare - dt * 2.0)
			if f.flare == 0.0 and f.work == 0.0:
				f.colour = f.base


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
		g.add_child(Entrance.approach(b))
		var fade := []
		for m in [b.front, b.roof]:
			var obj := Entrance.make_front(b) if m == b.front else Assets.instance(m)
			fade.append({"obj": obj, "mats": Rig.isolate_materials(obj)})
			g.add_child(obj)
		if b.get("light") and not ProjectSettings.get_setting("shadowfell/lighting/pooled", true):
			var light := Tex.point_light(Color("ffa050"), 4, 10, 1.4)
			light.position = Vector3(b.light[0], 1.1, b.light[1])
			g.add_child(light)
			flicker_lights.append({"light": light, "base": 4.0, "seed": x})
		group.add_child(g)
		_wall_colliders(x, z, 0, Entrance.walls(b), 0.28, true) # building walls block sight
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


## The town shapes (buildings, houses, pads, boxed props) that reach into a
## rectangle, so a chunk's many samples test a few of them instead of every
## shape in the world (_clear_of_town scans them all).
static func _town_near(x0: float, z0: float, x1: float, z1: float) -> Array:
	var out := [] # [centre x, centre z, half x, half z] or [x, z, radius]
	for list in [Layout.buildings, Layout.houses]:
		for b in list:
			_box_near(out, b.position[0], b.position[1], b.size[0] / 2.0 + 3, b.size[1] / 2.0 + 3, x0, z0, x1, z1)
	for p in Layout.pads:
		var r: float = p[2] + 2
		if p[0] + r > x0 and p[0] - r < x1 and p[1] + r > z0 and p[1] - r < z1:
			out.append([p[0], p[1], r])
	for p in Layout.props:
		var col = p.get("collider")
		if typeof(col) == TYPE_DICTIONARY and col.has("box"):
			_box_near(out, p.position[0], p.position[1], col.box[0] / 2.0 + 3, col.box[1] / 2.0 + 3, x0, z0, x1, z1)
	return out


static func _box_near(out: Array, cx: float, cz: float, hx: float, hz: float, x0: float, z0: float, x1: float, z1: float) -> void:
	if cx + hx > x0 and cx - hx < x1 and cz + hz > z0 and cz - hz < z1:
		out.append([cx, cz, hx, hz])


## _clear_of_town against the shapes _town_near found
static func _clear_of(near: Array, x: float, z: float) -> bool:
	for s in near:
		if s.size() == 4:
			if absf(x - s[0]) < s[2] and absf(z - s[1]) < s[3]:
				return false
		elif U.hyp(x - s[0], z - s[1]) < s[2]:
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


## The see-through circle is for when you are outside and something stands
## between you and the camera. Inside a building (its front and roof already
## lift away) it is switched off: camera and focus at one point cut nothing.
func set_cutaway(camera_pos: Vector3, focus: Vector3) -> void:
	if indoors != null:
		camera_pos = focus
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
		if not l.get("noLight") and not ProjectSettings.get_setting("shadowfell/lighting/pooled", true):
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
			flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			flame.material_override = fm
			flame.position.y = 1.42
			var gm := Tex.fx_material(Tex.glint(), Color(Color("ffa050"), 0.8), true, true)
			gm.disable_fog = true
			var glow := Tex.sprite(gm)
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.scale = Vector3.ONE * 2.2
			glow.position.y = 1.45
			for n in [post, bowl, flame, glow]:
				brazier.add_child(n)
			brazier.position = Vector3(x, Terrain.height_at(x, z), z)
			mark_light_fixture(brazier)
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
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		return
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


func update(dt: float, time: float) -> void:
	var focus: Vector3 = game.camera_target
	land.update(focus)
	town.update(dt)
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
	_update_rune_forges(dt, time)
	for f in flicker_lights:
		var t: float = time * 7 + f.seed
		f.light.light_energy = f.base * Tex.OMNI_SCALE * (0.82 + sin(t) * 0.06 + sin(t * 2.7) * 0.05 + sin(t * 5.3) * 0.04)

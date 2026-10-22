class_name World
extends RefCounted
## Builds the world (src/world/world.js): terrain, hand-placed props,
## buildings you can walk into, signposts, scattered woodland, ground cover,
## warm light sources and mist. Registers obstacles with collision and
## examine points with the interaction system.

const CUTAWAY := preload("res://game/render/cutaway.gdshader")

var game
var group: Node3D
var flicker_lights: Array = []
var flames: Array = []
var mist: Array = []
var examine_points: Array = []
var buildings: Array = []
var indoors = null
var map_trees: Array = []
var cutaway: ShaderMaterial


func _init(g) -> void:
	game = g
	group = Node3D.new()
	group.name = "World"


func build() -> World:
	group.add_child(build_terrain())
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
	_build_signposts()
	_scatter_woodland()
	_scatter_ground_cover()
	_add_lights()
	_add_mist()
	_add_sun_shafts()
	_add_motes()
	_add_fairy_rings()
	return self


## The ground (src/world/terrain.js buildTerrain): a grid following
## height_at, painted per vertex with the same seeded colours, flat shaded.
static func build_terrain() -> MeshInstance3D:
	var b: Dictionary = Layout.bounds
	var width: float = b.maxX - b.minX + 70
	var depth: float = b.maxZ - b.minZ + 70
	var seg_x := int(round(width / 1.25))
	var seg_z := int(round(depth / 1.25))
	var cx: float = (b.minX + b.maxX) / 2.0
	var cz: float = (b.minZ + b.maxZ) / 2.0
	var rand := U.Seeded.new(42)
	var grass := Color("3b4a2c").srgb_to_linear()
	var grass_dark := Color("2a3622").srgb_to_linear()
	var dirt := Color("5a4a36").srgb_to_linear()
	var road_col := Color("6a5c48").srgb_to_linear()
	var bw_floor := Color("1f2419").srgb_to_linear()
	var bw_moss := Color("2a3a22").srgb_to_linear()
	var half_w: float = Layout.road_half_width
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	for iz in seg_z + 1:
		for ix in seg_x + 1:
			var x := cx - width / 2 + ix * width / seg_x
			var z := cz - depth / 2 + iz * depth / seg_z
			pos.append(Vector3(x, Terrain.height_at(x, z), z))
			var d := Terrain.distance_to_road(x, z)
			var c := grass.lerp(grass_dark, rand.next() * 0.7)
			if rand.next() < 0.12:
				c = c.lerp(dirt, 0.5)
			var road_k := 1 - smoothstep(half_w * 0.7, half_w * 1.35, d)
			c = c.lerp(road_col, road_k * (0.75 + rand.next() * 0.25))
			# the Blackwood floor: dark needles and moss
			var bw := Terrain.blackwoodness(z)
			if bw > 0:
				c = c.lerp(bw_moss if rand.next() < 0.3 else bw_floor, bw * 0.75)
			# turned earth around Hallow Cut
			var hc := U.hyp(x - 22.5, z + 19.5)
			if hc < 7:
				c = c.lerp(dirt, (1 - hc / 7) * 0.6)
			# mixed in linear space as three.js does, stored as sRGB (8-bit
			# vertex colours keep dark shades better that way)
			cols.append(c.linear_to_srgb())
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shading
	var w := seg_x + 1
	for iz in seg_z:
		for ix in seg_x:
			var a := iz * w + ix
			var bb := (iz + 1) * w + ix
			var c := (iz + 1) * w + ix + 1
			var d := iz * w + ix + 1
			# three.js faces (a, b, d) and (b, c, d), wound the other way for Godot
			for i in [a, d, bb, bb, d, c]:
				st.set_color(cols[i])
				st.set_uv(Vector2(pos[i].x, pos[i].z) / 6.0)
				st.add_vertex(pos[i])
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.albedo_texture = Tex.ground_detail()
	# (nearest-with-mipmaps samples black on some GL drivers, so the grain is
	# filtered linearly; three.js used nearest close up)
	mat.roughness = 1.0
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	# the ground only receives shadows: casting them drew the whole terrain
	# again in the sun's shadow pass for no visible change
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.mesh = st.commit()
	mesh.material_override = mat
	return mesh


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
	for b in Layout.buildings:
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


## The woodland: every tree, planted, registered with collision and drawn
## in batches, one per model.
func _scatter_woodland() -> void:
	map_trees = [] # for the minimap
	var by_model := {}
	for t in trees():
		if t.get("solid", true):
			game.collision.add(t.x, t.z, 0.45 * t.s)
		map_trees.append(Vector2(t.x, t.z))
		if not by_model.has(t.model):
			by_model[t.model] = []
		by_model[t.model].append(t)
	for m in by_model:
		_instanced(m, by_model[m])


## Every tree as {model, x, z, s (scale), r (turn, radians), solid}: the
## hand-placed list in scenery.json (`trees`) once the World editor has
## saved one, or else the seeded scatter below.
static func trees() -> Array:
	var placed = DB.scenery.get("trees")
	return placed if placed is Array else scattered_trees()


## The woodland, laid out exactly as the browser build lays it (same seeds,
## same draws, same order), so every tree stands where it always has.
static func scattered_trees() -> Array:
	var road: Dictionary = DB.region_by_id("fallen_road").bounds
	var rand := U.Seeded.new(1999)
	var pines := []
	var dead := []
	var pad := 22.0
	var i := 0
	while i < 2600 and pines.size() < 520:
		i += 1
		var x: float = road.minX - pad + rand.next() * (road.maxX - road.minX + pad * 2)
		var z: float = road.minZ - pad + rand.next() * (road.maxZ - road.minZ + pad * 2)
		var inside: bool = x >= road.minX and x <= road.maxX and z >= road.minZ and z <= road.maxZ
		var edge: float = minf(minf(x - road.minX, road.maxX - x), minf(z - road.minZ, road.maxZ - z))
		var to_road := Terrain.distance_to_main_road(x, z)
		if to_road < 4.2:
			continue
		if not _clear(x, z):
			continue
		# sparse inside the play space, dense at and beyond its edge
		var density := 0.85 if not inside else 0.6 if edge < 5 else 0.08 if to_road < 9 else 0.2
		if rand.next() > density:
			continue
		if _crowded(pines, x, z, 3.2 if inside else 2.1):
			continue
		var s := 0.8 + rand.next() * 0.7
		var entry := {"x": x, "z": z, "s": s, "r": rand.next() * TAU, "solid": inside or edge > -3}
		if inside and rand.next() < 0.12:
			dead.append(entry)
		else:
			pines.append(entry)
	# (south of z 49 is Brackenford now, which plants its own)
	var keep := func(t): return t.z > -47 and t.z < 49 and Terrain.distance_to_road(t.x, t.z) >= 3.4
	var road_pines := pines.filter(keep)
	var road_dead := dead.filter(keep)
	for t in road_pines:
		t.model = "pine"
	for t in road_dead:
		t.model = "dead_tree"

	# The Blackwood: black pines, close-set, with the track the only clear way.
	var bw: Dictionary = DB.region_by_id("blackwood").bounds
	var rb := U.Seeded.new(2024)
	var black := []
	var bw_dead := []
	i = 0
	while i < 6000 and black.size() < 900:
		i += 1
		var x: float = bw.minX - pad + rb.next() * (bw.maxX - bw.minX + pad * 2)
		var z: float = bw.minZ - pad + rb.next() * (-47 - bw.minZ + pad)
		var inside: bool = x >= bw.minX and x <= bw.maxX and z >= bw.minZ
		var edge: float = minf(minf(x - bw.minX, bw.maxX - x), z - bw.minZ)
		var to_path := Terrain.distance_to_road(x, z)
		if to_path < 3.4 or not _clear(x, z):
			continue
		var density := 0.85 if not inside else 0.7 if edge < 5 else 0.3 if to_path < 7 else 0.5
		if rb.next() > density:
			continue
		var gap := 2.5 if inside else 2.0
		if _crowded(black, x, z, gap) or _crowded(bw_dead, x, z, gap):
			continue
		var s := 0.85 + rb.next() * 0.6
		var entry := {"x": x, "z": z, "s": s, "r": rb.next() * TAU, "solid": inside or edge > -3}
		if inside and rb.next() < 0.1:
			entry.model = "dead_tree"
			bw_dead.append(entry)
		else:
			entry.model = "black_pine"
			black.append(entry)
	# Brackenford: a few pines about the town and a wood at its edges, never
	# on the road, a pad or a building
	var town: Dictionary = DB.region_by_id("brackenford").bounds
	var rt := U.Seeded.new(1213)
	var town_pines := []
	i = 0
	while i < 2400 and town_pines.size() < 160:
		i += 1
		var x: float = town.minX - pad + rt.next() * (town.maxX - town.minX + pad * 2)
		var z: float = town.minZ + rt.next() * (town.maxZ - town.minZ + pad)
		var inside: bool = x >= town.minX and x <= town.maxX and z <= town.maxZ
		var edge: float = minf(minf(x - town.minX, town.maxX - x), town.maxZ - z)
		if Terrain.distance_to_main_road(x, z) < 4.2 or not _clear(x, z) or not _clear_of_town(x, z):
			continue
		var density := 0.85 if not inside else 0.6 if edge < 5 else 0.06
		if rt.next() > density:
			continue
		if _crowded(town_pines, x, z, 3.2 if inside else 2.1):
			continue
		var s := 0.8 + rt.next() * 0.7
		town_pines.append({"model": "pine", "x": x, "z": z, "s": s, "r": rt.next() * TAU, "solid": inside or edge > -3})
	# in the order each model has always been drawn
	return road_pines + town_pines + road_dead + bw_dead + black


func _instanced(model: String, list: Array) -> void:
	if list.is_empty() or not Assets.has(model):
		return
	var src := Assets.instance(model)
	var meshes := src.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		src.free()
		return
	var mi: MeshInstance3D = meshes[0]
	var mat := _cutaway_material(mi)
	var xfs := []
	for t in list:
		var basis := Basis(Vector3.UP, t.r).scaled(Vector3.ONE * t.s)
		xfs.append(Transform3D(basis, Vector3(t.x, Terrain.height_at(t.x, t.z) - 0.1, t.z)))
	for cell in _cells(xfs):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = cell.size()
		for i in cell.size():
			mm.set_instance_transform(i, xfs[cell[i]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.name = "Woodland_" + model
		mmi.material_override = mat
		group.add_child(mmi)
	src.free()


## Instances grouped into square cells of the map, as lists of indices. A
## MultiMesh is culled as one box, so one for the whole world was drawn (and
## shadowed) in full every frame; one per cell lets the camera and the sun's
## shadow skip everything out of view.
const CELL := 24.0


static func _cells(xfs: Array) -> Array:
	var cells := {}
	for i in xfs.size():
		var o: Vector3 = xfs[i].origin
		var key := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(i)
	return cells.values()


## Trees between the camera and the player are dissolved with a dither
## pattern (render/cutaway.gdshader). One material per tree model, sharing
## the camera and focus points.
func _cutaway_material(mi: MeshInstance3D) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CUTAWAY
	var base := mi.get_active_material(0)
	m.set_shader_parameter("albedo", base.albedo_color if base is BaseMaterial3D else Color.WHITE)
	if cutaway == null:
		cutaway = m
	m.set_meta("cutaway", true)
	_cutaways.append(m)
	return m


var _cutaways: Array = []


func set_cutaway(camera_pos: Vector3, focus: Vector3) -> void:
	for m in _cutaways:
		m.set_shader_parameter("uCamPos", camera_pos)
		m.set_shader_parameter("uFocus", focus)


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


## low-poly grass tufts: three crossed blades per tuft
func _scatter_ground_cover() -> void:
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
	var blade := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("4a5a32")
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	var b: Dictionary = Layout.bounds
	var rand := U.Seeded.new(77)
	var count := U.jround(3600 * ((b.maxZ - b.minZ + 12) / 184.0)) # the same density as the first map
	var xfs := []
	var cols := []
	var n := 0
	var i := 0
	while i < count * 3 and n < count:
		i += 1
		var x: float = b.minX - 6 + rand.next() * (b.maxX - b.minX + 12)
		var z: float = b.minZ - 6 + rand.next() * (b.maxZ - b.minZ + 12)
		var road := Terrain.distance_to_road(x, z)
		if road < 1.6 and rand.next() > 0.15:
			continue # a few tufts break through the road
		var on_floor := false
		for bd in buildings:
			if x > bd.minX - 0.3 and x < bd.maxX + 0.3 and z > bd.minZ - 0.3 and z < bd.maxZ + 0.3:
				on_floor = true
		if on_floor:
			continue # not through a floor
		var rot := rand.next() * PI
		var s := 0.6 + rand.next() * 0.9
		var sy := s * (0.7 + rand.next() * 0.8)
		xfs.append(Transform3D(Basis(Vector3.UP, rot).scaled(Vector3(s, sy, s)), Vector3(x, Terrain.height_at(x, z) - 0.02, z)))
		var hue := 0.2 + rand.next() * 0.06
		var sat := 0.25 + rand.next() * 0.15
		# lighter than the browser build's, which read as black specks here
		var lig := (0.34 + rand.next() * 0.16) * (1 - 0.4 * Terrain.blackwoodness(z))
		# the tint multiplies the base colour, as three.js instance colours do
		cols.append(_hsl(hue, sat, lig))
		n += 1
	for cell in _cells(xfs):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = blade
		mm.instance_count = cell.size()
		for k in cell.size():
			mm.set_instance_transform(k, xfs[cell[k]])
			mm.set_instance_color(k, cols[cell[k]])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.name = "GroundCover"
		# grass is only worth drawing near the player: cells past the fog go
		# (visibility ranges are per instance, so they cull per local camera)
		mmi.visibility_range_end = 36.0
		mmi.visibility_range_end_margin = 4.0
		group.add_child(mmi)


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


## Low drifting mist: a few large soft layers just above the ground. The
## fog thickens them with distance, which sells the depth.
func _add_mist() -> void:
	for i in 14:
		var x := -30.0 + ((i * 37) % 60)
		var z := 40.0 - i * 11.5
		var deep := z < -52 # the Blackwood's mist lies thicker and greener
		var mat := Tex.fx_material(Tex.mist(), Color(Color("9cb8a8") if deep else Color("b8c4c0"), 0.28 if deep else 0.22), false)
		mat.render_priority = 1
		var m := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(30, 30)
		m.mesh = pm
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.rotation.y = i * 1.3
		m.position = Vector3(x, Terrain.height_at(x, z) + 0.5 + (i % 3) * 0.25, z)
		m.name = "Mist"
		group.add_child(m)
		mist.append({"mesh": m, "x": x, "z": z, "seed": i * 2.1})


## Sun shafts where the low sun pokes through the canopy: only between trees
## that stand close together (a gap in a thick crown), a few per wood and
## well apart, never over open ground. Cheap additive ribbons (see
## light_shaft.gdshader), only drawn near the camera. In the Blackwood the
## light is thinner and greener.
const SHAFT_AXIS := Vector3(14, -26, -6) ## the sun's travel, as Game._place_sun aims it
const SHAFT_CANOPY := 4 ## trees within SHAFT_NEAR of a gap for it to count as canopy
const SHAFT_NEAR := 6.0
const SHAFT_GAP := 22.0 ## metres between shafts
const SHAFT_MAX := 28

func _add_sun_shafts() -> void:
	var shader: Shader = load("res://game/render/light_shaft.gdshader")
	var axis := SHAFT_AXIS.normalized()
	var rand := U.Seeded.new(313)
	# the trees in 6 m cells, to count neighbours cheaply
	var cells := {}
	var all := trees()
	for t in all:
		var key := Vector2i(floori(t.x / SHAFT_NEAR), floori(t.z / SHAFT_NEAR))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(t)
	var near := func(x: float, z: float) -> Array:
		var out := []
		var cx := floori(x / SHAFT_NEAR)
		var cz := floori(z / SHAFT_NEAR)
		for i in range(-1, 2):
			for j in range(-1, 2):
				for t in cells.get(Vector2i(cx + i, cz + j), []):
					if U.hyp(t.x - x, t.z - z) < SHAFT_NEAR:
						out.append(t)
		return out
	var placed := []
	for t in all:
		if placed.size() >= SHAFT_MAX:
			break
		if not t.get("solid", true) or rand.next() > 0.35:
			continue
		var around: Array = near.call(t.x, t.z)
		if around.size() < SHAFT_CANOPY + 1:
			continue
		# the light falls in the gap between this tree and a neighbour
		var o: Dictionary = around[int(rand.next() * around.size())]
		if o == t:
			continue
		var x: float = (t.x + o.x) / 2.0
		var z: float = (t.z + o.z) / 2.0
		if U.hyp(t.x - o.x, t.z - o.z) < 2.5 or _crowded(placed, x, z, SHAFT_GAP):
			continue
		placed.append({"x": x, "z": z})
		var deep := Terrain.blackwoodness(z) > 0.5
		var length := 10.0 + rand.next() * 3
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("uAxis", axis)
		mat.set_shader_parameter("uLength", length)
		mat.set_shader_parameter("uWidth", 1.0 + rand.next() * 1.0)
		mat.set_shader_parameter("uSeed", rand.next() * 10)
		mat.set_shader_parameter("uColor", Color(Color("c8e0a0") if deep else Color("ffd08a"), 0.13 + rand.next() * 0.06))
		var m := Tex.sprite(mat)
		# the origin sits up in the crowns so the shaft lands on (x, z)
		m.position = Vector3(x, Terrain.height_at(x, z), z) - axis * length * 0.95
		# culling uses the quad's own box: give it the shaft's real reach
		var reach := axis * length
		m.custom_aabb = AABB(reach.min(Vector3.ZERO) - Vector3(4, 4, 4), reach.abs() + Vector3(8, 8, 8))
		m.visibility_range_end = 44.0
		m.name = "SunShaft"
		group.add_child(m)


func update(dt: float, time: float) -> void:
	for m in mist:
		m.mesh.position.x = m.x + sin(time * 0.05 + m.seed) * 3
		m.mesh.position.z = m.z + cos(time * 0.04 + m.seed) * 2
		m.mesh.rotation.y += dt * 0.01
	for f in flames:
		var t: float = time * 9 + f.seed
		var k := 1 + sin(t) * 0.12 + sin(t * 2.3) * 0.08
		if f.flame:
			f.flame.scale = Vector3(1, k, 1)
		f.glow.material_override.albedo_color.a = 0.65 + sin(t * 1.7) * 0.15
	for f in flicker_lights:
		var t: float = time * 7 + f.seed
		f.light.light_energy = f.base * Tex.OMNI_SCALE * (0.82 + sin(t) * 0.06 + sin(t * 2.7) * 0.05 + sin(t * 5.3) * 0.04)

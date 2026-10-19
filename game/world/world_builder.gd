@tool
class_name WorldBuilder
extends Node3D
## Builds the Fallen Road from data/world.json and data/scenery.json: terrain,
## roads, ponds, props, buildings, townsfolk, enemies, loot, chests, lights and
## the woodland. It runs in the editor too, so the world shows in the 3D view.
## Press "Rebuild from data" in the Inspector after changing a data file.
##
## Everything built goes under a "Generated" child that is never saved into
## the scene: the data files stay the one place the world is described.

const MODELS := "res://assets/models/%s.glb"

@export_tool_button("Rebuild from data") var rebuild_button = rebuild
@export var build_woodland := true

var _root: Node3D
var _mesh_cache := {}


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	var data := _data()
	data.load_all()
	if _root:
		_root.free()
	_root = Node3D.new()
	_root.name = "Generated"
	add_child(_root)
	var world: Dictionary = data.files.world
	var scenery: Dictionary = data.files.scenery
	Terrain.setup(world)
	_build_terrain(world)
	_build_water(world)
	for p in scenery.props:
		var node := _place(p.model, p.position, p.get("rotation", 0.0), "props")
		var s: float = p.get("scale", 1.0)
		node.scale = Vector3.ONE * s
		if p.has("tilt"):
			node.rotate_object_local(Vector3.BACK, deg_to_rad(-p.tilt))
		_collider(p.position, p.get("rotation", 0.0), p.get("collider", 0), s)
	for b in world.get("buildings", []):
		for part in ["shell", "front", "roof"]:
			if b.has(part):
				_place(b[part], b.position, b.get("rotation", 0.0), "buildings")
	for s in world.npcSpawns:
		var npc: Dictionary = data.get_record("npcs", s.npc)
		var node := _place(npc.get("model", s.npc), s.position, s.get("facing", 0.0), "townsfolk")
		node.name = s.npc
		_label(node, npc.get("name", s.npc), Color("e8d9a8"))
		_collider(s.position, 0.0, 0.5)
	for s in world.enemySpawns:
		var enemy: Dictionary = data.get_record("enemies", s.enemy)
		var node := _place(enemy.get("model", s.enemy), s.position, randf_range(0.0, 360.0), "enemies")
		node.name = s.id
		if enemy.has("scale"):
			node.scale = Vector3.ONE * enemy.scale
		_label(node, "%s (%d)" % [enemy.get("name", s.enemy), enemy.get("level", 1)], Color("e0705a"))
	for l in world.placedLoot:
		var node := _place(l.get("model", "crate"), l.position, l.get("rotation", 0.0), "loot")
		node.name = l.id
		if l.has("scale"):
			node.scale = Vector3.ONE * l.scale
	for c in world.get("chests", []):
		_place("chest", c.position, c.get("facing", 0.0), "loot").name = c.id
	for s in world.get("signposts", []):
		_place("signpost", s.position, 0.0, "props").name = s.id
	for s in world.shrines:
		_place("shrine", s.position, s.get("rotation", 0.0), "props").name = s.id
	_build_lights(scenery)
	if build_woodland:
		_build_woodland(world, scenery)
	if data.get_parent() == null:
		data.free()


func _data() -> Node:
	# GameData is an autoload in the game; in the editor make a private copy
	if not Engine.is_editor_hint() and is_inside_tree() and has_node("/root/GameData"):
		return get_node("/root/GameData")
	return preload("res://game/autoload/game_data.gd").new()


func _group(name: String) -> Node3D:
	if _root.has_node(name):
		return _root.get_node(name)
	var g := Node3D.new()
	g.name = name
	_root.add_child(g)
	return g


## A model from assets/models at [x, z], standing on the ground, turned by
## degrees. A model with no .glb yet shows as a grey box so it is not lost.
func _place(model: String, pos: Array, degrees: float, group: String) -> Node3D:
	var node: Node3D
	var path := MODELS % model
	if ResourceLoader.exists(path):
		node = load(path).instantiate()
	else:
		node = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.8, 1.2, 0.8)
		node.mesh = box
		node.position.y = 0.6
		var holder := Node3D.new()
		holder.add_child(node)
		node = holder
	node.name = model
	node.position = Vector3(pos[0], Terrain.height_at(pos[0], pos[1]), pos[1])
	node.rotation.y = deg_to_rad(degrees)
	_group(group).add_child(node)
	return node


func _label(node: Node3D, text: String, colour: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = colour
	label.outline_size = 6
	label.font_size = 28
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.3
	node.add_child(label)


## Ground the player cannot walk through (scenery.json `collider`): a radius,
## a list of [x, z, radius] circles in the prop's own space, or {box: [w, d]}.
func _collider(pos: Array, degrees: float, collider, s := 1.0) -> void:
	var circles := []
	if typeof(collider) == TYPE_ARRAY:
		circles = collider
	elif typeof(collider) != TYPE_DICTIONARY and collider and collider > 0:
		circles = [[0, 0, collider * s]]
	var body := StaticBody3D.new()
	body.position = Vector3(pos[0], Terrain.height_at(pos[0], pos[1]), pos[1])
	body.rotation.y = deg_to_rad(degrees)
	if typeof(collider) == TYPE_DICTIONARY and collider.has("box"):
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(collider.box[0] * s, 4.0, collider.box[1] * s)
		shape.shape = box
		shape.position.y = 1.0
		body.add_child(shape)
	elif circles.is_empty():
		body.free()
		return
	for c in circles:
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = c[2]
		cyl.height = 4.0
		shape.shape = cyl
		shape.position = Vector3(c[0], 1.0, c[1])
		body.add_child(shape)
	_group("colliders").add_child(body)


func _build_terrain(world: Dictionary) -> void:
	var b: Dictionary = world.bounds
	var min_x: float = b.minX - 35.0
	var max_x: float = b.maxX + 35.0
	var min_z: float = b.minZ - 35.0
	var max_z: float = b.maxZ + 35.0
	var step := 1.25
	var nx := int((max_x - min_x) / step)
	var nz := int((max_z - min_z) / step)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var grass := Color("3b4a2c")
	var grass_dark := Color("2a3622")
	var dirt := Color("5a4a36")
	var road_col := Color("6a5c48")
	var bw_floor := Color("1f2419")
	var bw_moss := Color("2a3a22")
	var half_w: float = Terrain._road_half_width
	# one height and colour per grid point
	var heights := PackedFloat32Array()
	var colours := PackedColorArray()
	for j in nz + 1:
		for i in nx + 1:
			var x := min_x + i * step
			var z := min_z + j * step
			heights.append(Terrain.height_at(x, z))
			var c := grass.lerp(grass_dark, rng.randf() * 0.7)
			if rng.randf() < 0.12:
				c = c.lerp(dirt, 0.5)
			var road_k := 1.0 - smoothstep(half_w * 0.7, half_w * 1.35, Terrain.distance_to_road(x, z))
			c = c.lerp(road_col, road_k * (0.75 + rng.randf() * 0.25))
			var bw := Terrain.blackwoodness(z)
			if bw > 0.0:
				c = c.lerp(bw_moss if rng.randf() < 0.3 else bw_floor, bw * 0.75)
			var hc := Vector2(x - 22.5, z + 19.5).length()
			if hc < 7.0:
				c = c.lerp(dirt, (1.0 - hc / 7.0) * 0.6)
			colours.append(c)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shading, like the browser build
	var w := nx + 1
	for j in nz:
		for i in nx:
			var quad := [j * w + i, j * w + i + 1, (j + 1) * w + i + 1, (j + 1) * w + i]
			for k in [0, 1, 2, 0, 2, 3]:
				var idx: int = quad[k]
				var gx := idx % w
				var gz := idx / w
				st.set_color(colours[idx])
				st.set_uv(Vector2(min_x + gx * step, min_z + gz * step) / 6.0)
				st.add_vertex(Vector3(min_x + gx * step, heights[idx], min_z + gz * step))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	var mesh := MeshInstance3D.new()
	mesh.name = "Terrain"
	mesh.mesh = st.commit()
	mesh.material_override = mat
	_root.add_child(mesh)


func _build_water(world: Dictionary) -> void:
	for w in world.get("water", []):
		var disc := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = w.radius
		cyl.bottom_radius = w.radius
		cyl.height = 0.02
		disc.mesh = cyl
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.17, 0.2, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.metallic = 0.3
		mat.roughness = 0.15
		disc.material_override = mat
		disc.position = Vector3(w.position[0], Terrain.water_level(w), w.position[1])
		disc.name = w.id
		_group("water").add_child(disc)


func _build_lights(scenery: Dictionary) -> void:
	for l in scenery.get("lights", []):
		var light := OmniLight3D.new()
		light.light_color = Color("ffb35c")
		light.light_energy = l.get("intensity", 4.0) * 0.25
		light.omni_range = l.get("distance", 8.0)
		light.position = Vector3(l.position[0], Terrain.height_at(l.position[0], l.position[1]) + l.get("height", 1.0), l.position[1])
		_group("lights").add_child(light)
	for wl in scenery.get("witchlights", []):
		var light := OmniLight3D.new()
		light.light_color = Color("7dffb0")
		light.light_energy = 1.2
		light.omni_range = 6.0
		light.position = Vector3(wl[0], Terrain.height_at(wl[0], wl[1]) + 1.5, wl[1])
		_group("lights").add_child(light)


# The woodland: pines along the road, black pines in the Blackwood and a wood
# around Brackenford, kept off roads and clearings. Seeded, so it is the same
# every time. Drawn as one MultiMesh per tree model.
func _build_woodland(world: Dictionary, scenery: Dictionary) -> void:
	var regions := {}
	for r in world.regions:
		regions[r.id] = r.bounds
	var clearings: Array = scenery.clearings
	var pads: Array = world.get("pads", [])
	var trees := {"pine": [], "dead_tree": [], "black_pine": []}
	var placed := {} # trees so far, by 4 m grid cell
	var plans := [
		{"region": "fallen_road", "seed": 1999, "tries": 2600, "max": 520, "model": "pine", "gap_in": 3.2, "gap_out": 2.1, "road": 4.2, "dense": [0.85, 0.6, 0.08, 0.2], "z": [-47.0, 49.0]},
		{"region": "blackwood", "seed": 2024, "tries": 6000, "max": 900, "model": "black_pine", "gap_in": 2.5, "gap_out": 2.0, "road": 3.4, "dense": [0.85, 0.7, 0.3, 0.5], "z": [-INF, -47.0]},
		{"region": "brackenford", "seed": 1213, "tries": 2400, "max": 160, "model": "pine", "gap_in": 3.2, "gap_out": 2.1, "road": 4.2, "dense": [0.85, 0.6, 0.06, 0.06], "z": [49.0, INF]},
	]
	var pad := 22.0
	for plan in plans:
		var b: Dictionary = regions[plan.region]
		var rng := RandomNumberGenerator.new()
		rng.seed = plan.seed
		var count := 0
		for t in plan.tries:
			if count >= plan.max:
				break
			var x := rng.randf_range(b.minX - pad, b.maxX + pad)
			var z := rng.randf_range(b.minZ - pad, b.maxZ + pad)
			if z < plan.z[0] or z > plan.z[1]:
				continue
			var inside: bool = x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ
			var edge: float = minf(minf(x - b.minX, b.maxX - x), minf(z - b.minZ, b.maxZ - z))
			var to_road := Terrain.distance_to_road(x, z)
			if to_road < plan.road or not _clear(x, z, clearings, pads):
				continue
			var density: float = plan.dense[0] if not inside else plan.dense[1] if edge < 5.0 else plan.dense[2] if to_road < 9.0 else plan.dense[3]
			if rng.randf() > density:
				continue
			var gap: float = plan.gap_in if inside else plan.gap_out
			if _crowded(placed, x, z, gap):
				continue
			var cell := Vector2i(floori(x / 4.0), floori(z / 4.0))
			if not placed.has(cell):
				placed[cell] = []
			placed[cell].append(Vector2(x, z))
			var s := rng.randf_range(0.8, 1.5)
			var model: String = "dead_tree" if inside and rng.randf() < 0.1 else plan.model
			trees[model].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, Terrain.height_at(x, z) - 0.1, z)))
			count += 1
			if inside or edge > -3.0:
				_collider([x, z], 0.0, 0.45 * s)
	for model in trees:
		_multimesh(model, trees[model])


func _crowded(placed: Dictionary, x: float, z: float, gap: float) -> bool:
	var cx := floori(x / 4.0)
	var cz := floori(z / 4.0)
	for i in range(cx - 1, cx + 2):
		for j in range(cz - 1, cz + 2):
			for p in placed.get(Vector2i(i, j), []):
				if p.distance_to(Vector2(x, z)) < gap:
					return true
	return false


func _clear(x: float, z: float, clearings: Array, pads: Array) -> bool:
	for c in clearings:
		if Vector2(x - c[0], z - c[1]).length() < c[2]:
			return false
	for p in pads:
		if Vector2(x - p[0], z - p[1]).length() < p[2] + 2.0:
			return false
	return true


func _multimesh(model: String, transforms: Array) -> void:
	if transforms.is_empty() or not ResourceLoader.exists(MODELS % model):
		return
	var src: Node = load(MODELS % model).instantiate()
	var meshes := src.find_children("*", "MeshInstance3D", true, false)
	for m: MeshInstance3D in meshes:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = m.mesh
		mm.instance_count = transforms.size()
		var local := _local_to(src, m)
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "%s_%s" % [model, m.name]
		mmi.multimesh = mm
		_group("woodland").add_child(mmi)
	src.free()


func _local_to(root: Node, node: Node3D) -> Transform3D:
	var t := node.transform
	var p := node.get_parent()
	while p and p != root:
		if p is Node3D:
			t = p.transform * t
		p = p.get_parent()
	return t

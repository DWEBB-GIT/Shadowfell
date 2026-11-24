@tool
extends RefCounted
## Walkable ground-floor variants for the Coast's existing modular building kit.

const KIT := preload("building_kit.gd")
const PROFILES := {
	"wooden_hut": Vector4(11.8, 8.0, 4.0, 2.42),
	"counting_house": Vector4(13.8, 11.2, 4.7, 2.55),
	"bellharbor_inn": Vector4(19.4, 12.0, 5.1, 2.85),
	"chapel": Vector4(12.8, 17.0, 5.2, 2.70),
	"round_watchtower": Vector4(8.4, 8.4, 4.3, 2.25),
}
const INNS := {
	"Oatwick Cookhouse":"oat",
	"The Brass Bell Inn":"bell", "Gloamwood Lamp Cottage":"gloam", "Coppervein Lamp House":"flint",
	"Reedmire Ferry Lodge":"reed", "Ironstep Tollkeepers Lodge":"iron", "Ashcourt Lamplighters House":"ash",
	"Tidemark Salvage House":"tide", "Redgate Commons Inn":"gate", "Redwash Caravan House":"red",
	"Cinder March Shift House":"cinder", "Whitehorn Shelter":"white", "Saltglass Wellkeepers Hall":"salt",
	"Starfall Sailors Bunkhouse":"star",
}
const WALL := 0.25
const DOOR_HEIGHT := 3.05
const APRON := 4.0
const PAD_MARGIN := 0.55
const STYLES := {
	"Original": ["b5a080", "775942", "8b8479", "46525e"],
	"Weathered Oak": ["959480", "625646", "777c72", "4a5147"],
	"Ochre": ["d3ae79", "825841", "ad9476", "805442"],
	"Winter Slate": ["adb1aa", "65594e", "8e989c", "70848e"],
}
const TEXTURES := ["bellharbor_inn_lime_plaster.png", "bellharbor_inn_oak.png",
	"bellharbor_inn_river_stone.png", "bellharbor_inn_blue_slate.png"]
const SIGN := "inn_parts/bell_sign.glb"
const LANTERN := "inn_parts/lantern.glb"
const CHIMNEY := "inn_parts/chimney.glb"
const CHAPEL_WINDOW := "parts/chapel_window.glb"
static var materials := {}


static func profile(prop: Dictionary) -> Vector4:
	return PROFILES.get(KIT.key(str(prop.get("model", ""))), Vector4.ZERO)


static func supported(prop: Dictionary) -> bool:
	return not prop.get("solidOnly", false) and profile(prop) != Vector4.ZERO


static func site(land: Node3D, prop: Dictionary) -> Dictionary:
	var dimensions := profile(prop)
	var size: Array = prop.get("scale3", [prop.get("scale", 1.0), prop.get("scale", 1.0), prop.get("scale", 1.0)])
	var center := Vector2(prop.position[0], prop.position[1])
	var yaw := deg_to_rad(float(prop.get("rotation", 0.0)))
	var x_scale := maxf(float(size[0]), 0.98)
	var z_scale := maxf(float(size[2]), 0.98)
	var hx := dimensions.x * 0.5 * x_scale
	var hz := dimensions.y * 0.5 * z_scale
	var aperture := dimensions.w * 0.5 * x_scale
	var belt := Rect2(Vector2(-hx, -hz) - Vector2.ONE * PAD_MARGIN,
		Vector2(hx, hz) * 2.0 + Vector2.ONE * PAD_MARGIN * 2.0)
	var route := Rect2(Vector2(-aperture - 0.55, hz - 0.05), Vector2(aperture * 2.0 + 1.1, APRON + 0.05))
	var height: float = land.floor_height(center)
	for x in samples(-hx, hx, 1.5):
		for z in samples(-hz, hz, 1.5):
			height = maxf(height, land.floor_height(center + Vector2(x, z).rotated(-yaw)))
	var top := float(maxf(height + 0.08, prop.get("worldY", height)))
	var reference_ground: float = land.floor_height(center + Vector2(0, hz + APRON).rotated(-yaw))
	var name: String = str(prop.get("label", ""))
	if name.is_empty():
		name = KIT.key(prop.model).replace("_", " ").capitalize()
	var is_inn := INNS.has(name) or KIT.key(str(prop.model)) == "bellharbor_inn"
	return {"def":{"id":name.to_snake_case(), "name":name, "rest":is_inn}, "prop":prop,
		"center":center, "yaw":yaw, "floor":top, "ground":reference_ground,
		"size":Vector4(hx * 2.0, hz * 2.0, dimensions.z * maxf(float(size[1]), 1.0), aperture * 2.0),
		"floor_area":belt, "approach":route, "visual":null, "inside":0.0}


static func samples(from: float, to: float, spacing: float) -> PackedFloat32Array:
	var count := maxi(1, ceili((to - from) / spacing))
	var result := PackedFloat32Array()
	for i in range(count + 1):
		result.append(lerpf(from, to, float(i) / count))
	return result


static func local(s: Dictionary, point: Vector2) -> Vector2:
	return (point - (s.center as Vector2)).rotated(s.yaw)


static func to_world(s: Dictionary, point: Vector2) -> Vector2:
	return (s.center as Vector2) + point.rotated(-s.yaw)


static func exterior(s: Dictionary) -> Vector2:
	return to_world(s, Vector2(0, s.size.y * 0.5 + APRON + 0.45))


static func inside(s: Dictionary, point: Vector2) -> bool:
	return Rect2(-Vector2(s.size.x, s.size.y) * 0.5, Vector2(s.size.x, s.size.y)).grow(-0.12).has_point(local(s, point))


static func walls(size: Vector4) -> Array:
	var h := Vector2(size.x, size.y) * 0.5
	var jamb := (size.x - size.w) * 0.5
	var offset := size.w * 0.5 + jamb * 0.5
	return [[-offset, h.y, jamb, WALL], [offset, h.y, jamb, WALL],
		[0.0, -h.y, size.x, WALL], [-h.x, 0.0, WALL, size.y], [h.x, 0.0, WALL, size.y]]


static func furniture(s: Dictionary) -> Array:
	var key := KIT.key(str(s.prop.model))
	var hx: float = s.size.x * 0.5
	var hz: float = s.size.y * 0.5
	if key == "chapel":
		var seats := [[0.0, -hz + 1.45, 2.6, 0.92, 1.0]]
		for x in [-hx * 0.51, hx * 0.51]:
			for z in [-hz * 0.39, 0, hz * 0.39]:
				seats.append([x, z, 2.50, 0.52, 0.55])
		return seats
	var pieces := [[-hx + 1.7, -hz + 1.36, 2.65, 0.85, 1.10], [hx - 0.85, -hz + 2.5, 0.52, 2.18, 0.55]]
	if s.def.get("rest", false):
		pieces.append([0.0, -hz + 0.51, 2.25, 0.84, 1.2])
	if key == "bellharbor_inn":
		for x in [-hx * 0.5, hx * 0.5]:
			pieces.append([x, 0.0, 2.55, 0.91, 0.83])
			pieces.append([x, 0.9, 2.35, 0.52, 0.55])
	return pieces


static func preview(prop: Dictionary) -> Node3D:
	var stub := {"size":profile(prop), "def":{"name":prop.get("label", "")}, "prop":prop, "floor":0.0, "ground":0.0}
	return _assemble(stub, false)


static func instantiate_site(record: Dictionary) -> Node3D:
	var root := _assemble(record, true)
	root.position = Vector3(record.center.x, record.floor, record.center.y)
	root.rotation.y = record.yaw
	record.fade = {}
	for name in ["Roof", "Street", "Rear", "West", "East"]:
		var part := root.get_node(name)
		record.fade[name] = {"obj":part, "mats":Rig.isolate_materials(part), "opacity":1.0}
	return root


static func _assemble(s: Dictionary, runtime: bool) -> Node3D:
	var key := KIT.key(str(s.prop.model))
	var style: String = s.prop.get("finish", "Original")
	var size: Vector4 = s.size
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	var h := size.z
	var root := Node3D.new()
	root.name = "SettlementBuilding"
	var roof := _group(root, "Roof")
	var interior := _group(root, "Interior")
	var faces := [_group(root, "Street"), _group(root, "Rear"), _group(root, "West"), _group(root, "East")]
	var stone := _finish(style, 2)
	var oak := _finish(style, 1)
	var wall := _finish(style, 2 if key in ["chapel", "round_watchtower"] else 0)
	var roof_material := _finish(style, 3)
	var glass := _glass()
	var depth: float = clampf(s.floor - s.ground + 0.65, 0.65, 3.5)
	_box(root, Vector3(0, -depth * 0.5 - 0.04, 0), Vector3(size.x + 0.3, depth, size.y + 0.3), stone)
	_box(root, Vector3(0, -0.045, 0), Vector3(size.x + 0.21, 0.09, size.y + 0.21), stone if key in ["chapel", "round_watchtower"] else oak)
	if runtime:
		_add_floor_ray(root, size)
		_ramp(root, hz, size.w + 1.1, s.ground - s.floor, stone)
	var jamb := (size.x - size.w) * 0.5
	for direction in [-1.0, 1.0]:
		var x: float = direction * (size.w * 0.5 + jamb * 0.5)
		_panel(faces[0], Vector3(x, 0, hz), jamb, h, 0.0, wall, oak, glass)
		_box(faces[0], Vector3(direction * (size.w * 0.5 + 0.11), DOOR_HEIGHT * 0.5, hz + 0.10),
			Vector3(0.22, DOOR_HEIGHT, 0.46), stone if key == "chapel" else oak)
	_box(faces[0], Vector3(0, (DOOR_HEIGHT + h) * 0.5, hz), Vector3(size.w, h - DOOR_HEIGHT, WALL), wall)
	_box(faces[0], Vector3(0, DOOR_HEIGHT + 0.13, hz + 0.137), Vector3(size.w + 0.45, 0.26, 0.51), stone if key == "chapel" else oak)
	_panel(faces[1], Vector3(0, 0, -hz), size.x, h, PI, wall, oak, glass)
	_panel(faces[2], Vector3(-hx, 0, 0), size.y, h, -PI * 0.5, wall, oak, glass)
	_panel(faces[3], Vector3(hx, 0, 0), size.y, h, PI * 0.5, wall, oak, glass)
	if key == "round_watchtower":
		_round(roof, Vector3(0, h + 1.5, 0), hx * 0.94, hx * 0.94, 3.0, stone)
		_round(roof, Vector3(0, h + 3.65, 0), hx * 1.05, 0.0, 2.4, roof_material)
	else:
		var rise := minf(hx * 0.54, 3.35)
		var slope := atan2(rise, hx)
		for side in [-1.0, 1.0]:
			var leaf := _box(roof, Vector3(side * hx * 0.5, h + rise * 0.5, 0),
				Vector3(hx / cos(slope) + 0.75, 0.25, size.y + 1.26), roof_material)
			leaf.rotation.z = -side * slope
			for z in [-hz - 0.61, hz + 0.61]:
				var trim := _box(roof, Vector3(side * hx * 0.5, h + rise * 0.5, z), Vector3(hx / cos(slope) + 0.77, 0.33, 0.17), oak)
				trim.rotation.z = -side * slope
		_gables(roof, hx, hz, h, rise, wall)
		_box(roof, Vector3(0, h + rise + 0.12, 0), Vector3(0.25, 0.26, size.y + 1.13), oak)
		if key == "chapel":
			_round(roof, Vector3(0, h + rise + 0.54, -hz * 0.53), 0.82, 0.76, 1.78, stone)
			_round(roof, Vector3(0, h + rise + 2.0, -hz * 0.53), 0.89, 0.0, 1.33, roof_material)
			_part(roof, CHAPEL_WINDOW, Vector3(0, h + 0.74, hz + 0.17), 0.0, 0.7)
		else:
			_part(roof, CHIMNEY, Vector3(hx * 0.59, h + rise * 0.33, -hz * 0.34), 0.0, 1.08)
		if key == "bellharbor_inn":
			_part(roof, "inn_parts/dormer.glb", Vector3(hx * 0.50, h + rise * 0.43, hz * 0.48), PI * 0.5, 1.19)
			_part(roof, "inn_parts/dormer.glb", Vector3(-hx * 0.49, h + rise * 0.43, -hz * 0.28), -PI * 0.5, 1.19)
	if key == "bellharbor_inn":
		_part(faces[0], SIGN, Vector3(-size.w * 0.5 - 0.47, h - 0.7, hz + 0.12))
		_part(faces[0], "inn_parts/ivy_strip.glb", Vector3(hx * 0.85, 0.015, hz + 0.23), 0.0, 1.25)
		var awning := _box(faces[0], Vector3(0, DOOR_HEIGHT + 0.53, hz + 0.85), Vector3(size.w + 1.4, 0.19, 1.75), roof_material)
		awning.rotation.x = 0.17
		for side in [-1.0, 1.0]:
			var brace := _box(faces[0], Vector3(side * (size.w * 0.5 + 0.42), 2.92, hz + 0.53), Vector3(0.18, 0.18, 1.07), oak)
			brace.rotation.x = -0.52
	if s.def.name == "Oatwick Millhouse":
		_part(faces[2], "parts/barrel.glb", Vector3(-hx + 0.46, 0, -hz * 0.58))
		var wheel := Assets.instance("wheel")
		wheel.position = Vector3(-hx - 0.24, 1.5, 0)
		wheel.rotation.y = PI * 0.5
		wheel.scale = Vector3.ONE * 1.9
		faces[2].add_child(wheel)
	for side in [-1.0, 1.0]:
		_part(faces[0], LANTERN, Vector3(side * (size.w * 0.5 + 0.55), 2.79, hz + 0.22))
	_box(faces[0], Vector3(0, DOOR_HEIGHT + 0.49, hz + 0.18), Vector3(size.w + 0.43, 0.31, 0.11), oak)
	if runtime and not str(s.def.name).is_empty():
		var sign := Label3D.new()
		sign.text = s.def.name
		sign.font_size = 32
		sign.pixel_size = 0.011
		sign.outline_size = 8
		sign.modulate = Color("edca8c")
		sign.visibility_range_end = 22.0
		sign.position = Vector3(0, DOOR_HEIGHT + 0.49, hz + 0.252)
		faces[0].add_child(sign)
	_furnish(interior, key, size, oak, stone, s.def.get("rest", key == "bellharbor_inn" or s.def.name == "Whitehorn Shelter"))
	for layer in [roof, interior] + faces:
		_batch_boxes(layer)
	return root


static func _batch_boxes(layer: Node3D) -> void:
	var batches := {}
	_gather_boxes(layer, Transform3D.IDENTITY, batches)
	for material in batches:
		var part := MeshInstance3D.new()
		part.mesh = batches[material].commit()
		part.material_override = material
		layer.add_child(part)


static func _gather_boxes(parent: Node3D, transform: Transform3D, batches: Dictionary) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D and child.mesh is BoxMesh and child.material_override != null:
			var mat: Material = child.material_override
			if not batches.has(mat):
				var batch := SurfaceTool.new()
				batch.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[mat] = batch
			batches[mat].append_from(child.mesh, 0, transform * child.transform)
			child.free()
		elif child is Node3D and (child.name.begins_with("WallBay") or child.name.begins_with("Bench")):
			_gather_boxes(child, transform * child.transform, batches)


static func _panel(parent: Node3D, at: Vector3, length: float, h: float, yaw: float,
		wall: Material, oak: Material, glass: Material) -> void:
	var panel := _group(parent, "WallBay")
	panel.position = at
	panel.rotation.y = yaw
	_box(panel, Vector3(0, h * 0.5, 0), Vector3(length, h, WALL), wall)
	for z in [-1.0, 1.0]:
		for height in [0.30, h - 0.18]:
			_box(panel, Vector3(0, height, z * 0.17), Vector3(length + 0.025, 0.20, 0.10), oak)
		var bays := maxi(1, roundi(length / 4.0))
		for i in range(bays + 1):
			var x := lerpf(-length * 0.5 + 0.13, length * 0.5 - 0.13, float(i) / bays)
			_box(panel, Vector3(x, h * 0.5, z * 0.17), Vector3(0.23, h, 0.11), oak)
		for i in range(bays):
			var x := lerpf(-length * 0.5, length * 0.5, (i + 0.5) / bays)
			var glass_y := h * 0.53
			_box(panel, Vector3(x, glass_y, z * 0.19), Vector3(1.12, 1.31, 0.16), oak)
			_box(panel, Vector3(x, glass_y, z * 0.28), Vector3(0.87, 1.08, 0.045), glass)
			_box(panel, Vector3(x, glass_y, z * 0.308), Vector3(0.07, 1.08, 0.03), oak)
			_box(panel, Vector3(x, glass_y, z * 0.308), Vector3(0.87, 0.075, 0.03), oak)


static func _furnish(room: Node3D, key: String, size: Vector4, oak: Material, stone: Material, hearth: bool) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	if key == "chapel":
		_box(room, Vector3(0, 0.5, -hz + 1.45), Vector3(2.6, 1.0, 0.92), stone)
		for x in [-hx * 0.51, hx * 0.51]:
			for z in [-hz * 0.39, 0, hz * 0.39]:
				_bench(room, Vector3(x, 0, z), oak, 0.0, 2.5)
	else:
		_box(room, Vector3(-hx + 1.7, 0.55, -hz + 1.36), Vector3(2.65, 1.10, 0.85), oak)
		_bench(room, Vector3(hx - 0.85, 0, -hz + 2.5), oak, PI * 0.5, 2.18)
		_part(room, "parts/barrel.glb", Vector3(-hx + 0.89, 0, hz - 0.78))
		_part(room, "parts/crate.glb", Vector3(hx - 0.85, 0, -hz + 0.80))
		if hearth:
			_box(room, Vector3(0, 0.53, -hz + 0.46), Vector3(2.25, 1.06, 0.76), stone)
			_box(room, Vector3(0, 1.19, -hz + 0.42), Vector3(2.52, 0.23, 0.91), stone)
			_box(room, Vector3(0, 0.48, -hz + 0.85), Vector3(1.44, 0.59, 0.08), _glass())
		if key == "bellharbor_inn":
			var rug := _rug()
			for x in [-hx * 0.5, hx * 0.5]:
				_box(room, Vector3(x, 0.009, 0.5), Vector3(3.65, 0.015, 2.7), rug)
				_bench(room, Vector3(x, 0, 0.9), oak, 0.0, 2.35)
				_box(room, Vector3(x, 0.73, 0.0), Vector3(2.55, 0.20, 0.91), oak)
				for dx in [-0.93, 0.93]:
					_box(room, Vector3(x + dx, 0.34, 0), Vector3(0.23, 0.68, 0.63), oak)
				var crockery := Assets.instance("stew")
				crockery.position = Vector3(x - 0.48, 0.84, 0.09)
				crockery.scale = Vector3.ONE * 0.9
				room.add_child(crockery)


static func _bench(parent: Node3D, at: Vector3, oak: Material, yaw: float, length: float) -> void:
	var bench := _group(parent, "Bench")
	bench.position = at
	bench.rotation.y = yaw
	_box(bench, Vector3(0, 0.46, 0), Vector3(length, 0.19, 0.52), oak)
	for sign_ in [-1.0, 1.0]:
		_box(bench, Vector3(sign_ * (length * 0.5 - 0.23), 0.20, 0), Vector3(0.22, 0.40, 0.43), oak)


static func _gables(parent: Node3D, hx: float, hz: float, h: float, rise: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sign_ in [-1.0, 1.0]:
		var z: float = hz * sign_
		st.add_vertex(Vector3(hx * sign_, h, z))
		st.add_vertex(Vector3(-hx * sign_, h, z))
		st.add_vertex(Vector3(0, h + rise, z))
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	parent.add_child(node)


static func _ramp(parent: Node3D, half_depth: float, width: float, lower: float, mat: Material) -> void:
	var slope := atan2(lower, APRON)
	var mesh := _box(parent, Vector3(0, lower * 0.5 - 0.035, half_depth + APRON * 0.5),
		Vector3(width, 0.075, Vector2(APRON, lower).length()), mat)
	mesh.rotation.x = -slope


static func _add_floor_ray(parent: Node3D, size: Vector4) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, 0.12, size.y)
	shape.shape = box
	shape.position.y = -0.06
	body.add_child(shape)
	parent.add_child(body)


static func _group(parent: Node3D, label: String) -> Node3D:
	var node := Node3D.new()
	node.name = label
	parent.add_child(node)
	return node


static func _box(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node


static func _round(parent: Node3D, at: Vector3, base: float, top: float, height: float, mat: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = base
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 0
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)


static func _part(parent: Node3D, part: String, at: Vector3, yaw := 0.0, size := 1.0) -> void:
	var obj := Assets.instance(KIT.ROOT + part)
	obj.position = at
	obj.rotation.y = yaw
	obj.scale = Vector3.ONE * size
	parent.add_child(obj)


static func _finish(style: String, index: int) -> StandardMaterial3D:
	var id := style + str(index)
	if not materials.has(id):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color.html(STYLES.get(style, STYLES.Original)[index]).lightened(0.22)
		mat.albedo_texture = load(KIT.ROOT + TEXTURES[index]) as Texture2D
		mat.uv1_triplanar = true
		mat.uv1_scale = Vector3.ONE * (0.48 if index == 3 else 0.38)
		mat.roughness = 0.88
		materials[id] = mat
	return materials[id]


static func _glass() -> StandardMaterial3D:
	if not materials.has("glass"):
		var glass := StandardMaterial3D.new()
		glass.albedo_color = Color("c99b58")
		glass.emission_enabled = true
		glass.emission = Color("c58a48")
		glass.emission_energy_multiplier = 0.52
		materials.glass = glass
	return materials.glass


static func _rug() -> StandardMaterial3D:
	if not materials.has("rug"):
		var rug := StandardMaterial3D.new()
		rug.albedo_color = Color("6f453d")
		rug.roughness = 1.0
		materials.rug = rug
	return materials.rug

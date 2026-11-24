extends RefCounted
## Low-cost, deterministic silhouette dressing. Roads and steep faces stay clear.

const GRASS_PATH := "res://assets/environment/nature/grass/"
const FIELD_PATCHES := 122
static var _meshes := {}


static func dress(cell: Node3D, key: Vector2i, vertices: PackedVector3Array,
		normals: PackedVector3Array, paint: Image, road: Image, paving: Image, cliff_grade: float, path: Image) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var clumps: Array[Transform3D] = []
	var colours: Array[Color] = []
	var rushes: Array[Transform3D] = []
	var rush_tints: Array[Color] = []
	var meadow: Array[Transform3D] = []
	var meadow_tints: Array[Color] = []
	var dry_grass: Array[Transform3D] = []
	var dry_tints: Array[Color] = []
	var reedbeds := _reedbeds(key, vertices, paint)
	for i in FIELD_PATCHES + reedbeds.size():
		var bank_patch := i >= FIELD_PATCHES
		var centre := reedbeds[i - FIELD_PATCHES] if bank_patch else Vector2(
			rng.randf_range(2.0, 30.0), rng.randf_range(2.0, 30.0))
		var world_at := Vector2(key) * 64.0 + centre * 2.0
		var density := sin(world_at.x*.092 + cos(world_at.y*.077)) * cos(world_at.y*.069)
		if not bank_patch and density < -.29 and i % 4 != 0:
			continue
		var dress_patch := density > .10 or i % 5 == 0
		for j in rng.randi_range(4, 9):
			var local := centre + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.10, 1.45)
			var x := floori(local.x)
			var z := floori(local.y)
			var index := z * 33 + x
			var p := vertices[index]
			var ground := paint.get_pixel(x + 1, z + 1)
			var at_world := Vector2(key) * 64.0 + local * 2.0
			var road_strength := _road_at(road, local, ground.a)
			var paving_strength := paving.get_pixel(x + 1, z + 1).r if paving != null else 0.0
			if path != null:
				var edit := path.get_pixelv(Vector2i((local * 4.0 + Vector2(2, 2)).round()))
				road_strength = road_strength * (1.0 - edit.b) + edit.r
				paving_strength = paving_strength * (1.0 - edit.b) + edit.g
			var allow_verge := _overgrown(at_world) and road_strength <= .41
			if normals[index].y < .75 or (road_strength > .19 and not allow_verge):
				continue
			if paving_strength > .08:
				continue
			var alpine := ground.b > .65 and ground.b > ground.r * 1.01
			var dry := ground.r > ground.g * 1.17
			var woodland := ground.g < .50 and not dry
			var ash := ground.g < .43 and ground.r > ground.g + .04 and ground.r < ground.b + .14
			if alpine and (i % 14 != 0 or density < .45):
				continue
			if (dry or ash) and (i % 5 != 0 or density < .04):
				continue
			var u := local.x - x
			var v := local.y - z
			var b := vertices[index + 1].y
			var c := vertices[index + 33].y
			var d := vertices[index + 34].y
			var y := p.y + (b - p.y) * u + (c - p.y) * v
			if u + v > 1.0:
				y = d + (c - d) * (1.0 - u) + (b - d) * (1.0 - v)
			var damp := y < 2.6 and not dry and not alpine and not ash
			if y < .26 or (normals[index].y < .86 and not damp):
				continue
			var size := rng.randf_range(.53, 1.19)
			var colour := ground.lerp(Color("4c612f"), .79)
			if alpine:
				colour = Color("77745d")
			elif ash:
				colour = Color("5e5144")
			elif dry:
				colour = ground.lerp(Color("8b7750"), .68)
			elif woodland:
				colour = ground.lerp(Color("394c32"), .72)
			var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(1.25, 1.0, 1.25) * size)
			var at := Vector3(local.x * 2.0, y - .018, local.y * 2.0)
			if bank_patch and (not damp or road_strength >= .13):
				continue
			if damp and (bank_patch or density > -.17) and road_strength < .13:
				var frond_height := lerpf(.52, .27, smoothstep(.30, 2.6, y))
				rushes.append(Transform3D(basis.scaled(Vector3(.69, frond_height, .69)), at))
				rush_tints.append(colour.lerp(Color("899451"), .28 + y * .08))
			elif dry or alpine or ash:
				if j <= 2:
					dry_grass.append(Transform3D(basis.scaled(Vector3(.47, .27, .47)), at))
					dry_tints.append(colour.lerp(Color("b7a677"), .40))
			elif dress_patch or allow_verge:
				var width := .72 if woodland else .84
				var verge_height := lerpf(.21, .38, smoothstep(-.2, .75, density))
				meadow.append(Transform3D(basis.scaled(Vector3(width, verge_height, width)), at))
				meadow_tints.append(colour.lerp(Color("879653"), rng.randf_range(.24, .47)))
			else:
				clumps.append(Transform3D(basis, at))
				colours.append(colour.darkened(rng.randf_range(.06,.23)))
	_batch(cell, "GroundCover", _mesh("tuft"), clumps, colours)
	_batch(cell, "MeadowGrass", _grass_mesh("Grass_Common_Short"), meadow, meadow_tints)
	_batch(cell, "DryGrass", _grass_mesh("Grass_Wispy_Short"), dry_grass, dry_tints)
	_batch(cell, "ShoreRushes", _grass_mesh("Grass_Wispy_Tall"), rushes, rush_tints)
	_cliff_outcrops(cell, vertices, paint, cliff_grade, rng)


static func _reedbeds(key: Vector2i, vertices: PackedVector3Array, paint: Image) -> Array[Vector2]:
	var centres: Array[Vector2] = []
	for z in range(2, 31, 2):
		for x in range(2, 31, 2):
			var index := z * 33 + x
			var h := vertices[index].y
			if h < -.35 or h > 2.3:
				continue
			var ground := paint.get_pixel(x + 1, z + 1)
			if ground.r > ground.g * 1.14 or ground.b > .64:
				continue
			var nearby_water := minf(minf(vertices[index - 1].y, vertices[index + 1].y),
				minf(vertices[index - 33].y, vertices[index + 33].y))
			var at := Vector2(key * 64 + Vector2i(x, z) * 2)
			var patch := sin(at.x * .23 + at.y * .16) + sin(at.y * .42 - at.x * .16)
			if nearby_water < .45 and patch > -.65:
				centres.append(Vector2(x, z))
	return centres


static func _road_at(road: Image, local: Vector2, coarse: float) -> float:
	if road == null:
		return coarse
	var p := Vector2i((local * 4.0 + Vector2(2, 2)).round())
	return road.get_pixelv(p).r


static func _overgrown(at: Vector2) -> bool:
	var drift := .5 + .5 * sin(at.dot(Vector2(.116, .069)) + .8 * sin(at.y * .13)) * cos(at.dot(Vector2(-.077, .161)))
	return drift > .64


static func _grass_mesh(model: String) -> Mesh:
	if _meshes.has(model):
		return _meshes[model]
	var scene := load(GRASS_PATH + model + ".gltf") as PackedScene
	var root := scene.instantiate()
	var node := root as MeshInstance3D
	if node == null:
		node = root.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays := node.mesh.surface_get_arrays(0)
	var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	for i in colours.size():
		# The source vertex channel holds blade shading. Lift its near-black
		# roots gently so a patch blends into the painted ground.
		var shade := lerpf(.55, 1.0, sqrt(colours[i].r))
		colours[i] = Color(shade, shade, shade)
	arrays[Mesh.ARRAY_COLOR] = colours
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in normals.size():
		normals[i] = normals[i].lerp(Vector3.UP, .72).normalized()
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	root.free()
	_meshes[model] = mesh
	return mesh


static func _cliff_outcrops(cell: Node3D, vertices: PackedVector3Array,
		paint: Image, cliff_grade: float, rng: RandomNumberGenerator) -> void:
	var outcrops: Array[Transform3D] = []
	for z in range(2, 31, 3):
		for x in range(2, 31, 3):
			var index := z * 33 + x
			var foot := vertices[index]
			if foot.y < 2.0 or paint.get_pixel(x + 1, z + 1).a > 0.12:
				continue
			var high := foot
			for neighbour in [index - 1, index + 1, index - 33, index + 33]:
				if vertices[neighbour].y > high.y:
					high = vertices[neighbour]
			if high.y - foot.y < cliff_grade * 2.0:
				continue
			var placed := foot.lerp(high, rng.randf_range(0.68, 0.94))
			var scale := Vector3(rng.randf_range(0.65, 1.35),
				rng.randf_range(0.8, 1.65), rng.randf_range(0.65, 1.25))
			var basis := Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(scale)
			outcrops.append(Transform3D(basis, placed))
	_batch(cell, "CliffOutcrops", _mesh("outcrop"), outcrops)


static func _batch(parent: Node3D, label: String, mesh: Mesh,
		transforms: Array[Transform3D], colors: Array[Color] = []) -> void:
	if transforms.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colors.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		if multi.use_colors:
			multi.set_instance_color(i, colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = multi
	if not colors.is_empty():
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.visibility_range_end = 58.0
	parent.add_child(node)


static func _mesh(kind: String) -> Mesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	var mesh: Mesh
	if kind == "outcrop":
		var rock := SphereMesh.new()
		rock.radius = 0.96
		rock.height = 1.7
		rock.radial_segments = 5
		rock.rings = 2
		var faceted := ShaderMaterial.new()
		faceted.shader = preload("res://game/render/cutaway.gdshader")
		faceted.set_shader_parameter("albedo", Color("565653"))
		rock.material = faceted
		_meshes[kind] = rock
		return rock
	else:
		var tuft := SurfaceTool.new()
		tuft.begin(Mesh.PRIMITIVE_TRIANGLES)
		for angle in [0.0, 2.09, 4.18]:
			var basis := Basis(Vector3.UP, angle)
			tuft.set_normal(Vector3.UP)
			tuft.add_vertex(basis * Vector3(-0.09, 0.0, 0.0))
			tuft.set_normal(Vector3.UP)
			tuft.add_vertex(basis * Vector3(0.13, 0.29, 0.10))
			tuft.set_normal(Vector3.UP)
			tuft.add_vertex(basis * Vector3(0.09, 0.0, 0.0))
		material.vertex_color_use_as_albedo = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh = tuft.commit()
	mesh.surface_set_material(0, material)
	_meshes[kind] = mesh
	return mesh

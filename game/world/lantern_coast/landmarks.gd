extends RefCounted
## Original low-poly landmarks for the terrain pass. Their axes stay clear for paths.

const COLORS := {
	"stone": Color("#817b68"),
	"mortar": Color("#5b5c56"),
	"chalk": Color("#aca18b"),
	"plaster": Color("#ccb184"),
	"wood": Color("#614831"),
	"edge": Color("#967148"),
	"roof": Color("#6b453d"),
	"moss": Color("#596a4a"),
	"slate": Color("#425257"),
	"gold": Color("#e4ae63"),
	"snow": Color("#c6cbd0"),
	"banner": Color("#455e70"),
	"linen": Color("#b99a61"),
	"red_canvas": Color("#963f37"),
	"tar": Color("#362e29"),
	"lily": Color("#658447"),
	"lily_young": Color("#829955"),
	"lily_flower": Color("#e1b4ad"),
}

const DRESSING := preload("res://game/world/lantern_coast/coast_dressing.gd")
const OUTLOOK_ROCKS := {
	"reed_lookout": [[-10.0, -9.3, 1.96, 1.44, 5.7], [-5.0, -11.8, 1.9, 1.55, 6.6],
		[7.8, -.8, 1.46, 1.11, 3.1], [-5.1, 3.25, 1.38, .81, .96],
		[-9.0, .4, 1.39, 1.23, 1.65], [-11.8, -7.1, 1.11, .99, 2.45],
		[-15.0, 15.0, 2.6, 2.0, 2.7], [-9.0, 19.0, 1.8, 1.65, 2.2]],
	"flint_overlook": [[-5.8, -3.3, 1.44, 1.24, 5.1], [-2.7, -6.4, 1.7, 1.25, 3.8],
		[-5.3, -2.0, 1.68, .91, 1.2], [4.8, -6.1, 1.34, 1.44, 2.2]],
	"iron_shelf": [[-6.0, -2.0, 1.31, 1.11, 4.0], [-4.0, 5.0, 1.51, 1.13, 1.1],
		[6.2, -3.4, 1.42, 1.13, 1.7], [7.8, 1.6, 1.71, 1.28, 2.8]],
	"white_summit": [[-6.2, -5.4, 2.04, 1.32, 4.3], [-2.1, -7.9, 1.24, 1.0, 2.8],
		[2.6, -6.0, 1.19, 1.14, 3.8], [-6.4, 5.9, 1.71, 1.24, .92]],
	"salt_bluff": [[-5.4, -3.7, 1.55, 1.63, 4.1], [.75, -5.5, 1.9, 1.45, 4.7],
		[5.9, -2.0, 1.55, 1.12, 2.9], [-5.9, 3.9, 1.24, .97, 1.25]],
	"salt_lookout": [[-5.4, 4.0, 1.60, 1.25, 2.1], [1.1, 5.8, 2.27, 1.19, .95],
		[5.9, -1.8, 1.94, 1.19, 4.7], [5.8, 1.6, 1.7, 1.09, 2.5]],
	"veilwood": [[-7.2, -3.0, 1.50, 1.28, 2.8], [-6.3, -5.5, 1.34, .94, 3.5],
		[-6.4, .6, 1.6, 1.24, .57]],
	"bell_barrows": [[-7.0, -4.8, 1.70, 1.33, 2.73], [5.8, -4.0, 1.45, 1.31, 2.2],
		[-7.3, -1.8, 1.55, 1.10, .96]],
	"cinder": [[-6.2, -13.8, 1.62, 1.29, 3.25], [3.8, -13.7, 1.54, 1.17, 2.65],
		[-8.9, -13.7, 1.79, 1.19, 1.33]],
	"ash": [[-15.3, -12.8, 2.3, 1.38, 2.05], [-13.0, -16.0, 1.35, 1.1, 2.9]],
	"red": [[-3.4, -14.0, 2.1, 1.25, 2.15], [3.4, -14.7, 1.66, 1.39, 1.55]],
	"tide": [[-13.1, 8.1, 1.9, 1.38, 2.6], [-15.0, 6.0, 1.52, 1.23, 1.2]],
	"star": [[-16.1, -4.7, 2.14, 1.68, 3.7], [-10.0, -9.8, 1.53, 1.22, 2.45],
		[-8.1, 9.4, 1.55, 1.47, 1.15]],
	"crown": [[5.7, -8.4, 1.85, 1.36, 3.3], [7.5, -11.3, 1.62, 1.41, 4.45],
		[10.2, -7.0, 1.3, 1.25, 2.3]],
}
static var _pad_mesh: ArrayMesh
static var _stone_material: ShaderMaterial


static func build(hub_id: String, use_settlement_buildings := false) -> Node3D:
	var hub := Node3D.new()
	hub.name = hub_id.capitalize().replace(" ", "") + "Landmarks"
	match hub_id:
		"oat", "oatwick":
			if not use_settlement_buildings:
				var mill := _piece(hub, "Mill")
				_house(mill, Vector3(-8.0, 0.0, -8.5), Vector3(6.8, 3.5, 6.0), "moss")
				_mill_wheel(mill, Vector3(-10.2, 1.50, -5.42))
			_fence(_piece(hub, "Fence"), Vector3(7.5, 0.0, -7.0), 6.0)
			_fence(_piece(hub, "Fence"), Vector3(-10.0, 0.0, 8.0), 8.0)
			_lamp(_piece(hub, "Lamp"), Vector3(-4.8, 0.0, -5.9))
			_supplies(_piece(hub, "Supplies"), Vector3(-4.0, 0.0, -4.7))
			_waypost(_piece(hub, "Signpost"), Vector3(4.7, 0.0, -2.4))
		"bell", "bellharbor":
			_lamp(_piece(hub, "Lamp"), Vector3(4.8, 0.0, -4.8))
			_stall(_piece(hub, "Stall"), Vector3(-7.8, 0.0, 7.6), "roof")
			_stall(_piece(hub, "Stall"), Vector3(7.2, 0.0, 7.4), "slate")
			if use_settlement_buildings:
				_palisade(_piece(hub, "Palisade"), Vector3(-37.0, 0.0, -5.4), 7.4)
				_palisade(_piece(hub, "Palisade"), Vector3(22.8, 0.0, -5.8), 6.2)
			else:
				_palisade(_piece(hub, "Palisade"), Vector3(-12.2, 0.0, -9.6), 7.4)
				_palisade(_piece(hub, "Palisade"), Vector3(12.2, 0.0, -9.6), 7.4)
			_supplies(_piece(hub, "Supplies"), Vector3(3.4, 0.0, -7.2))
		"gloam", "gloamwood":
			for i in 4:
				_grave(_piece(hub, "Grave"), Vector3(6.2 + (i % 2) * 2.2, 0.0, -6.1 - (i / 2) * 1.9), i % 2 == 0)
			_lamp(_piece(hub, "Lamp"), Vector3(-4.8, 0.0, -4.8))
			if use_settlement_buildings:
				_fence(_piece(hub, "Fence"), Vector3(15.7, 0.0, -9.7), 6.3)
			else:
				_fence(_piece(hub, "Fence"), Vector3(7.7, 0.0, -11.8), 8.3)
		"flint", "flintcut":
			_quarry_hoist(_piece(hub, "Quarry Hoist"), Vector3(-7.3, 0.0, -7.9))
		"reed", "reedmire":
			_lamp(_piece(hub, "Lamp"), Vector3(-4.8, 0.0, -4.9))
			_stall(_piece(hub, "Stall"), Vector3(8.2, 0.0, -6.6), "moss")
			_dock(_piece(hub, "Dock"), Vector3(-8.6, 0.0, 9.1))
		"iron", "ironstep":
			_palisade(_piece(hub, "Palisade"), Vector3(8.1, 0.0, -7.4), 6.2)
			_arch(_piece(hub, "Arch"), Vector3(0.0, 0.0, -9.4), "stone")
			_lamp(_piece(hub, "Lamp"), Vector3(4.8, 0.0, -4.8))
		"ash", "ashcourt":
			_ruin(_piece(hub, "Ruin"), Vector3(-8.2, 0.0, -8.6), "chalk")
			_fence(_piece(hub, "Fence"), Vector3(7.5, 0.0, -8.5), 6.0)
		"tide", "tidemark":
			_dock(_piece(hub, "Dock"), Vector3(7.2, 0.0, -8.2))
		"gate", "redgate":
			_lamp(_piece(hub, "Lamp"), Vector3(4.8, 0.0, -4.8))
		"red", "redwash":
			_well(_piece(hub, "Well"), Vector3(-6.7, 0.0, -6.7))
			if not use_settlement_buildings:
				_house(_piece(hub, "House"), Vector3(8.0, 0.0, -8.0), Vector3(5.9, 3.2, 5.1), "roof")
		"cinder", "cinder_march":
			_quarry_hoist(_piece(hub, "Quarry Hoist"), Vector3(-7.2, 0.0, -7.7))
		"white", "whitehorn":
			_lamp(_piece(hub, "Lamp"), Vector3(-18.0, 0.0, -2.1))
		"salt", "saltglass":
			_well(_piece(hub, "Well"), Vector3(-6.5, 0.0, -6.6))
		"star", "starfall":
			_dock(_piece(hub, "Dock"), Vector3(7.2, 0.0, -8.2))
		"crown", "crown_of_ash":
			_ruin(_piece(hub, "Ruin"), Vector3(-8.7, 0.0, -8.6), "mortar")
			_watchtower(_piece(hub, "Watchtower"), Vector3(7.8, 0.0, -8.3), "roof")
			_arch(_piece(hub, "Arch"), Vector3(0.0, 0.0, -9.6), "mortar")
		"millpond":
			_fence(_piece(hub, "Fence"), Vector3(-1.8, 0.0, -3.7), 6.5)
			_dock(_piece(hub, "Dock"), Vector3(2.8, 0.0, 2.8))
			_supplies(_piece(hub, "Supplies"), Vector3(4.7, 0.0, -1.8))
		"watchers_knoll":
			_watchtower(_piece(hub, "Watchtower"), Vector3(-5.8, -0.55, 0.7), "moss", true)
			_fence(_piece(hub, "Fence"), Vector3(4.0, 0.0, -3.3), 4.8)
		"bell_barrows":
			_cave(_piece(hub, "Cave"), "mortar")
			_grave(_piece(hub, "Grave"), Vector3(4.3, 0.0, 0.8), true)
			_grave(_piece(hub, "Grave"), Vector3(-4.2, 0.0, 0.3), false)
		"coppervein":
			_cave(_piece(hub, "Cave"), "wood")
			_quarry_hoist(_piece(hub, "Quarry Hoist"), Vector3(-5.3, 0.0, -0.8))
		"webbed_deep", "vigil_crypt", "rimewatch":
			_cave(_piece(hub, "Cave"), "chalk" if hub_id == "rimewatch" else "mortar")
		"sluice_keeper":
			_well(_piece(hub, "Well"), Vector3(-3.2, 0.0, -2.2))
			_dock(_piece(hub, "Dock"), Vector3(3.0, 0.0, -3.0))
		"redwash_robbers":
			_fence(_piece(hub, "Fence"), Vector3(-7.6, 0, 1.4), 4.7)
		"heron_oxbow":
			_waypost(_piece(hub, "Signpost"), Vector3(2.1, 0.0, -2.1))
			_box(_piece(hub, "Decoration"), Vector3(2.6, 0.16, 0.0), Vector3(1.8, 0.32, 0.45), "edge")
			_supplies(_piece(hub, "Supplies"), Vector3(-2.0, 0.0, -0.8))
		"bracken_falls":
			_waypost(_piece(hub, "Signpost"), Vector3(-2.0, 0.12, -1.5))
			_lamp(_piece(hub, "Lamp"), Vector3(0.6, 0.0, 2.3))
			_box(_piece(hub, "Decoration"), Vector3(1.8, 0.15, 2.3), Vector3(1.6, 0.3, 0.46), "edge")
		"cutlass_cove":
			_tent(_piece(hub, "Tent"), Vector3(-5.8, 0.60, -2.3), "red_canvas")
			_tent(_piece(hub, "Tent"), Vector3(-9.6, 1.15, 0.7), "linen")
			_campfire(_piece(hub, "Campfire"), Vector3(-5.2, 0.25, 1.7))
			_lamp(_piece(hub, "Lamp"), Vector3(-1.3, 0.2, 0.4))
			_supplies(_piece(hub, "Supplies"), Vector3(-3.3, 0.08, 1.5))
			_supplies(_piece(hub, "Supplies"), Vector3(-6.8, 0.35, 3.4))
			_box(_piece(hub, "Decoration"), Vector3(1.5, 1.1, -1.8), Vector3(0.17, 2.85, 0.18), "wood")
			_box(_piece(hub, "Decoration"), Vector3(1.93, 2.3, -1.77), Vector3(0.95, 0.40, 0.04), "red_canvas")
			_cove_boat(_piece(hub, "Cove Boat"), Vector3(10.5, -1.65, 8.7))
		"smugglers_cut":
			_fence(_piece(hub, "Fence"), Vector3(0.8, 0.0, 2.0), 3.4)
			_lamp(_piece(hub, "Lamp"), Vector3(2.2, 0.0, 1.1))
			_waypost(_piece(hub, "Signpost"), Vector3(2.7, 0.0, -0.4))
		"lantern_bridge", "quarry_gate", "iron_gate":
			var stone := "chalk" if hub_id == "lantern_bridge" else "stone"
			_arch(_piece(hub, "Arch"), Vector3.ZERO, stone)
			_lamp(_piece(hub, "Lamp"), Vector3(-5.9, 0, -0.35))
			_lamp(_piece(hub, "Lamp"), Vector3(5.9, 0, -0.35))
			_fence(_piece(hub, "Fence"), Vector3(-8.8, 0, 0), 5.4)
			_fence(_piece(hub, "Fence"), Vector3(8.8, 0, 0), 5.4)
			for x in [-4.75, 4.75]:
				_banner(_piece(hub, "Banner"), Vector3(x, 2.45, 0.85))
		"reed_lookout":
			_lamp(_piece(hub, "Lamp"), Vector3(-3.9, 0, -4.2))
			_lamp(_piece(hub, "Lamp"), Vector3(5.0, 0, 1.6))
		"salt_lookout":
			_lamp(_piece(hub, "Lamp"), Vector3(-2.8, 0, 4.1))
		"iron_shelf":
			_fence(_piece(hub, "Fence"), Vector3(1, 0, 3.8), 5.0)
			_waypost(_piece(hub, "Signpost"), Vector3(2.4, 0, 2.3))
			_campfire(_piece(hub, "Campfire"), Vector3(-3.1, 0, 2.0))
		"west_snowfields":
			_fence(_piece(hub, "Fence"), Vector3(-2.8, 0, -2.6), 3.9)
			_banner(_piece(hub, "Banner"), Vector3(-2.5, 0.7, -2.6))
		"whitehorn_cirque":
			_waypost(_piece(hub, "Signpost"), Vector3(2.9, 0, 0.7))
			_box(_piece(hub, "Decoration"), Vector3(3.5, 0.23, 1.8), Vector3(1.4, 0.45, 0.8), "stone")
		"dry_wells":
			for base in [Vector3(-4, 0, 1), Vector3(3, 0, 2), Vector3(-3, 0, -5)]:
				_well(_piece(hub, "Well"), base)
		"sailcloth_dunes":
			_stall(_piece(hub, "Stall"), Vector3(4, 0, 1), "linen")
			_supplies(_piece(hub, "Supplies"), Vector3(5.4, 0, -1.1))
		"veilwood":
			_ruin(_piece(hub, "Ruin"), Vector3(3.2, -0.1, -2.1), "moss")
			_grave(_piece(hub, "Grave"), Vector3(-2.8, 0, 1.4), false)
			_grave(_piece(hub, "Grave"), Vector3(2.8, 0, 2.2), false)
		"flint_overlook":
			_waypost(_piece(hub, "Signpost"), Vector3(-1.2, 0, 2.4))
			_fence(_piece(hub, "Fence"), Vector3(1.0, 0, 4.3), 6.0)
			_lamp(_piece(hub, "Lamp"), Vector3(2.2, 0, 3.1))
			_quarry_hoist(_piece(hub, "Quarry Hoist"), Vector3(-4.6, 0, 0.8))
			_supplies(_piece(hub, "Supplies"), Vector3(-3.8, 0, 2.6))
		"white_summit":
			_waypost(_piece(hub, "Signpost"), Vector3(2.7, 0, 2.3))
			_lamp(_piece(hub, "Lamp"), Vector3(3.3, 0, 1.1))
			_fence(_piece(hub, "Fence"), Vector3(-1.2, 0, 4.4), 7.0)
			_cairn(_piece(hub, "Cairn"), Vector3(-3.3, 0, 2.9), "stone")
		"white_cairns":
			for i in 3:
				_cairn(_piece(hub, "Cairn"), Vector3(1.8 - i * 1.2, 0, 1.5 + 0.5 * i), "chalk")
		"salt_bluff":
			_fence(_piece(hub, "Fence"), Vector3(2.7, 0, 3.1), 5.0)
			_waypost(_piece(hub, "Signpost"), Vector3(2.1, 0, 2.4))
			_cairn(_piece(hub, "Cairn"), Vector3(4.3, 0, 1.7), "chalk")
		"salt_cairn":
			_cairn(_piece(hub, "Cairn"), Vector3(0.25, 0, 1.1), "chalk")
	_center_pieces(hub)
	return hub


static func _piece(parent: Node3D, label: String) -> Node3D:
	var piece := Node3D.new()
	piece.name = label
	piece.set_meta("editable_landmark", true)
	parent.add_child(piece, true)
	return piece


static func _center_pieces(parent: Node3D) -> void:
	for piece: Node3D in parent.get_children():
		if not piece.has_meta("editable_landmark") or piece.get_child_count() == 0:
			continue
		var first: Node3D = piece.get_child(0)
		_shift_pivot(piece, Vector3(first.position.x, 0.0, first.position.z))


static func _shift_pivot(piece: Node3D, pivot: Vector3) -> void:
	piece.position += pivot
	for child: Node3D in piece.get_children():
		child.position -= pivot


static func ridge_passage(length: float, clear_width: float) -> Node3D:
	var cave := Node3D.new()
	var step := length / 8.0
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var radius := clear_width * 0.5
	# Trace the inner wall up from the floor and around the outside to close
	# the ridge. Uneven sections keep the entrances visibly open.
	var section := PackedVector2Array([
		Vector2(-radius, -0.24), Vector2(-radius - .06, 1.85), Vector2(-radius + .12, 2.66),
		Vector2(-radius * .58, 3.35), Vector2(.16, 3.65), Vector2(radius * .66, 3.30),
		Vector2(radius - .18, 2.60), Vector2(radius + .05, 1.77), Vector2(radius, -.24),
		Vector2(radius + 3.40, -.30), Vector2(radius + 2.52, 2.07), Vector2(radius + 1.37, 3.60),
		Vector2(radius * .52, 4.85), Vector2(-radius * .62, 5.12), Vector2(-radius - 1.24, 3.84),
		Vector2(-radius - 2.86, 1.79), Vector2(-radius - 3.40, -.30),
	])
	for i in 9:
		var ring := PackedVector3Array()
		for j in section.size():
			var point := section[j]
			var outer := float(j > 8)
			var z := i * step - length * 0.5
			var ripple := sin(i * 1.88 + j * 2.34)
			ring.append(Vector3(point.x + ripple * (.09 + outer * .36),
				point.y + cos(i * 2.3 + j * 1.9) * (.11 + outer * .36), z + ripple * .32))
		rings.append(ring)
	for i in 8:
		var z := (i + 0.5) * step - length * 0.5
		for side in [-1.0, 1.0]:
			var x := float(side) * (radius + 1.65)
			_solid(cave, Vector3(x, 1.5, z), Vector3(3.0, 3.0, step))
		for j in section.size() - 1:
			_rock_quad(rock, rings[i][j + 1], rings[i][j], rings[i + 1][j], rings[i + 1][j + 1])
	for i in [0, 8]:
		var ring := rings[i]
		var skin := [16, 16, 15, 14, 13, 12, 11, 10, 9]
		for j in 8:
			if i == 0:
				_rock_quad(rock, ring[j], ring[j + 1], ring[skin[j + 1]], ring[skin[j]])
			else:
				_rock_quad(rock, ring[j + 1], ring[j], ring[skin[j]], ring[skin[j + 1]])
	rock.generate_normals()
	_model(cave, rock.commit(), Vector3.ZERO, "mortar")
	for z in [-length * .41, length * .32]:
		_lamp(cave, Vector3(-radius + .21, 0.0, z))
	return cave


static func _rock_quad(rock: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for face in [[a, b, c], [a, c, d]]:
		if Plane(face[0], face[1], face[2]).normal.length_squared() < .5:
			continue
		rock.set_smooth_group(-1)
		for point in face:
			rock.add_vertex(point)


static func _cairn(parent: Node3D, base: Vector3, stone: String) -> void:
	for i in 4:
		var radius := 0.58 - i * .114
		_round(parent, base + Vector3(0.05 * sin(i * 2.0), 0.15 + 0.26 * i, 0.0),
			radius * 0.68, radius, .31, stone)


static func route_lamp(style: String) -> Node3D:
	var landmark := Node3D.new()
	_lamp(_piece(landmark, "Lamp"), Vector3.ZERO, style)
	return landmark


static func trail_sign(title: String) -> Node3D:
	var post := Node3D.new()
	_box(post, Vector3(0, 1.0, 0), Vector3(.18, 2.0, .18), "wood")
	_box(post, Vector3(.31, 1.64, 0), Vector3(.78, .32, .16), "edge")
	_box(post, Vector3(.70, 1.64, 0), Vector3(.23, .23, .16), "edge", Vector3(0, 0, PI * .25))
	_round(post, Vector3(0, .15, 0), .26, .34, .3, "stone")
	_box(post, Vector3(0, .72, 0), Vector3(.21, .38, .21), "banner")
	var label := Label3D.new()
	label.text = title
	label.font_size = 34
	label.outline_size = 11
	label.pixel_size = .008
	label.modulate = Color("f8dc9a")
	label.outline_modulate = Color("31241b")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position.y = 2.32
	label.visibility_range_end = 75.0
	post.add_child(label)
	return post


static func ground_detail(parent: Node3D, id: String, land: Node3D) -> void:
	if OUTLOOK_ROCKS.has(id):
		var pigment := Color("535653")
		if id.begins_with("salt") or id == "red":
			pigment = Color("82705a")
		elif id == "white_summit":
			pigment = Color("627077")
		elif id in ["cinder", "crown"]:
			pigment = Color("514544")
		elif id in ["tide", "star"]:
			pigment = Color("525f67")
		elif id == "veilwood":
			pigment = Color("48594d")
		for i in OUTLOOK_ROCKS[id].size():
			var stone: Array = OUTLOOK_ROCKS[id][i]
			var base := Vector3(stone[0], 0, stone[1])
			var world := parent.transform * base
			base.y = land.floor_height(Vector2(world.x, world.z)) - parent.position.y
			var piece := _piece(parent, "Standing Rock")
			_standing_rock(piece, base, Vector2(stone[2], stone[3]), stone[4], pigment, hash(id) + i)
			_shift_pivot(piece, base)
	if id not in ["oat", "heron_oxbow"]:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	if id == "oat":
		_lily_pads(parent, land, [Vector2(-752, 154), Vector2(-753, 162), Vector2(-744, 153)], rng)
	elif id == "heron_oxbow":
		_lily_pads(parent, land, [Vector2(-388, 84), Vector2(-381, 87), Vector2(-396, 92)], rng)


static func _standing_rock(parent: Node3D, base: Vector3, footprint: Vector2, height: float,
		pigment: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var stone := SurfaceTool.new()
	stone.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var levels := [-.20, .17, .42, .67, .77, .90, 1.0]
	var taper := rng.randf_range(.40, .77)
	var lean := Vector2(rng.randf_range(-.95, .95), rng.randf_range(-.83, .83))
	var turn := rng.randf_range(0, TAU)
	var fracture := rng.randf_range(.11, .32)
	var band_skew := rng.randf_range(-.17, .17)
	var sides := 7
	for i in levels.size():
		var ring := PackedVector3Array()
		for j in sides:
			var angle := turn + j * TAU / sides + sin(j * 4.4) * .16
			var share := float(levels[i])
			var width := lerpf(1.08, taper, share) + fracture * sin(2.1 * j + 1.4 * i + turn)
			var rim := Vector2.from_angle(angle) * footprint * width + lean * share
			ring.append(Vector3(rim.x, height * (share + band_skew * rim.x / footprint.x)
				+ .13 * sin(j * 2.8 + i * 1.7), rim.y))
		rings.append(ring)
	for i in rings.size() - 1:
		for j in sides:
			var shade := 1.0 + .13 * sin(j * 2.14 + turn) - .17 * float(i in [2, 4])
			stone.set_color(pigment.darkened(1.0 - minf(shade, 1.0)))
			var next := (j + 1) % sides
			_rock_quad(stone, rings[i][j], rings[i][next], rings[i+1][next], rings[i+1][j])
	var crown := Vector3(lean.x, height * .99, lean.y)
	stone.set_color(pigment.lightened(.07))
	for j in sides:
		_rock_quad(stone, rings[-1][j], rings[-1][(j+1) % sides], crown, crown)
	stone.generate_normals()
	if _stone_material == null:
		_stone_material = ShaderMaterial.new()
		_stone_material.shader = preload("res://game/world/lantern_coast/lookout_stone.gdshader")
		_stone_material.set_shader_parameter("stone_detail", preload("res://game/world/lantern_coast/rock_detail.png"))
	var mesh := MeshInstance3D.new()
	mesh.name = "StandingRock"
	mesh.mesh = stone.commit()
	mesh.material_override = _stone_material
	mesh.position = base
	parent.add_child(mesh, true)
	_solid(parent, base + Vector3.UP * height * .35, Vector3(footprint.x * 1.26, height * .94, footprint.y * 1.26))


static func _lily_pads(parent: Node3D, land: Node3D, patches: Array, rng: RandomNumberGenerator) -> void:
	var pads: Array[Transform3D] = []
	var colours: Array[Color] = []
	for centre: Vector2 in patches:
		for i in rng.randi_range(3, 7):
			var p := centre + Vector2.from_angle(rng.randf_range(0, TAU)) * rng.randf_range(0.2, 1.55)
			if land.floor_height(p) > -0.24:
				continue
			var at := Vector3(p.x, 0.055, p.y) - parent.position
			var radius := rng.randf_range(0.15, 0.33)
			pads.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * radius), at))
			colours.append(COLORS.lily if i % 2 == 0 else COLORS.lily_young)
			if i == 0:
				_round(parent, at + Vector3(0, 0.07, 0), 0.11, 0.07, 0.10, "lily_flower")
	_ground_batch(parent, "LilyPads", _lily_mesh(), pads, colours)


static func _lily_mesh() -> ArrayMesh:
	if _pad_mesh != null:
		return _pad_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_material(_ground_material())
	for side in 9:
		for t in [-1, side, side + 1]:
			surface.set_normal(Vector3.UP)
			var angle := lerpf(0.24, TAU - 0.24, float(t) / 9.0)
			surface.add_vertex(Vector3.ZERO if t < 0 else Vector3(cos(angle), 0, sin(angle) * 0.86))
	_pad_mesh = surface.commit()
	return _pad_mesh


static func _ground_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.95
	return material


static func _ground_batch(parent: Node3D, label: String, mesh: Mesh,
		transforms: Array[Transform3D], colours: Array[Color]) -> void:
	if transforms.is_empty():
		return
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.use_colors = true
	batch.mesh = mesh
	batch.instance_count = transforms.size()
	for i in transforms.size():
		batch.set_instance_transform(i, transforms[i])
		batch.set_instance_color(i, colours[i])
	var node := MultiMeshInstance3D.new()
	node.name = label
	node.multimesh = batch
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)


static func _material(key: String) -> ShaderMaterial:
	return DRESSING.prop_material(key, COLORS.get(key, Color("251c28")), key == "gold")


static func _tent(parent: Node3D, base: Vector3, canvas: String) -> void:
	for sign_ in [-1.0, 1.0]:
		_box(parent, base + Vector3(sign_ * 0.87, 1.07, 0),
			Vector3(2.48, 0.09, 3.65), canvas, Vector3(0, 0, -sign_ * 0.88))
	_box(parent, base + Vector3(0, 0.97, -1.59), Vector3(0.12, 1.94, 0.13), "wood")
	_box(parent, base + Vector3(0, 0.97, 1.59), Vector3(0.12, 1.94, 0.13), "wood")
	_box(parent, base + Vector3(0, 1.96, 0), Vector3(0.11, 0.11, 3.6), "wood")
	_solid(parent, base + Vector3(0, 0.58, 0), Vector3(2.9, 1.16, 2.5))


static func _campfire(parent: Node3D, base: Vector3) -> void:
	for i in 8:
		var turn := TAU * i / 8.0
		var rim := base + Vector3(cos(turn) * 0.72, 0.15, sin(turn) * 0.72)
		_box(parent, rim, Vector3(0.33, 0.26, 0.37), "stone", Vector3(0, turn, 0))
	_box(parent, base + Vector3(0, 0.15, 0), Vector3(0.92, 0.15, 0.16), "wood", Vector3(0, 0.7, 0))
	_box(parent, base + Vector3(0, 0.21, 0), Vector3(0.82, 0.13, 0.18), "wood", Vector3(0, -0.6, 0))
	_round(parent, base + Vector3(0, 0.35, 0), 0.025, 0.24, 0.56, "gold")
	var source := Marker3D.new()
	source.add_to_group("coast_lamp", true)
	source.position = base + Vector3.UP * 0.55
	parent.add_child(source)


static func _stall(parent: Node3D, base: Vector3, colour: String) -> void:
	for x in [-1.27, 1.27]:
		for z in [-0.7, 0.7]:
			_box(parent, base + Vector3(x, 1.14, z), Vector3(0.16, 2.28, 0.16), "wood")
	_box(parent, base + Vector3(0, 0.81, 0), Vector3(2.78, 0.14, 1.40), "edge")
	_box(parent, base + Vector3(0, 2.23, 0), Vector3(3.0, 0.13, 1.80), colour, Vector3(0.16, 0, 0))
	for i in 5:
		_box(parent, base + Vector3(-1.18 + i * 0.59, 2.12, 0.86), Vector3(0.26, 0.24, 0.05), "chalk")


static func _cave(parent: Node3D, stone: String) -> void:
	var back := Vector3(0, 0, -3.8)
	_box(parent, back + Vector3(0, 1.1, -0.19), Vector3(3.35, 2.25, 0.55), "shade")
	_solid(parent, back + Vector3(0, 1.1, -0.19), Vector3(3.35, 2.25, 0.55))
	for x in [-1.8, 1.8]:
		for row in 3:
			_box(parent, back + Vector3(x, 0.50 + row * 0.86, 0), Vector3(0.82, 0.83, 0.84), stone)
	_box(parent, back + Vector3(0, 2.82, 0), Vector3(4.48, 0.66, 1.15), stone)
	_box(parent, back + Vector3(0, 0.12, 0.85), Vector3(3.02, 0.19, 2.24), "chalk")
	_lamp(parent, back + Vector3(2.65, 0, 0.3))


static func _banner(parent: Node3D, at: Vector3) -> void:
	_box(parent, at, Vector3(0.72, 1.42, 0.045), "banner")
	_box(parent, at + Vector3(0, 0.73, 0), Vector3(0.89, 0.11, 0.14), "wood")
	_box(parent, at + Vector3(0, -0.42, 0.03), Vector3(0.64, 0.095, 0.022), "linen")
	_box(parent, at + Vector3(0, 0.18, 0.03), Vector3(0.18, 0.18, 0.025), "linen", Vector3(0, 0, PI * 0.25))


static func _supplies(parent: Node3D, at: Vector3) -> void:
	_round(parent, at + Vector3(0, 0.40, 0), 0.29, 0.33, 0.8, "edge")
	for y in [0.19, 0.64]:
		_round(parent, at + Vector3(0, y, 0), 0.34, 0.34, 0.11, "mortar")
	_box(parent, at + Vector3(0.64, 0.25, -0.19), Vector3(0.66, 0.5, 0.62), "wood")
	_box(parent, at + Vector3(0.64, 0.51, -0.19), Vector3(0.65, 0.06, 0.61), "edge")
	_solid(parent, at + Vector3(0.30, 0.40, -0.08), Vector3(1.30, 0.8, 0.85))


static func _waypost(parent: Node3D, at: Vector3) -> void:
	_box(parent, at + Vector3(0, 0.82, 0), Vector3(0.18, 1.64, 0.18), "wood")
	_box(parent, at + Vector3(0.22, 1.34, 0), Vector3(0.77, 0.20, 0.15), "edge")
	_box(parent, at + Vector3(0.53, 1.34, 0), Vector3(0.16, 0.16, 0.15), "edge", Vector3(0, 0, PI / 4))


static func _model(
	parent: Node3D, mesh: Mesh, center: Vector3, material: String, rotation := Vector3.ZERO
) -> MeshInstance3D:
	var prop := MeshInstance3D.new()
	prop.mesh = mesh
	prop.material_override = _material(material)
	prop.position = center
	prop.rotation = rotation
	parent.add_child(prop)
	return prop


static func _box(
	parent: Node3D, center: Vector3, size: Vector3, material: String, rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _model(parent, mesh, center, material, rotation)


static func _round(
	parent: Node3D, center: Vector3, top: float, bottom: float, length: float,
	material: String, rotation := Vector3.ZERO
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 0
	_model(parent, mesh, center, material, rotation)


static func _solid(parent: Node3D, center: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.position = center
	body.rotation = rotation
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)


static func _house(parent: Node3D, base: Vector3, size: Vector3, roof: String) -> void:
	var width := size.x
	var height := size.y
	var depth := size.z
	var front := base + Vector3(0.0, 0.0, depth * 0.5)
	_box(parent, base + Vector3(0.0, height * 0.5, 0.0), size, "plaster")
	_box(parent, base + Vector3(0.0, 0.19, 0.0), Vector3(width + 0.09, 0.38, depth + 0.09), "stone")
	_solid(parent, base + Vector3(0.0, height * 0.5, 0.0), size)
	var rise := width * 0.30
	var gable := PrismMesh.new()
	gable.size = Vector3(width, rise, depth)
	_model(parent, gable, base + Vector3(0.0, height + rise * 0.5, 0.0), "plaster")
	var overhang := width * 0.5 + 0.32
	var angle := atan2(rise, width * 0.5)
	for sign_ in [-1.0, 1.0]:
		_box(parent, base + Vector3(sign_ * overhang * 0.5, height + rise * 0.50, 0.0),
			Vector3(overhang / cos(angle), 0.16, depth + 0.68), roof, Vector3(0.0, 0.0, -sign_ * angle))
		_box(parent, front + Vector3(sign_ * (width * 0.5 - 0.1), height * 0.53, 0.065),
			Vector3(0.17, height * 0.95, 0.14), "wood")
		var window := front + Vector3(sign_ * width * 0.28, height * 0.60, 0.045)
		_box(parent, window, Vector3(0.78, 0.91, 0.16), "wood")
		_box(parent, window + Vector3(0.0, 0.0, 0.09), Vector3(0.57, 0.68, 0.04), "gold")
		_box(parent, window + Vector3(0.0, 0.0, 0.125), Vector3(0.055, 0.7, 0.035), "wood")
	_box(parent, front + Vector3(0.0, 0.99, 0.075), Vector3(1.42, 1.96, 0.19), "wood")
	_box(parent, front + Vector3(0.0, 0.95, 0.185), Vector3(1.10, 1.74, 0.05), "edge")
	_box(parent, front + Vector3(0.37, 0.91, 0.227), Vector3(0.07, 0.07, 0.035), "gold")
	_box(parent, base + Vector3(width * 0.32, height + rise * 0.61, -depth * 0.23),
		Vector3(0.61, 1.45, 0.65), "mortar")


static func _mill_wheel(parent: Node3D, center: Vector3) -> void:
	_round(parent, center, 0.24, 0.24, 0.68, "wood", Vector3(PI / 2.0, 0.0, 0.0))
	for i in 12:
		var angle := TAU * i / 12.0
		var vector := Vector3(sin(angle), cos(angle), 0.0)
		_box(parent, center + vector * 0.72, Vector3(0.10, 1.30, 0.16),
			"edge", Vector3(0.0, 0.0, -angle))
		_box(parent, center + vector * 1.36, Vector3(0.54, 0.16, 0.39),
			"wood", Vector3(0.0, 0.0, -angle))


static func _lamp(parent: Node3D, base: Vector3, style := "amber") -> void:
	_box(parent, base + Vector3(0.0, 0.98, 0.0), Vector3(0.12, 1.95, 0.12), "wood")
	_box(parent, base + Vector3(0.0, 1.90, 0.22), Vector3(0.12, 0.10, 0.52), "wood")
	_box(parent, base + Vector3(0.0, 1.70, 0.43), Vector3(0.19, 0.25, 0.19), "gold")
	_round(parent, base + Vector3(0.0, 1.85, 0.43), 0.035, 0.17, 0.15, "mortar")
	var source := Marker3D.new()
	source.add_to_group("coast_lamp", true)
	source.set_meta("light_style", style)
	source.position = base + Vector3(0, 1.7, 0.43)
	parent.add_child(source)
	if style != "amber":
		var lens := MeshInstance3D.new()
		var bulb := SphereMesh.new()
		bulb.radius = 0.11
		bulb.height = 0.22
		bulb.radial_segments = 8
		bulb.rings = 4
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color({"veil":"9bffcf", "reed":"cfe6a1", "grave":"9ddbec"}.get(style, "ffc58d"))
		lens.mesh = bulb
		lens.material_override = material
		lens.position = source.position + Vector3(0.0, 0.02, 0.05)
		parent.add_child(lens)


static func _fence(parent: Node3D, base: Vector3, width: float) -> void:
	for y in [0.38, 0.77]:
		_box(parent, base + Vector3(0.0, y, 0.0), Vector3(width, 0.12, 0.14), "edge")
	for i in 5:
		_box(parent, base + Vector3(-width * 0.5 + i * width / 4.0, 0.5, 0.0),
			Vector3(0.15, 1.05, 0.18), "wood")
	_solid(parent, base + Vector3(0, 0.50, 0), Vector3(width + 0.14, 1.0, 0.2))


static func _arch(parent: Node3D, base: Vector3, stone: String) -> void:
	for side in [-1.0, 1.0]:
		var column := base + Vector3(side * 4.75, 1.98, 0.0)
		_box(parent, column, Vector3(1.20, 3.96, 1.38), stone)
		_solid(parent, column, Vector3(1.20, 3.96, 1.38))
		for y in [0.26, 1.10, 1.94, 2.78]:
			_box(parent, base + Vector3(side * 4.75, y, 0), Vector3(1.24, 0.06, 1.42), "mortar")
		_box(parent, column + Vector3(0.0, 2.05, 0.0), Vector3(1.55, 0.25, 1.64), "mortar")
	_box(parent, base + Vector3(0.0, 4.28, 0.0), Vector3(10.72, 0.48, 0.56), stone)
	_box(parent, base + Vector3(0.0, 4.25, 0.37), Vector3(2.2, 0.40, 0.19), "edge")


static func _grave(parent: Node3D, base: Vector3, tall: bool) -> void:
	var height := 0.88 if tall else 0.57
	_box(parent, base + Vector3(0.0, height * 0.50, 0.0), Vector3(0.48, height, 0.14), "stone")
	_box(parent, base + Vector3(0.0, height * 0.73, 0.0), Vector3(0.69, 0.13, 0.16), "mortar")
	_box(parent, base + Vector3(0.0, 0.07, 0.68), Vector3(0.59, 0.14, 1.35), "mortar")


static func _ruin(parent: Node3D, base: Vector3, stone: String) -> void:
	for side in [-1.0, 1.0]:
		var wall := base + Vector3(side * 2.9, 0.92, 0.0)
		var flank := Vector3(0.41, 1.84, 5.2)
		_box(parent, wall, flank, stone)
		_solid(parent, wall, flank)
		var pillar := base + Vector3(side * 2.12, 1.62, 2.48)
		_box(parent, pillar, Vector3(1.10, 3.24, 0.52), stone)
		_solid(parent, pillar, Vector3(1.10, 3.24, 0.52))
		for i in 3:
			_box(parent, wall + Vector3(0.0, 1.04 + i * 0.18, -1.8 + i * 1.20),
				Vector3(0.44, 0.52 + i * 0.35, 0.78), stone)
	var rear := base + Vector3(0.0, 1.20, -2.50)
	_box(parent, rear, Vector3(5.8, 2.4, 0.44), stone)
	_solid(parent, rear, Vector3(5.8, 2.4, 0.44))
	_box(parent, base + Vector3(0.0, 0.09, -0.8), Vector3(3.2, 0.16, 2.8), "chalk")
	_box(parent, base + Vector3(0.0, 0.62, -1.63), Vector3(1.19, 0.89, 0.52), "mortar")


static func _palisade(parent: Node3D, base: Vector3, width: float) -> void:
	for i in 12:
		var height := 1.8 + 0.1 * (i % 3)
		var position := base + Vector3(-width * 0.5 + i * width / 11.0, height * 0.5, 0.0)
		_round(parent, position, 0.15, 0.17, height, "wood")
		_round(parent, position + Vector3(0.0, height * 0.50 + 0.18, 0.0), 0.012, 0.15, 0.36, "edge")
	_solid(parent, base + Vector3(0.0, 0.91, 0.0), Vector3(width + 0.25, 1.82, 0.34))


static func _watchtower(parent: Node3D, base: Vector3, roof: String, beacon := false) -> void:
	_round(parent, base + Vector3(0.0, 2.04, 0.0), 1.35, 1.65, 4.08, "stone")
	_round(parent, base + Vector3(0.0, 4.05, 0.0), 1.61, 1.36, 0.41, "mortar")
	_solid(parent, base + Vector3(0.0, 2.03, 0.0), Vector3(2.60, 4.06, 2.60))
	_box(parent, base + Vector3(0.0, 0.98, 1.57), Vector3(1.00, 1.79, 0.19), "wood")
	if beacon:
		_round(parent, base + Vector3(0.0, 4.63, 0.0), 1.03, 1.03, 0.80, "gold")
		_round(parent, base + Vector3(0.0, 5.41, 0.0), 0.06, 1.31, 0.90, roof)
	else:
		_round(parent, base + Vector3(0.0, 4.89, 0.0), 0.04, 1.68, 1.66, roof)


static func _quarry_hoist(parent: Node3D, base: Vector3) -> void:
	for side in [-1.0, 1.0]:
		_box(parent, base + Vector3(side * 1.48, 1.70, 0.0), Vector3(0.24, 3.42, 0.32), "wood")
		_box(parent, base + Vector3(side * 1.13, 1.50, 0.10), Vector3(0.16, 2.20, 0.15),
			"edge", Vector3(0.0, 0.0, -side * 0.44))
	_box(parent, base + Vector3(0.0, 3.27, 0.0), Vector3(3.70, 0.30, 0.31), "edge")
	_round(parent, base + Vector3(0.0, 2.92, 0.03), 0.34, 0.34, 0.19,
		"wood", Vector3(PI / 2.0, 0.0, 0.0))
	_box(parent, base + Vector3(0.0, 1.89, 0.0), Vector3(0.045, 1.75, 0.045), "edge")
	_box(parent, base + Vector3(0.0, 0.82, 0.0), Vector3(0.68, 0.36, 0.66), "stone")


static func _dock(parent: Node3D, base: Vector3) -> void:
	_box(parent, base + Vector3(0.0, 0.12, 0.0), Vector3(2.25, 0.24, 4.60), "wood")
	for i in 10:
		_box(parent, base + Vector3(0.0, 0.26, -2.14 + i * 0.47), Vector3(2.16, 0.07, 0.44), "edge")
	for x in [-1.07, 1.07]:
		for z in [-2.08, 2.08]:
			_box(parent, base + Vector3(x, 0.32, z), Vector3(0.18, 1.0, 0.19), "wood")
	_lamp(parent, base + Vector3(0.9, 0.0, -2.08))


static func pier(def: Dictionary) -> Node3D:
	var node := Node3D.new()
	var a := Vector2(def.a[0], def.a[1])
	var b := Vector2(def.b[0], def.b[1])
	var p := (a + b) * 0.5
	var length := a.distance_to(b)
	node.name = "CutlassCovePier" if def.id == "cutlass_cove" else str(def.id).to_pascal_case()
	node.position = Vector3(p.x, def.height, p.y)
	node.rotation.y = atan2(b.x - a.x, b.y - a.y)
	var count := ceili(length / 0.52)
	var step := length / count
	var ramp: float = def.get("ramp", 0.0)
	var rise: float = def.get("bank_height", def.height) - def.height
	var pitch := atan2(rise, maxf(0.001, ramp))
	for i in count:
		var at := (i + 0.5) * step
		var drop := 0.0 if ramp == 0.0 else rise * (1.0 - clampf(at / ramp, 0.0, 1.0))
		var board_pitch := pitch if at < ramp else 0.0
		_box(node, Vector3(0, drop - 0.095, -length * 0.5 + at),
			Vector3(def.width, 0.19, (step - 0.015) / cos(board_pitch)), "edge" if i % 3 == 0 else "wood",
			Vector3(board_pitch, 0, 0))
	for side in [-1.0, 1.0]:
		for fraction in [-0.4, -0.13, 0.13, 0.4]:
			var at: float = length * fraction
			var h := 0.0 if ramp == 0.0 else rise * (1.0 - clampf((at + length * 0.5) / ramp, 0.0, 1.0))
			_box(node, Vector3(side * (def.width * 0.5 - 0.15), h * 0.5 - 0.95, at), Vector3(0.21, 3.4 + h, 0.21), "wood")
	if ramp > 0.0:
		_solid(node, Vector3(0, rise * 0.5 - 0.15, (ramp - length) * 0.5),
			Vector3(def.width, 0.3, Vector2(ramp, rise).length()), Vector3(pitch, 0, 0))
	_solid(node, Vector3(0, -0.15, ramp * 0.5), Vector3(def.width, 0.3, length - ramp))
	return node


static func _cove_boat(parent: Node3D, base: Vector3, sail_colour := "red_canvas") -> Node3D:
	var boat := Node3D.new()
	boat.position = base
	boat.rotation_degrees.y = -24.0
	parent.add_child(boat)
	_box(boat, Vector3(0, 0.2, 0), Vector3(2.02, 0.52, 5.4), "tar")
	_box(boat, Vector3(0, 0.53, 0), Vector3(1.84, 0.16, 5.35), "wood")
	for side in [-1.0, 1.0]:
		_box(boat, Vector3(side * 1.03, 0.58, 0), Vector3(0.16, 0.54, 5.45), "edge")
		for end in [-1.0, 1.0]:
			_box(boat, Vector3(side * 0.57, 0.48, end * 3.11),
				Vector3(0.18, 0.66, 1.5), "wood", Vector3(0, -end * side * 0.59, 0))
	_box(boat, Vector3(0, 2.55, 0), Vector3(0.18, 4.1, 0.18), "wood")
	_box(boat, Vector3(0, 3.62, 0.05), Vector3(3.5, 0.12, 0.13), "edge")
	_box(boat, Vector3(0, 2.93, 0.19), Vector3(3.15, 1.4, 0.06), sail_colour, Vector3(0.16, 0, 0)).name = "Sail"
	_box(boat, Vector3(0.43, 4.36, 0.06), Vector3(0.88, 0.38, 0.04), "tar")
	return boat


static func ferry_hull(parent: Node3D, salt: bool) -> Node3D:
	var hull := _cove_boat(parent, Vector3.ZERO, "red_canvas" if salt else "linen")
	hull.name = "Hull"
	hull.rotation = Vector3.ZERO
	hull.scale = Vector3(1.45, 1.5, 1.2)
	for side in [-1.0, 1.0]:
		_box(hull, Vector3(side * 0.72, 0.83, -1.98), Vector3(0.32, 0.38, 0.35), "edge")
	_box(hull, Vector3(-0.54, 0.79, 1.63), Vector3(0.78, 0.38, 0.65), "wood")
	return hull


static func _well(parent: Node3D, base: Vector3) -> void:
	_round(parent, base + Vector3(0.0, 0.27, 0.0), 0.98, 1.05, 0.55, "stone")
	_round(parent, base + Vector3(0.0, 0.555, 0.0), 0.69, 0.71, 0.028, "mortar")
	_solid(parent, base + Vector3(0.0, 0.27, 0.0), Vector3(1.56, 0.56, 1.56))
	for side in [-1.0, 1.0]:
		_box(parent, base + Vector3(side * 0.84, 0.85, 0.0), Vector3(0.15, 1.55, 0.16), "wood")
	_box(parent, base + Vector3(0.0, 1.60, 0.0), Vector3(2.18, 0.12, 0.51), "edge")

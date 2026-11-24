extends RefCounted
## Landmark props are authored around the route, with foliage streamed in batches.

const NATURE := "res://assets/environment/nature/"
const MATERIAL := preload("res://game/world/lantern_coast/painted_prop.gdshader")
const SCENERY_LAYOUT := preload("res://game/world/lantern_coast/scenery_layout.tres")
const ATLAS := preload("res://game/world/lantern_coast/atlas.tres")
const BIOME_MODELS := {
	"meadow": ["trees/CommonTree_1", "rocks/Rock_Medium_2", "plants/Bush_Common", "plants/Flower_4_Group", "grass/Clover_2", "grass/Grass_Common_Short"],
	"orchard": ["trees/CommonTree_2", "rocks/Rock_Medium_1", "plants/Bush_Common_Flowers", "plants/Flower_3_Group", "grass/Clover_1", "grass/Grass_Common_Short"],
	"wood": ["trees/Pine_2", "rocks/Rock_Medium_3", "plants/Fern_1", "plants/Bush_Common", "plants/Mushroom_Common", "grass/Grass_Wispy_Short"],
	"grave": ["trees/DeadTree_2", "rocks/Rock_Medium_2", "plants/Fern_1", "plants/Mushroom_Laetiporus", "plants/Mushroom_Common", "grass/Grass_Wispy_Short"],
	"quarry": ["trees/Pine_4", "rocks/Rock_Medium_3", "grass/Grass_Wispy_Short", "plants/Fern_1", "props/Pebble_Round_2", "grass/Grass_Wispy_Short"],
	"fen": ["trees/DeadTree_3", "rocks/Rock_Medium_2", "plants/Fern_1", "grass/Grass_Wispy_Tall", "grass/Clover_2", "grass/Grass_Wispy_Short"],
	"bank": ["trees/CommonTree_1", "rocks/Rock_Medium_1", "grass/Grass_Wispy_Tall", "plants/Fern_1", "grass/Grass_Wispy_Short", "grass/Clover_1"],
	"veil": ["trees/CommonTree_3", "rocks/Rock_Medium_3", "plants/Fern_1", "plants/Mushroom_Common", "plants/Flower_4_Group", "grass/Clover_2"],
	"scrub": ["", "rocks/Rock_Medium_2", "plants/Bush_Common", "grass/Grass_Wispy_Short", "props/Pebble_Round_3", "grass/Grass_Wispy_Short"],
	"ashland": ["trees/DeadTree_2", "rocks/Rock_Medium_3", "grass/Grass_Wispy_Short", "props/Pebble_Round_2", "grass/Grass_Wispy_Short", "props/Pebble_Round_3"],
	"alpine": ["trees/Pine_4", "rocks/Rock_Medium_2", "grass/Grass_Wispy_Short", "props/Pebble_Round_2", "grass/Grass_Wispy_Short", "rocks/Rock_Medium_1"],
	"summit": ["", "rocks/Rock_Medium_3", "props/Pebble_Round_2", "grass/Grass_Wispy_Short", "props/Pebble_Round_3", "rocks/Rock_Medium_2"],
	"dunes": ["", "rocks/Rock_Medium_3", "grass/Grass_Wispy_Short", "props/Pebble_Round_2", "grass/Grass_Wispy_Short", "props/Pebble_Round_3"],
	"island": ["trees/Pine_2", "rocks/Rock_Medium_2", "plants/Bush_Common", "grass/Grass_Wispy_Short", "plants/Flower_4_Group", "plants/Fern_1"],
}
const ROCK_TINTS := {
	"quarry": "b9b0a2", "fen": "7f9a84", "veil": "82998f", "scrub": "c49373",
	"ashland": "857375", "alpine": "c0ced3", "summit": "d2e0e2", "dunes": "d2aa7d",
}
const CANOPIES := {
	"meadow": ["trees/CommonTree_1", "trees/CommonTree_3", "trees/CommonTree_5"],
	"orchard": ["trees/CommonTree_1", "trees/CommonTree_2", "trees/CommonTree_5"],
	"wood": ["trees/Pine_1", "trees/Pine_3", "trees/Pine_5", "trees/CommonTree_4"],
	"grave": ["trees/DeadTree_1", "trees/DeadTree_4", "trees/TwistedTree_1", "trees/TwistedTree_5"],
	"fen": ["trees/DeadTree_1", "trees/DeadTree_3", "trees/TwistedTree_3"],
	"bank": ["trees/CommonTree_2", "trees/CommonTree_4", "trees/TwistedTree_5"],
	"veil": ["trees/CommonTree_3", "trees/CommonTree_4", "trees/TwistedTree_4"],
	"alpine": ["trees/Pine_3", "trees/Pine_4", "trees/Pine_5"],
	"quarry": ["trees/Pine_1", "trees/Pine_4", "trees/Pine_5"],
	"island": ["trees/Pine_1", "trees/Pine_2", "trees/Pine_5"],
	"ashland": ["trees/DeadTree_2", "trees/DeadTree_4", "trees/DeadTree_5"],
}
# Measured heights of the original glTF meshes, in world metres.
const TREE_HEIGHTS := {
	"CommonTree_1": 7.26, "CommonTree_2": 7.64, "CommonTree_3": 9.43, "CommonTree_4": 9.44, "CommonTree_5": 7.01,
	"DeadTree_1": 9.50, "DeadTree_2": 11.49, "DeadTree_3": 13.28, "DeadTree_4": 12.77, "DeadTree_5": 16.44,
	"Pine_1": 7.32, "Pine_2": 7.38, "Pine_3": 7.39, "Pine_4": 10.24, "Pine_5": 8.72,
	"TwistedTree_1": 16.73, "TwistedTree_2": 18.95, "TwistedTree_3": 16.07, "TwistedTree_4": 18.74, "TwistedTree_5": 15.66,
}

const TABLE := [
	# Centre, type, spread, count. Taller silhouettes stand mainly on the far side.
	[Vector2(-763, 175), "orchard", 8.0, 11],
	[Vector2(-763, 152), "orchard", 7.5, 9],
	[Vector2(-726, 144), "orchard", 8.0, 11],
	[Vector2(-725, 186), "meadow", 8.0, 13],
	[Vector2(-740, 159), "meadow", 9.5, 16],
	[Vector2(-691, 130), "orchard", 11.0, 14],
	[Vector2(-714, 120), "stone", 7.5, 18],
	[Vector2(-687, 110), "orchard", 5.5, 16],
	[Vector2(-680, 127), "meadow", 7.5, 17],
	[Vector2(-676, 152), "orchard", 8.0, 19],
	[Vector2(-668, 123), "stone", 7.0, 15],
	[Vector2(-710, 152), "meadow", 9.0, 27],
	[Vector2(-718, 172), "meadow", 9.0, 22],
	[Vector2(-694, 153), "meadow", 15.0, 29],
	[Vector2(-718, 153), "orchard", 3.9, 11],
	[Vector2(-723, 171), "meadow", 4.5, 17],
	[Vector2(-581, 57), "meadow", 5.0, 18],
	[Vector2(-569, 50), "meadow", 5.0, 17],
	[Vector2(-654, 152), "meadow", 9.0, 12],
	[Vector2(-611, 109), "orchard", 13.0, 18],
	[Vector2(-577, 78), "orchard", 12.0, 17],
	[Vector2(-572, 111), "meadow", 8.0, 12],
	[Vector2(-597, 37), "wood", 17.0, 23],
	[Vector2(-601, -12), "wood", 19.0, 25],
	[Vector2(-606, -64), "wood", 19.0, 25],
	[Vector2(-638, -110), "wood", 22.0, 28],
	[Vector2(-667, -160), "wood", 16.0, 24],
	[Vector2(-641, -183), "wood", 16.0, 20],
	[Vector2(-625, -138), "wood", 15.0, 20],
	[Vector2(-575, -166), "wood", 18.0, 24],
	[Vector2(-501, -168), "wood", 20.0, 20],
	[Vector2(-402, -209), "stone", 18.0, 21],
	[Vector2(-371, -163), "stone", 13.0, 13],
	[Vector2(-531, -59), "wood", 21.0, 24],
	[Vector2(-480, 17), "wood", 20.0, 22],
	[Vector2(-415, 135), "fen", 19.0, 24],
	[Vector2(-343, 147), "fen", 14.0, 22],
	[Vector2(-302, 151), "fen", 18.0, 27],
	[Vector2(-400, 88), "fen", 12.0, 22],
	[Vector2(-404, 67), "fen", 8.0, 22],
	[Vector2(-374, 81), "fen", 8.0, 20],
	[Vector2(-370, 101), "fen", 9.0, 19],
	[Vector2(-370, 73), "fen", 12.0, 21],
	[Vector2(-341, 62), "stone", 12.0, 22],
	[Vector2(-356, 38), "wood", 12.0, 16],
	[Vector2(-236, 57), "wood", 13.0, 17],
	[Vector2(-132, -23), "stone", 13.0, 18],
	[Vector2(-67, -66), "stone", 18.0, 20],
	[Vector2(92, -234), "meadow", 17.0, 21],
	[Vector2(135, -183), "orchard", 19.0, 19],
	[Vector2(70, 197), "fen", 14.0, 17],
	[Vector2(120, 209), "meadow", 10.0, 14],
	[Vector2(276, -3), "meadow", 11.0, 12],
	[Vector2(339, 166), "stone", 18.0, 18],
	[Vector2(371, 203), "stone", 14.0, 12],
	[Vector2(551, -43), "stone", 18.0, 23],
	[Vector2(605, -45), "stone", 14.0, 15],
	[Vector2(433, -333), "alpine", 18.0, 25],
	[Vector2(472, -340), "alpine", 15.0, 20],
	[Vector2(396, -329), "alpine", 24.0, 24],
	[Vector2(364, -290), "alpine", 23.0, 22],
	[Vector2(518, -356), "alpine", 24.0, 26],
	[Vector2(551, -326), "alpine", 20.0, 21],
	[Vector2(695, 232), "stone", 15.0, 16],
	[Vector2(750, 250), "stone", 19.0, 21],
	[Vector2(697, 287), "stone", 9.0, 18],
	[Vector2(763, 286), "stone", 9.0, 14],
	[Vector2(662, 252), "dunes", 19.0, 18],
	[Vector2(792, 217), "dunes", 21.0, 22],
	[Vector2(816, 238), "dunes", 18.0, 18],
	[Vector2(702, 300), "dunes", 17.0, 17],
	[Vector2(147, -158), "veil", 18.0, 25],
	[Vector2(177, -180), "veil", 20.0, 30],
	[Vector2(190, -157), "veil", 18.0, 23],
	[Vector2(153, -181), "veil", 10.0, 21],
	[Vector2(165, -182), "veil", 11.0, 24],
	[Vector2(172, -157), "veil", 8.0, 20],
	[Vector2(790, 235), "dunes", 9.0, 18],
	[Vector2(620, 466), "fen", 8.0, 12],
	[Vector2(791, -214), "stone", 15.0, 24],
]
const KITS := {
	"orchard": ["trees/CommonTree_1", "plants/Bush_Common_Flowers", "plants/Flower_3_Group", "grass/Clover_1"],
	"meadow": ["grass/Grass_Common_Short", "plants/Flower_3_Group", "grass/Clover_1", "plants/Flower_3_Group"],
	"wood": ["trees/TwistedTree_2", "trees/Pine_2", "plants/Fern_1", "plants/Bush_Common_Flowers"],
	"fen": ["trees/DeadTree_2", "plants/Fern_1", "grass/Grass_Wispy_Short", "grass/Clover_1"],
	"stone": ["rocks/Rock_Medium_1", "props/Pebble_Round_2", "rocks/Rock_Medium_1", "grass/Grass_Wispy_Short"],
	"alpine": ["trees/Pine_2", "rocks/Rock_Medium_1", "props/Pebble_Round_2", "grass/Grass_Wispy_Short"],
	"dunes": ["rocks/Rock_Medium_1", "props/Pebble_Round_2", "grass/Grass_Wispy_Short", "props/Pebble_Round_2"],
	"veil": ["trees/Pine_2", "plants/Mushroom_Common", "plants/Fern_1", "plants/Flower_3_Group"],
}

static var _materials := {}


static func props(land, landmarks: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var shoreline := ATLAS.get_meta("water_crossings", []) as Array
	for group in TABLE:
		var centre: Vector2 = group[0]
		var kind: String = group[1]
		var spread: float = group[2]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(centre)
		for i in int(group[3]):
			var key: String = KITS[kind][i % 4]
			var tall := key.begins_with("trees/")
			var point := centre + Vector2.from_angle(rng.randf_range(0.0, TAU)) * (sqrt(rng.randf()) * spread)
			var sample: Vector2 = land.floor_sample(point)
			if sample.x < 0.75 or sample.y > 0.47 or land.road_at(point, true) > (0.03 if tall else 0.15):
				continue
			if tall and landmarks.any(func(h): return point.distance_squared_to(Vector2(h.point[0], h.point[1])) < 210.0):
				continue
			if tall and _near_water_crossing(point, shoreline):
				continue
			var scale := _scale(key, kind) * rng.randf_range(0.75, 1.23)
			if tall:
				scale = maxf(scale, _tree_scale(key, lerpf(5.4, 8.1, fposmod(point.x + point.y, 1.0))))
			out.append({"model": NATURE + key + ".gltf", "position": [point.x, point.y],
				"scale": scale, "rotation": rng.randf_range(0, 360), "heightOffset": -0.05,
				"collider": (0.65 * scale if tall else 0.0)})
	# These silhouettes were placed in the actual camera frame. Low plants
	# occupy the near corners, with the trees standing behind the road.
	for entry in [
		[-755, 185, "trees/CommonTree_1", 0.76],
		[-744, 173, "trees/CommonTree_1", 0.69],
		[-757, 196, "plants/Bush_Common_Flowers", 0.63],
		[-739, 193, "plants/Flower_3_Group", 0.44],
		[-741, 194, "plants/Flower_3_Group", 0.37],
		[-756, 169, "plants/Fern_1", 0.26],
		[-758, 166, "plants/Fern_1", 0.22],
		[-731, 157, "plants/Fern_1", 0.24],
		[-734, 154, "plants/Fern_1", 0.29],
		[-571, 96, "trees/CommonTree_1", 0.72],
		[-552, 106, "plants/Bush_Common_Flowers", 0.55],
		[-650, -155, "trees/TwistedTree_2", 0.35],
		[-656, -155, "trees/Pine_2", 0.80],
		[-655, -149, "trees/TwistedTree_2", 0.38],
		[-640, -150, "plants/Fern_1", 0.34],
		[-638, -153, "plants/Fern_1", 0.28],
		[-644, -144, "trees/DeadTree_2", 0.87],
		[-641, -137, "trees/Pine_2", 1.05],
		[-634, -129, "trees/Pine_2", 0.96],
		[-623, -122, "plants/Fern_1", 0.46],
		[-629, -122, "rocks/Rock_Medium_3", 1.34, 0.70],
		[-618, -128, "rocks/Rock_Medium_2", 1.24, 0.66],
		[-618, -123, "plants/Fern_1", 0.48],
		[-625, -138, "rocks/Rock_Medium_3", 1.39, 0.78],
		[-629, -142, "plants/Fern_1", 0.56],
		[-636, -152, "rocks/Rock_Medium_3", 1.20, 0.66],
		[-668, -124, "trees/TwistedTree_2", 0.42],
		[-672, -118, "trees/Pine_2", 0.8],
		[-660, -115, "plants/Fern_1", 0.30],
		[-652, -119, "plants/Fern_1", 0.28],
		[-710, 115, "trees/Pine_2", 0.61],
		[-706, 110, "plants/Fern_1", 0.23],
		[-711, 121, "rocks/Rock_Medium_2", 1.13],
		[-711.8, 123, "grass/Grass_Wispy_Tall", 0.51],
		[-698, 110, "plants/Fern_1", 0.43],
		[-686, 125, "rocks/Rock_Medium_3", 0.83],
		[-680, 129, "plants/Bush_Common_Flowers", 0.48],
		[-683, 148, "rocks/Rock_Medium_1", 0.92],
		[-679, 151, "trees/CommonTree_1", 0.63],
		[-681, 145, "plants/Fern_1", 0.36],
		[-714, 153, "plants/Bush_Common_Flowers", 0.70],
		[-710, 155, "props/Pebble_Round_2", 0.85],
		[-709, 154, "grass/Grass_Wispy_Short", 0.55],
		[-718, 168, "plants/Bush_Common_Flowers", 0.62],
		[-715, 170, "grass/Grass_Common_Short", 0.54],
		[-717, 154, "rocks/Rock_Medium_2", 0.41],
		[-718, 155, "grass/Grass_Common_Short", 0.64],
		[-718.6, 154.8, "plants/Flower_3_Group", 0.47],
		[-723, 168, "props/Pebble_Round_2", 0.86],
		[-724.2, 169, "grass/Grass_Wispy_Short", 0.68],
		[-724.6, 169.5, "plants/Flower_3_Group", 0.46],
		[-571.8, 54, "rocks/Rock_Medium_3", 0.62],
		[-571.8, 55.2, "plants/Bush_Common_Flowers", 0.66],
		[-572.1, 56.2, "plants/Fern_1", 0.37],
		[-584.8, 55.8, "rocks/Rock_Medium_1", 0.57],
		[-584.2, 56.9, "plants/Fern_1", 0.45],
		[-584.3, 57.4, "grass/Grass_Wispy_Short", 0.59],
		[-758, 170, "plants/Bush_Common_Flowers", 0.51],
		[-753, 178, "plants/Flower_3_Group", 0.44],
		[-754, 178, "grass/Grass_Common_Short", 0.61],
		[-358, 66, "grass/Grass_Wispy_Tall", 0.45],
		[-354, 63, "grass/Grass_Wispy_Tall", 0.55],
		[-362, 60, "plants/Fern_1", 0.48],
		[-358, 61, "rocks/Rock_Medium_2", 0.50],
		[-350, 52, "rocks/Rock_Medium_2", 0.88],
		[-386, 77, "grass/Grass_Wispy_Tall", 0.52],
		[-384, 77, "grass/Grass_Wispy_Tall", 0.68],
		[-394, 80, "grass/Grass_Wispy_Tall", 0.57],
		[-299, 186, "grass/Grass_Wispy_Tall", 0.52],
		[-294, 184, "grass/Grass_Wispy_Tall", 0.61],
		[736, 295, "rocks/Rock_Medium_2", 1.20],
		[738, 295, "grass/Grass_Wispy_Short", 0.64],
		[718, 298, "rocks/Rock_Medium_3", 0.67],
		[714, 295, "grass/Grass_Wispy_Tall", 0.59],
		[-381, -216, "rocks/Rock_Medium_1", 1.35],
		[-369, -222, "rocks/Rock_Medium_1", 1.18],
		[149, -171, "trees/Pine_2", 0.85],
		[145, -173, "trees/Pine_2", 0.67],
		[155, -176, "trees/CommonTree_1", 0.79],
		[162, -175, "rocks/Rock_Medium_3", 1.1],
		[160, -176, "plants/Mushroom_Common", 0.52],
		[159, -174, "plants/Mushroom_Common", 0.33],
		[166, -177, "plants/Fern_1", 0.44],
		[173, -180, "trees/Pine_2", 0.81],
		[179, -179, "rocks/Rock_Medium_2", 0.89],
		[158, -162, "plants/Fern_1", 0.39],
		[162, -162, "grass/Clover_1", 0.62],
		[167, -163, "plants/Mushroom_Common", 0.35],
		[-401, 72, "trees/DeadTree_2", 0.53],
		[-399, 74, "rocks/Rock_Medium_2", 0.7],
		[-398, 73, "plants/Fern_1", 0.4],
		[-388, 71, "grass/Grass_Wispy_Tall", 0.66],
		[-386, 73, "grass/Grass_Wispy_Tall", 0.66],
		[-383, 76, "grass/Grass_Wispy_Tall", 0.68],
		[-394, 81, "grass/Grass_Wispy_Tall", 0.58],
		[785, 235, "rocks/Rock_Medium_3", 1.48],
		[783, 237, "rocks/Rock_Medium_1", 0.90],
		[784, 237, "grass/Grass_Wispy_Tall", 0.46],
		[783, 240, "grass/Grass_Wispy_Short", 0.69],
		[795, 252, "rocks/Rock_Medium_2", 1.19],
		[799, 254, "grass/Grass_Wispy_Tall", 0.64],
		[525, -350, "rocks/Rock_Medium_3", 1.12],
		[527, -352, "rocks/Rock_Medium_2", 0.63],
		[515, -339, "trees/Pine_2", 0.65],
		[511, -340, "rocks/Rock_Medium_3", 0.95],
		[-260, 84, "trees/Pine_2", 0.95],
		[-264, 88, "rocks/Rock_Medium_3", 1.50, 0.85],
		[-249, 84, "rocks/Rock_Medium_2", 1.65, 0.85],
		[-248, 86, "plants/Fern_1", 0.55],
		[-239, 68, "trees/Pine_2", 0.86],
		[469, 91, "rocks/Rock_Medium_3", 1.52, 0.83],
		[475, 91, "rocks/Rock_Medium_3", 1.39, 0.74],
		[480, 88, "grass/Grass_Wispy_Tall", 0.61],
		[515, -163, "rocks/Rock_Medium_3", 1.30, 0.75],
		[523, -170, "rocks/Rock_Medium_2", 1.42, 0.82],
		[519, -158, "trees/Pine_2", 0.96],
	]:
		var at := Vector2(entry[0], entry[1])
		var key: String = entry[2]
		var size: float = entry[3]
		if land.floor_height(at) < 0.7:
			continue
		var collider: float = entry[4] if entry.size() > 4 else 0.46 * size if key.begins_with("trees/") else 0.0
		if key.begins_with("trees/"):
			size = maxf(size, _tree_scale(key, 6.5))
		if collider > 0.0 and land.road_at(at, true) > 0.24:
			continue
		if collider > 0.0 and _near_water_crossing(at, shoreline):
			continue
		out.append({"model": NATURE + key + ".gltf", "position": [at.x, at.y],
			"scale": size, "rotation": float(posmod(int(at.x + at.y) * 17, 360)),
			"heightOffset": -0.05, "collider": collider})
	_add_districts(land, landmarks, out)
	for prop in out:
		if not str(prop.model).contains("/trees/Pine_"):
			continue
		var colour = land.colour_at(Vector2(prop.position[0], prop.position[1]))
		if colour is Color and colour.b > .62 and colour.b > colour.r + .025:
			prop.snow_cover = 2 if colour.b > .76 else 1
	return out


static func _add_districts(land, landmarks: Array, out: Array[Dictionary]) -> void:
	var clearance: Array[Vector2] = []
	for hunt in ATLAS.get_meta("hunts", []):
		for spawn in hunt.spawns:
			clearance.append(Vector2(spawn.position[0], spawn.position[1]))
	for spot in ATLAS.get_meta("fishing", []):
		clearance.append(Vector2(spot.bank[0], spot.bank[1]))
	var trunks := {}
	for prop in out:
		if prop.collider > 0.0:
			_remember_solid(trunks, Vector2(prop.position[0], prop.position[1]))
	for district in SCENERY_LAYOUT.get_meta("districts"):
		var region: String = district[0]
		var style: String = district[1]
		for i in district[2].size():
			var p := Vector2(district[2][i][0], district[2][i][1])
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(p) ^ hash(style)
			var spread := float(district[3])
			var shape := Vector2(1.0, rng.randf_range(.48, .86))
			var axis := rng.randf_range(0.0, PI)
			for j in 35:
				var offset := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * spread
				var at := p + (offset * shape).rotated(axis)
				var slot := j % 10
				var model: String = BIOME_MODELS[style][0 if slot == 0 else 1 if slot < 3 else 2 + slot % 4]
				_place_nature(land, landmarks, clearance, trunks, out, rng, region, style, model, at, false)
	for sequence in SCENERY_LAYOUT.get_meta("sequences"):
		var region: String = sequence[0]
		var style: String = sequence[1]
		for i in range(1, sequence[2].size()):
			var a := Vector2(sequence[2][i - 1][0], sequence[2][i - 1][1])
			var b := Vector2(sequence[2][i][0], sequence[2][i][1])
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(a) ^ hash(region)
			var along := a.direction_to(b)
			var n := maxi(1, ceili(a.distance_to(b) / 3.0))
			for j in n:
				var on_route := a.lerp(b, float(j) / n)
				var edge := along.orthogonal()
				if edge.dot(Vector2.ONE) < 0.0:
					edge = -edge
				for side in [-1.0, 1.0]:
					var at: Vector2 = on_route + edge * side * rng.randf_range(3.1, 8.5)
					var index := (j + i * 3) % 6
					if side > 0 and index == 0:
						index = 3
					var model: String = BIOME_MODELS[style][index]
					_place_nature(land, landmarks, clearance, trunks, out, rng, region, style, model, at, side > 0)
	for vignette in SCENERY_LAYOUT.get_meta("vignettes"):
		var region: String = vignette[0]
		var style: String = vignette[1]
		var centre := Vector2(vignette[2][0], vignette[2][1])
		var angle := deg_to_rad(float(vignette[3]))
		var models: Array = BIOME_MODELS[style]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(centre)
		# A tall backdrop, broken shoulders and a low foreground give the
		# fixed camera a frame while preserving playable floor in the middle.
		for slot in [[-16, -11, 0], [-9, -14, 0], [3, -17, 0], [-15, -6, 1], [14, -4, 1], [11, 9, 1]]:
			var at := centre + Vector2(slot[0], slot[1]).rotated(angle)
			_place_nature(land, landmarks, clearance, trunks, out, rng, region, style, models[slot[2]], at, false)
		for anchor: Vector2 in [Vector2(-10, -12), Vector2(13, -5), Vector2(-9, 8), Vector2(8, 10)]:
			for i in 17:
				var offset := Vector2(rng.randfn(0, 1.95), rng.randfn(0, 0.95))
				var at := centre + (anchor + offset).rotated(angle)
				_place_nature(land, landmarks, clearance, trunks, out, rng, region, style, models[2 + i % 4], at, true)


static func _place_nature(land, landmarks: Array, clearance: Array[Vector2], trunks: Dictionary,
		out: Array[Dictionary], rng: RandomNumberGenerator, region: String, style: String,
		model: String, at: Vector2, foreground: bool) -> void:
	if model.is_empty():
		return
	var tall := model.begins_with("trees/")
	var rock := model.begins_with("rocks/")
	var sample: Vector2 = land.floor_sample(at)
	if sample.x < .85 or sample.y > (.50 if rock else .42):
		return
	# Painted paths change grass coverage without moving generated objects.
	var road: float = land.road_at(at, true)
	if road > (.08 if tall or rock else .28) or land.paving_at(at, true) > .10:
		return
	if tall or rock:
		if _near_water_crossing(at, ATLAS.get_meta("water_crossings", [])):
			return
		for landmark in landmarks:
			var p := Vector2(landmark.point[0], landmark.point[1])
			if p.distance_squared_to(at) < (190.0 if tall else 54.0):
				return
		for safe in clearance:
			if safe.distance_squared_to(at) < 27.0:
				return
	# Base widths are measured from the imported meshes. Short grass reads at
	# ankle height. Rocks in front of a route stay below the player's waist.
	var scale_: float
	if tall:
		var alternatives: Array = CANOPIES.get(style, [model])
		model = alternatives[posmod(hash(at), alternatives.size())]
		var frame_height := rng.randf_range(7.8, 12.5)
		if foreground or style == "orchard":
			frame_height *= .76
		scale_ = _tree_scale(model, frame_height)
	elif rock:
		scale_ = rng.randf_range(.28, .64) * (.67 if foreground else 1.0)
	elif model.contains("Fern"):
		scale_ = rng.randf_range(.12, .24)
	elif model.contains("Bush") or model.contains("Wispy_Tall"):
		scale_ = rng.randf_range(.22, .43)
	else:
		scale_ = rng.randf_range(.15, .32)
	var collider := (.51 * scale_ if tall else .86 * scale_ if rock and scale_ > .43 else 0.0)
	if collider > 0:
		var key := Vector2i((at / 4.0).floor())
		for x in range(-1,2):
			for z in range(-1,2):
				for other in trunks.get(key + Vector2i(x,z), []):
					if at.distance_squared_to(other) < (11.0 if tall else 4.0):
						return
		_remember_solid(trunks, at)
	var prop := {"model": NATURE + model + ".gltf", "position": [at.x, at.y],
		"scale": scale_, "rotation": rng.randf_range(0.0,360.0), "heightOffset": -.055,
		"collider": collider, "coast_region": region}
	if rock and ROCK_TINTS.has(style):
		prop.tint = ROCK_TINTS[style]
	out.append(prop)


static func _remember_solid(trunks: Dictionary, point: Vector2) -> void:
	var key := Vector2i((point / 4.0).floor())
	if not trunks.has(key):
		trunks[key] = []
	trunks[key].append(point)


static func _tree_scale(model: String, metres: float) -> float:
	return metres / float(TREE_HEIGHTS[model.get_file()])


static func _near_water_crossing(at: Vector2, crossings: Array) -> bool:
	for path in crossings:
		for i in range(1, path.size()):
			var a := Vector2(path[i - 1][0], path[i - 1][1])
			var b := Vector2(path[i][0], path[i][1])
			if at.distance_squared_to(Geometry2D.get_closest_point_to_segment(at, a, b)) < 13.0:
				return true
	return false


static func _scale(model: String, kind: String) -> float:
	if model.contains("TwistedTree"):
		return 0.41
	if model.begins_with("trees/"):
		return 0.82 if kind != "fen" else 0.56
	if model.contains("Fern"):
		return 0.20
	if model.contains("Rock_Medium"):
		return 0.60
	if model.begins_with("props/"):
		return 0.6
	return 0.29


static func prop_material(key: String, colour: Color, glow: bool) -> ShaderMaterial:
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = MATERIAL
		mat.set_shader_parameter("pigment", colour)
		mat.set_shader_parameter("glow", 0.38 if glow else 0.0)
		mat.set_shader_parameter("grain_direction", Vector3(2.8, 0.65, 2.8) if key in ["wood", "edge", "roof", "moss", "slate"] else Vector3.ONE)
		_materials[key] = mat
	return _materials[key]

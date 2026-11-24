extends RefCounted
## Gathering routes around the settled hubs. Mining ranks are separate from character levels.

const FORAGE := {
	"oat":["wild_garlic", "ditchbell", "ash_tree", "white_birch"],
	"bell":["wild_garlic", "ditchbell", "woundwort", "ash_tree", "white_birch"],
	"gloam":["ditchbell", "woundwort", "white_birch", "oak_tree"],
	"flint":["wild_garlic", "woundwort", "white_birch", "oak_tree"],
	"reed":["ditchbell", "woundwort", "bloodroot", "river_willow", "oak_tree"],
	"iron":["woundwort", "bloodroot", "oak_tree", "yew_tree"],
	"ash":["bloodroot", "gravemoss", "oak_tree", "yew_tree"],
	"tide":["woundwort", "bloodroot", "river_willow", "salt_cedar"],
	"gate":["ditchbell", "bloodroot", "oak_tree", "salt_cedar"],
	"red":["woundwort", "bloodroot", "salt_cedar"],
	"cinder":["bloodroot", "gravemoss", "ironbark_tree"],
	"white":["woundwort", "gravemoss", "yew_tree", "frostpine"],
	"salt":["woundwort", "bloodroot", "salt_cedar", "ironbark_tree"],
	"star":["bloodroot", "gravemoss", "salt_cedar", "ironbark_tree"],
	"crown":["gravemoss", "ironbark_tree"],
}

# Ridge and foothill anchors keep prospecting near a road or trail players can follow.
const SEAMS := {
	"oat":[Vector2(-699, 125), ["fieldstone", "copper_vein"]],
	"bell":[Vector2(-557, 49), ["fieldstone", "copper_vein"]],
	"gloam":[Vector2(-664, -120), ["copper_vein", "tin_vein"]],
	"flint":[Vector2(-400, -218), ["copper_vein", "tin_vein", "bog_iron"]],
	"reed":[Vector2(-356, 64), ["tin_vein", "bog_iron"]],
	"iron":[Vector2(-77, -61), ["bog_iron", "granite_coal", "silver_vein"]],
	"ash":[Vector2(183, -160), ["granite_coal", "silver_vein", "slate_shelf"]],
	"tide":[Vector2(133, 198), ["granite_coal", "silver_vein"]],
	"gate":[Vector2(298, -10), ["silver_vein", "slate_shelf", "gold_vein"]],
	"red":[Vector2(461, 104), ["slate_shelf", "gold_vein", "mithril_vein"]],
	"cinder":[Vector2(609, -45), ["gold_vein", "mithril_vein", "marble_face", "cobalt_vein"]],
	"white":[Vector2(449, -356), ["marble_face", "cobalt_vein", "jade_seam"]],
	"salt":[Vector2(842, 181), ["jade_seam", "iridium_vein"]],
	"star":[Vector2(646, 432), ["cobalt_vein", "iridium_vein", "fallen_star"]],
	"crown":[Vector2(815, -227), ["jade_seam", "iridium_vein", "fallen_star"]],
}

const NEW_TREES := [
	["white_birch", "White birch", "CommonTree_1", 8, 0.92, "#d4ddac", "ash_log"],
	["river_willow", "River willow", "CommonTree_5", 12, 1.08, "#9fad76", "ash_log"],
	["salt_cedar", "Salt cedar", "CommonTree_3", 24, 0.91, "#c5b98d", "oak_log"],
	["frostpine", "Frostpine", "Pine_5", 42, 1.15, "#c5d9db", "yew_log"],
]


static func build(surface, hubs: Dictionary, reservations: Dictionary) -> void:
	DB.nodes.nodeKinds = DB.nodes.nodeKinds.duplicate()
	for row in NEW_TREES:
		DB.nodes.nodeKinds.append({"id":row[0], "name":row[1], "skill":"woodcutting", "verb":"Chop",
			"tool":"woodcuttingAxe", "toolName":"a hatchet", "model":"res://assets/environment/nature/trees/%s.gltf" % row[2],
			"level":row[3], "scale":row[4], "tint":row[5], "picks":[3, 5], "yields":{"item":row[6], "min":1, "max":1}})
	var used: Array[Vector2] = []
	for hub in SEAMS:
		var centre: Vector2 = SEAMS[hub][0]
		var kinds: Array = SEAMS[hub][1]
		for i in kinds.size():
			var kind: String = kinds[i]
			var outcrops := _spots(surface, centre, reservations, used, true, false, i, 5)
			if not outcrops.is_empty():
				DB.mining.veinGroups.append({"id":"lc_" + kind + "_" + hub, "name":kind.capitalize(),
					"live":mini(3, outcrops.size()), "respawn":[55, 100], "rocks":[{"rock":kind, "weight":1}], "outcrops":outcrops})
	for hub in FORAGE:
		var point: Array = hubs[hub].point
		var centre := Vector2(point[0], point[1])
		var kinds: Array = FORAGE[hub]
		for i in kinds.size():
			var kind: String = kinds[i]
			var tree: bool = DB.nodes.nodeKinds.any(func(k): return k.id == kind and k.skill == "woodcutting")
			var spots := _spots(surface, centre, reservations, used, false, tree, i, 5 if tree else 7)
			if not spots.is_empty():
				DB.nodes.nodeGroups.append({"id":"lc_" + kind + "_" + hub, "name":kind.capitalize(),
					"live":mini(3 if tree else 5, spots.size()), "respawn":[45, 90],
					"kinds":[{"kind":kind, "weight":1}], "spots":spots})


static func _spots(surface, centre: Vector2, reservations: Dictionary, used: Array[Vector2],
		mineral: bool, tree: bool, phase: int, amount: int) -> Array:
	var spots := []
	var stride := 5.0 if mineral else 7.0
	var clearance := 6.0 if mineral or tree else 3.8
	for band in 15:
		var radius := (5.0 if mineral else 19.0) + stride * band
		for ray in 28:
			var angle := (ray * 11 % 28) * TAU / 28.0 + band * 0.73 + phase * 1.4
			var at := (centre + Vector2.from_angle(angle) * radius).snapped(Vector2(0.01, 0.01))
			if in_reservation(at, reservations) or surface.clear_for_building(at, 1.25):
				continue
			var floor_info: Vector2 = surface.land.floor_sample(at)
			if floor_info.y > (0.65 if mineral else 0.44) or surface.land.road_at(at) > (0.17 if tree else 0.24):
				continue
			if not surface.stable_footing(at, 0.58 if tree else 0.42) or not surface.has_exit(at):
				continue
			if mineral and not near_rock(surface, at, floor_info.x):
				continue
			if used.any(func(existing): return existing.distance_squared_to(at) < clearance * clearance):
				continue
			used.append(at)
			spots.append([at.x, at.y])
			if spots.size() >= amount:
				return spots
	return spots


static func in_reservation(at: Vector2, reservations: Dictionary) -> bool:
	for centre in reservations:
		var radius: float = reservations[centre]
		if at.distance_squared_to(centre) <= radius * radius:
			return true
	return false


static func near_rock(surface, at: Vector2, base_height: float) -> bool:
	for ray in 12:
		var offset := Vector2.from_angle(ray * TAU / 12.0)
		for distance in [2.4, 4.5, 6.2]:
			var land: Vector2 = surface.land.floor_sample(at + offset * distance)
			if land.x >= base_height + 1.25 and land.y >= 0.57:
				return true
	return false

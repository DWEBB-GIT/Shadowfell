extends RefCounted
## Adapts the terrain survey's atlas to the game database for one session.

const ATLAS := preload("res://game/world/lantern_coast/atlas.tres")
const PLACEMENTS := preload("placement_records.gd")
const JOURNEY := preload("journey.gd")
const BUILDINGS := preload("settlement_building.gd")
const FERRY_DOCKS := preload("ferry_docks.gd")
const WORLD_ID := "lantern_coast"
const BOUNDS := {"minX": -960.0, "maxX": 960.0, "minZ": -544.0, "maxZ": 576.0}
const ANGLER := "lc_mill_angler"
const FISHING_LESSON := "lc_the_spare_rod"
const POI_KINDS := {
	"oat": "village", "bell": "town", "gloam": "ruin", "flint": "camp",
	"reed": "village", "iron": "fort", "ash": "landmark", "tide": "dock",
	"gate": "town", "red": "camp", "cinder": "camp", "white": "village",
	"salt": "dock", "star": "dock", "crown": "ruin",
}
const COAST_MOODS := {
	"oat": [95, "e0d7b0", "4d6561", "a5ad91", "94a7b3", 1.05, .84, .92, .83],
	"bell": [72, "ded4ba", "596777", "aba18e", "899ab1", 1.04, .85, .95, .82],
	"gloam": [104, "b4b7a1", "3a5366", "486573", "718895", 1.10, .74, 2.32, .55],
	"flint": [84, "ded0aa", "626473", "a19b8e", "979896", 1.08, .78, 1.18, .76],
	"reed": [79, "c5c4a7", "415d53", "718878", "839995", 1.04, .78, 1.84, .66],
	"iron": [78, "d4c9ad", "505d73", "8796a3", "8394aa", 1.09, .79, 1.22, .78],
	"ash": [104, "ded6b0", "596b70", "a1aa93", "8ea0ad", 1.05, .81, 1.04, .81],
	"tide": [81, "d3cbb2", "586e7a", "8aa2a5", "849bab", 1.06, .82, 1.38, .76],
	"gate": [78, "ded0ad", "626979", "aa9c88", "9a9a9c", 1.05, .83, 1.02, .80],
	"red": [102, "dec8a0", "78626a", "aa8c75", "9d9390", 1.07, .81, .97, .85],
	"cinder": [107, "c9a48d", "51434b", "715952", "8d7d7b", 1.12, .74, 1.80, .62],
	"white": [102, "d6e1df", "556b8a", "9eafbb", "a5b5c3", 1.10, .73, 2.28, .69],
	"salt": [101, "e1cba5", "7b6a72", "b9a48c", "a09a97", 1.08, .79, .97, .86],
	"star": [75, "c9cbbd", "4d6179", "768c9f", "8495ad", 1.10, .76, 1.54, .71],
	"crown": [98, "cfb7a1", "504d65", "6c677e", "7c7b96", 1.12, .76, 1.71, .61],
}


static func grades() -> Array:
	var zones := []
	for hub in ATLAS.get_meta("hubs"):
		if not COAST_MOODS.has(hub.id):
			continue
		var mood: Array = COAST_MOODS[hub.id]
		zones.append(ZoneGrade.parse({"name": hub.name, "position": hub.point,
			"radius": mood[0], "feather": 66, "tint": mood[1], "shadowTint": mood[2],
			"fogColor": mood[3], "ambientColor": mood[4], "contrast": mood[5],
			"saturation": mood[6], "mist": mood[7], "sunlight": mood[8],
			"fogNear": 36.0, "fogFar": 114.0, "fogAmount": 0.76,
			"brightness": .95, "tintStrength": .21, "ambient": .89}))
	# Woodland fog starts beyond the lantern bridge and thickens in the
	# burial hollow. These use the same eased fog and lighting as the world.
	zones.append(ZoneGrade.parse({"name": "Gloamwood approach", "position": [-611, -108],
		"radius": 49, "feather": 57, "fogColor": "4f6771", "fogNear": 39.0, "fogFar": 100.0,
		"fogAmount": 0.88, "mist": 2.0, "sunlight": 0.64}))
	zones.append(ZoneGrade.parse({"name": "Bell Barrows", "position": [-665, -120],
		"radius": 32, "feather": 37, "fogColor": "4a5f72", "fogNear": 28.0, "fogFar": 85.0,
		"fogAmount": 0.91, "mist": 2.55, "sunlight": 0.50, "ambient": 0.88}))
	zones.append(ZoneGrade.parse({"name": "Reedmire low bog", "position": [-356, 133],
		"radius": 64, "feather": 46, "fogColor": "748d76", "fogNear": 27.0, "fogFar": 81.0,
		"fogAmount": 0.93, "mist": 2.18, "sunlight": 0.72, "ambientColor": "91a899",
		"shadowTint": "354e4c", "saturation": 0.79}))
	zones.append(ZoneGrade.parse({"name": "Veilwood Hollow", "position": [161, -169],
		"radius": 30, "feather": 25, "fogColor": "679b82", "fogNear": 30.0, "fogFar": 92.0,
		"fogAmount": 0.87, "mist": 2.05, "sunlight": 0.70, "ambientColor": "9ba7bd",
		"shadowTint": "4b517f", "tint": "bed1aa", "saturation": .84, "motes": 1.0}))
	zones.append(ZoneGrade.parse({"name": "Redwash wind", "position": [360, 170],
		"radius": 69, "feather": 61, "fogColor": "c39a75", "fogNear": 44.0, "fogFar": 112.0,
		"fogAmount": 0.82, "mist": 0.95, "dust": 0.45}))
	zones.append(ZoneGrade.parse({"name": "Saltglass wind", "position": [722, 239],
		"radius": 112, "feather": 49, "fogColor": "b8a28b", "fogNear": 34.0, "fogFar": 99.0,
		"fogAmount": 0.87, "mist": 1.19, "dust": 0.96, "sunlight": .86, "tint": "e2cda9",
		"ambientColor": "a79d9b", "saturation": .79}))
	for position in [[401, -315], [500, -329]]:
		zones.append(ZoneGrade.parse({"name": "Whitehorn snowline", "position": position,
			"radius": 70, "feather": 56, "fogColor": "a5bdce", "fogNear": 30.0, "fogFar": 84.0,
			"fogAmount": 0.88, "mist": 2.25, "snow": 1.0}))
	zones.append(ZoneGrade.parse({"name": "Whitehorn high shelf", "position": [460, -402],
		"radius": 55, "feather": 23, "fogColor": "a5bdce", "fogNear": 32.0, "fogFar": 102.0,
		"fogAmount": 0.84, "mist": 2.05, "snow": 1.0}))
	zones.append(ZoneGrade.parse({"name": "Stonecutters' Passage", "position": [-462, -224],
		"radius": 7, "feather": 6, "fogColor": "787378", "fogNear": 20.0, "fogFar": 66.0,
		"mist": 1.08, "ambient": .63, "sunlight": .60}))
	return zones


static func make_world(edits := {}) -> Dictionary:
	if edits.is_empty():
		edits = PLACEMENTS.read()
	var hubs: Array = ATLAS.get_meta("hubs")
	var world := {
		"id": WORLD_ID,
		"bounds": BOUNDS.duplicate(),
		"playerStart": {"position": hubs[0].point.duplicate(), "facing": 180},
		"openingText": "Young boars graze just south of Oatwick. Nell has a spare fishing rod at the millpond. The road east leads to Bellharbor.",
		"regions": [],
		"pois": [],
		"subzones": [],
		"roads": [],
		"boats": [],
		"shrines": [],
		"npcSpawns": [{"npc": ANGLER, "position": [-754, 173]}],
		"enemySpawns": [],
		"placedLoot": [],
		"dangerZones": [],
		"water": ATLAS.get_meta("fishing", []).duplicate(true),
		"fishingTrainer": ANGLER,
	}
	var by_id := {}
	for hub in hubs:
		by_id[hub.id] = hub
		var id := "lc_" + str(hub.id)
		var label := str(hub.name)
		var name := label.get_slice(" · ", 0)
		var level := label.get_slice(" · ", 1).replace("–", "-").get_slice(" / ", 0)
		if not level.get_slice("-", 0).is_valid_int():
			level = ""
		world.regions.append({
			"id": id, "name": name, "levels": level,
			"coastCenter": hub.point.duplicate(),
		})
		world.pois.append({
			"id": id, "name": name, "region": id, "kind": POI_KINDS.get(hub.id, "place"),
			"at": hub.point.duplicate(), "noMarker": true,
			"hub": id, "levels": level,
			"note": "Suggested levels %s." % level if level != "" else "",
		})
	for lookout in ATLAS.get_meta("overlooks"):
		var name: String = lookout.name
		world.pois.append({
			"id": "lc_" + name.to_snake_case(), "name": name, "kind": "landmark",
			"at": lookout.position.duplicate(), "noMarker": true,
			"note": "A perch above the coast.",
		})
	for trail in ATLAS.get_meta("footpaths", []):
		world.pois.append({
			"id": "lc_" + trail.id, "name": trail.name, "kind": trail.kind,
			"at": trail.at, "note": trail.note, "noMarker": true, "discoverRadius": 8.0,
		})
	for hunt in ATLAS.get_meta("hunts", []):
		var levels := "%d–%d" % [hunt.levels[0], hunt.levels[1]] if hunt.levels[0] != hunt.levels[1] else str(hunt.levels[0])
		world.enemySpawns.append_array(hunt.spawns)
		world.pois.append({
			"id": "lc_hunt_" + hunt.id, "name": hunt.name, "kind": "camp",
			"at": hunt.point, "region": "lc_" + hunt.hub, "noMarker": true, "discoverRadius": 16.0,
			"levels": levels, "huntingGround": true,
			"note": "Hunting ground · level %s%s" % [levels, " elite" if hunt.id == "crown_elite" else ""],
		})
	world.boats = FERRY_DOCKS.routes()
	for route in ATLAS.get_meta("routes"):
		if route.ferry:
			continue
		world.roads.append({
			"id": "lc_%s_%s" % [route.a, route.b],
			"name": route.get("name", ""),
			"halfWidth": route.get("paint_width", 2.65 if route.half >= 5 else 1.75),
			"points": route.points.duplicate(true),
		})
	if ResourceLoader.exists(PLACEMENTS.PATH):
		world.npcSpawns = edits.NPCs.filter(func(sp): return sp.npc == ANGLER or DB.npcs.has(sp.npc))
		world.enemySpawns = edits.Enemies.filter(func(sp): return DB.enemies.has(sp.enemy))
	return world


static func activate(surface = null) -> Dictionary:
	var old := {
		"world": DB.world, "world_map": DB.world_map, "scenery": DB.scenery,
		"water": DB.water, "mining": DB.mining, "nodes": DB.nodes, "quests": DB.quests,
		"npcs": DB.npcs, "loot_tables": DB.loot_tables, "items": DB.items, "locations": DB.locations,
		"skills": DB.skills, "recipes": DB.recipes, "archetypes": DB.archetypes,
		"shops": DB.shops,
		"infamy": DB.infamy, "boons": DB.boons,
	}
	var edits := PLACEMENTS.read()
	if surface != null:
		surface.prepare_buildings(edits.Props)
	DB.world = make_world(edits)
	DB.world_map = {}
	DB.scenery = {"props": edits.Props, "clearings": [], "lights": [], "witchlights": []}
	DB.water = {}
	DB.mining = DB.mining.duplicate()
	DB.mining.veinGroups = []
	DB.nodes = DB.nodes.duplicate()
	DB.nodes.nodeGroups = []
	# Keep quest definitions available to the character's save and journal.
	DB.quests = DB.quests.duplicate()
	for id in DB.quests:
		if DB.quests[id].get("autoAccept", false):
			DB.quests[id] = DB.quests[id].duplicate()
			DB.quests[id].autoAccept = false
	_add_fishing_content()
	if surface != null:
		surface.set_fishing_water(DB.world.water)
	var campaign: Dictionary = old.world
	if not campaign.has("questHubs"):
		campaign = DB.new_map_world(campaign, "res://data/terrain/new_map/spawns.json")
	JOURNEY.build(surface, campaign)
	if surface != null:
		_staff_buildings(surface)
	Layout.setup(DB.world, DB.scenery)
	WorldMap.setup()
	WorldMap.boats = DB.world.boats
	return old


static func place_gathering(surface) -> void:
	JOURNEY.place_gathering(surface)


static func _staff_buildings(surface) -> void:
	var staff := {"Bellharbor Counting House":"lc_reeve",
		"Flintcut Tool Hut":"lc_base_resident_garet", "Reedmire Net Menders Hut":"lc_base_resident_nymm",
		"Saltglass Caravan Office":"lc_salt_warden"}
	for name in BUILDINGS.INNS:
		staff[name] = "lc_" + BUILDINGS.INNS[name] + "_inn"
	staff["Oatwick Cookhouse"] = "lc_elsie"
	for site in surface.buildings:
		var id: String = staff.get(site.def.name, "")
		if id.is_empty() or not DB.npcs.has(id):
			continue
		var desk := BUILDINGS.to_world(site, Vector2(-site.size.x * 0.5 + 2.25, -site.size.y * 0.5 + 2.35))
		var arrival := BUILDINGS.to_world(site, Vector2(0, site.size.y * 0.5 - 1.42))
		var position := [desk.x, desk.y]
		for row in DB.world.npcSpawns:
			if row.npc == id:
				row.position = position
				row.facing = rad_to_deg(site.yaw)
		if DB.locations.has(id):
			DB.locations[id].position = position
		if DB.npcs[id].get("innkeeper", false):
			DB.npcs[id] = DB.npcs[id].duplicate()
			DB.npcs[id].title = site.def.name
			DB.npcs[id].innArrival = [arrival.x, arrival.y]
			DB.npcs[id].innLabel = site.def.name
			var hearth := BUILDINGS.to_world(site, Vector2(0, -site.size.y * 0.5 + 1.42))
			var hearth_id: String = "lc_" + BUILDINGS.INNS[site.def.name] + "_hearth"
			var hearth_name: String = site.def.name + " hearth"
			DB.world.stations.append({"id":hearth_id, "name":hearth_name, "kind":"fire",
				"position":[hearth.x, hearth.y], "radius":2.0, "indoors":true})
			DB.locations[hearth_id] = {"name":hearth_name, "position":[hearth.x, hearth.y], "radius":2.0}


static func restore(old: Dictionary) -> void:
	DB.world = old.world
	DB.world_map = old.world_map
	DB.scenery = old.scenery
	DB.water = old.water
	DB.mining = old.mining
	DB.nodes = old.nodes
	DB.quests = old.quests
	DB.npcs = old.npcs
	DB.loot_tables = old.loot_tables
	DB.items = old.items
	DB.locations = old.locations
	DB.skills = old.skills
	DB.recipes = old.recipes
	DB.archetypes = old.archetypes
	DB.shops = old.shops
	DB.infamy = old.infamy
	DB.boons = old.boons
	Layout.setup(DB.world, DB.scenery)
	WorldMap.setup()


static func _add_fishing_content() -> void:
	DB.npcs = DB.npcs.duplicate()
	DB.npcs[ANGLER] = PLACEMENTS.ANGLER_DEF.duplicate(true)
	DB.world.fishingLesson = {"quest":FISHING_LESSON, "water":"lc_millpond"}
	DB.locations = DB.locations.duplicate()
	var skill_levels := {"lc_fallpool":8, "lc_oxbow":14, "lc_reedpond":21, "lc_pirate_cove":32}
	for spot in DB.world.water:
		spot.fishLevel = skill_levels.get(spot.id, 1)
		if spot.id in ["lc_oxbow", "lc_reedpond"]:
			spot.fishTable = "blackpool_fish"
		DB.locations[spot.id] = {"name": spot.name, "position": spot.position, "radius": maxf(spot.rx, spot.rz)}
	DB.quests[FISHING_LESSON] = {
		"id": FISHING_LESSON, "map": WORLD_ID, "name": "The Spare Rod",
		"giver": ANGLER, "turnIn": ANGLER, "minLevel": 1, "level": [1, 5],
		"offer": "Nell holds out a rod. “This one belonged to my brother. He swore the fish were too clever for it, but I watched him bait it with cheese.”",
		"progress": "Try Fishing from the millpond bank. Cast within nine metres, then click the bobber or use {interact} when it dips. Bring Nell a Gloomwater perch.",
		"complete": "Nell looks at the perch. “Good. Keep the rod. If my brother asks for it back, tell him the fish have it.”",
		"lend": [{"item": "old_rod", "count": 1}],
		"acceptLearn": ["fishing"],
		"objectives": [{"id": "perch", "type": "collect", "target": "gloomwater_perch",
			"count": 1, "location": "lc_millpond", "label": "Catch a Gloomwater perch"}],
		"reward": {"items": [{"item": "fishing_rod", "count": 1}]},
	}
	DB.items = DB.items.duplicate()
	DB.items["lc_saltglass_mullet"] = U.merged(DB.items.silver_dace, {
		"id": "lc_saltglass_mullet", "name": "Saltglass mullet",
		"description": "A silver fish from the sandy shallows of Cutlass Cove.",
	})
	DB.loot_tables = DB.loot_tables.duplicate()
	DB.loot_tables["lc_cove_fish"] = {"drops": {"rolls": 1, "chance": 1,
		"rarity": {"junk": 12, "common": 88},
		"items": {"junk": [{"item": "old_boot", "weight": 1}],
			"common": [{"item": "lc_saltglass_mullet", "weight": 1}]}}}


static func nearest_region(x: float, z: float) -> Dictionary:
	var nearest := {}
	var nearest_distance := INF
	var at := Vector2(x, z)
	for region in DB.world.regions:
		var centre: Array = region.coastCenter
		var distance := at.distance_squared_to(Vector2(centre[0], centre[1]))
		if distance < nearest_distance:
			nearest = region
			nearest_distance = distance
	return nearest

extends RefCounted
## The Coast campaign layers quests and services over the edited terrain.

const ATLAS := preload("atlas.tres")
const MAP := "lantern_coast"
const HUBS_PATH := "res://data/quests/lantern_coast_hubs.json"
const CHAPTERS := [
	{"id":"gloam", "level":5, "hunt":"gloam_dead", "npc":"vr_morrow", "source":"vr_names", "needs":["lc_bell_receipt"],
		"name":"The Names They Left Behind", "notice":"The Erased Register", "evidence":"Burial register",
		"offer":"The graves started answering to numbers after the levy took the names. Put three gravewalkers down and read the register at Hollow Graves. I want to know who thought the dead could pay."},
	{"id":"flint", "level":10, "hunt":"flint_robbers", "npc":"in_edda", "source":"in_hold_the_lane", "needs":["lc_gloam_evidence"],
		"name":"Hold the Lane", "notice":"Coppervein Shift Board", "evidence":"Coppervein payroll",
		"offer":"The collectors sacked the shift office when the miners asked where their wages went. Clear the spoil yard and read the shift board. The names belong to people, even if the payroll says otherwise."},
	{"id":"reed", "level":11, "hunt":"reed_haunts", "npc":"wm_mossreed_landing_lead", "source":"wm_mossreed_landing_work", "needs":["lc_gloam_evidence"],
		"name":"The Landing Still Opens", "notice":"Crofters’ Landing Notice", "evidence":"Reedmire ferry receipts",
		"offer":"The drowned crofters are keeping the ferry bank to themselves. Clear their path and read the notice. We have people on both banks waiting for ordinary things to happen."},
	{"id":"iron", "level":16, "hunt":"iron_raiders", "npc":"in_sella", "source":"in_crossing_bill", "needs":["lc_flint_evidence","lc_reed_evidence"],
		"name":"The Toll That Was Paid", "notice":"Broken Toll Ledger", "evidence":"Ironstep orders",
		"offer":"Miners and boatmen showed me the same seal. The bowmen at Broken Toll take a second payment or take your cart. See what their orders say once you can stand there without catching an arrow."},
	{"id":"ash", "level":22, "hunt":"ash_crypt", "npc":"wm_greyroot_lead", "source":"wm_greyroot_work", "needs":["lc_iron_evidence"],
		"name":"The Knights’ Last Account", "notice":"Bell Knight Oath Stone", "evidence":"Bell Knight oath tablet",
		"offer":"Our dead knights still stand their watch. Somebody has told them the oath means guarding the king’s debts. Lay a few to rest and read the stone. I would rather trust the words they cut while alive."},
	{"id":"tide", "level":25, "hunt":"tide_camp", "npc":"wm_brinewatch_docks_lead", "source":"wm_brinewatch_docks_work", "needs":["lc_iron_evidence"],
		"name":"Wreckers’ Due", "notice":"Wreckers’ Signal List", "evidence":"Wreckers’ cargo manifest",
		"offer":"The wreckers answered our beacon with a false light. Clear their bluff and read the signal list. Ships cost money to replace. The people on them are harder."},
	{"id":"red", "level":28, "hunt":"red_camp", "npc":"wm_saltmere_lead", "source":"wm_saltmere_work", "needs":["lc_ash_evidence","lc_tide_evidence"],
		"name":"What the Sand Kept", "notice":"Siltjack Caravan Register", "evidence":"Siltjack stamped bill",
		"offer":"The Siltjacks insist they found these wagons abandoned. Their register lists how much they charged to abandon them. Clear the camp and read it yourself."},
	{"id":"cinder", "level":31, "hunt":"cinder_ogres", "npc":"wm_ashworks_lead", "source":"wm_ashworks_work", "needs":["lc_ash_evidence","lc_tide_evidence","lc_red_evidence"],
		"name":"The Cost of the Fire", "notice":"Cinder March Fuel Tallies", "evidence":"Crucible supply tally",
		"offer":"The foundry is burning marked relief timber. The ogres outside its yard were promised payment too. Clear an approach and see whose signature is on the fuel tallies."},
	{"id":"cinder_watch", "hub":"cinder", "level":36, "hunt":"cinder_dead", "npc":"wm_ember_relay_lead", "source":"wm_ember_relay_work", "needs":["lc_cinder_evidence"],
		"name":"After the Last Shift", "notice":"Cinder Watch Orders", "evidence":"Cinder relief warrant",
		"offer":"The last shift never clocked out. Their shades have orders to turn the relief wagons back. Take a look at the orders when the road is quiet."},
	{"id":"white", "level":40, "hunt":"white_wolves", "npc":"wm_frostgate_lead", "source":"wm_frostgate_work", "needs":["lc_cinder_watch_evidence"],
		"name":"A Winter’s Ration", "notice":"Whitehorn Ration Board", "evidence":"Whitehorn winter account",
		"offer":"The wolves broke into the lower flour store. Get the trail open and read the board. It should say who took the extra sacks. I know what it says about the wolves."},
	{"id":"white_watch", "hub":"white", "level":43, "hunt":"white_dead", "npc":"wm_hearthwatch_lead", "source":"wm_hearthwatch_work", "needs":["lc_white_evidence"],
		"name":"The Lights Above Whitehorn", "notice":"Whitehorn Watch Slate", "evidence":"The watch’s final witness",
		"offer":"The upper watch kept lighting lamps after they died. Read their slate. It may tell us what they expected to come through the pass."},
	{"id":"salt", "level":45, "hunt":"salt_bandits", "npc":"wm_saltroad_lead", "source":"wm_saltroad_work", "needs":["lc_white_evidence"],
		"name":"The Price of Water", "notice":"Saltglass Well Charter", "evidence":"The Saltglass witness seal",
		"offer":"The raiders have put a tariff on the wells. I asked if rain was included and they took it as a business suggestion. Clear the road and read the original charter."},
	{"id":"star", "level":48, "hunt":"star_dead", "npc":"wm_glass_road_lead", "source":"wm_glass_road_work", "needs":["lc_salt_evidence","lc_white_watch_evidence"],
		"name":"Entries for the Living", "notice":"Starfall Landing Register", "evidence":"Starfall free passage deed",
		"offer":"Take the ferry to Starfall. Drowned levy men are keeping lists at the landing. Put them down and read the register. The people on that list deserve an actual way home."},
]


const GATHERING_SITES := preload("gathering_sites.gd")
const SETTLEMENT_RADII := {"bell":39.0, "gloam":18.0, "flint":23.0,
	"reed":25.0, "iron":22.0, "ash":23.0, "tide":26.0, "gate":37.0, "red":36.0,
	"cinder":28.0, "white":25.0, "salt":33.0, "star":23.0}


static func build(surface, campaign_world: Dictionary) -> void:
	var hubs := _indexed(ATLAS.get_meta("hubs"))
	var hunts := _indexed(ATLAS.get_meta("hunts", []))
	if surface != null:
		_sync_hunting_sites(surface, hunts)
	var source_quests := DB.quests.duplicate()
	DB.world.stations = []
	DB.world.puzzles = []
	DB.world.journeyProps = []
	DB.world.lootBySpawn = {}
	DB.world.openingText = "The last cart has broken a wheel outside Oatwick. Speak to Abel, then read the road marker."
	for hunt in hunts.values():
		_location("lc_hunt_" + str(hunt.id), hunt.name, hunt.point, 24.0)
	_opening(surface, hubs, hunts, source_quests)
	for chapter in CHAPTERS:
		_chapter(surface, hubs, hunts, chapter, source_quests)
	_services(surface, hubs, campaign_world)
	_local_stories(surface, hubs, hunts, campaign_world, source_quests)
	_community(surface, hubs)
	var shaft := _dry(surface, hubs.bell.point, Vector2(16, -14))
	DB.world.blackpick = {"position":shaft, "minimum":8}
	DB.world.pois.append({"id":"lc_blackpick", "name":"Blackpick Mine", "kind":"dungeon", "region":"lc_bell",
		"at":shaft, "noMarker":true, "note":"Optional solo dungeon, levels 8–10. Take the mine lift beside the timber winch."})
	_prop("cart", [shaft[0] + 2.2, shaft[1] - 1.0])
	_prop("signpost", [shaft[0] - 1.8, shaft[1]])
	_contracts(surface, hubs, hunts)
	_finale(surface, hubs, hunts)
	_build_hub_stories(surface, hubs, hunts)
	if surface != null:
		var reservations := _settlement_reservations(surface, hubs)
		_protect_settlements(surface, reservations)
		_sync_hunting_sites(surface, hunts)
		for hunt in hunts.values():
			DB.locations["lc_hunt_" + str(hunt.id)].position = hunt.point


## Run after dressing and placed scenery register their collision footprints.
static func place_gathering(surface) -> void:
	var hubs := _indexed(ATLAS.get_meta("hubs"))
	GATHERING_SITES.build(surface, hubs, _settlement_reservations(surface, hubs))


static func _settlement_reservations(surface, hubs: Dictionary) -> Dictionary:
	var reservations := {Vector2(727, 299):19.0, Vector2(119, 306):13.0,
		Vector2(583, 459):12.0, Vector2(678, 449):12.0,
		Vector2(-748, 178):12.0} # Oatwick green ends at the lower pasture.
	for id in SETTLEMENT_RADII:
		var point: Array = hubs[id].point
		reservations[Vector2(point[0], point[1])] = SETTLEMENT_RADII[id]
	for site in surface.buildings:
		reservations[site.center] = maxf(site.size.x, site.size.y) * 0.62 + 4.5
	return reservations


static func _protect_settlements(surface, reservations: Dictionary) -> void:
	var spawns: Array = DB.world.enemySpawns
	for i in spawns.size():
		var spawn: Dictionary = spawns[i]
		var enemy: Dictionary = DB.enemies.get(spawn.enemy, {})
		if enemy.get("dummy", false) or enemy.get("lawful", "") in ["guard", "livestock"]:
			continue
		var from := Vector2(spawn.position[0], spawn.position[1])
		if not GATHERING_SITES.in_reservation(from, reservations):
			continue
		var end := _outside_settlement(surface, from, reservations, spawns)
		if not end.is_finite():
			push_warning("No eligible field location for settlement spawn %s" % spawn.id)
			continue
		spawns[i] = spawn.duplicate()
		spawns[i].position = [end.x, end.y]


static func _outside_settlement(surface, from: Vector2, reservations: Dictionary, spawns: Array) -> Vector2:
	for distance in range(4, 104, 4):
		for ray in 24:
			var at := from + Vector2.from_angle(ray * TAU / 24.0) * distance
			if GATHERING_SITES.in_reservation(at, reservations) or surface.clear_for_building(at, 1.0):
				continue
			if not surface.stable_footing(at, 0.7) or not surface.has_exit(at) or surface.land.road_at(at) > 0.64:
				continue
			if not spawns.any(func(sp): return Vector2(sp.position[0], sp.position[1]).distance_squared_to(at) < 16.0):
				return at
	return Vector2.INF


## Edited spawn positions can move a field away from its old map label.
static func _sync_hunting_sites(surface, hunts: Dictionary) -> void:
	var spawn_points := {}
	for sp in DB.world.enemySpawns:
		spawn_points[sp.id] = Vector2(sp.position[0], sp.position[1])
	for id in hunts:
		var original: Dictionary = hunts[id]
		var centre := Vector2(original.point[0], original.point[1])
		var points: Array[Vector2] = []
		for sp in original.spawns:
			var at: Vector2 = spawn_points.get(sp.id, Vector2.INF)
			if at.is_finite() and surface.walk_at(at) >= 0.5 and not surface.is_wading(at):
				points.append(at)
		if points.is_empty() or (surface.walk_at(centre) >= 0.5 and
				points.any(func(at): return at.distance_squared_to(centre) <= 324.0)):
			continue
		var mean := Vector2.ZERO
		for at in points:
			mean += at
		mean /= points.size()
		points.sort_custom(func(a, b): return a.distance_squared_to(mean) < b.distance_squared_to(mean))
		var hunt := original.duplicate()
		hunt.authored_point = original.point
		hunt.point = [points[0].x, points[0].y]
		hunts[id] = hunt
		for poi in DB.world.pois:
			if poi.id == "lc_hunt_" + id:
				poi.at = hunt.point
				break


static func _build_hub_stories(surface, hubs: Dictionary, hunts: Dictionary) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(HUBS_PATH))
	if not data is Dictionary:
		push_error("Lantern Coast hub stories could not be read.")
		return
	var trails := _indexed(ATLAS.get_meta("footpaths", []))
	for field in data.fields:
		var base: Dictionary = hunts[field.near]
		var region: String = field.get("hub", base.hub)
		var point := _dry(surface, base.get("authored_point", base.point), Vector2(field.offset[0], field.offset[1]))
		var spawns := []
		for index in field.enemies.size():
			var actor: Array = field.enemies[index]
			var id: String = "lc_base_%s_%d" % [field.id, index + 1]
			var at := _dry(surface, point, Vector2(actor[2], actor[3]))
			var encounter := {"respawn":int(field.get("respawn", 70))}
			if actor.size() > 4:
				encounter.name = actor[4]
			var spawn := {"id":id, "enemy":actor[0], "level":int(actor[1]), "position":at, "coastEncounter":encounter}
			DB.world.enemySpawns.append(spawn)
			spawns.append(spawn)
		var levels := Vector2i(spawns[0].level, spawns[0].level)
		for spawn in spawns:
			levels.x = mini(levels.x, spawn.level)
			levels.y = maxi(levels.y, spawn.level)
		hunts[field.id] = {"id":field.id, "name":field.name, "hub":region, "point":point, "spawns":spawns}
		var loc := "lc_hunt_" + str(field.id)
		_location(loc, field.name, point, 18.0)
		DB.world.pois.append({"id":loc, "name":field.name, "at":point, "region":"lc_" + region,
			"kind":"camp", "noMarker":true, "huntingGround":true, "discoverRadius":12.0,
			"levels":"%d–%d" % [levels.x, levels.y], "note":field.note})
	for resident in data.get("residents", []):
		var at := _dry(surface, hubs[resident.hub].point, Vector2(resident.offset[0], resident.offset[1]))
		_resident(resident.id, resident.model, at, {"name":resident.name, "title":resident.trade})
	for local in data.hubs:
		for task in local.quests:
			_add_hub_quest(surface, hubs, hunts, trails, local, task)
	for starter in data.links:
		if DB.quests.has(starter):
			DB.quests[starter].leadsFrom = data.links[starter]
	_coast_equipment(hunts, data.get("supplies", {}))


static func _add_hub_quest(surface, hubs: Dictionary, hunts: Dictionary, trails: Dictionary, local: Dictionary, task: Dictionary) -> void:
	var id := "lc_base_" + str(task.id)
	var giver: String = task.get("giver", local.contact)
	var recipient: String = task.get("turnIn", giver)
	var level := int(task.level)
	var extras := {"story":task.get("handoff", false), "localStory":not task.get("handoff", false),
		"handoff":task.get("handoff", false), "minLevel":int(task.get("min", maxi(1, level - 2))),
		"chapter":local.story, "requires":task.get("after", []), "leadsFrom":task.get("leadsFrom", []),
		"reward":{"size":"standard", "xpScale":float(task.get("xp", 0.58)) / DB.CONFIG.progression.questSizes.standard,
			"coins":4 + level * 4, "items":task.get("items", [])}}
	if task.has("skill"):
		extras.acceptLearn = [task.skill]
	if task.has("skillReq"):
		extras.skillReq = task.skillReq
	if task.has("choice"):
		extras.choice = task.choice
	if task.has("loan"):
		extras.lend = [{"item":task.loan, "count":1}]
	var objectives := []
	if task.has("starter"):
		var site: Dictionary = task.starter
		var trail: Dictionary = trails[site.trail]
		var offset: Array = site.get("offset", [2, -1])
		var place := _dry(surface, trail.at, Vector2(offset[0], offset[1]))
		var letter := id + "_item"
		_hub_item(letter, site.name)
		DB.world.placedLoot.append({"id":letter, "reward":{"item":letter, "count":1}, "position":place,
			"startsQuest":id, "model":"satchel", "name":site.name, "prompt":"Pick up %s" % site.name})
		extras.starterItem = letter
		objectives.append(_collect(letter, "Bring %s to %s" % [site.name, DB.npcs[recipient].name], 1, false, recipient))
	for objective in task.get("goals", []):
		objectives.append(_hub_objective(surface, hubs, hunts, trails, local.hub, id, objective, objectives.size()))
	_quest(id, task.name, giver, recipient, local.hub, level, task.offer, task.finish, objectives, extras)


static func _hub_objective(surface, hubs: Dictionary, hunts: Dictionary, trails: Dictionary, hub: String,
		quest: String, goal: Dictionary, index: int) -> Dictionary:
	var id := "%s_%d" % [quest, index]
	var count := int(goal.get("count", 1))
	match goal.kind:
		"talk":
			return _talk(goal.npc, goal.label)
		"kill":
			var objective := _kill(hunts[goal.hunt], count)
			objective.id = id
			objective.label = goal.label
			return objective
		"collect":
			return _collect(goal.item, goal.label, count, goal.get("keep", false), goal.location)
		"salvage":
			var hunt: Dictionary = hunts[goal.hunt]
			_hub_item(id, goal.item)
			for spawn in hunt.spawns:
				var local := _spawn_loot(spawn.id)
				local.questDrops.append({"quest":quest, "item":id, "chance":1.0})
			return _collect(id, goal.label, count, false, "lc_hunt_" + str(hunt.id))
	var at: Array = hubs[hub].point
	if goal.has("hunt"):
		at = hunts[goal.hunt].point
	if goal.has("trail"):
		at = trails[goal.trail].at
	if goal.has("near"):
		at = hubs[goal.near].point
	var offset: Array = goal.get("offset", [2, -2])
	at = _dry(surface, at, Vector2(offset[0], offset[1]))
	if goal.kind == "inspect":
		_notice(id, goal.item, at, hub, goal.note)
		var objective := _read(id, goal.label)
		objective.id = id
		return objective
	_document(id, goal.item, at, quest)
	return _collect(id, goal.label)


static func _hub_item(id: String, label: String) -> void:
	DB.items[id] = {"id":id, "name":label, "kind":"quest", "rarity":"quest", "stack":20, "icon":"book",
		"model":"satchel", "description":"Someone on the Lantern Coast is looking for this."}


static func _spawn_loot(id: String) -> Dictionary:
	if not DB.world.lootBySpawn.has(id):
		DB.world.lootBySpawn[id] = {"questDrops":[]}
	return DB.world.lootBySpawn[id]


static func _coast_equipment(hunts: Dictionary, supplies: Dictionary) -> void:
	var gear: Array = DB.items.values().filter(func(d):
		return (d.get("rarity") == "common" and DB.DURABLE_KINDS.has(d.get("kind"))
			and not d.get("quest", false) and not d.has("reservedFor") and int(d.get("itemLevel", 0)) >= 10))
	var by_level := {}
	for hunt in hunts.values():
		var goods: Array = supplies.get(hunt.hub, []).map(func(item): return {"item":item,"weight":1})
		for spawn in hunt.spawns:
			var level := int(spawn.level)
			var enemy: Dictionary = DB.enemies[spawn.enemy]
			if not enemy.get("worldDrops", true):
				continue
			var local := _spawn_loot(spawn.id)
			if not goods.is_empty():
				local.supplies = {"drops":{"rolls":1, "chance":0.19, "rarity":{"common":100}, "items":{"common":goods}}}
			if level <= 10:
				continue
			if not by_level.has(level):
				var stock := gear.filter(func(g): return absf(float(g.itemLevel) - level) <= 3.0)
				by_level[level] = stock.map(func(g): return {"item":g.id,"weight":2 if g.itemLevel <= level else 1})
			var pool: Array = by_level[level]
			if not pool.is_empty():
				local.drops = {"rolls":1, "chance":0.24 if enemy.get("elite", false) else 0.12,
					"rarity":{"common":83,"enhanced":17}, "items":{"common":pool,"enhanced":pool}}


static func _indexed(records: Array) -> Dictionary:
	var out := {}
	for record in records:
		out[record.id] = record
	return out


static func _dry(surface, xz: Array, offset := Vector2.ZERO, keep_entrances_clear := false) -> Array:
	var at := Vector2(xz[0], xz[1]) + offset
	if surface == null:
		return [at.x, at.y]
	for step in range(0, 25 if keep_entrances_clear else 17):
		for bearing in (1 if step == 0 else 12):
			var p := at + Vector2.from_angle(TAU * bearing / 12.0) * step
			if keep_entrances_clear and surface.clear_for_building(p, 1.45):
				continue
			if (surface.walk_at(p) >= 0.5 and surface.building_at(p).is_empty()
					and surface.land.floor_height(p) >= 0.85 and surface.land.floor_sample(p).y < 0.46):
				return [snappedf(p.x, .05), snappedf(p.y, .05)]
	return [at.x, at.y]


static func _resident(id: String, base: String, point: Array, change: Dictionary = {}) -> void:
	var npc: Dictionary = DB.npcs.get(base, DB.npcs.nell).duplicate(true)
	npc.erase("routine")
	npc.erase("dialogue")
	npc.merge(change, true)
	npc.id = id
	DB.npcs[id] = npc
	if not DB.world.npcSpawns.any(func(sp): return sp.npc == id or sp.get("person") == id):
		DB.world.npcSpawns.append({"npc":id, "position":point})
	_location(id, npc.name, point)


static func _location(id: String, label: String, position: Array, radius := 12.0) -> void:
	DB.locations[id] = {"name":label, "position":position, "radius":radius}


static func _notice(id: String, label: String, at: Array, hub: String, text: String) -> void:
	DB.world.pois.append({"id":id, "name":label, "kind":"landmark", "region":"lc_" + hub,
		"at":at, "note":text, "discoverRadius":8.0, "noMarker":true})
	_prop("signpost", at)
	_location(id, label, at)


static func _document(id: String, label: String, at: Array, quest: String) -> void:
	DB.items[id] = {"id":id, "name":label, "kind":"quest", "rarity":"quest", "stack":1,
		"icon":"book", "description":"Evidence for the Coast’s account."}
	DB.world.placedLoot.append({"id":id, "reward":{"item":id,"count":1}, "position":at, "quest":quest,
		"model":"satchel", "name":label, "prompt":"Recover %s" % label})
	_location(id, label, at)


static func _talk(npc: String, label: String) -> Dictionary:
	return {"id":"talk", "type":"talk", "target":npc, "label":label, "requireVisit":true, "location":npc}


static func _read(id: String, label: String) -> Dictionary:
	return {"id":"read", "type":"examine", "target":"poi:" + id, "label":label, "location":id}


static func _collect(id: String, label: String, count := 1, keep := false, location := "") -> Dictionary:
	return {"id":"take_" + id, "type":"collect", "target":id, "label":label, "count":count,
		"location":id if location.is_empty() else location, "keep":keep}


static func _kill(hunt: Dictionary, count: int, selected: Array = []) -> Dictionary:
	var spawns: Array = selected if not selected.is_empty() else hunt.spawns
	return {"id":"kills", "type":"kill", "target":spawns[0].enemy, "spawnIds":spawns.map(func(s): return s.id),
		"count":count, "location":"lc_hunt_" + hunt.id, "label":"Defeat enemies at %s" % hunt.name}


static func _quest(id: String, name: String, who: String, to: String, hub: String, level: int,
		intro: String, outro: String, goals: Array, extras: Dictionary = {}) -> void:
	var quest := {"id":id, "name":name, "map":MAP, "zone":"lc_" + hub, "level":level,
		"giver":who, "turnIn":to, "story":true, "offer":intro, "progress":intro, "summary":intro,
		"complete":outro, "objectives":goals,
		"reward":{"size":"chainStep", "xpScale":3.0, "coins":6 + level * 3}}
	quest.merge(extras, true)
	DB.quests[id] = quest


static func _opening(surface, hubs: Dictionary, hunts: Dictionary, original: Dictionary) -> void:
	var town: Array = hubs.oat.point
	DB.world.playerStart.position = _dry(surface, town, Vector2(-5, 4))
	_resident("lc_abel", "ni_abel", _dry(surface, town, Vector2(-7, 1)))
	_resident("lc_heda", "vr_heda", _dry(surface, town, Vector2(-13, 9)))
	_resident("lc_elsie", "tf_elsie", _dry(surface, town, Vector2(6, -3)))
	_resident("lc_bell_keeper", "wm_lantern_crossing_lead", _dry(surface, hubs.bell.point, Vector2(-4, -7)), {"name":"Merrit Vale"})
	_notice("lc_milestone", "Oatwick Road Marker", _dry(surface, town, Vector2(-10, 0)), "oat", "Oatwick just ahead. ALE NOT INCLUDED.")
	_notice("lc_bell_manifest", "Bellharbor Relief Manifest", _dry(surface, hubs.bell.point, Vector2(-8, -9)), "bell",
		"Three signed deliveries. One unfamiliar seal beside 'arrears'.")
	_quest("lc_stretch", str(original.ni_stretch_your_legs.name), "lc_abel", "lc_abel", "oat", 1,
		"Abel Hurst sits beside his broken cart. “Up you get. Wheel’s off. Ask me what happened, then walk up to the Oatwick road marker. Press {interact} to read it.”",
		"“ALE NOT INCLUDED? Sensible. People expect miracles from a milestone.”", [_talk("lc_abel", "Speak to Abel"), _read("lc_milestone", "Read the road marker")],
		{"autoAccept":true, "allowAbandon":true, "sourceQuest":"ni_stretch_your_legs",
		"reward":{"size":"chainStep", "xpScale":1.5, "coins":3}})
	_quest("lc_pig", str(original.ni_loose_boar.name), "lc_abel", "lc_abel", "oat", 1,
		"“The young boars in the lower pasture have found my grain. Select one and use {bar0}. When it paints a wedge on the ground, step out of it.”",
		"“Good. A wheelwright may keep me waiting, but supper shouldn’t.”", [_kill(hunts.oat_green, 1)],
		{"requires":["lc_stretch"], "sourceQuest":"ni_loose_boar", "reward":{"size":"chainStep", "xpScale":3.4, "coins":8}})
	_quest("lc_road_in", str(original.ni_the_road_in.name), "lc_abel", "lc_elsie", "oat", 1,
		"“Tell Elsie her grain is late and the next load of it has legs. She keeps the Cookhouse just past the Oatwick village green.”",
		"Elsie sighs. “That man will be late to his own wake and complain about the ale. Ask Heda if you want a bit of honest work, or see Nell at the millpond. I’ll have a letter for Bellharbor soon.”",
		[_talk("lc_elsie", "Bring Abel’s message to Elsie")],
		{"requires":["lc_pig"], "sourceQuest":"ni_the_road_in", "reward":{"size":"chainStep", "xpScale":3.0, "coins":8}})
	_quest("lc_first_hunt", str(original.vr_first_hunt.name), "lc_heda", "lc_heda", "oat", 2,
		"“Those are wild boars in Briar Pasture. Mine have names and better manners. Thin out three young ones before they finish the orchard.”",
		"“Three. Excellent. Last week I was down to two pigs and a very convincing argument.”", [_kill(hunts.oat_pigs, 3)],
		{"sourceQuest":"vr_first_hunt", "reward":{"size":"chainFinale", "xpScale":3.4, "coins":18}})
	_quest("lc_fence", "One Pig Too Many", "lc_heda", "lc_heda", "oat", 4,
		"“The wolves in Splitrail Wood have had two of my pigs. You’ll know the wood by the broken rails. Clear the beasts out before they learn to open the gate.”",
		"“The remaining pigs are offended that you didn’t ask their advice.”", [_kill(hunts.oat_wolves, 3)],
		{"sourceQuest":"vr_briarjaw", "localStory":true, "story":false, "minLevel":3})
	_quest("lc_bell_message", "A Letter Under Seal", "lc_elsie", "lc_bell_keeper", "bell", 4,
		"“Merrit keeps the relief records in Bellharbor. Follow the eastward cart road from Oatwick and tell him to compare our receipt with his manifest.”",
		"Merrit looks at the seal. “The dead are the only ones left on this list who haven’t been asked to pay twice.”", [_talk("lc_bell_keeper", "Deliver Elsie’s message to Merrit")],
		{"minLevel":3, "reward":{"size":"chainStep", "xpScale":3.8, "coins":24}})
	_quest("lc_bell_receipt", "The Quiet Levy", "lc_bell_keeper", "lc_bell_keeper", "bell", 5,
		"“Read the relief manifest just by the square. The levy also holds accounts in Gloamwood. Once you have the names, take them to Morrow at the chapel.”",
		"“That’s the seal. Show it to Morrow in Gloamwood. If the levy is keeping two books, we’ll make three and send one to each town.”",
		[_read("lc_bell_manifest", "Read the relief manifest")], {"requires":["lc_bell_message"]})


static func _chapter(surface, hubs: Dictionary, hunts: Dictionary, c: Dictionary, originals: Dictionary) -> void:
	var hub: String = c.get("hub", c.id)
	var h: Dictionary = hunts[c.hunt]
	var npc := "lc_" + str(c.id) + "_warden"
	var offset := Vector2(9, -8) if c.has("hub") else Vector2(-8, 2)
	_resident(npc, c.npc, _dry(surface, hubs[hub].point, offset))
	var id := "lc_" + str(c.id)
	var notice := id + "_notice"
	_notice(notice, c.notice, _dry(surface, h.point, Vector2(2, -3)), hub,
		"The same relief seal appears in two columns, once for money received and once for money still owed.")
	var inherited: Dictionary = originals.get(c.source, {}).get("reward", {})
	var reward := {"size":"chainStep", "xpScale":clampf(inherited.get("xpScale", 3.6), 2.6, 4.3), "coins":14 + c.level * 4}
	_quest(id + "_work", c.name, npc, npc, hub, c.level, c.offer,
		"“There it is again. Two books, one seal. The clerk left a separate paper near the worksite. We’ll keep that one where nobody can burn it.”",
		[_kill(h, 3 if c.level < 20 else 4), _read(notice, "Read %s" % c.notice)],
		{"requiresAny":c.needs, "minLevel":maxi(1, c.level - 1), "sourceQuest":c.source, "reward":reward})
	var document := id + "_packet"
	_document(document, c.evidence, _dry(surface, h.point, Vector2(-4, 4)), id + "_evidence")
	_quest(id + "_evidence", "%s’s Own Copy" % str(hubs[hub].name).get_slice(" · ", 0), npc, npc, hub, c.level + 1,
		"Recover the %s near %s and bring it back. Copy it here before the collectors can claim it was lost on the road." % [str(c.evidence).to_lower(), h.name],
		"“One copy here and one with you. If anyone loses ours, it will have to be on purpose.”",
		[_collect(document, "Recover %s" % c.evidence)], {"requires":[id + "_work"],
		"reward":{"size":"chainStep", "xpScale":2.7, "coins":11 + c.level * 3}})


static func _contracts(surface, hubs: Dictionary, hunts: Dictionary) -> void:
	for hub in hubs:
		if hub in ["bell", "gate", "crown"]:
			continue
		var board := "lc_" + str(hub) + "_contracts"
		_resident(board, "vr_dunn", _dry(surface, hubs[hub].point, Vector2(3, 9)),
			{"name":"%s Contracts" % str(hubs[hub].name).get_slice(" · ", 0), "title":"Road Warden", "mapIcon":"quest"})
		for h in hunts.values():
			if h.hub != hub:
				continue
			for level in range(maxi(1, h.levels[0]), mini(49, h.levels[1] + 1) + 1):
				var targets: Array = h.spawns.filter(func(s): return s.level >= level - 2 and s.level <= level + 1)
				if targets.is_empty():
					continue
				var rounds := clampi(4 + level / 4, 4, 15)
				_quest("lc_patrol_%s_%d" % [h.id, level], "%s Patrol (%d)" % [h.name, level], board, board, hub, level,
					"Help keep the routes near %s clear. Hunt the marked enemies and report back to the local road warden." % h.name,
					"“I’ll pass the word to the next wagon. Get some rest if you need it.”", [_kill(h, rounds, targets)],
					{"story":false, "repeatable":true, "minLevel":level, "maxLevel":level, "chapter":"Road Warden contracts",
					"reward":{"size":"standard", "xpScale":2.3, "coins":4 + level * 2}})


static func _services(surface, hubs: Dictionary, campaign: Dictionary) -> void:
	var staff := [
		["lc_tam", "tam", "oat", Vector2(5, 10)],
		["lc_agna", "agna", "oat", Vector2(-11, 6)],
		["lc_cook", "tf_cook", "oat", Vector2(6, -5)],
		["lc_rowan", "tf_rowan", "bell", Vector2(4, 0)],
		["lc_mira", "vr_rogue", "bell", Vector2(6, 3)],
		["lc_fen", "tf_scout", "bell", Vector2(-4, 3)],
		["lc_lyra", "vr_lyra", "bell", Vector2(8, -2)],
		["lc_iren", "tf_iren", "bell", Vector2(-9, 6)],
		["lc_bank", "banker", "bell", Vector2(-7, 2)],
		["lc_jeweller", "hub_jeweller", "gate", Vector2(7, 10)],
		["lc_ysolde", "ysolde", "gate", Vector2(-8, 11)],
		["lc_pell", "pell", "gate", Vector2(-6, 14)],
		["lc_sabeth", "sabeth", "gate", Vector2(-5, 16)],
	]
	for entry in staff:
		_resident(entry[0], entry[1], _dry(surface, hubs[entry[2]].point, entry[3]))
	var inns := {"bell":"lantern_crossing", "gloam":"mossreed_landing", "flint":"millward", "reed":"reedward",
		"iron":"tollhouse_rise", "ash":"scribes_rest", "gate":"highmere_market", "tide":"brinewatch_docks",
		"red":"quarryend", "cinder":"ember_relay", "white":"frostgate", "salt":"saltroad", "star":"glass_road"}
	DB.shops = DB.shops.duplicate()
	for hub in inns:
		var base: String = "wm_" + inns[hub] + "_inn"
		var shop: String = "wm_" + inns[hub] + "_supplies"
		var label: String = str(hubs[hub].name).get_slice(" · ", 0)
		var keeper: String = "lc_" + hub + "_inn"
		var local_shop: String = keeper + "_supplies"
		var provisions: Dictionary = DB.shops[shop].duplicate(true)
		provisions.name = label + " provisions"
		provisions.stock.append("trail_bread")
		DB.shops[local_shop] = provisions
		var front := _dry(surface, hubs[hub].point, Vector2(7, -1))
		_resident(keeper, base, front,
			{"name":"Keeper %s" % label.split(" ")[0], "innkeeper":true, "shop":local_shop,
			"mapIcon":"innkeeper", "innArrival":front, "innLabel":"the %s inn" % label})
	_station(surface, "lc_oat_campfire", "Oatwick cooking fire", "fire", hubs.oat.point, Vector2(8, -4), "camp")
	_station(surface, "lc_iron_campfire", "Ironstep watch campfire", "fire", hubs.iron.point, Vector2(6, -10), "camp")
	_station(surface, "lc_red_campfire", "Redwash caravan campfire", "fire", hubs.red.point, Vector2(-7, 8), "camp")
	_station(surface, "lc_oat_workbench", "Oatwick workbench", "workbench", hubs.oat.point, Vector2(4, 12), "crate")
	_station(surface, "lc_bell_forge", "Iren’s forge", "forge", hubs.bell.point, Vector2(-8, 9), "anvil")
	_station(surface, "lc_iron_forge", "Ironstep watch forge", "forge", hubs.iron.point, Vector2(-11, 6), "anvil")
	_station(surface, "lc_cinder_forge", "Cinder works forge", "forge", hubs.cinder.point, Vector2(-11, 8), "anvil")
	_station(surface, "lc_gloam_alchemy", "Morrow’s alchemy bench", "alchemy", hubs.gloam.point, Vector2(-10, 5), "crate")
	_station(surface, "lc_gate_refinery", "Redgate refining altar", "refining", hubs.gate.point, Vector2(-3, 15), "")
	_station(surface, "lc_gate_runes", "Redgate rune forge", "runeforge", hubs.gate.point, Vector2(1, 15), "")
	for hub in ["oat","gloam","iron","gate","white","salt","crown"]:
		DB.world.shrines.append({"id":"lc_" + hub + "_shrine", "name":"Wayside shrine", "label":"the wayside shrine",
			"position":_dry(surface, hubs[hub].point, Vector2(11, 3)), "arrival":_dry(surface, hubs[hub].point, Vector2(9.2, 3))})
		_prop("shrine", DB.world.shrines[-1].position)
	_bind_trainers(campaign)


static func _station(surface, id: String, label: String, kind: String, hub: Array, offset: Vector2, model: String) -> void:
	var at := _dry(surface, hub, offset)
	DB.world.stations.append({"id":id, "name":label, "kind":kind, "position":at, "radius":3.0})
	_location(id, label, at, 4.0)
	if not model.is_empty():
		_prop(model, at)


static func _prop(model: String, at: Array) -> void:
	if Assets.has(model):
		DB.world.journeyProps.append({"model":model, "position":at, "rotation":45})


static func _bind_trainers(campaign: Dictionary) -> void:
	var teachers := {"brask":"lc_rowan", "tf_rowan":"lc_rowan", "nell":"lc_mira", "vr_rogue":"lc_mira", "odo":"lc_fen",
		"tf_scout":"lc_fen", "grue":"lc_gloam_warden", "briony":"lc_gloam_warden", "vr_morrow":"lc_gloam_warden",
		"aveline":"lc_lyra", "vr_lyra":"lc_lyra", "tam":"lc_tam", "vr_tobin":"lc_mill_angler", "hester":"lc_cook",
		"tf_cook":"lc_cook", "orrin":"lc_iren", "tf_iren":"lc_iren", "agna":"lc_agna", "pell":"lc_pell",
		"ysolde":"lc_ysolde", "sabeth":"lc_sabeth", "wenna":"lc_rowan"}
	for trainer in campaign.get("trainerOverrides", {}):
		var mapped = campaign.trainerOverrides[trainer]
		if teachers.has(trainer) and not teachers.has(mapped):
			teachers[mapped] = teachers[trainer]
	var remap := func(entry: Dictionary, fallback := "") -> void:
		if entry.has("trainer"):
			entry.trainer = teachers.get(entry.trainer, DB.npcs.get(entry.trainer, {}).get("id", fallback))
			if not DB.world.npcSpawns.any(func(sp): return sp.npc == entry.trainer) and not fallback.is_empty():
				entry.trainer = fallback
		if entry.has("trainers"):
			entry.trainers = entry.trainers.map(func(n): return teachers.get(n, fallback))
		if entry.has("quest") and DB.quests.get(entry.quest, {}).get("map") != MAP:
			entry.erase("quest")
	DB.skills = DB.skills.duplicate(true)
	DB.recipes = DB.recipes.duplicate(true)
	DB.archetypes = DB.archetypes.duplicate(true)
	var class_teachers := {"warden":"lc_rowan", "rogue":"lc_mira", "ranger":"lc_fen", "paladin":"lc_lyra",
		"wizard":"lc_gloam_warden", "occultist":"lc_gloam_warden"}
	for id in DB.archetypes:
		for entry in DB.archetypes[id].get("trained", []):
			entry.trainer = class_teachers.get(id, "lc_rowan")
			remap.call(entry, entry.trainer)
	var profession_teachers := {"fishing":"lc_mill_angler", "cooking":"lc_cook", "skinning":"lc_agna",
		"herbalism":"lc_gloam_warden", "alchemy":"lc_gloam_warden", "mining":"lc_iren", "smithing":"lc_iren"}
	for id in DB.skills:
		var skill: Dictionary = DB.skills[id]
		var teacher: String = profession_teachers.get(id, "lc_tam")
		skill.trainer = teacher
		remap.call(skill, teacher)
		for entry in skill.get("train", []):
			entry.trainer = teacher
			remap.call(entry, teacher)
	for entry in DB.recipes.values():
		remap.call(entry, "lc_cook")


static func _local_stories(surface, hubs: Dictionary, hunts: Dictionary, campaign: Dictionary, source: Dictionary) -> void:
	for supply in [["firewood", "bundle of firewood", "crate", Vector2(-5, -8)],
			["wild_garlic", "wild garlic", "satchel", Vector2(-2, 9)]]:
		var spot := _dry(surface, hubs.oat.point, supply[3])
		DB.world.placedLoot.append({"id":"lc_supper_" + str(supply[0]), "reward":{"item":supply[0],"count":1},
			"position":spot, "name":supply[1], "quest":"lc_supper", "model":supply[2], "prompt":"Gather %s" % supply[1]})
		_location(supply[0], supply[1], spot)
	_location("boar_meat", hunts.oat_pigs.name, hunts.oat_pigs.point, 20.0)
	var boar_table: Dictionary = DB.loot_tables.wild_boar.duplicate(true)
	boar_table.questDrops.append({"item":"boar_meat", "quest":"lc_supper", "chance":1.0})
	DB.loot_tables.wild_boar = boar_table
	_quest("lc_supper", str(source.sf_a_meal_earned.name), "lc_cook", "lc_cook", "oat", 2,
		"“I can make a pot of whatever the boars have left. Wood for the fire, meat from the pasture, and wild garlic from the green. The garlic knows what it did.”",
		"Hobb sets out three bowls. “One for you, one for later, one in case later comes early.”",
		[_collect("firewood", "Gather firewood"), _collect("boar_meat", "Bring a cut of boar meat"), _collect("wild_garlic", "Gather wild garlic")],
		{"story":false, "localStory":true, "sourceQuest":"sf_a_meal_earned", "reward":source.sf_a_meal_earned.reward.duplicate(true)})
	_quest("lc_toolbelt", "What Fits in a Pocket", "lc_tam", "lc_tam", "oat", 2,
		"“The trouble with carrying all your tools in your pockets is the first time you sit down. Let’s find you a better arrangement.”",
		"“It goes around your waist. If you’ve got it on your head, start again.”", [_talk("lc_tam", "Speak to Tam about a tool belt")],
		{"story":false, "localStory":true, "reward":{"coins":4, "items":[{"item":"tool_pack", "count":1}]}})
	var dispute := "lc_water_shares"
	var p := _dry(surface, hubs.reed.point, Vector2(-10, 11))
	for original in campaign.get("puzzles", []):
		if original.id != "wm_millward_allocation":
			continue
		var copy: Dictionary = original.duplicate(true)
		copy.merge({"id":dispute, "name":"Reedmire water shares", "position":p, "quest":"lc_water_dispute"}, true)
		DB.world.puzzles.append(copy)
		_location(dispute, copy.name, p)
		_quest("lc_water_dispute", "Half a Ditch Each", "lc_reed_warden", "lc_reed_warden", "reed", 12,
			"“Three neighbours claim the whole ditch. Set Homes to Half, Work to Full, and Reserve to Half, then check the result. That is what they agreed before each remembered signing something else.”",
			"“The channels all run again. I’ll give them a day before they argue about whose water went first.”",
			[{"id":"sluice", "type":"puzzle", "target":dispute, "location":dispute, "label":"Set the three water shares"}],
			{"story":false, "localStory":true, "minLevel":10, "sourceQuest":"wm_millward_local"})
	var lost := "lc_borrowed_shovel"
	_document(lost, "Beren’s borrowed shovel", _dry(surface, hunts.flint_robbers.point, Vector2(-8, -4)), "lc_loaned_shovel")
	_quest("lc_loaned_shovel", "Beren’s Borrowed Shovel", "lc_flint_warden", "lc_flint_warden", "flint", 11,
		"“Find the stamped shovel at Coppervein Spoil. It is not worth much coin. That is not quite the same as it not being worth anything.”",
		"“Same notch. Good. Beren can return it without making a speech. Its owner enjoys speeches even less than he does.”",
		[_collect(lost, "Recover the stamped shovel")], {"story":false, "localStory":true, "sourceQuest":"wm_lantern_crossing_local", "minLevel":9})


static func _community(surface, hubs: Dictionary) -> void:
	_resident("lc_reeve", "pell", _dry(surface, hubs.bell.point, Vector2(-11, 3)), {"name":"Reeve Harl"})
	_resident("lc_bard", "wenna", _dry(surface, hubs.bell.point, Vector2(9, 1)))
	DB.boons = DB.boons.duplicate(true)
	DB.boons.bard.npc = "lc_bard"
	DB.infamy = DB.infamy.duplicate()
	DB.infamy.jurisdictions = [{"id":"lc_bell_watch", "name":"Bellharbor Watch", "reeve":"lc_reeve",
		"regions":["lc_oat", "lc_bell"], "gaol":_dry(surface, hubs.bell.point, Vector2(-12, 6)),
		"gaolName":"the Bellharbor watch yard"}]
	DB.world.healers = ["lc_lyra", "lc_ysolde"]
	for post in [["lc_oat_guard", "vr_watchman", "oat", Vector2(-14, 3)],
			["lc_bell_guard", "vr_watchman", "bell", Vector2(-13, 3)],
			["lc_farm_pig", "vr_farm_pig", "oat", Vector2(-17, 11)]]:
		DB.world.enemySpawns.append({"id":post[0], "enemy":post[1], "position":_dry(surface, hubs[post[2]].point, post[3])})
	DB.world.chests = [
		{"id":"lc_tam_tackle", "name":"Tam’s old tackle box", "position":_dry(surface, hubs.oat.point, Vector2(8, 11)),
			"lock":{"pick":1}, "coins":6, "items":[{"id":"cut_bait", "count":3}]},
		{"id":"lc_reed_reserve", "name":"The sluicekeepers’ reserve", "position":_dry(surface, hubs.reed.point, Vector2(-13, 9)),
			"puzzle":"lc_water_shares", "coins":22, "items":[{"id":"healing_draught", "count":2}]},
		{"id":"lc_crown_treasury", "name":"Crown relief chest", "position":_dry(surface, hubs.crown.point, Vector2(-8, 8)),
			"requiresFlag":"lc_coast_freed", "coins":240, "items":[{"id":"fellstone", "count":4}]},
	]


static func _finale(surface, hubs: Dictionary, hunts: Dictionary) -> void:
	_resident("lc_crown_witness", "wm_north_ledger_gate_lead", _dry(surface, hubs.crown.point, Vector2(-6, 5)),
		{"name":"Magistrate Sera", "title":"Witness for the Coast"})
	_notice("lc_crown_decree", "The Unwritten Decree", _dry(surface, hunts.crown_elite.point, Vector2(-3, 4)), "crown",
		"A blank space was left for the king’s hand. The levy used it for its own seal.")
	_quest("lc_crown_finale", "The Unwritten Decree", "lc_crown_witness", "lc_crown_witness", "crown", 50,
		"“We have the coast’s witnesses. The last clerk is still claiming the king’s authority. Defeat the champion who guards him and read the decree with your own eyes.”",
		"Sera strikes through the seal. “The roads are open. The dead have their names. If the king ever asks who paid his bill, tell him to come and ask us himself.”",
		[_kill(hunts.crown_elite, 1), _read("lc_crown_decree", "Read the decree at the Crown of Ash")],
		{"minLevel":50, "requiresAny":["lc_salt_evidence", "lc_star_evidence"], "setsFlag":"lc_coast_freed",
		"reward":{"coins":500, "reputation":{"road_wardens":150}, "items":[{"item":"fellstone", "count":3}]}})
	for area in ["salt_dunes", "star_dead", "crown_knights"]:
		var hunt: Dictionary = hunts[area]
		var leader: String = "lc_crown_witness" if hunt.hub == "crown" else "lc_" + str(hunt.hub) + "_contracts"
		_quest("lc_free_" + area, "Free Roads: %s" % hunt.name, leader, leader, hunt.hub, 50,
			"The collectors are gone. Help the people reopening the old routes by keeping this stretch clear.",
			"“The next caravan just left. These are the first drivers I’ve seen in a while carrying a full purse.”",
			[_kill(hunt, 8)], {"story":false, "minLevel":50, "requires":["lc_crown_finale"], "repeatable":true,
			"reward":{"xp":0, "coins":120, "items":[{"item":"fellstone", "count":1}]}})

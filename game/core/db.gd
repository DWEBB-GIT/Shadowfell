class_name DB
extends RefCounted
## The game database: every data/*.json file, indexed by id, plus the engine
## tuning (CONFIG). A port of src/data/db.js and src/config.js. Gameplay code
## reads content from here, never from the files directly.
##
## DB.setup(GameData) runs once at start (the Game node does it).

## Engine tuning: the numbers that shape how the game plays and looks.
## Content lives in /data. Kept as in src/config.js.
const CONFIG := {
	# true: entries with an `imported` block (enemies.json, items.json) use the
	# imported, textured models in it (assets/blender/import_models.py);
	# false: every entry keeps its own code-built model, as before. `player`:
	# the imported player body, used while `imported` is on
	"models": {"imported": true, "player": "base_male"},
	"player": {"archetype": "warden", "speed": 5.6, "runGait": 1.3, "turnRate": 3.2, "backpedal": 0.55, "radius": 0.4, "startCoins": 0, "startDraughts": 1, "startFood": 5, "startDrinks": 5},
	"control": {"bossStaggerNeed": 6.0, "staggered": 4.0, "staggeredDamageTaken": 25.0, "staggerGrowth": 1.5, "eliteDr": [1.0, 0.5, 0.25], "eliteDrReset": 15.0},
	"shop": {"sellFraction": 0.25, "buybackSlots": 6, "talkRange": 3.0, "leaveRange": 6.0},
	"death": {
		# your bags and coins wait in a grave for graveSeconds of play, then
		# `scavengers` carry them off; each revival leaves a wound (-woundHealth%
		# max health, up to maxWounds) until you rest woundRestSeconds at an inn
		# or pay a healer healPrice a wound (Dan, 2026-10-27)
		"graveSeconds": 900.0, "scavengers": 2, "woundHealth": 15.0, "maxWounds": 3, "woundRestSeconds": 20.0,
		"healers": ["grue", "aveline"], "healPrice": 5,
		"screenDelay": 1.3, "ghostSpeed": 1.5, "corpseReach": 3.5, "restReach": 4.0, "corpseHealth": 0.5, "revengeBonus": 0.0, "revengeXp": 0.0},
	"fishing": {"castTime": 0.6, "duration": 12.0, "biteMin": 2.0, "biteMax": 8.0, "biteWindow": 1.4, "biteBase": 85.0, "bitePerSkill": 0.5, "biteCap": 97.0, "noBiteAfter": 6.0, "reelTime": 0.45, "baseChance": 75.0, "chancePerRank": 0.6, "clickRadius": 60.0},
	# a bed at an inn (an innkeeper npc; its `bedPrice` beats this price):
	# sleep through a fade, wake whole (health, mana, wounds), with restedShare
	# of a level of rested experience, and the inn as your rest point
	"inn": {"bedPrice": 5, "restedShare": 0.25, "fade": 0.7, "hold": 0.6},
	"camp": {"clearRadius": 14.0, "restRadius": 4.0, "restedFullSeconds": {"camp": 1200.0, "inn": 720.0}, "restedCap": 1.0},
	"progression": {"maxLevel": 100, "firstLevelXp": 280, "xpGrowthPerLevel": 200, "greyGap": 5, "aboveBonus": 5.0, "aboveCap": 4},
	"stats": {
		"healthBase": 20.0, "healthPerStamina": 6.0, "manaPerIntellect": 10.0, "rangedPowerShare": 0.5,
		"powerPerMainStat": 0.3, "spellPowerPerIntellect": 0.25, "critBase": 5.0, "critMultiplier": 1.5,
		"mitigationCap": 75.0, "blockCap": 50.0, "blockReduction": 30.0, "hasteCap": 30.0, "gcdFloor": 1.0,
		"missBase": 5.0, "missPerLevelAbove": 5.0, "missPerLevelBelow": 2.5, "missCap": 60.0, "accuracyCap": 30.0,
		"enemyVariance": 0.35, "fistDamage": [1, 2], "fistSpeed": 2.0, "offHandDamage": 0.5, "offHandResolve": 0.5,
	},
	"interaction": {"radius": 2.2},
	"durability": {"deathLoss": 10, "repairFraction": 0.5},
	"damageNumbers": {"font": 22, "sizePower": 0.6, "minScale": 0.65, "maxScale": 2.4, "life": 1.1, "critLife": 1.6, "pulseAt": 2.0, "pulse": 0.5},
	"impact": {"shake": 0.07, "critShake": 0.16, "shakeDecay": 9.0,
		# hit-stop on a landed melee blow: both bodies hold still this long,
		# more for slower (heavier) weapons, more again on a crit
		"hitStop": 0.03, "hitStopPerSecond": 0.02, "hitStopMax": 0.1, "critHitStop": 1.5},
	"fog": {"color": Color("3a4244"), "near": 24.0, "far": 50.0},
	"blackwood": {"fogColor": Color("1d2725"), "fogNear": 14.0, "fogFar": 38.0, "light": 0.68},
	"camera": {
		"offset": Vector3(0, 11, 10), "lookAhead": 0.5, "zoomMin": 0.6, "zoomMax": 1.35, "zoomStep": 0.08,
		"indoorZoom": 0.22, "fov": 35.0,
		# the camera's angle follows the zoom (Settings: Classic camera keeps
		# `offset`'s one angle): pitch in degrees above the ground at zoomMin,
		# at zoom 1 and at zoomMax; distance is `offset`'s length times this
		"tilt": {"pitchNear": 46.0, "pitchMid": 56.0, "pitchFar": 62.0, "distance": 1.5, "zoomMax": 1.6}, "followSharpness": 8.0, "renderScale": 0.62,
		# framed like Diablo 4 and Lost Ark: locked on the Warden, high, well
		# back and narrow, so the ground reads flat and far all round; the view
		# is centred `frame` metres north of them, just clear of the action bar
		"frame": 0.5,
		"showcase": {"distance": 5.2, "side": 1.3, "height": 1.7, "lookHeight": 1.0},
	},
	"targeting": {"range": 26.0, "dropRange": 34.0, "clickRadius": 46.0, "softArc": 60.0, "softAimRadius": 2.5, "screenMargin": 0.03},
	"minimap": {"questRange": 90.0},
	"loot": {"areaRadius": 5.0, "clickRadius": 40.0, "reach": 3.2, "gatherTime": 2.0},
	"skinning": {"time": 2.2, "freeLevel": 2, "rankPerLevel": 5, "easyAfter": 10, "trivialAfter": 20, "easyChance": 0.5},
	"draught": {"cooldown": 120.0},
}

const KINDS := ["weapon", "armor", "shield", "jewellery", "torch", "tool", "key", "bag", "ammo", "consumable", "material", "junk", "document", "gem"]
const STAT_KEYS := ["stamina", "strength", "agility", "intellect", "armour", "resistance", "block", "haste", "accuracy"]
const DURABLE_KINDS := ["weapon", "armor", "shield", "jewellery"]
## Character slots, laid out as in WoW: `col` is where the panel shows it.
const EQUIP_SLOTS := [
	{"id": "head", "label": "Head", "col": "left"},
	{"id": "neck", "label": "Neck", "col": "left"},
	{"id": "shoulders", "label": "Shoulder", "col": "left"},
	{"id": "back", "label": "Back", "col": "left"},
	{"id": "chest", "label": "Chest", "col": "left"},
	{"id": "wrists", "label": "Wrists", "col": "right"},
	{"id": "hands", "label": "Hands", "col": "right"},
	{"id": "waist", "label": "Waist", "col": "right"},
	{"id": "legs", "label": "Legs", "col": "right"},
	{"id": "feet", "label": "Feet", "col": "right"},
	{"id": "finger1", "label": "Finger", "fits": "finger", "col": "fig"},
	{"id": "finger2", "label": "Finger", "fits": "finger", "col": "fig"},
	{"id": "trinket1", "label": "Trinket", "fits": "trinket", "col": "fig"},
	{"id": "trinket2", "label": "Trinket", "fits": "trinket", "col": "fig"},
	{"id": "mainHand", "label": "Main hand", "col": "bottom", "also": ["oneHand"]},
	{"id": "offHand", "label": "Off hand", "col": "bottom", "also": ["oneHand"]},
	{"id": "ranged", "label": "Ranged", "col": "bottom"},
]

static var ready := false
## items with gear numbers worked out (scaled), by id
static var items := {}
## items as written in data/items.json (a tempered item is worked out again from these)
static var raw_items := {}
static var armour_types := {}
static var suffixes := {}
static var archetypes := {}
static var abilities := {}
## how each spell looks: its cast animation and effects (data/spell_fx.json)
static var spell_fx := {}
## each spell's cast pose by name (data/spell_fx.json `poses`; Rig)
static var spell_poses := {}
static var enemies := {} ## raw records
static var loot_tables := {}
static var world_drops: Array = [] ## level bands of shared gear (WoW's world drops)
static var rarities := {} ## in order, lowest first (Dictionary keeps insertion order)
static var npcs := {}
static var vendor_types := {}
static var shops := {}
static var quests := {}
static var dialogues := {}
static var locations := {}
static var skills := {}
static var factions := {}
static var recipes := {}
static var titles := {}
static var standings: Array = []
static var renown: Dictionary = {}
static var title_lines: Dictionary = {}
static var mock_chance := 0.2
static var world: Dictionary = {}
static var world_map: Dictionary = {} ## data/world_map.json (WorldMap): the whole world's design map and Act 1's layout
static var water: Dictionary = {} ## data/terrain/water.json: sea level, rivers and lakes, baked with the terrain
static var scenery: Dictionary = {}
static var text: Dictionary = {}
static var ability_file: Dictionary = {}
static var builds: Dictionary = {} ## data/builds.json (Builds)
static var mining: Dictionary = {} ## data/mining.json (Mining)
static var nodes: Dictionary = {} ## data/nodes.json (Gathering): herb patches and the like
static var skill_ladder: Dictionary = {} ## skills.json `ladder` (Skills): trainer ranks, skill experience, perks
static var forge: Dictionary = {} ## data/forge.json (Forge)
static var enchanting: Dictionary = {} ## data/enchanting.json (Forge: enchant, scrap)
static var gems: Dictionary = {} ## data/gems.json (Gems)
static var infamy: Dictionary = {} ## data/infamy.json (Law)
static var boons: Dictionary = {} ## data/boons.json (Boons)
static var leash_distance := 18.0

## Tuning taken from the content, under the names gameplay code uses
## (CONFIG.attack in the browser build is DB.attack here).
static var attack: Dictionary
static var auto_shot: Dictionary
static var brace: Dictionary
static var global_cooldown := 1.5
static var spell_queue_window := 0.4
static var cast_pushback := 0.5
static var max_pushbacks := 2
## enemy types with numbers from their level and type
static var enemy_cfg := {}
## abilities with a `kind` (the spell engine runs them)
static var spells := {}


static func setup(data) -> void:
	var f: Dictionary = data.files
	forge = f.get("forge", {})
	enchanting = f.get("enchanting", {})
	gems = f.get("gems", {})
	Scaling.socket_share = forge.get("sockets", {}).get("share", 0.0)
	items.clear()
	raw_items = with_imported(data.table("items"))
	for id in raw_items:
		items[id] = Scaling.scaled_item(raw_items[id])
	# every gem type in every quality is an item (gems.json)
	for g in Gems.item_records():
		items[g.id] = g
	armour_types = data.table("armourTypes")
	suffixes = data.table("suffixes")
	archetypes = data.table("archetypes")
	abilities = data.table("abilities")
	spell_fx = f.get("spell_fx", {}).get("spells", {})
	spell_poses = f.get("spell_fx", {}).get("poses", {})
	enemies = with_imported(resolve_enemies(data.table("enemies")))
	loot_tables = data.table("lootTables")
	world_drops = data.table("worldDrops").values()
	rarities = data.table("rarities")
	npcs = data.table("npcs")
	vendor_types = data.table("vendorTypes")
	shops = data.table("shops")
	quests = data.table("quests")
	dialogues = data.table("dialogues")
	locations = data.table("locations")
	skills = data.table("skills")
	factions = data.table("factions")
	recipes = data.table("recipes")
	titles = data.table("titles")
	standings = f.factions.standings
	renown = f.factions.renown
	title_lines = {"greetings": f.titles.greetings, "farewells": f.titles.farewells}
	mock_chance = f.titles.get("mockChance", 0.2)
	world = f.world
	scenery = f.scenery
	text = f.text
	ability_file = f.abilities
	builds = f.get("builds", {})
	mining = f.get("mining", {})
	nodes = f.get("nodes", {})
	skill_ladder = f.skills.get("ladder", {})
	infamy = f.get("infamy", {})
	boons = f.get("boons", {})
	leash_distance = f.enemies.get("leashDistance", 18)
	attack = abilities.strike.tuning
	auto_shot = abilities.autoShot.tuning
	brace = abilities.get("brace", {}).get("tuning", {})
	global_cooldown = f.abilities.globalCooldown
	spell_queue_window = f.abilities.spellQueueWindow
	cast_pushback = f.abilities.castPushback
	max_pushbacks = int(f.abilities.maxPushbacks)
	enemy_cfg.clear()
	_cfg_at_level.clear()
	for id in enemies:
		enemy_cfg[id] = Scaling.scaled_enemy(enemies[id], CONFIG.stats, attack.abilityWeaponSeconds)
	spells.clear()
	for id in abilities:
		if abilities[id].has("kind"):
			spells[id] = abilities[id]
	world_map = f.get("world_map", {})
	Terrain.use_map(Terrain.chosen_map())
	if Terrain.is_new_map():
		# Dan's new map has only its ground so far: nothing from the old world
		# is put on it (he marks the towns and places things later)
		world_map = {}
		world = new_map_world(world)
		scenery = new_map_scenery(scenery)
	var wpath := Terrain.dir + "water.json"
	water = JSON.parse_string(FileAccess.get_file_as_string(wpath)) if FileAccess.file_exists(wpath) else {}
	Terrain.setup(world)
	Layout.setup(world, scenery)
	WorldMap.setup()
	ready = true


## The world as the new map has it: the old world's records with nothing
## placed (no NPCs, enemies, loot, buildings or roads), starting where
## data/terrain/new_map/map.json says.
static func new_map_world(w: Dictionary) -> Dictionary:
	var out := w.duplicate()
	for k in ["npcSpawns", "enemySpawns", "placedLoot", "chests", "shrines", "signposts", "gates", "townWalls",
			"houses", "stations", "buildings", "pads", "water", "obscured", "dangerZones", "roads"]:
		out[k] = []
	# one region for the lot until Dan marks the zones on the map
	out.regions = [{"id": "new_map", "name": "Unmarked land", "levels": "1"}]
	var m = JSON.parse_string(FileAccess.get_file_as_string(Terrain.dir + "map.json"))
	if m is Dictionary:
		out.playerStart = {"position": m.start, "facing": 180}
		out.bounds = {"minX": m.x0, "maxX": m.x0 + m.sizeX, "minZ": m.z0, "maxZ": m.z0 + m.sizeZ}
	return out


static func new_map_scenery(s: Dictionary) -> Dictionary:
	var out := s.duplicate()
	for k in ["props", "clearings", "lights", "witchlights", "motes", "fairyRings"]:
		out[k] = []
	return out


## Make sure the database is loaded (for tools and tests that run without the game).
static func ensure() -> void:
	if ready:
		return
	setup(load("res://game/autoload/game_data.gd").new())


static func xp_for_next_level(level: int) -> int:
	return CONFIG.progression.firstLevelXp + (level - 1) * CONFIG.progression.xpGrowthPerLevel


## Experience for killing an enemy of `enemy_level` at `player_level`, WoW
## style: a fifth less for each level it is below you, nothing once it is
## `greyGap` levels below (grey), and 5% more for each level above (up to 4).
static func kill_xp(xp: float, player_level: int, enemy_level: int) -> int:
	var pr: Dictionary = CONFIG.progression
	var gap := player_level - enemy_level
	if gap >= pr.greyGap:
		return 0
	if gap > 0:
		return U.jround(xp * (1.0 - float(gap) / pr.greyGap))
	return U.jround(xp * (1.0 + pr.aboveBonus / 100.0 * mini(-gap, pr.aboveCap)))


## Does an item with this `slot` go in that character slot?
static func slot_fits(slot_id: String, item_slot) -> bool:
	for s in EQUIP_SLOTS:
		if s.id == slot_id:
			return s.id == item_slot or s.get("fits") == item_slot or s.get("also", []).has(item_slot)
	return false


## The region (world.json `regions`) at a place: Brackenford, one of Act 1's
## regions, or a world zone (see WorldMap.region_at).
static func region_at(x: float, z: float) -> Dictionary:
	return WorldMap.region_at(x, z)


static func region_by_id(id: String) -> Dictionary:
	for r in world.regions:
		if r.id == id:
			return r
	return {}


static func examine_text(id: String) -> String:
	if id.begins_with("poi:"):
		var p := WorldMap.poi(id.substr(4))
		return "%s. %s" % [p.get("name", ""), p.get("note", "")] if not p.is_empty() else ""
	return text.examine.get(id, "")


## A level variant (as WoW has one creature entry per zone: a level 2 ghoul by
## the road, a level 12 one in the barrows) names its `base` enemy and states
## only what differs. Everything else comes from the base, bar a unique drop.
## An entry's `imported` block swaps in an imported model (and the fields that
## go with it, like `scale`) while CONFIG.models.imported is on. The entry's
## own fields are the code-built version to switch back to.
static func with_imported(table: Dictionary) -> Dictionary:
	if not CONFIG.models.imported:
		return table
	var out := {}
	for id in table:
		var e: Dictionary = table[id]
		if e.get("imported") is Dictionary:
			e = e.duplicate(true)
			e.merge(e.imported, true)
		out[id] = e
	return out


static func resolve_enemies(raw: Dictionary) -> Dictionary:
	var out := {}
	for id in raw:
		out[id] = _resolved(raw, id, [id])
	return out


static func _resolved(raw: Dictionary, id: String, seen: Array) -> Dictionary:
	var e: Dictionary = raw[id]
	var base = e.get("base")
	if base == null or not raw.has(base) or seen.has(base):
		return e
	var out := _resolved(raw, base, seen + [base]).duplicate(true)
	out.erase("uniqueDrop")
	for k in e:
		out[k] = e[k]
	return out


static var _cfg_at_level := {}

## An enemy type's numbers at the level a spawn rolled (from its level to its
## maxLevel, fixed by the spawn's id).
## `level` > 0: that level instead (a hunter who comes back stronger).
static func enemy_cfg_at(type: String, spawn_id: String, level := 0) -> Dictionary:
	var e: Dictionary = enemies[type]
	if level <= 0 and (not e.has("maxLevel") or e.maxLevel <= e.level):
		return enemy_cfg[type]
	if level <= 0:
		level = int(e.level) + int(Scaling.spawn_roll(spawn_id + "#level") * (int(e.maxLevel) - int(e.level) + 1))
	var key := "%s@%d" % [type, level]
	if not _cfg_at_level.has(key):
		var at := e.duplicate()
		at.level = level
		# a stronger variant pays more, on the same growth line as its health
		at.xp = U.jround(float(e.get("xp", 0)) * Scaling.growth(level) / Scaling.growth(e.level))
		_cfg_at_level[key] = Scaling.scaled_enemy(at, CONFIG.stats, attack.abilityWeaponSeconds)
	return _cfg_at_level[key]


## The world-drop band for an enemy of this level, or {} (none fits, or the
## enemy is marked worldDrops: false, as beasts drop no gear).
static func world_drop_band(cfg: Dictionary) -> Dictionary:
	if cfg.get("worldDrops", true) == false:
		return {}
	for b in world_drops:
		if cfg.get("level", 1) >= b.minLevel and cfg.get("level", 1) <= b.maxLevel:
			return b
	return {}

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
	"player": {"archetype": "warden", "speed": 5.6, "runGait": 1.3, "radius": 0.4, "startCoins": 8, "startDraughts": 1},
	"control": {"bossStaggerNeed": 6.0, "staggered": 4.0, "staggeredDamageTaken": 25.0, "staggerGrowth": 1.5, "eliteDr": [1.0, 0.5, 0.25], "eliteDrReset": 15.0},
	"shop": {"sellFraction": 0.25, "buybackSlots": 6, "talkRange": 3.0, "leaveRange": 6.0},
	"death": {"coinLossFraction": 0.2, "coinLossCap": 5, "screenDelay": 1.3, "ghostSpeed": 1.5, "corpseReach": 3.5, "restReach": 4.0, "corpseHealth": 0.5, "revengeBonus": 25.0, "revengeXp": 0.5},
	"fishing": {"castTime": 0.6, "duration": 12.0, "biteMin": 2.0, "biteMax": 8.0, "biteWindow": 1.4, "biteBase": 85.0, "bitePerSkill": 0.5, "biteCap": 97.0, "noBiteAfter": 6.0, "reelTime": 0.45, "baseChance": 75.0, "chancePerRank": 0.6, "clickRadius": 60.0},
	"camp": {"clearRadius": 14.0, "restRadius": 4.0, "restedPerSecond": 0.01, "restedCap": 1.0},
	"progression": {"firstLevelXp": 100, "xpGrowthPerLevel": 60},
	"stats": {
		"healthBase": 40.0, "healthPerStamina": 6.0, "manaPerIntellect": 10.0, "rangedPowerShare": 0.5,
		"powerPerMainStat": 0.25, "spellPowerPerIntellect": 0.25, "critBase": 5.0, "critMultiplier": 1.5,
		"mitigationCap": 75.0, "blockCap": 50.0, "blockReduction": 30.0, "hasteCap": 30.0, "gcdFloor": 1.0,
		"enemyVariance": 0.15, "fistDamage": [1, 2], "fistSpeed": 2.0, "offHandDamage": 0.5, "offHandResolve": 0.5,
	},
	"interaction": {"radius": 2.2},
	"durability": {"deathLoss": 10, "repairFraction": 0.5},
	"damageNumbers": {"font": 22, "sizePower": 0.6, "minScale": 0.65, "maxScale": 2.4, "life": 1.1, "critLife": 1.6, "pulseAt": 2.0, "pulse": 0.5},
	"impact": {"shake": 0.07, "critShake": 0.16, "shakeDecay": 9.0},
	"fog": {"color": Color("3a4244"), "near": 14.0, "far": 40.0},
	"blackwood": {"fogColor": Color("1d2725"), "fogNear": 9.0, "fogFar": 32.0, "light": 0.68},
	"camera": {
		"offset": Vector3(0, 11, 10), "lookAhead": 0.5, "zoomMin": 0.6, "zoomMax": 1.35, "zoomStep": 0.08,
		"indoorZoom": 0.22, "fov": 45.0,
		# the camera's angle follows the zoom (Settings: Classic camera keeps
		# `offset`'s one angle): pitch in degrees above the ground at zoomMin,
		# at zoom 1 and at zoomMax; distance is `offset`'s length times this
		"tilt": {"pitchNear": 40.0, "pitchMid": 52.0, "pitchFar": 60.0, "distance": 1.05, "zoomMax": 1.6}, "followSharpness": 8.0, "renderScale": 0.62,
		"showcase": {"distance": 5.2, "side": 1.3, "height": 1.7, "lookHeight": 1.0},
	},
	"targeting": {"range": 26.0, "dropRange": 34.0, "clickRadius": 46.0, "softArc": 60.0, "softAimRadius": 2.5, "screenMargin": 0.03},
	"minimap": {"questRange": 90.0},
	"loot": {"areaRadius": 5.0, "clickRadius": 40.0, "reach": 3.2, "gatherTime": 2.0},
	"skinning": {"time": 2.2, "freeLevel": 2, "rankPerLevel": 5, "easyAfter": 10, "trivialAfter": 20, "easyChance": 0.5},
	"draught": {"cooldown": 1.0},
}

const KINDS := ["weapon", "armor", "shield", "jewellery", "torch", "tool", "key", "bag", "ammo", "consumable", "material", "junk", "document"]
const STAT_KEYS := ["stamina", "strength", "agility", "intellect", "armour", "resistance", "block", "haste"]
const DURABLE_KINDS := ["weapon", "armor", "shield", "jewellery"]
## Character slots, laid out as in WoW: `col` is where the panel shows it.
const EQUIP_SLOTS := [
	{"id": "head", "label": "Head", "col": "left"},
	{"id": "neck", "label": "Neck", "col": "left"},
	{"id": "shoulders", "label": "Shoulder", "col": "left"},
	{"id": "back", "label": "Back", "col": "left"},
	{"id": "chest", "label": "Chest", "col": "left"},
	{"id": "wrists", "label": "Wrists", "col": "left"},
	{"id": "hands", "label": "Hands", "col": "left"},
	{"id": "waist", "label": "Waist", "col": "right"},
	{"id": "legs", "label": "Legs", "col": "right"},
	{"id": "feet", "label": "Feet", "col": "right"},
	{"id": "finger1", "label": "Finger", "fits": "finger", "col": "right"},
	{"id": "finger2", "label": "Finger", "fits": "finger", "col": "right"},
	{"id": "trinket1", "label": "Trinket", "fits": "trinket", "col": "right"},
	{"id": "trinket2", "label": "Trinket", "fits": "trinket", "col": "right"},
	{"id": "mainHand", "label": "Main hand", "col": "bottom", "also": ["oneHand"]},
	{"id": "offHand", "label": "Off hand", "col": "bottom", "also": ["oneHand"]},
	{"id": "ranged", "label": "Ranged", "col": "bottom"},
]

static var ready := false
## items with gear numbers worked out (scaled), by id
static var items := {}
static var armour_types := {}
static var suffixes := {}
static var archetypes := {}
static var abilities := {}
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
static var scenery: Dictionary = {}
static var text: Dictionary = {}
static var ability_file: Dictionary = {}
static var builds: Dictionary = {} ## data/builds.json (Builds)
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
	items.clear()
	for id in data.table("items"):
		items[id] = Scaling.scaled_item(data.table("items")[id])
	armour_types = data.table("armourTypes")
	suffixes = data.table("suffixes")
	archetypes = data.table("archetypes")
	abilities = data.table("abilities")
	enemies = resolve_enemies(data.table("enemies"))
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
	Terrain.setup(world)
	Layout.setup(world, scenery)
	ready = true


## Make sure the database is loaded (for tools and tests that run without the game).
static func ensure() -> void:
	if ready:
		return
	setup(load("res://game/autoload/game_data.gd").new())


static func xp_for_next_level(level: int) -> int:
	return CONFIG.progression.firstLevelXp + (level - 1) * CONFIG.progression.xpGrowthPerLevel


## Does an item with this `slot` go in that character slot?
static func slot_fits(slot_id: String, item_slot) -> bool:
	for s in EQUIP_SLOTS:
		if s.id == slot_id:
			return s.id == item_slot or s.get("fits") == item_slot or s.get("also", []).has(item_slot)
	return false


## Regions are bands along the road; the one at `z`.
static func region_at(z: float) -> Dictionary:
	var regions: Array = world.regions
	for r in regions:
		if r.minZ == null or z >= r.minZ:
			return r
	return regions[regions.size() - 1]


static func region_by_id(id: String) -> Dictionary:
	for r in world.regions:
		if r.id == id:
			return r
	return {}


static func examine_text(id: String) -> String:
	return text.examine.get(id, "")


## A level variant (as WoW has one creature entry per zone: a level 2 ghoul by
## the road, a level 12 one in the barrows) names its `base` enemy and states
## only what differs. Everything else comes from the base, bar a unique drop.
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
static func enemy_cfg_at(type: String, spawn_id: String) -> Dictionary:
	var e: Dictionary = enemies[type]
	if not e.has("maxLevel") or e.maxLevel <= e.level:
		return enemy_cfg[type]
	var level := int(e.level) + int(Scaling.spawn_roll(spawn_id + "#level") * (int(e.maxLevel) - int(e.level) + 1))
	var key := "%s@%d" % [type, level]
	if not _cfg_at_level.has(key):
		var at := e.duplicate()
		at.level = level
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

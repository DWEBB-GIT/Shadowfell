@tool
extends RefCounted
## The data files the Game Data editor changes, held in memory until Save.
## Records are the same Dictionaries the files hold, edited in place; a file
## is written only if something in it changed.

const IO := preload("json_io.gd")

## where the data files are (a test points this at a copy)
var data_dir := "res://data"
const MODELS_DIR := "res://assets/models"
const SPRITES_DIR := "res://assets/icons"

const KINDS := ["weapon", "armor", "shield", "jewellery", "torch", "tool", "key", "bag", "ammo", "consumable", "material", "junk", "document"]
const KIND_NAMES := {"weapon": "Weapon", "armor": "Armour", "shield": "Shield", "jewellery": "Jewellery", "torch": "Torch", "tool": "Tool", "key": "Key", "bag": "Bag", "ammo": "Ammo", "consumable": "Consumable", "material": "Material", "junk": "Junk", "document": "Document"}
const GEAR := ["weapon", "armor", "shield"]
const EQUIPPABLE := ["weapon", "armor", "shield", "jewellery", "torch"]
const STAT_KEYS := ["stamina", "strength", "agility", "intellect", "armour", "resistance", "block", "haste"]
## what an item's `slot` may say, with the name the editor shows
const SLOTS := {
	"oneHand": "One-hand (either hand)", "mainHand": "Main hand only", "offHand": "Off hand", "ranged": "Ranged",
	"head": "Head", "neck": "Neck", "shoulders": "Shoulders", "back": "Back", "chest": "Chest", "wrists": "Wrists",
	"hands": "Hands", "waist": "Waist", "legs": "Legs", "feet": "Feet", "finger": "Finger", "trinket": "Trinket",
}
const KIND_SLOTS := {
	"weapon": ["oneHand", "mainHand", "ranged"],
	"armor": ["head", "shoulders", "back", "chest", "wrists", "hands", "waist", "legs", "feet"],
	"shield": ["offHand"],
	"jewellery": ["neck", "finger", "trinket"],
	"torch": ["offHand"],
}
## weapon types in the game, and some for new weapons; a class can ban a type
const WEAPON_TYPES := ["sword", "axe", "mace", "dagger", "staff", "spear", "bow"]
## a new weapon's swing speed and stand-in model until it has its own
const WEAPON_DEFAULTS := {
	"sword": {"speed": 2.4, "model": "arming_sword"},
	"axe": {"speed": 2.6, "model": "rusted_falchion"},
	"mace": {"speed": 2.6, "model": "blackwood_cleaver"},
	"dagger": {"speed": 1.6, "model": "dirk"},
	"staff": {"speed": 3.0, "model": "worn_sword"},
	"spear": {"speed": 2.8, "model": "worn_sword"},
	"bow": {"speed": 2.8, "model": "hunting_bow"},
}
## the extra properties some kinds of item have: key -> [label, type, kinds]
const EXTRAS := {
	"range": ["Range (metres, 8 to 40)", "float", ["weapon"]],
	"bagSlots": ["Bag slots", "int", ["bag"]],
	"toolPack": ["Tool pack (holds tools)", "bool", ["bag"]],
	"rangedHaste": ["Quiver haste % (up to 30)", "float", ["bag"]],
	"ammoDps": ["Damage a second it adds", "float", ["ammo"]],
	"buyCount": ["Sold in stacks of", "int", ["ammo", "consumable", "material"]],
	"light": ["Light (metres)", "float", ["torch"]],
	"rod": ["Fishing rod", "bool", ["tool"]],
	"fishingSkill": ["Fishing skill bonus", "float", ["tool"]],
	"bait": ["Bait (fishing skill bonus)", "float", ["consumable", "material"]],
	"skinningKnife": ["Skinning knife", "bool", ["tool"]],
	"skinningSkill": ["Skinning skill bonus", "float", ["tool"]],
	"miningPick": ["Mining pick", "bool", ["tool"]],
	"sockets": ["Sockets (gem slots)", "int", ["weapon", "armor", "shield", "jewellery"]],
}

## Spells the generic spell engine runs (schema.js SPELL_KINDS): what each
## targets (enemy, or self, or self or the ground) and the tuning it needs.
const SPELL_KINDS := {
	"cast": {"enemy": true, "tuning": ["castTime", "damageMin", "damageMax", "projectileSpeed"], "about": "A cast at an enemy: a bolt flies once the cast ends. Moving interrupts it."},
	"dot": {"enemy": true, "tuning": ["duration", "tickInterval", "tickMultiplier"], "about": "Damage over time on an enemy (a bleed, poison or curse)."},
	"instant": {"enemy": true, "tuning": ["damageMin", "damageMax"], "about": "Instant damage to an enemy. With damageMultiplier instead, it rolls your weapon."},
	"aoe": {"enemy": false, "ground": true, "tuning": ["radius", "duration", "tickInterval", "damageMin", "damageMax"], "about": "Damage every tick to enemies in a circle around you or on the ground."},
	"cleave": {"enemy": false, "tuning": ["damageMultiplier", "coneDegrees", "range", "maxTargets", "windup"], "about": "A swing in a cone in front of you."},
	"burst": {"enemy": false, "tuning": ["damageMultiplier", "radius", "windup", "stagger", "knockback"], "about": "A blow around you that staggers and knocks back."},
	"charge": {"enemy": true, "tuning": ["damageMultiplier", "distance", "duration", "hitRadius"], "about": "Rush at an enemy and strike."},
	"leap": {"enemy": false, "tuning": ["distance", "duration"], "about": "A jump back."},
	"guard": {"enemy": false, "tuning": ["window"], "about": "Block or dodge hits for a moment (Brace, Guile)."},
	"interrupt": {"enemy": true, "tuning": ["lockout", "damageMin", "damageMax"], "about": "Breaks an enemy's cast."},
	"control": {"enemy": true, "tuning": [], "about": "Only its `applies` aura: a sleep, hex or stun."},
	"buff": {"enemy": false, "tuning": ["duration", "damageBonus"], "about": "More damage for a while."},
	"stealth": {"enemy": false, "tuning": [], "about": "Hide in shadow."},
	"trap": {"enemy": false, "tuning": ["armTime", "triggerRadius", "lifetime", "maxTraps", "radius", "duration", "slow"], "about": "A trap on the ground that slows."},
	"purge": {"enemy": false, "tuning": ["healPerPoint", "extend"], "about": "Spends all of a bar (spendsAll) to heal."},
	"channel": {"enemy": true, "tuning": ["castTime", "tickInterval", "damageMin", "damageMax", "healPercent"], "about": "Drains an enemy while you hold still."},
	"shield": {"enemy": false, "tuning": ["duration", "absorbPercent"], "about": "A shield that soaks damage."},
	"portal": {"enemy": false, "tuning": ["castTime", "cooldown"], "about": "A long cast that takes you to your camp or your home inn (Return Home). Not while fighting."},
	"camp": {"enemy": false, "tuning": ["castTime"], "about": "Set Camp."},
}
const SCHOOLS := ["physical", "shadow", "holy", "nature", "fire"]
const TARGETS := ["enemy", "ground", "self"]

var files := {} ## name -> parsed file
var dirty := {} ## name -> true
var items: Array = []
var rarities: Array = []
var armour_types: Array = []
var loot_tables: Array = []
var world_drops: Array = [] ## level bands of shared gear (WoW's world drops)
var enemies: Array = []
var quests: Array = []
var chests: Array = []
var waters: Array = []
var npcs: Array = []
var npc_spawns: Array = []
var enemy_spawns: Array = []
var shops: Array = []
var vendor_types: Array = []
var dialogues: Array = []
var factions: Array = []
var locations: Array = []
var skills: Array = []
var abilities: Array = []
var archetypes: Array = []
var recipes: Array = []
## examine points (text.json), which a quest can ask the player to look at
var examine_points: PackedStringArray = []
## models in assets/models, and sprites in assets/icons
var models: PackedStringArray = []
var sprites: PackedStringArray = []

signal changed


func load_all() -> void:
	files.clear()
	dirty.clear()
	for f in ["items", "rarities", "loot_tables", "enemies", "quests", "world", "npcs", "shops", "dialogue", "factions", "text", "skills", "abilities", "archetypes", "recipes", "builds"]:
		files[f] = IO.load_file(_path(f))
		if files[f] == null:
			files[f] = {}
			push_error("Game Data: cannot read " + _path(f))
	items = files.items.get("items", [])
	armour_types = files.items.get("armourTypes", [])
	rarities = files.rarities.get("rarities", [])
	loot_tables = files.loot_tables.get("lootTables", [])
	if not files.loot_tables.has("worldDrops"):
		files.loot_tables.worldDrops = []
	world_drops = files.loot_tables.worldDrops
	enemies = files.enemies.get("enemies", [])
	quests = files.quests.get("quests", [])
	chests = files.world.get("chests", [])
	waters = files.world.get("water", [])
	npcs = files.npcs.get("npcs", [])
	if not files.world.has("npcSpawns"):
		files.world.npcSpawns = []
	npc_spawns = files.world.npcSpawns
	enemy_spawns = files.world.get("enemySpawns", [])
	locations = files.world.get("locations", [])
	if not files.shops.has("shops"):
		files.shops.shops = []
	shops = files.shops.shops
	vendor_types = files.shops.get("vendorTypes", [])
	if not files.dialogue.has("dialogues"):
		files.dialogue.dialogues = []
	dialogues = files.dialogue.dialogues
	factions = files.factions.get("factions", [])
	examine_points = PackedStringArray(files.text.get("examine", {}).keys())
	if not files.skills.has("skills"):
		files.skills.skills = []
	skills = files.skills.skills
	abilities = files.abilities.get("abilities", [])
	archetypes = files.archetypes.get("archetypes", [])
	recipes = files.recipes.get("recipes", [])
	scan_art()


func _path(file: String) -> String:
	return "%s/%s.json" % [data_dir, file]


func scan_art() -> void:
	models = _names(MODELS_DIR, ".glb")
	sprites = _names(SPRITES_DIR, ".png")


static func _names(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(ext):
			out.append(f.get_basename())
	out.sort()
	return out


func touch(file: String) -> void:
	dirty[file] = true
	changed.emit()


func save_all() -> PackedStringArray:
	var saved := PackedStringArray()
	for f in dirty:
		var err := IO.save_file(_path(f), files[f])
		if err != OK:
			push_error("Game Data: cannot write %s (%s)" % [_path(f), error_string(err)])
			continue
		saved.append(f + ".json")
	dirty.clear()
	changed.emit()
	return saved


# ------------------------------------------------------------------ lookups
static func find(list: Array, id) -> Dictionary:
	for r in list:
		if r.get("id") == id:
			return r
	return {}


func item(id) -> Dictionary:
	return find(items, id)


func rarity(id) -> Dictionary:
	return find(rarities, id)


func rarity_colour(id) -> Color:
	return Color(rarity(id).get("colour", "#cccccc"))


## rarities a loot table can roll (not the quest tier)
func drop_rarities() -> Array:
	return rarities.filter(func(r): return r.get("drops", true) != false)


func table_or_band(id) -> Dictionary:
	var t := find(loot_tables, id)
	return t if not t.is_empty() else find(world_drops, id)


## a table or band id not yet used by either
func unique_table_id(base: String) -> String:
	var id := base
	var n := 2
	while not table_or_band(id).is_empty():
		id = "%s_%d" % [base, n]
		n += 1
	return id


func is_band(t: Dictionary) -> bool:
	return world_drops.has(t)


## An enemy as the game sees it: a level variant's `base` filled in (as
## DB.resolve_enemies does), so its level and tables can be read.
func resolved(e: Dictionary, seen := []) -> Dictionary:
	var base = e.get("base")
	if base == null or seen.has(base):
		return e
	var b := find(enemies, base)
	if b.is_empty():
		return e
	var out := resolved(b, seen + [e.id]).duplicate(true)
	out.erase("uniqueDrop")
	for k in e:
		out[k] = e[k]
	return out


## the world-drop band an enemy rolls, or {} (none fits, or worldDrops: false)
func band_for(e: Dictionary) -> Dictionary:
	var r := resolved(e)
	if r.get("worldDrops", true) == false:
		return {}
	for b in world_drops:
		if r.get("level", 1) >= b.get("minLevel", 0) and r.get("level", 1) <= b.get("maxLevel", 0):
			return b
	return {}


## enemies whose level falls in a band (a level range counts if any of it does)
func band_users(b: Dictionary) -> Array:
	var out := []
	for e in enemies:
		var r := resolved(e)
		if r.get("worldDrops", true) == false:
			continue
		var lo: float = r.get("level", 1)
		var hi: float = maxf(lo, r.get("maxLevel", lo))
		if hi >= b.get("minLevel", 0) and lo <= b.get("maxLevel", 0):
			out.append(e)
	return out


func npc_name(id) -> String:
	return find(npcs, id).get("name", str(id))


func npc(id) -> Dictionary:
	return find(npcs, id)


func quest(id) -> Dictionary:
	return find(quests, id)


func shop(id) -> Dictionary:
	return find(shops, id)


func vendor_type(id) -> Dictionary:
	return find(vendor_types, id)


func dialogue(id) -> Dictionary:
	return find(dialogues, id)


## the tuning a spell must have: a weapon or bow instant rolls the weapon
## (damageMultiplier), a bow cast too (schema.js)
static func needed_tuning(a: Dictionary) -> Array:
	var k: Dictionary = SPELL_KINDS.get(a.get("kind"), {})
	if k.is_empty():
		return []
	var weapon: bool = a.get("ranged") == true or a.get("tuning", {}).has("damageMultiplier")
	if a.kind == "instant" and weapon:
		return ["cooldown", "damageMultiplier"]
	if a.kind == "cast" and a.get("ranged") == true:
		return ["cooldown", "castTime", "damageMultiplier"]
	return ["cooldown"] + k.tuning


## mana and every class bar: what a cost or gain may name
func resource_ids() -> Array:
	var out := ["mana"]
	for a in archetypes:
		for b in a.get("resources", {}).get("bars", []):
			if not out.has(b.get("id")):
				out.append(b.get("id"))
	return out


## the classes whose spellbook holds an ability
func classes_with(id) -> Array:
	return archetypes.filter(func(a): return a.get("abilities", []).has(id))


func ability(id) -> Dictionary:
	return find(abilities, id)


func skill(id) -> Dictionary:
	return find(skills, id)


func ability_name(id) -> String:
	return str(ability(id).get("name", id))


## [id, label] pairs of the class spells and skill tools, by name
func ability_choices(filter := Callable()) -> Array:
	var out := []
	for a in abilities:
		if filter.is_valid() and not filter.call(a):
			continue
		out.append([a.id, "%s (%s)" % [a.get("name", a.id), a.id]])
	out.sort_custom(func(x, y): return x[1] < y[1])
	return out


## [{class, entry}] for every class spell a trainer teaches
## How a class gets a spell: "defensive" (its Space slot), "bar" (on the
## starting bar), "book" (in the spellbook from the start), "trained" (a
## trainer teaches it, archetypes.json `trained`) or "" (not the class's).
const SPELL_SOURCES := [["bar", "Knows it from the start, on the starting bar"], ["book", "Knows it from the start, in the spellbook"], ["defensive", "Knows it from the start, as the defensive (Space)"], ["trained", "A trainer teaches it"]]


static func trained_entry(c: Dictionary, id) -> Dictionary:
	for t in c.get("trained", []):
		if t.get("ability") == id:
			return t
	return {}


static func spell_source(c: Dictionary, id) -> String:
	if not c.get("abilities", []).has(id):
		return ""
	if c.get("defensive") == id:
		return "defensive"
	if not trained_entry(c, id).is_empty():
		return "trained"
	return "bar" if c.get("bar", []).has(id) else "book"


## Move a spell to another source for a class (see SPELL_SOURCES); a new
## trainer entry starts at level 2 for 10 coins, taught by `trainer`.
func set_spell_source(c: Dictionary, id: String, to: String, trainer = null) -> Dictionary:
	var from := spell_source(c, id)
	if from == to and to != "trained":
		return trained_entry(c, id)
	var t := trained_entry(c, id)
	if not t.is_empty() and to != "trained":
		c.trained.erase(t)
		t = {}
	if c.has("trained") and c.trained.is_empty():
		c.erase("trained")
	if to != "bar" and to != "defensive":
		c.get("bar", []).erase(id)
	if c.get("defensive") == id and to != "defensive":
		c.erase("defensive")
	# on the bar, taught now or dropped: no longer left for a later trainer
	if c.has("later"):
		c.later.erase(id)
		if c.later.is_empty():
			c.erase("later")
	match to:
		"":
			c.get("abilities", []).erase(id)
		"bar", "defensive":
			if not c.has("bar"):
				c.bar = []
			if not c.bar.has(id):
				c.bar.append(id)
			if to == "defensive":
				c.defensive = id
		"trained":
			if t.is_empty():
				if not c.has("trained"):
					c.trained = []
				t = {"ability": id, "trainer": trainer if trainer != null else (npcs[0].id if npcs.size() else ""), "level": 2, "cost": 10}
				c.trained.append(t)
			elif trainer != null:
				t.trainer = trainer
	if to != "":
		if not c.has("abilities"):
			c.abilities = []
		if not c.abilities.has(id):
			c.abilities.append(id)
	touch("archetypes")
	return t


## class spells: abilities with a kind or in some class's spellbook, not skill tools
func class_spells() -> Array:
	return abilities.filter(func(a): return not a.has("skill") and not a.get("everyone", false) and (a.has("kind") or not classes_with(a.id).is_empty()))


func statuses() -> Array:
	return files.get("builds", {}).get("statuses", [])


func powers() -> Array:
	return files.get("builds", {}).get("powers", [])


func quest_choices() -> Array:
	return quests.map(func(q): return [q.id, q.get("name", q.id)])


func trained_by(npc_id) -> Array:
	var out := []
	for a in archetypes:
		for t in a.get("trained", []):
			if t.get("trainer") == npc_id:
				out.append({"class": a, "entry": t})
	return out


## every condition an npc's lines check: a quest's status, a flag or a place looked at
static func condition_text(c) -> String:
	if not c is Dictionary or c.is_empty():
		return "always"
	if c.has("quest"):
		return "quest %s is %s" % [c.quest, str(c.get("status", "")).replace("_", " ")]
	if c.has("flag"):
		return "flag %s is set" % c.flag
	if c.has("examined"):
		return "looked at %s" % c.examined
	return JSON.stringify(c)


func enemy_name(id) -> String:
	var e := find(enemies, id)
	return "%s (level %d)" % [resolved(e).get("name", id), resolved(e).get("level", 1)] if not e.is_empty() else str(id)


## [id, label] pairs for dropdowns
func npc_choices() -> Array:
	return npcs.map(func(n): return [n.id, "%s (%s)" % [n.get("name", n.id), n.get("title", n.id)] if n.has("title") else n.get("name", n.id)])


func location_choices() -> Array:
	return locations.map(func(l): return [l.id, l.get("name", l.id)])


func faction_choices() -> Array:
	return factions.map(func(f): return [f.id, f.get("name", f.id)])


## where an npc stands in the world (world.json npcSpawns), or {}
func spawn_of(npc_id) -> Dictionary:
	for sp in npc_spawns:
		if sp.get("npc") == npc_id:
			return sp
	return {}


## quests that require this one (the ones it unlocks)
func quests_after(id) -> Array:
	return quests.filter(func(q): return q.get("requires", []).has(id))


## Dialogue lines that check a quest: [{npc, text, status}]
func dialogue_mentions(quest_id) -> Array:
	var out := []
	for d in dialogues:
		_mentions(d, d.id, quest_id, out)
	return out


static func _mentions(node, who: String, quest_id, out: Array) -> void:
	if node is Array:
		for x in node:
			_mentions(x, who, quest_id, out)
	elif node is Dictionary:
		var w = node.get("when")
		if w is Dictionary and w.get("quest") == quest_id:
			out.append({"npc": who, "text": str(node.get("text", node.get("prompt", node.get("id", "")))), "status": w.get("status", "")})
		for k in node:
			if k != "when":
				_mentions(node[k], who, quest_id, out)


## the npcs (and skills) that name an npc, to warn before it is deleted
func uses_of_npc(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for q in quests:
		if q.get("giver") == id or q.get("turnIn") == id:
			out.append("quest " + q.id)
	for sk in skills:
		if sk.get("trainer") == id:
			out.append("skill " + sk.get("id", ""))
	for a in archetypes:
		for t in a.get("trained", []):
			if t.get("trainer") == id:
				out.append("%s spell %s" % [a.get("name", a.id), t.get("ability")])
	for r in recipes:
		if r.get("trainer") == id:
			out.append("recipe " + r.get("id", ""))
	return out


## lower_snake_case from a name: "Hunter's Sword" -> hunters_sword
static func slug(name: String) -> String:
	var s := name.to_lower().replace("'", "")
	var out := ""
	for c in s:
		out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	return out.strip_edges().trim_prefix("_").trim_suffix("_")


func unique_id(list: Array, base: String) -> String:
	var id := base if base != "" else "new"
	var n := 2
	while not find(list, id).is_empty():
		id = "%s_%d" % [base, n]
		n += 1
	return id


## Everything that names an item: loot tables, quest rewards, chests, shops...
## Used to warn before an item is deleted.
func uses_of_item(id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in loot_tables + world_drops:
		if _table_has(t, id):
			out.append("loot table " + t.id)
	for q in quests:
		for e in q.get("reward", {}).get("items", []):
			if e.get("item") == id:
				out.append("quest " + q.id)
	for c in chests:
		for e in c.get("items", []):
			if e.get("id") == id:
				out.append("chest " + c.id)
	# files the editor does not load, searched as text
	for sh in shops:
		if sh.get("stock", []).has(id):
			out.append("shop " + sh.id)
	for f in ["recipes", "archetypes", "world", "dialogue", "npcs"]:
		var text := FileAccess.get_file_as_string(_path(f))
		if text.contains("\"%s\"" % id) and not out.has(f + ".json"):
			out.append(f + ".json")
	return out


static func _table_has(t: Dictionary, id: String) -> bool:
	for a in t.get("always", []):
		if a.get("item") == id:
			return true
	for list in t.get("drops", {}).get("items", {}).values():
		for e in list:
			if e.get("item") == id:
				return true
	return false


## what uses a loot table: enemies (loot or skinning) and fishing waters
func users_of_table(id: String) -> Array:
	var out := []
	# `enemy` is the record in the file; `own` is false when a level variant
	# only inherits the table from its base
	for e in enemies:
		var r := resolved(e)
		if r.get("lootTable") == id:
			out.append({"kind": "loot", "enemy": e, "own": e.get("lootTable") == id, "text": "%s (%s) drops it" % [r.get("name", e.id), e.id]})
		if r.get("skin") == id:
			out.append({"kind": "skin", "enemy": e, "own": e.get("skin") == id, "text": "Skinning %s (%s)" % [r.get("name", e.id), e.id]})
	for w in waters:
		if w.get("fishTable") == id:
			out.append({"kind": "fish", "water": w, "text": "Fishing in %s" % w.get("name", w.get("id", "water"))})
	return out


## The chance in one kill (or one cast) that a table drops at least one of
## this entry, rarity roll then item roll, every roll.
func entry_chance(t: Dictionary, rarity_id: String, entry: Dictionary) -> float:
	var d: Dictionary = t.get("drops", {})
	var weights: Dictionary = d.get("rarity", {})
	var total := 0.0
	for w in weights.values():
		total += w
	var list: Array = d.get("items", {}).get(rarity_id, [])
	var sum := 0.0
	for e in list:
		sum += e.get("weight", 0)
	if total <= 0 or sum <= 0:
		return 0.0
	var one: float = d.get("chance", 0) * weights.get(rarity_id, 0) / total * entry.get("weight", 0) / sum
	return 1.0 - pow(1.0 - one, d.get("rolls", 1))

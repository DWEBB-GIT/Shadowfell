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
}

var files := {} ## name -> parsed file
var dirty := {} ## name -> true
var items: Array = []
var rarities: Array = []
var armour_types: Array = []
var loot_tables: Array = []
var enemies: Array = []
var quests: Array = []
var chests: Array = []
var waters: Array = []
var npcs: Array = []
## models in assets/models, and sprites in assets/icons
var models: PackedStringArray = []
var sprites: PackedStringArray = []

signal changed


func load_all() -> void:
	files.clear()
	dirty.clear()
	for f in ["items", "rarities", "loot_tables", "enemies", "quests", "world", "npcs"]:
		files[f] = IO.load_file(_path(f))
		if files[f] == null:
			files[f] = {}
			push_error("Game Data: cannot read " + _path(f))
	items = files.items.get("items", [])
	armour_types = files.items.get("armourTypes", [])
	rarities = files.rarities.get("rarities", [])
	loot_tables = files.loot_tables.get("lootTables", [])
	enemies = files.enemies.get("enemies", [])
	quests = files.quests.get("quests", [])
	chests = files.world.get("chests", [])
	waters = files.world.get("water", [])
	npcs = files.npcs.get("npcs", [])
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


func npc_name(id) -> String:
	return find(npcs, id).get("name", str(id))


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
	for t in loot_tables:
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
	for f in ["shops", "recipes", "archetypes", "world", "dialogue", "npcs"]:
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
	for e in enemies:
		if e.get("lootTable") == id:
			out.append({"kind": "loot", "enemy": e, "text": "%s drops it" % e.get("name", e.id)})
		if e.get("skin") == id:
			out.append({"kind": "skin", "enemy": e, "text": "Skinning %s" % e.get("name", e.id)})
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

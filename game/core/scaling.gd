class_name Scaling
extends RefCounted
## Growth by level: a port of src/data/scaling.js. Everything that gets bigger
## with level grows on one line, n = level + 4: the armour constant, item
## armour, stat budgets, weapon damage, spell damage and the enemy table.
## When levels differ every hit is x1.2 per level the attacker is above its
## target. The design and its tables are in docs/stats-and-damage.md.

const S := {
	"levelOffset": 4,
	"armourConstant": 400,
	"armourPerLevel": 100,
	"levelGap": 1.2,
	"critAgility": 0.4,
	"slotWeights": {
		"head": 1.0, "chest": 1.0, "legs": 1.0, "mainHand": 1.0,
		"oneHand": 0.75,
		"ranged": 0.5,
		"shoulders": 0.75, "hands": 0.75, "waist": 0.75, "feet": 0.75,
		"wrists": 0.5, "back": 0.5, "neck": 0.5, "finger": 0.5, "offHand": 0.5,
		"trinket": 0.0,
	},
	"armourFactors": {"cloth": 3, "leather": 6, "mail": 9, "plate": 12},
	"shieldArmour": 20,
	"shieldBlock": 10,
	"weaponDps": 0.45,
	"rangedDamage": 0.5,
	"weaponSpread": 0.4,
	"rarity": {
		"junk": {"budget": 0.0, "main": 1.0},
		"common": {"budget": 0.0, "main": 1.0},
		"enhanced": {"budget": 1.0, "main": 1.0},
		"rare": {"budget": 1.3, "main": 1.1},
		"epic": {"budget": 1.6, "main": 1.2},
		"legendary": {"budget": 2.0, "main": 1.3},
		"quest": {"budget": 0.0, "main": 1.0},
	},
	"budgetPerLevel": 0.4,
	"statCost": {"strength": 1.0, "agility": 1.0, "intellect": 1.0, "stamina": 1.0, "armour": 0.02, "resistance": 0.02},
	"statCostPerLevel": {"haste": 1.0 / 15.0, "block": 1.0 / 50.0},
	"budgetTolerance": 0.1,
	"par": {"mainStat": 4, "mainStatPerLevel": 2, "stamina": 10, "staminaPerLevel": 2},
	"enemyHealthSeconds": 7,
	"enemyHitShare": 12,
	"enemyHealthRoll": 0.1,
	"enemyTypes": {
		"fodder": {"health": 0.5, "hit": 0.5, "interval": 1.35, "armour": "none"},
		"pack_beast": {"health": 0.6, "hit": 0.6, "interval": 0.95, "armour": "none"},
		"normal": {"health": 1.0, "hit": 1.0, "interval": 1.35, "armour": "none"},
		"skirmisher": {"health": 0.6, "hit": 1.75, "interval": 2.5, "armour": "light"},
		"armoured": {"health": 1.25, "hit": 1.0, "interval": 1.35, "armour": "heavy"},
		"elite": {"health": 1.7, "hit": 1.375, "interval": 1.2, "armour": "armoured", "special": 0.25},
		"heavy": {"health": 4.0, "hit": 3.0, "interval": 2.2, "armour": "armoured", "special": 0.5},
		"boss": {"health": 15.0, "armour": "armoured", "special": 0.5},
	},
	"armourClasses": {"none": 0.0, "light": 0.1, "armoured": 0.2, "heavy": 0.4},
}

const GEAR := ["weapon", "armor", "shield", "jewellery"]

## the share of an item's stat budget each socket takes (forge.json
## `sockets.share`); a gem of the item's quality gives it back (gems.json)
static var socket_share := 0.0


static func growth(level: float) -> float:
	return level + S.levelOffset


static func armour_k(level: float) -> float:
	return S.armourConstant + S.armourPerLevel * level


static func level_gap_factor(attacker_level, target_level) -> float:
	var a: float = attacker_level if attacker_level else 1.0
	var t: float = target_level if target_level else 1.0
	return pow(S.levelGap, a - t)


static func spell_scale(level: float) -> float:
	return growth(level) / growth(1)


static func is_scaled_item(d: Dictionary) -> bool:
	return not d.is_empty() and GEAR.has(d.get("kind")) and d.has("itemLevel")


static func _rarity_of(d: Dictionary) -> Dictionary:
	return S.rarity.get(d.get("rarity"), S.rarity.common)


static func slot_weight(d: Dictionary) -> float:
	return S.slotWeights.get(d.get("slot"), 0.0)


static func stat_cost(k: String, item_level := 1.0) -> float:
	if S.statCost.has(k):
		return S.statCost[k]
	if S.statCostPerLevel.has(k):
		return S.statCostPerLevel[k] * growth(item_level)
	return 1.0


static func item_budget(d: Dictionary, rarity = null) -> float:
	var r: String = rarity if rarity != null else d.get("rarity", "common")
	return S.budgetPerLevel * slot_weight(d) * growth(d.get("itemLevel", 1)) * S.rarity.get(r, S.rarity.common).budget


## An item's armour (and a shield's own block chance), and a weapon's damage per swing.
static func item_main(d: Dictionary) -> Dictionary:
	var n := growth(d.itemLevel)
	var main: float = _rarity_of(d).main
	var stats := {}
	var damage = null
	if d.kind == "armor":
		var factor: float = S.armourFactors.cloth if d.get("slot") == "back" else S.armourFactors.get(d.get("armourType"), 0)
		stats.armour = U.jround(factor * slot_weight(d) * n * main)
	elif d.kind == "shield":
		stats.armour = U.jround(S.shieldArmour * n * main)
		stats.block = U.jround(S.shieldBlock * main)
	elif d.kind == "weapon":
		var swing: float = S.weaponDps * n * main * d.speed * (S.rangedDamage if d.get("slot") == "ranged" else 1.0)
		damage = [maxi(1, U.jround(swing * (1 - S.weaponSpread))), maxi(1, U.jround(swing * (1 + S.weaponSpread)))]
	return {"stats": stats, "damage": damage}


## Spend `points` across `split` (shares), each stat at its price.
static func spend_points(points: float, split, item_level: float) -> Dictionary:
	var out := {}
	if split == null or not (points > 0):
		return out
	var shares := 0.0
	for k in split:
		shares += split[k]
	if not (shares > 0):
		return out
	for k in split:
		var v := U.jround(points * split[k] / shares / stat_cost(k, item_level))
		if v > 0:
			out[k] = v
	return out


## A gear record with its numbers filled in from its item level.
## `levels`: tempering ranks, each worth one item level; `sockets`: how many
## sockets it has (each takes `socket_share` of the budget), -1 for its own.
static func scaled_item(d: Dictionary, levels := 0, sockets := -1) -> Dictionary:
	if not is_scaled_item(d):
		return d
	if levels:
		d = d.duplicate()
		d.itemLevel = d.itemLevel + levels
	var n: int = sockets if sockets >= 0 else int(d.get("sockets", 0))
	var main := item_main(d)
	var stats: Dictionary = main.stats.duplicate()
	var spent := spend_points(item_budget(d) * maxf(0, 1 - socket_share * n), d.get("statSplit"), d.itemLevel)
	for k in spent:
		stats[k] = stats.get(k, 0) + spent[k]
	for k in d.get("stats", {}):
		stats[k] = d.stats[k]
	var out := d.duplicate()
	out.stats = stats
	if d.has("damage") or main.damage != null:
		out.damage = d.get("damage", main.damage)
	return out


## Par at a level: damage a second and health of a character of that level.
static func par(level: float, stats: Dictionary, weapon_seconds: float) -> Dictionary:
	var p: Dictionary = S.par
	var main: float = p.mainStat + p.mainStatPerLevel * (level - 1)
	var stamina: float = p.stamina + p.staminaPerLevel * (level - 1)
	return {
		"dps": S.weaponDps * growth(level) + (main * stats.powerPerMainStat) / weapon_seconds,
		"health": stats.healthBase + stamina * stats.healthPerStamina,
	}


## An enemy record with its numbers filled in from its level and type.
static func scaled_enemy(e: Dictionary, stats: Dictionary, weapon_seconds: float) -> Dictionary:
	if not S.enemyTypes.has(e.get("type", "")):
		return e
	var t: Dictionary = S.enemyTypes[e.type]
	var level: float = e.get("level", 1)
	var p := par(level, stats, weapon_seconds)
	var health: float = S.enemyHealthSeconds * p.dps * t.health
	var hit = null if not t.has("hit") else U.jround(p.health / S.enemyHitShare * t.hit)
	var out := {
		"health": U.jround(health),
		"attackInterval": t.get("interval", 0.0),
		"armour": U.jround(S.armourClasses.get(e.get("armourClass", t.armour), 0.0) * armour_k(level)),
	}
	if hit != null:
		out.damage = hit
	for k in e:
		out[k] = e[k]
	if e.has("special") and t.has("special"):
		var sp := {"damage": U.jround(p.health * t.special)}
		for k in e.special:
			sp[k] = e.special[k]
		out.special = sp
	if e.has("ranged"):
		var r := {"damage": hit, "interval": t.get("interval", 0.0)}
		for k in e.ranged:
			r[k] = e.ranged[k]
		out.ranged = r
	return out


## A number from 0 to 1 fixed by a spawn's id (FNV-1a).
static func spawn_roll(spawn_id: String) -> float:
	var h := 2166136261
	for i in spawn_id.length():
		h = ((h ^ spawn_id.unicode_at(i)) * 16777619) & 0xFFFFFFFF
	return float(h) / 4294967296.0


## Each spawn point's enemy has its own health, +-10% around its type's,
## fixed by the spawn's id (FNV-1a, as the browser build hashes it).
static func spawn_health(health: float, spawn_id: String) -> int:
	var u := spawn_roll(spawn_id)
	return maxi(1, U.jround(health * (1 + S.enemyHealthRoll * (2 * u - 1))))

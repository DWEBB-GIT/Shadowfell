class_name Stats
extends RefCounted
## Character stats and the one damage formula every hit goes through.
## A port of src/systems/stats.js; see docs/stats-and-damage.md.

const ATTRS := ["stamina", "strength", "agility", "intellect"]

var game


func _init(g) -> void:
	game = g


static func S() -> Dictionary:
	return DB.CONFIG.stats


## Percent reduction from armour or resistance: armour / (armour + K), K by
## the defender's own level.
static func mitigation(value: float, defender_level := 1.0) -> float:
	if not value or value <= 0:
		return 0.0
	return minf(S().mitigationCap, (100.0 * value) / (value + Scaling.armour_k(defender_level)))


## the character's class
var archetype: Dictionary:
	get:
		return DB.archetypes.get(game.archetype_id, DB.archetypes[DB.CONFIG.player.archetype])


## every attribute and gear stat, summed
var totals: Dictionary:
	get:
		var a := archetype
		var lv: int = game.progression.level - 1
		var t: Dictionary = a.base.duplicate()
		for k in a.perLevel:
			t[k] = t.get(k, 0) + a.perLevel[k] * lv
		for slot in game.inventory.equipment:
			var s = game.inventory.equipment[slot]
			if s == null:
				continue
			var st: Dictionary = Items.view(s).get("stats", {})
			for k in st:
				t[k] = t.get(k, 0) + st[k]
		for k in ATTRS:
			t[k] = t.get(k, 0)
		if game.cooking:
			t.stamina += game.cooking.well_fed_stamina
		return t


var max_health: int:
	get:
		return int(S().healthBase + totals.stamina * S().healthPerStamina)

var max_mana: int:
	get:
		var m = archetype.get("resources", {}).get("mana")
		return U.jround(m.base + totals.intellect * m.perIntellect) if m else 0

var power: float:
	get:
		return totals.get(archetype.mainStat, 0) * S().powerPerMainStat

## Ranged power comes from Agility at half a main stat's rate (a class may say its own share).
var ranged_power: float:
	get:
		return totals.agility * S().powerPerMainStat * archetype.get("rangedPowerShare", S().rangedPowerShare)

var spell_power: float:
	get:
		return totals.intellect * S().spellPowerPerIntellect

var crit_chance: float:
	get:
		return S().critBase + totals.agility / agility_per_crit

var agility_per_crit: float:
	get:
		return Scaling.S.critAgility * Scaling.growth(game.progression.level)

var spell_scale: float:
	get:
		return Scaling.spell_scale(game.progression.level)

var armour: float:
	get:
		return totals.get("armour", 0)

## a shield's own block chance plus block from other gear; no shield, no block
var block_chance: float:
	get:
		var shield = game.inventory.equipment.offHand
		if shield == null or Items.get_def(shield.id).kind != "shield":
			return 0.0
		return minf(S().blockCap, totals.get("block", 0))

var haste: float:
	get:
		return minf(S().hasteCap, totals.get("haste", 0))

var speed: float:
	get:
		return 1 + haste / 100.0


func hasted(seconds: float) -> float:
	return seconds / speed


## The swing timer (Dan's formula): T = W / (1 + H). Each hand has its own.
var attack_cooldown: float:
	get:
		return attack_cooldown_for("main")


func attack_cooldown_for(hand: String) -> float:
	# a quiver quickens Auto Shot on top of haste
	var quiver: float = 1 + game.inventory.quiver_haste / 100.0 if hand == "ranged" else 1.0
	return hand_speed(hand) / speed / quiver


func swing_windup_for(hand: String) -> float:
	return minf(DB.attack.windup, attack_cooldown_for(hand) * 0.4)


func swing_animation_for(hand: String) -> float:
	return minf(DB.attack.swingAnimation, attack_cooldown_for(hand) * 0.9)


var swing_windup: float:
	get:
		return swing_windup_for("main")

var swing_animation: float:
	get:
		return swing_animation_for("main")

var weapon_speed: float:
	get:
		return hand_speed("main")

var dual_wielding: bool:
	get:
		return game.inventory.off_weapon != null


## `hand`: 'main', 'off' (dual wielding) or 'ranged' (the bow)
func hand_weapon(hand: String):
	var inv = game.inventory
	return inv.off_weapon if hand == "off" else inv.ranged_weapon if hand == "ranged" else inv.weapon


var has_ranged: bool:
	get:
		return game.inventory.ranged_weapon != null

var ranged_reach: float:
	get:
		var w = game.inventory.ranged_weapon
		return w.get("range", 0) if w else 0.0


func hand_speed(hand: String) -> float:
	var w = hand_weapon(hand)
	return w.get("speed", S().fistSpeed) if w else S().fistSpeed


func weapon_range_for(hand: String) -> Array:
	var w = hand_weapon(hand)
	return w.get("damage", S().fistDamage) if w else S().fistDamage


func swing_power_for(hand: String) -> float:
	return ((ranged_power if hand == "ranged" else power) * hand_speed(hand)) / DB.attack.abilityWeaponSeconds


## what one swing of that hand does before crits and armour
func swing_range_for(hand: String) -> Array:
	var r := weapon_range_for(hand)
	var p := swing_power_for(hand)
	var k: float = S().offHandDamage if hand == "off" else 1.0
	return [U.jround((r[0] + p) * k), U.jround((r[1] + p) * k)]


var global_cooldown: float:
	get:
		return maxf(S().gcdFloor, hasted(DB.global_cooldown))

var weapon_range: Array:
	get:
		return game.inventory.weapon.get("damage", S().fistDamage)

## Abilities use the weapon's damage normalised to abilityWeaponSeconds.
var ability_weapon_range: Array:
	get:
		var k: float = DB.attack.abilityWeaponSeconds / weapon_speed
		var r := weapon_range
		return [r[0] * k, r[1] * k]

var swing_power: float:
	get:
		return (power * weapon_speed) / DB.attack.abilityWeaponSeconds

var swing_range: Array:
	get:
		var r := weapon_range
		return [U.jround(r[0] + swing_power), U.jround(r[1] + swing_power)]

## damage per second from auto attack, haste and the off hand included
var dps: float:
	get:
		var per := func(hand):
			var r := swing_range_for(hand)
			return (r[0] + r[1]) / 2.0 / attack_cooldown_for(hand)
		return per.call("main") + (per.call("off") if dual_wielding else 0.0)


func ability_range(mult := 1.0) -> Array:
	var r := ability_weapon_range
	return [U.jround((r[0] + power) * mult), U.jround((r[1] + power) * mult)]


func ability_average(mult := 1.0) -> int:
	var r := ability_weapon_range
	return U.jround(((r[0] + r[1]) / 2.0 + power) * mult)


## What a level-up compares: label, value, and how to show it.
func snapshot() -> Dictionary:
	var t := totals
	return {
		"stamina": {"label": "Stamina", "v": t.stamina},
		"strength": {"label": "Strength", "v": t.strength},
		"agility": {"label": "Agility", "v": t.agility},
		"intellect": {"label": "Intellect", "v": t.intellect},
		"health": {"label": "Maximum health", "v": max_health},
		"mana": {"label": "Maximum mana", "v": max_mana},
		"dps": {"label": "Auto attack", "v": dps, "text": "%s per second" % U.fixed(dps, 1)},
		"crit": {"label": "Crit", "v": crit_chance, "text": "%s%%" % U.fixed(crit_chance, 1)},
		"spellPower": {"label": "Spell power", "v": spell_power},
		"block": {"label": "Block chance", "v": block_chance, "text": "%s%%" % U.n(block_chance)},
		"haste": {"label": "Haste", "v": haste, "text": "%s%%" % U.n(haste)},
	}


## A stat block for the damage formula.
var stat_block: Dictionary:
	get:
		var t := totals
		return {
			"level": game.progression.level,
			"crit": crit_chance,
			"critMultiplier": S().critMultiplier,
			"armour": t.get("armour", 0),
			"resistance": t.get("resistance", 0),
			"block": block_chance,
		}


## An enemy's stat block, straight from its config.
static func enemy_block(cfg: Dictionary) -> Dictionary:
	return {
		"level": cfg.get("level", 1),
		"crit": cfg.get("crit", 0),
		"critMultiplier": S().critMultiplier,
		"armour": cfg.get("armour", 0),
		"resistance": cfg.get("resistance", 0),
		"block": cfg.get("block", 0),
	}


## The damage formula: base x mult x level gap -> crit? -> armour or
## resistance -> block? -> round, at least 1.
## opts: base, mult, school, canCrit, canBlock, critBonus, forceCrit
static func compute_hit(rand: Callable, attacker: Dictionary, defender: Dictionary, opts: Dictionary) -> Dictionary:
	var school: String = opts.get("school", "physical")
	var dmg: float = opts.base * opts.get("mult", 1.0)
	var crit: bool = opts.get("canCrit", true) and (opts.get("forceCrit", false) or rand.call() * 100 < attacker.crit + opts.get("critBonus", 0))
	if crit:
		dmg *= attacker.critMultiplier
	dmg *= 1 - mitigation(defender.armour if school == "physical" else defender.resistance, defender.level) / 100.0
	var blocked := 0
	if opts.get("canBlock", false) and defender.block > 0 and rand.call() * 100 < defender.block:
		blocked = U.jround(dmg * S().blockReduction / 100.0)
	var amount := maxi(1, U.jround(dmg) - blocked)
	return {"amount": amount, "crit": crit, "blocked": blocked, "school": school}


## A weapon roll for an ability: anywhere in the normalised range, plus power.
static func weapon_roll(rand: Callable, stats) -> float:
	var r: Array = stats.ability_weapon_range
	return r[0] + (r[1] - r[0]) * rand.call() + stats.power


## An auto attack swing: anywhere in that hand's weapon range, plus swing power.
static func swing_roll(rand: Callable, stats, hand := "main") -> float:
	var r: Array = stats.weapon_range_for(hand)
	return r[0] + (r[1] - r[0]) * rand.call() + stats.swing_power_for(hand)


## An enemy blow's raw damage, varied a little either side.
static func enemy_roll(rand: Callable, damage: float) -> float:
	return damage * (1 + S().enemyVariance * (2 * rand.call() - 1))

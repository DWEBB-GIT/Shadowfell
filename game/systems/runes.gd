class_name Runes
extends RefCounted
## Weapon runes (Dan, 2026-11-02; data/professions/runes.json). One rune a
## weapon, kept in the item's rolls as `rune`, fused at a rune forge
## (RuneForge: weapon slot, rune slot, Fuse). On your weapon hits a rune
## procs `ppm` times a minute on average (WoW's procs per minute, so slow
## and fast weapons proc alike), and what it does is a share of the hit, so
## it grows with your gear without ever being worth more than a new drop.
## The weapon glows in the rune's colour (FancyGear), brighter for each
## enchant rank on it.

var game
var dots: Array = [] ## {enemy, rune, ticks (left), next, per_tick, carry}


func _init(g) -> void:
	game = g


func reset() -> void:
	dots = []


static func file() -> Dictionary:
	return DB.runes


static func def(id) -> Dictionary:
	if id == null:
		return {}
	for r in file().get("runes", []):
		if r.id == id:
			return r
	return {}


## The rune on a stack (an item instance), or "".
static func of(stack) -> String:
	var r = stack.get("rolls") if stack != null else null
	return String(r.get("rune", "")) if typeof(r) == TYPE_DICTIONARY else ""


## The rune's text with its numbers filled in.
static func text(id: String) -> String:
	var d := def(id)
	if d.is_empty():
		return ""
	return String(d.text).replace("{pct}", str(int(d.effect.get("percent", 0))))


## The glow a weapon stack shows: its rune's, scaled by its enchant ranks,
## else the item's own `glow` (the test weapons), else {}.
static func glow_for(stack) -> Dictionary:
	if stack == null:
		return {}
	var d := def(of(stack))
	if d.is_empty():
		return Items.get_def(stack.id).get("glow", {})
	var g: Dictionary = d.glow.duplicate()
	var sc: Dictionary = file().get("glowScale", {})
	var rank := Items.temper_of(stack)
	g.strength = float(g.get("strength", 1.5)) + rank * float(sc.get("strengthPerRank", 0.25))
	g.motes = rank >= int(sc.get("motesFromRank", 3))
	return g


## Chance a hit procs: ppm x weapon speed / 60.
static func proc_chance(ppm: float, speed: float) -> float:
	return clampf(ppm * speed / 60.0, 0.0, 1.0)


# ------------------------------------------------------------ fusing
## Runes are fused at a rune forge (RuneForge, Dan 2026-11-03): the forge's
## window calls apply when its channel finishes.
## Put rune `rid` on the weapon at `target`, using up one scroll from
## `loc` (if any). Returns whether it took.
func apply(loc, rid: String, target := "e:mainHand") -> bool:
	var inv = game.inventory
	var weapon = inv.get_at(target)
	if weapon == null or def(rid).is_empty() or Items.get_def(weapon.id).get("kind") != "weapon":
		return false
	if loc != null:
		var st = inv.get_at(loc)
		if st == null or Items.get_def(st.id).get("rune", "") != rid:
			return false
		inv.remove_count(st.id, 1)
	var r = weapon.get("rolls")
	r = r.duplicate(true) if typeof(r) == TYPE_DICTIONARY else {}
	r.rune = rid
	weapon.rolls = r
	if target.begins_with("e:"):
		inv._equipment_changed()
	inv._changed()
	game.events.emit("itemEnchanted", {"loc": target, "rune": rid})
	game.events.emit("spellFlash", {"position": game.player.position, "colour": def(rid).glow.colour})
	game.events.emit("log", {"text": "The %s rune sinks into your %s." % [def(rid).name, Items.view(weapon).name], "kind": "level"})
	return true


# ------------------------------------------------------------ runecraft
## Runecraft rules (runes.json `runecraft`).
static func craft_rules() -> Dictionary:
	return file().get("runecraft", {})


## The element whose fragments an enemy carries, or "".
static func fragment_element(enemy_id: String) -> String:
	var src: Dictionary = craft_rules().get("sources", {})
	for rid in src:
		if src[rid].has(enemy_id):
			return rid
	return ""


## On a kill that gave XP: maybe a rune fragment of the enemy's element,
## and from a boss or rare elite, very rarely a whole rune. Returns the
## item ids dropped.
func drop_from_enemy(enemy, xp: int) -> Array:
	var out := []
	if xp <= 0:
		return out
	var rules := craft_rules()
	var kind := Loot.fellstone_kind(enemy.cfg)
	var el := fragment_element(String(enemy.cfg.get("id", "")))
	if el != "" and game.random.call() * 100 < float(rules.get("chance", {}).get(kind, 0)):
		out.append("rune_%s_fragment" % el)
	if kind == "boss" and game.random.call() * 100 < float(rules.get("bossRuneChance", 0)):
		var all: Array = file().get("runes", [])
		var r: Dictionary = all[int(game.random.call() * all.size()) % all.size()]
		out.append("rune_" + r.id)
		game.events.emit("log", {"text": "The %s leaves behind a Rune of %s!" % [enemy.cfg.name, r.name], "kind": "level"})
	for i in out.size():
		var a := 1.3 + i * 1.7
		game.loot.drop_at({"id": out[i], "count": 1}, Vector3(enemy.position.x + sin(a) * 0.7, 0, enemy.position.z + cos(a) * 0.7))
		if out[i].ends_with("_fragment"):
			game.events.emit("log", {"text": "The %s drops %s." % [enemy.cfg.name, U.article(Items.get_def(out[i]).name) + " " + Items.get_def(out[i]).name], "kind": "loot", "rarity": "rare"})
	if not out.is_empty():
		game.events.emit("fellstoneDropped", {"enemy": enemy, "count": out.size()})
	return out


## What binding rune `rid` costs: { fragment, count, coins }.
static func bind_cost(rid: String) -> Dictionary:
	var r := craft_rules()
	return {"fragment": "rune_%s_fragment" % rid, "count": int(r.get("fragments", 10)), "coins": int(r.get("coins", 0))}


func can_bind(rid: String) -> bool:
	var c := bind_cost(rid)
	return game.inventory.count(c.fragment) >= c.count and game.inventory.coins >= c.coins


## A Refiner binds fragments into a whole rune.
func bind(rid: String) -> bool:
	var inv = game.inventory
	if def(rid).is_empty() or not can_bind(rid):
		inv._refuse("You don't have what that needs.")
		return false
	if inv.first_free() == null and inv.count("rune_" + rid) == 0:
		inv._refuse("Your bags are full.")
		return false
	var c := bind_cost(rid)
	inv.remove_count(c.fragment, c.count)
	inv.lose_coins(c.coins)
	inv.add_item("rune_" + rid, 1, true)
	game.events.emit("itemEnchanted", {"loc": "", "rune": rid})
	game.events.emit("spellFlash", {"position": game.player.position, "colour": def(rid).glow.colour})
	game.events.emit("log", {"text": "The fragments run together: a Rune of %s." % def(rid).name, "kind": "level"})
	return true


# ------------------------------------------------------------ procs
## Called for each of your weapon hits that landed. `hand`: main, off or
## ranged. `amount`: the damage the hit did.
func on_weapon_hit(enemy, hand: String, amount: float, force := false) -> bool:
	var inv = game.inventory
	var stack = inv.equipment.get("offHand" if hand == "off" else "ranged" if hand == "ranged" else "mainHand")
	var d := def(of(stack))
	if d.is_empty() or amount <= 0 or enemy == null or not enemy.alive:
		return false
	if not force and game.random.call() >= proc_chance(float(d.ppm), game.stats.hand_speed(hand)):
		return false
	_proc(d, enemy, amount)
	return true


## Called for each damaging spell or ability hit that landed (not its
## ticks). Bow abilities draw on the bow's rune; every other spell, a
## caster's included, on the main-hand weapon's. Spells have no swing
## speed, so they count as `spellSpeed` seconds (runes.json) each.
func on_spell_hit(enemy, amount: float, ranged := false, force := false) -> bool:
	var stack = game.inventory.equipment.get("ranged" if ranged else "mainHand")
	var d := def(of(stack))
	if d.is_empty() or amount <= 0 or enemy == null or not enemy.alive:
		return false
	if not force and game.random.call() >= proc_chance(float(d.ppm), float(file().get("spellSpeed", 2.5))):
		return false
	_proc(d, enemy, amount)
	return true


func _colour(d: Dictionary) -> Color:
	return Color.from_string(String(d.glow.colour), Color.WHITE)


func _proc(d: Dictionary, enemy, amount: float) -> void:
	var e: Dictionary = d.effect
	var share: float = amount * float(e.get("percent", 0)) / 100.0
	var events: Events = game.events
	events.emit("spellFlash", {"position": enemy.position, "colour": d.glow.colour})
	match String(e.kind):
		"dot":
			var ticks := maxi(1, int(round(float(e.duration) / float(e.tick))))
			var had = null
			for x in dots:
				if x.enemy == enemy and x.rune == d.id:
					had = x
			var rec := {"enemy": enemy, "rune": d.id, "ticks": ticks, "next": float(e.tick), "per_tick": share / ticks, "carry": 0.0}
			if had != null:
				had.merge(rec, true)
			else:
				dots.append(rec)
			events.emit("log", {"text": "Your %s rune: the %s is %s." % [d.name, enemy.cfg.name, String(d.get("status", "afflicted"))], "kind": "hit"})
		"strike":
			_hurt(d, enemy, share, "Your %s rune strikes the %s for {n}." % [d.name, enemy.cfg.name])
			var left := int(e.get("chain", 0))
			for other in game.enemies.list:
				if left <= 0:
					break
				if other == enemy or not other.alive or other.dead:
					continue
				if U.hyp(other.position.x - enemy.position.x, other.position.z - enemy.position.z) > float(e.get("chainRange", 6)):
					continue
				left -= 1
				events.emit("spellFlash", {"position": other.position, "colour": d.glow.colour})
				_hurt(d, other, share, "Lightning leaps to the %s for {n}." % other.cfg.name)
		"slow":
			_hurt(d, enemy, share, "Your %s rune chills the %s for {n}." % [d.name, enemy.cfg.name])
			if enemy.alive:
				game.spells.apply_aura("rune_" + d.id, enemy, {"name": "Chilled", "duration": float(e.duration), "slow": float(e.slow), "status": "slowed"})
		"heal":
			if is_undead(enemy):
				share *= 1 + float(e.get("undeadBonus", 0)) / 100.0
			var hit := _hurt(d, enemy, share, "Your %s rune sears the %s for {n}." % [d.name, enemy.cfg.name])
			var healed: float = game.player.heal(hit.get("amount", 0) * float(e.get("healPercent", 100)) / 100.0)
			if healed >= 1:
				events.emit("damageNumber", {"target": game.player, "amount": U.jround(healed), "kind": "heal"})
		"vulnerable":
			_hurt(d, enemy, share, "Your %s rune marks the %s for {n}." % [d.name, enemy.cfg.name])
			if enemy.alive:
				game.spells.apply_aura("rune_" + d.id, enemy, {"name": "Vulnerable", "duration": float(e.duration), "damageTaken": float(e.damageTaken), "status": "vulnerable"})


## Rune damage: magic, so resistance (not armour) takes its share; never
## blocked, never crits on its own (the hit it came from already rolled).
func _hurt(d: Dictionary, enemy, base: float, line: String, carry = null) -> Dictionary:
	if not enemy.alive or enemy.dead:
		return {}
	var o := {"base": base, "school": String(d.school), "canCrit": false}
	if carry != null:
		o.carry = carry
	var hit := Stats.compute_hit(game.random, game.stats.stat_block, Stats.enemy_block(enemy.cfg), o)
	if hit.amount <= 0:
		return hit
	enemy.hurt(hit.amount, {"stagger": 0.0, "quiet": true, "periodic": carry != null})
	var events: Events = game.events
	events.emit("damageNumber", {"target": enemy, "amount": hit.amount, "crit": false, "kind": "dealt", "hand": "main"})
	if line != "":
		events.emit("log", {"text": line.replace("{n}", str(hit.amount)), "kind": "hit"})
	if enemy.dead:
		game.combat.on_enemy_defeated(enemy)
	return hit


## Bone and grave foes (Dawn's bonus): `undead: true`, or bone blood.
static func is_undead(enemy) -> bool:
	return enemy.cfg.get("undead", false) or enemy.cfg.get("blood", "") == "bone"


## Burning, Poisoned... from a rune's damage over time on `enemy`.
func has_status(enemy, status: String) -> bool:
	for x in dots:
		if x.enemy == enemy and def(x.rune).get("status", "") == status:
			return true
	return false


func update(dt: float) -> void:
	for i in range(dots.size() - 1, -1, -1):
		var x: Dictionary = dots[i]
		if not x.enemy.alive or x.enemy.dead:
			dots.remove_at(i)
			continue
		x.next -= dt
		var d := def(x.rune)
		while x.next <= 1e-6 and x.ticks > 0:
			x.next += float(d.effect.tick)
			x.ticks -= 1
			var hit := _hurt(d, x.enemy, x.per_tick, "", x.carry)
			x.carry = hit.get("carry", 0.0)
			if not x.enemy.alive:
				break
		if x.ticks <= 0 or not x.enemy.alive:
			dots.remove_at(i)

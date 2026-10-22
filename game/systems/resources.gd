class_name Resources
extends RefCounted
## What abilities are paid with (src/systems/resources.js). Mana is drawn
## from Intellect and refills slowly in combat (fast out of it). Every other
## resource is a class bar, one system with different numbers per class
## (data/archetypes.json `resources.bars`); the keys are documented in the
## JS file. Ability costs live in data/abilities.json (`cost`, `gain`, and
## `spendsAll` for finishers such as Double Cut and Purge).

var game
var values := {}
var mana := 0.0
var since_combat := INF
var since_hit := INF
var unlimited := false


func _init(g) -> void:
	game = g
	reset()
	var ev: Events = game.events
	ev.on("enemyHit", func(e):
		since_combat = 0.0
		since_hit = 0.0
		if not e.get("swing"):
			return
		var off: float = DB.CONFIG.stats.offHandResolve if e.get("hand") == "off" else 1.0
		for b in bars:
			if b.get("perSwing"):
				add(b.id, b.perSwing * off))
	ev.on("playerHurt", func(e):
		since_combat = 0.0
		for b in bars:
			add(b.id, b.get("perHitTaken", 0) + (b.get("perBlock", 0) if e.get("blocked") else 0)))
	ev.on("braceBlock", func(_e):
		since_combat = 0.0
		for b in bars:
			add(b.id, b.get("perBlock", 0)))
	ev.on("dotTick", func(_e):
		since_combat = 0.0
		for b in bars:
			add(b.id, b.get("perDotTick", 0)))
	ev.on("playerDied", func(_e): reset())


var cfg: Dictionary:
	get:
		return game.stats.archetype.get("resources", {})

var bars: Array:
	get:
		return cfg.get("bars", [])


func bar(id):
	for b in bars:
		if b.id == id:
			return b
	return null


## the class's main bar (Resolve, Energy, Focus, Corruption), for the HUD
var gauge_cfg:
	get:
		for b in bars:
			if not b.get("points"):
				return b
		return null

var gauge: float:
	get:
		return values.get(gauge_cfg.id, 0.0) if gauge_cfg else 0.0
	set(v):
		if gauge_cfg:
			values[gauge_cfg.id] = v

## combo points, if the class has them
var points_cfg:
	get:
		for b in bars:
			if b.get("points"):
				return b
		return null

var max_mana: float:
	get:
		return game.stats.max_mana

var in_combat: bool:
	get:
		return since_combat < (gauge_cfg.get("decayAfter", 6.0) if gauge_cfg else 6.0)

## a bar at its max with an `overload` (Overcorrupted), or null
var overload:
	get:
		for b in bars:
			if b.get("overload") and values.get(b.id, 0.0) >= b.max:
				return b.overload
		return null

## extra damage, in %, from an overloaded bar
var damage_bonus: float:
	get:
		var o = overload
		return o.get("damageBonus", 0) if o else 0.0


## how much of a resource you have now
func amount(id: String) -> float:
	if id == "mana":
		return mana
	return values.get(id, 0.0)


func name_of(id: String) -> String:
	if id == "mana":
		return "mana"
	var b = bar(id)
	return b.name if b else id


func add(id, n) -> void:
	if not id or not (n > 0):
		return
	if id == "mana":
		mana = minf(max_mana, mana + n)
		return
	var b = bar(id)
	if b:
		values[id] = minf(b.max, values.get(id, 0.0) + n)


## the first resource an ability needs and you lack, or ""
func lacking(ability: Dictionary) -> String:
	var cost: Dictionary = ability.get("cost", {})
	for id in cost:
		if amount(id) < cost[id]:
			return id
	if ability.get("spendsAll") and amount(ability.spendsAll) < 1:
		return ability.spendsAll
	return ""


func can_afford(ability: Dictionary) -> bool:
	return unlimited or lacking(ability) == ""


## refuse with WoW's red message if short; true if it can be paid
func check(ability: Dictionary) -> bool:
	var short := "" if unlimited else lacking(ability)
	if short != "":
		if ability.get("spendsAll") == short and not ability.get("cost", {}).get(short):
			game.hud.error("You have no %s" % name_of(short))
		else:
			game.hud.error("Not enough %s" % name_of(short))
	return short == ""


func _take(id: String, n: float) -> float:
	var had := amount(id)
	var paid := minf(had, n)
	if id == "mana":
		mana = had - paid
	else:
		values[id] = had - paid
	var b = bar(id)
	var heal = b.get("healPerSpent", 0.0) if b else 0.0
	# Unbroken, Soul Tithe: spending heals (more)
	if game.builds:
		for e in game.builds.effects("spendHeal"):
			if e.resource == id:
				heal += e.percentPerPoint
	if heal and paid > 0:
		var p = game.player
		var healed: float = p.heal(p.max_health * heal * paid / 100.0)
		if healed >= 1:
			game.events.emit("damageNumber", {"target": p, "amount": U.jround(healed), "kind": "heal"})
	return paid


## Pay an ability's cost and take its gain. Returns how much of its
## `spendsAll` resource it spent (the combo points behind a Double Cut).
func spend(ability: Dictionary, gain = null) -> float:
	if gain == null:
		gain = ability.get("gain")
	var all := 0.0
	if not unlimited:
		var cost: Dictionary = ability.get("cost", {})
		for id in cost:
			_take(id, cost[id])
	if ability.get("spendsAll"):
		all = maxf(1, amount(ability.spendsAll)) if unlimited else _take(ability.spendsAll, amount(ability.spendsAll))
	if gain:
		for id in gain:
			add(id, gain[id])
	if ability.get("cost") or gain or ability.get("spendsAll"):
		since_combat = minf(since_combat, 0.001)
	return all


func update(dt: float) -> void:
	var player = game.player
	if player.dead:
		return
	since_combat += dt
	since_hit += dt
	var fighting := in_combat
	var hidden: bool = game.spells != null and game.spells.hidden
	var m = cfg.get("mana")
	if m:
		mana = minf(max_mana, mana + (m.regenPerSecond if fighting else m.regenOutOfCombat) * dt)
	for b in bars:
		var v: float = values.get(b.id, 0.0)
		var regen: float = b.get("regenPerSecond", 0) if fighting else b.get("regenOutOfCombat", b.get("regenPerSecond", 0))
		if regen:
			v += regen * (b.get("shadowMultiplier", 1) if hidden else 1) * (1.0 if player.moving else 1 + b.get("stillBonus", 0)) * dt
		if b.get("decayPerSecond") and not fighting:
			v -= b.decayPerSecond * dt
		if b.get("points") and b.get("fadeAfter") and since_hit > b.fadeAfter and not hidden:
			v = 0
		values[b.id] = clampf(v, 0, b.max)
	# Overcorrupted: health bleeds away until the bar drops (never below 1)
	var o = overload
	if o:
		player.health = maxf(1, player.health - player.max_health * o.healthLossPercent * dt / 100.0)


## back to full mana and each bar at its start (respawn, load, a new character)
func reset() -> void:
	mana = max_mana if game.stats else 0.0
	values = {}
	if game.stats:
		for b in bars:
			values[b.id] = b.max if b.get("start") == "full" else 0.0
	since_combat = INF
	since_hit = INF

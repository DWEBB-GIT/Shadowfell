class_name Cooking
extends RefCounted
## Cooking (data/recipes.json; src/systems/cooking.js), learned from Hester
## at the Ford Inn, and the food it makes. A recipe needs a skill rank, its
## ingredients and a fire close by; each dish takes a short cast; moving
## stops it; a recipe is orange, yellow, green or grey by how easy it now
## is, and so how likely making it is to raise your skill. Food is eaten
## sitting down: it restores health over its time while you stay still and
## out of the fight. Eating for `wellFedAfter` seconds makes you Well Fed.

const SKILL_UP_CHANCE := {"orange": 1.0, "yellow": 0.75, "green": 0.25, "grey": 0.0}

var game
var learned := {} ## taught recipes (the starters need no learning)
var crafting = null ## { id, t, total, left }
var well_fed := 0.0 ## seconds of Well Fed left


func _init(g) -> void:
	game = g
	game.events.on("playerHurt", func(_e): stop_eating("You stop eating."))
	game.events.on("playerDied", func(_e):
		crafting = null
		game.player.eating = null)


func reset() -> void:
	learned = {}
	crafting = null
	well_fed = 0.0


## Stamina from being Well Fed (added to your stats)
var well_fed_stamina: float:
	get:
		return ability.tuning.wellFedStamina if well_fed > 0 else 0.0

## the buff row's entry
var well_fed_aura:
	get:
		return {"id": "wellFed", "name": "Well Fed", "left": well_fed, "total": ability.tuning.wellFedSeconds} if well_fed > 0 else null


func _set_well_fed(seconds: float) -> void:
	var was := well_fed > 0
	well_fed = seconds
	if was != (seconds > 0):
		game.recompute_max_health()


var ability: Dictionary:
	get:
		return DB.abilities.cook


func rank(sk := "cooking") -> int:
	return game.skills.rank(sk)


# ------------------------------------------------------------ recipes
func knows(id: String) -> bool:
	var r = DB.recipes.get(id)
	return r != null and game.skills.has(r.skill) and (not r.get("trainer") or learned.has(id))


## every recipe you know for a skill, easiest first
func known(sk := "cooking") -> Array:
	var out := DB.recipes.values().filter(func(r): return r.skill == sk and knows(r.id))
	out.sort_custom(func(a, b): return a.rank < b.rank)
	return out


## 'orange' | 'yellow' | 'green' | 'grey' (or 'red' while it is beyond you)
func colour(r: Dictionary) -> String:
	var n := rank(r.skill)
	if n < r.rank:
		return "red"
	var su: Array = r.skillUp
	return "orange" if n < su[0] else "yellow" if n < su[1] else "green" if n < su[2] else "grey"


## how many times you could make it with what is in your bags
func can_make(r: Dictionary) -> int:
	var best := 1 << 30
	for x in r.inputs:
		best = mini(best, int(floor(game.inventory.count(x.item) / float(x.count))))
	return best


var near_fire: String:
	get:
		return near_station("fire")


## The station of this kind you stand at (its name), or "": `fire` (your
## camp or a hearth), `forge` (a forge, for smelting).
func near_station(kind: String) -> String:
	var p: Vector3 = game.player.position
	if kind == "fire":
		var range_: float = ability.tuning.fireRange
		var camp = game.world_state.camp
		if camp != null and U.hyp(p.x - camp.x, p.z - camp.z) <= range_:
			return "your camp"
	for st in Layout.stations:
		if st.kind == kind and U.hyp(p.x - st.position[0], p.z - st.position[1]) <= st.radius:
			return st.name
	return ""


## A crafting skill's window, verb and button (skills.json `craft`).
static func craft_of(sk: String) -> Dictionary:
	return DB.skills.get(sk, {}).get("craft", {"window": "Cooking", "verb": "cook", "button": "Cook", "station": "a fire"})


## what a trainer can teach you now (you must know the skill first)
func offered_by(npc_id: String) -> Array:
	return DB.recipes.values().filter(func(r): return r.get("trainer") == npc_id and game.skills.has(r.skill) and not learned.has(r.id))


func learn_recipe(id: String) -> bool:
	var r = DB.recipes.get(id)
	var inventory = game.inventory
	var events: Events = game.events
	if r == null or not r.get("trainer") or learned.has(id):
		return false
	var name: String = Items.get_def(r.output.item).name
	if rank(r.skill) < r.rank:
		events.emit("log", {"text": "You need %s %d to learn %s." % [DB.skills[r.skill].name, r.rank, name], "kind": "muted", "throttle": "recipe-rank"})
		return false
	if inventory.coins < r.cost:
		events.emit("log", {"text": "You need %s to learn %s." % [U.money(r.cost), name], "kind": "muted", "throttle": "recipe-coins"})
		return false
	inventory.lose_coins(r.cost)
	learned[id] = true
	events.emit("log", {"text": "You learn to make %s." % name, "kind": "level"})
	if game.hud:
		game.hud.toast("Recipe: %s" % name)
	events.emit("skillsChanged", {"id": r.skill})
	return true


# ------------------------------------------------------------ cooking
## Why a recipe cannot be made now ("" if it can).
func blocked(r: Dictionary) -> String:
	var player = game.player
	if not knows(r.id):
		return "You don't know how to make that."
	if rank(r.skill) < r.rank:
		return "Requires %s %d." % [DB.skills[r.skill].name, r.rank]
	if can_make(r) < 1:
		return "You are missing ingredients."
	if near_station(r.get("station", "fire")) == "":
		return "Requires %s." % ("a cooking fire" if r.get("station", "fire") == "fire" else "a " + r.station)
	if player.dead or player.casting != null or player.lunge != null:
		return "You can't do that now."
	if player.moving:
		return "You can't do that while moving."
	return ""


## Start cooking `times` of a recipe (a huge number: as many as you can).
func start(id: String, times := 1) -> bool:
	var r = DB.recipes.get(id)
	if r == null:
		return false
	var why := blocked(r)
	if why != "":
		game.hud.error(why)
		return false
	stop_eating()
	crafting = {"id": id, "t": 0.0, "total": ability.tuning.castTime, "left": mini(times, can_make(r))}
	game.player.rig.play("brace", crafting.total, 0.9)
	game.events.emit("craftStart", {"id": id})
	return true


func stop(why := "") -> void:
	if crafting == null:
		return
	crafting = null
	game.player.rig.action = null
	if why != "":
		game.events.emit("log", {"text": why, "kind": "muted", "throttle": "craft-stop"})
	game.events.emit("craftEnd", {"done": false})


func _finish(r: Dictionary) -> void:
	var inventory = game.inventory
	for x in r.inputs:
		inventory.remove_count(x.item, x.count)
	inventory.add_item(r.output.item, r.output.count, true)
	var name: String = Items.get_def(r.output.item).name
	game.events.emit("log", {"text": "You %s %s%s." % [craft_of(r.skill).get("verb", "make"), "%d " % r.output.count if r.output.count > 1 else "", name], "kind": "loot"})
	var c: float = SKILL_UP_CHANCE.get(colour(r), 0.0)
	if c > 0 and game.random.call() < c:
		game.skills.raise(r.skill)


func update(dt: float) -> void:
	var player = game.player
	var c = crafting
	if c != null:
		if player.dead or player.moving:
			stop("Interrupted.")
		else:
			c.t += dt
			if c.t >= c.total:
				var r: Dictionary = DB.recipes[c.id]
				_finish(r)
				c.left -= 1
				if c.left > 0 and can_make(r) > 0 and near_station(r.get("station", "fire")) != "":
					c.t = 0.0
					player.rig.play("brace", c.total, 0.9)
				else:
					crafting = null
				# after the state is settled, so the window can offer the next dish at once
				game.events.emit("craftEnd", {"id": r.id, "done": true})
	if well_fed > 0:
		well_fed -= dt
		if well_fed <= 0:
			_set_well_fed(0)
			game.events.emit("log", {"text": "Well Fed fades.", "kind": "muted"})
	# eating: health over time while sitting still, out of the fight
	var e = player.eating
	if e != null:
		if player.dead or player.moving:
			stop_eating("You stop eating.")
		else:
			var step := minf(dt, e.left)
			e.left -= step
			e.carry += e.perSecond * step
			var whole := int(floor(e.carry))
			if whole > 0:
				e.carry -= whole
				if player.health < player.max_health:
					player.heal(whole)
			var t: Dictionary = ability.tuning
			if not e.get("fed", false) and e.total - e.left >= t.wellFedAfter - 1e-6:
				e.fed = true
				_set_well_fed(t.wellFedSeconds * (1 + _jade() / 100.0))
				game.events.emit("log", {"text": "You are Well Fed: +%s Stamina for %d minutes." % [U.n(t.wellFedStamina), U.jround(t.wellFedSeconds / 60.0)], "kind": "level"})
				if game.hud:
					game.hud.toast("Well Fed")
			# full and fed: get up
			var full: bool = player.health >= player.max_health
			if e.left <= 0 or (full and e.get("fed", false)):
				stop_eating("You feel full." if full else "")


## What Jade set in worn gear adds to Well Fed (percent).
func _jade() -> float:
	var n := 0.0
	for slot in game.inventory.equipment:
		var s = game.inventory.equipment[slot]
		if s != null:
			for g in Items.gems_of(s):
				if g != null:
					n += Gems.effect(g, "buffDuration")
	return n


# ------------------------------------------------------------ food
## Sit and eat a dish from your bags (out of combat only).
func eat(loc: String) -> bool:
	var player = game.player
	var inventory = game.inventory
	var s = inventory.get_at(loc)
	var food = Items.get_def(s.id).get("use", {}).get("food") if s != null else null
	if food == null or player.dead:
		return false
	if game.resources.in_combat or game.targeting.attacking:
		game.hud.error("You can't eat while fighting.")
		return false
	# at full health you still eat for Well Fed, unless you already are
	if player.health >= player.max_health and well_fed > 0:
		game.events.emit("log", {"text": "You are not hungry.", "kind": "muted", "throttle": "not-hungry"})
		return false
	stop()
	var id: String = s.id
	inventory.take(loc, 1)
	player.eating = {"id": id, "perSecond": food.heal / food.seconds, "left": food.seconds, "total": food.seconds, "carry": 0.0, "fed": false}
	player.rig.pose = "sit"
	game.events.emit("log", {"text": "You sit and eat the %s." % Items.get_def(id).name.to_lower(), "kind": "heal"})
	return true


func stop_eating(text := "") -> void:
	var player = game.player
	if player == null or player.eating == null:
		return
	player.eating = null
	if player.rig.pose == "sit":
		player.rig.pose = null
	if text != "":
		game.events.emit("log", {"text": text, "kind": "muted", "throttle": "eat-stop"})


# ------------------------------------------------------------ saving
func serialize() -> Dictionary:
	return {"recipes": learned.keys(), "wellFed": U.jround(well_fed)}


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data.get("recipes", []):
		if DB.recipes.get(id, {}).get("trainer"):
			learned[id] = true
	if data.get("wellFed", 0) > 0:
		_set_well_fed(data.wellFed)

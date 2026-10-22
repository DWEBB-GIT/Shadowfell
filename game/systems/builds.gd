class_name Builds
extends RefCounted
## Build layers (after Diablo 4), all from data/builds.json and the
## `upgrades` on spells in data/abilities.json:
## - path points, one a level from `pathPoints.fromLevel`, buy a spell's
##   Enhanced rank and then one of its two forks;
## - one key passive per character, from `keyPassiveLevel`;
## - legendary powers on equipped items (their own `power`, or one moved onto
##   them at the forge);
## - shared status tags (bleeding, slowed, vulnerable...) that all of these
##   read, so a new item can make a build without a new spell.
##
## A change (an upgrade, a fork, a power's `changes`) is a partial ability
## record: `tuning` keys are set, `add` and `scale` add to or multiply tuning
## numbers (so Weapon Master's loadouts still differ), and any other key
## replaces the ability's own (applies, follow, cost, gain, bonusVs,
## execute, spreadsOnDeath, range, stacks).
##
## Effect kinds (key passives and powers): statusDamage, execute, hitStacks,
## spendHeal, critBuild, dotHaste, zoneFortify, trap.

const EFFECT_KINDS := ["statusDamage", "execute", "hitStacks", "spendHeal", "critBuild", "dotHaste", "zoneFortify", "trap"]

var game
var upgrades := {} ## spell id -> { enhanced: bool, fork: fork id or "" }
var key_passive := "" ## a keyPassives id


func _init(g) -> void:
	game = g


func reset() -> void:
	upgrades = {}
	key_passive = ""


static func file() -> Dictionary:
	return DB.builds


static func points_rule() -> Dictionary:
	return file().get("pathPoints", {"fromLevel": 10, "perLevel": 1, "enhancedCost": 1, "forkCost": 1})


static func status_def(id: String) -> Dictionary:
	for s in file().get("statuses", []):
		if s.id == id:
			return s
	return {}


static func passive_def(id: String) -> Dictionary:
	for p in file().get("keyPassives", []):
		if p.id == id:
			return p
	return {}


static func power_def(id) -> Dictionary:
	if typeof(id) != TYPE_STRING:
		return {}
	for p in file().get("powers", []):
		if p.id == id:
			return p
	return {}


static func passives_for(archetype: String) -> Array:
	return file().get("keyPassives", []).filter(func(p): return p.archetype == archetype)


## A change applied to an ability record (see the top of this file).
static func apply_change(spell: Dictionary, c: Dictionary) -> Dictionary:
	var out := spell.duplicate()
	var t: Dictionary = spell.get("tuning", {}).duplicate()
	for k in c.get("tuning", {}):
		t[k] = c.tuning[k]
	for k in c.get("add", {}):
		t[k] = t.get(k, 0) + c.add[k]
	for k in c.get("scale", {}):
		if t.has(k):
			t[k] = t[k] * c.scale[k]
	out.tuning = t
	for k in c:
		if k in ["tuning", "add", "scale", "text", "id", "name"]:
			continue
		out[k] = c[k]
	return out


# ------------------------------------------------------------ path points
var points_total: int:
	get:
		var r := points_rule()
		var lvl: int = game.progression.level
		return maxi(0, (lvl - int(r.fromLevel) + 1) * int(r.get("perLevel", 1)))

var points_spent: int:
	get:
		var r := points_rule()
		var n := 0
		for id in upgrades:
			var u: Dictionary = upgrades[id]
			if u.get("enhanced"):
				n += int(r.get("enhancedCost", 1))
			if u.get("fork", "") != "":
				n += int(r.get("forkCost", 1))
		return n

var points_free: int:
	get:
		return points_total - points_spent


func has_enhanced(id: String) -> bool:
	return upgrades.get(id, {}).get("enhanced", false)


func fork_of(id: String) -> String:
	return upgrades.get(id, {}).get("fork", "")


## Buy the Enhanced rank of a spell. False (with a word) if it cannot.
func enhance(id: String) -> bool:
	var u = DB.abilities.get(id, {}).get("upgrades")
	if u == null or has_enhanced(id):
		return false
	if points_free < int(points_rule().get("enhancedCost", 1)):
		_say("You have no path points to spend")
		return false
	upgrades[id] = {"enhanced": true, "fork": fork_of(id)}
	_changed("%s is Enhanced." % DB.abilities[id].name)
	return true


## Choose one of a spell's forks (it must be Enhanced). One fork a spell.
func choose_fork(id: String, fork_id: String) -> bool:
	var u = DB.abilities.get(id, {}).get("upgrades")
	if u == null or not u.forks.any(func(f): return f.id == fork_id):
		return false
	if not has_enhanced(id):
		_say("Enhance %s first" % DB.abilities[id].name)
		return false
	if fork_of(id) != "":
		return false
	if points_free < int(points_rule().get("forkCost", 1)):
		_say("You have no path points to spend")
		return false
	upgrades[id].fork = fork_id
	for f in u.forks:
		if f.id == fork_id:
			_changed("%s: %s." % [DB.abilities[id].name, f.name])
	return true


## Take back every point (a mentor's service later; free for now).
func respec() -> void:
	upgrades = {}
	_changed("Your path points are free to spend again.")


# ------------------------------------------------------------ key passive
var key_passive_open: bool:
	get:
		return game.progression.level >= int(file().get("keyPassiveLevel", 10))


func choose_passive(id: String) -> bool:
	var p := passive_def(id)
	if p.is_empty() or p.archetype != game.stats.archetype.get("id"):
		return false
	if not key_passive_open:
		_say("Key passives open at level %d" % int(file().get("keyPassiveLevel", 10)))
		return false
	key_passive = id
	_changed("Key passive: %s." % p.name)
	return true


# ------------------------------------------------------------ powers
## The legendary powers on what you wear: [{ power def, item name }]
func powers() -> Array:
	var out := []
	var inv = game.inventory
	if inv == null:
		return out
	for slot in inv.equipment:
		var s = inv.equipment[slot]
		if s == null:
			continue
		var p := power_def(Items.power_of(s))
		if not p.is_empty():
			out.append(p)
	return out


## Every change that applies to a spell now, in order: Enhanced, its fork,
## then legendary powers that name it.
func changes_for(id: String) -> Array:
	var out := []
	var u = DB.abilities.get(id, {}).get("upgrades")
	if u != null and has_enhanced(id):
		out.append(u.enhanced)
		var f := fork_of(id)
		for x in u.forks:
			if x.id == f:
				out.append(x)
	for p in powers():
		if p.has("changes") and (p.get("spell") == id or p.get("spells", []).has(id)):
			out.append(p.changes)
	return out


## Effects of one kind from the key passive and from powers.
func effects(kind: String) -> Array:
	var out := []
	var sources := powers()
	if key_passive != "":
		sources.append(passive_def(key_passive))
	for s in sources:
		for e in s.get("effects", []):
			if e.kind == kind:
				out.append(e)
	return out


# ------------------------------------------------------------ save
func serialize() -> Dictionary:
	return {"upgrades": upgrades.duplicate(true), "keyPassive": key_passive}


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var ups = data.get("upgrades", {})
	if typeof(ups) == TYPE_DICTIONARY:
		for id in ups:
			var u = ups[id]
			var def = DB.abilities.get(id, {}).get("upgrades")
			if def == null or typeof(u) != TYPE_DICTIONARY:
				continue
			var f = u.get("fork", "")
			upgrades[id] = {"enhanced": bool(u.get("enhanced", false)), "fork": f if typeof(f) == TYPE_STRING and def.forks.any(func(x): return x.id == f) else ""}
	var kp = data.get("keyPassive", "")
	if typeof(kp) == TYPE_STRING and not passive_def(kp).is_empty():
		key_passive = kp


func _say(text: String) -> void:
	if game.hud:
		game.hud.error(text)


func _changed(text: String) -> void:
	game.events.emit("log", {"text": text, "kind": "level"})
	game.events.emit("buildChanged", {})
	game.events.emit("statsChanged")


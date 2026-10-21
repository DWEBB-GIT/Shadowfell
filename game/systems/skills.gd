class_name Skills
extends RefCounted
## Skills learned from trainers (data/skills.json; src/systems/skills.js).
## A skill unlocks the abilities it `teaches`. Skills with a `maxRank` rise
## with use, as WoW's professions do: fishing goes up by one with each catch.

var game
var ranks := {} ## skill id -> rank (1 when learned)
var all_spells := false ## a test hook: every class spell


func _init(g) -> void:
	game = g


func reset() -> void:
	ranks = {}


func has(id: String) -> bool:
	return ranks.has(id)


func rank(id: String) -> int:
	return ranks.get(id, 0)


## May the character use this ability? A skill's tool once the skill is
## learned; a class spell if it is in the class's spellbook, or is the
## Shadow or follow-up form of one. Abilities in no class (auto attack) always.
func knows_ability(ability) -> bool:
	var a = DB.abilities.get(ability)
	if a == null:
		return false
	if a.has("skill"):
		return has(a.skill)
	if not a.has("kind") or all_spells:
		return true
	var book: Array = game.stats.archetype.get("abilities", [])
	if book.has(ability):
		return true
	for id in book:
		var b: Dictionary = DB.abilities.get(id, {})
		if b.get("inShadow") == ability or b.get("follow") == ability:
			return true
	return false


## What a trainer offers that the character has not learned.
func offered_by(npc_id: String) -> Array:
	return DB.skills.values().filter(func(s): return s.get("trainer") == npc_id and not has(s.id))


## Pay the trainer and learn; false (with a word why) if it cannot be done.
func learn(id: String) -> bool:
	var s = DB.skills.get(id)
	var inventory = game.inventory
	var events: Events = game.events
	if s == null or has(id):
		return false
	if inventory.coins < s.cost:
		events.emit("log", {"text": "You need %s to learn %s." % [U.money(s.cost), s.name], "kind": "muted", "throttle": "train-coins"})
		return false
	inventory.lose_coins(s.cost)
	ranks[id] = 1
	# what it teaches goes onto an empty slot of the bar, if there is one
	for ab in s.get("teaches", []):
		var free := ActionBar.free_slot(game.action_bar.slots)
		if free >= 0:
			game.action_bar.place(ab, free)
	var names := " and ".join(s.get("teaches", []).map(func(ab): return DB.abilities[ab].name))
	events.emit("log", {"text": "You learn %s.%s" % [s.name, " %s is under Professions (U)." % names if names != "" else ""], "kind": "level"})
	if game.hud:
		game.hud.toast("Learned: %s" % s.name)
	events.emit("skillsChanged", {"id": id})
	return true


## One step up a skill that rises with use (up to its maxRank).
func raise(id: String) -> bool:
	var s = DB.skills.get(id)
	if s == null or not s.get("maxRank") or not has(id) or rank(id) >= s.maxRank:
		return false
	ranks[id] = rank(id) + 1
	game.events.emit("log", {"text": "Your skill in %s rises to %d." % [s.name, rank(id)], "kind": "level"})
	game.events.emit("skillsChanged", {"id": id})
	return true


func serialize() -> Dictionary:
	return ranks.duplicate()


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data:
		var r = data[id]
		if DB.skills.has(id) and (typeof(r) == TYPE_INT or (typeof(r) == TYPE_FLOAT and r == floor(r))) and r >= 1:
			ranks[id] = mini(int(r), int(DB.skills[id].get("maxRank", 1)))

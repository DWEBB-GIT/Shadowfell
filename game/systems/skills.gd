class_name Skills
extends RefCounted
## Skills learned from trainers (data/skills.json; src/systems/skills.js).
## A skill unlocks the abilities it `teaches`. Skills with a `maxRank` rise
## with use, as WoW's professions do: fishing goes up by one with each catch.
## A class's `trained` spells (archetypes.json) are learned from a trainer
## for coins once the character is high enough level, WoW's class trainers.
## A class starts with only its basic spell; its `later` spells wait for
## trainers in the big cities.

var game
var ranks := {} ## skill id -> rank (1 when learned)
var spells: Array = [] ## class spells learned from a trainer
var all_spells := false ## a test hook: every class spell


func _init(g) -> void:
	game = g


func reset() -> void:
	ranks = {}
	spells = []


func has(id: String) -> bool:
	return ranks.has(id)


func rank(id: String) -> int:
	return ranks.get(id, 0)


## What the best tool carried adds to a skill: an item's `<skill>Skill`
## (fishingSkill, skinningSkill) counts while it is in the bags, the tool
## pack or equipped. Only the best one counts, as in WoW.
func tool_bonus(id: String) -> int:
	var key := id + "Skill"
	var best := 0
	for item in DB.items:
		var d: Dictionary = DB.items[item]
		if d.has(key) and int(d[key]) > best and game.inventory.has(item):
			best = int(d[key])
	return best


## The rank plus the best tool's bonus, plus gathering gems (Moonstone) worn.
func effective(id: String) -> int:
	return rank(id) + tool_bonus(id) + (gem_bonus() if ["mining", "skinning", "fishing"].has(id) else 0)


## What Moonstones set in worn gear add to gathering skills.
func gem_bonus() -> int:
	var n := 0.0
	var inv = game.inventory
	if inv == null:
		return 0
	for slot in inv.equipment:
		var s = inv.equipment[slot]
		if s != null:
			for g in Items.gems_of(s):
				if g != null:
					n += Gems.effect(g, "gatherSkill")
	return int(n)


## May the character use this ability? A skill's tool once the skill is
## learned; a class spell if it is in the class's spellbook, or is the
## Shadow or follow-up form of one. Abilities in no class (auto attack) always.
func knows_ability(ability) -> bool:
	var a = DB.abilities.get(ability)
	if a == null:
		return false
	if a.has("skill"):
		return has(a.skill)
	if a.get("everyone"):
		return true
	if not a.has("kind") or all_spells:
		return true
	var book: Array = game.stats.archetype.get("abilities", [])
	if book.has(ability):
		return not needs_training(ability)
	for id in book:
		var b: Dictionary = DB.abilities.get(id, {})
		if (b.get("inShadow") == ability or b.get("follow") == ability) and not needs_training(id):
			return true
	return false


## the class's trainer entry for a spell ({ability, trainer, level, cost,
## quest?}), or {}
func trained_entry(ability) -> Dictionary:
	for t in game.stats.archetype.get("trained", []):
		if t.get("ability") == ability:
			return t
	return {}


## a class spell a trainer teaches that this character has not learned yet,
## or one left for a later trainer (archetypes.json `later`), not in the world yet
func needs_training(ability) -> bool:
	if all_spells or spells.has(ability):
		return false
	return not trained_entry(ability).is_empty() or game.stats.archetype.get("later", []).has(ability)


## The name of the quest a trainer entry waits on (its `quest`, not yet
## handed in), or "" when nothing holds it back.
func quest_gate(t: Dictionary) -> String:
	var q = t.get("quest")
	if not q or game.quests.status(q) == "done":
		return ""
	return DB.quests.get(q, {}).get("name", q)


## Pay a class trainer and learn a spell; false (with a word why) if not.
func learn_spell(ability: String) -> bool:
	var t := trained_entry(ability)
	var events: Events = game.events
	if t.is_empty() or spells.has(ability):
		return false
	var a: Dictionary = DB.abilities[ability]
	if game.progression.level < int(t.get("level", 1)):
		events.emit("log", {"text": "You must be level %d to learn %s." % [t.level, a.name], "kind": "muted", "throttle": "train-level"})
		return false
	var gate := quest_gate(t)
	if gate != "":
		events.emit("log", {"text": "You must first complete %s to learn %s." % [gate, a.name], "kind": "muted", "throttle": "train-quest"})
		return false
	var cost := int(t.get("cost", 0))
	if game.inventory.coins < cost:
		events.emit("log", {"text": "You need %s to learn %s." % [U.money(cost), a.name], "kind": "muted", "throttle": "train-coins"})
		return false
	game.inventory.lose_coins(cost)
	spells.append(ability)
	var free := ActionBar.free_slot(game.action_bar.slots)
	if free >= 0:
		game.action_bar.place(ability, free)
	events.emit("log", {"text": "You learn %s. It is in your spellbook (P)." % a.name, "kind": "level"})
	if game.hud:
		game.hud.toast("Learned: %s" % a.name)
	events.emit("skillsChanged", {"id": ability})
	return true


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


func serialize_spells() -> Array:
	return spells.duplicate()


func apply_spells(data) -> void:
	spells = []
	if typeof(data) == TYPE_ARRAY:
		for id in data:
			if typeof(id) == TYPE_STRING and DB.abilities.has(id):
				spells.append(id)


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data:
		var r = data[id]
		if DB.skills.has(id) and (typeof(r) == TYPE_INT or (typeof(r) == TYPE_FLOAT and r == floor(r))) and r >= 1:
			ranks[id] = mini(int(r), int(DB.skills[id].get("maxRank", 1)))

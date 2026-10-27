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
var ranks := {} ## skill id -> rank (1 when learned); on the ladder, the skill level (1-60)
var xp := {} ## laddered skill id -> skill experience towards the next level
var tiers := {} ## laddered skill id -> trainer rank reached (0 Novice, 1 Apprentice, ...)
var perks := {} ## laddered skill id -> { "10": perk id, ... }
var capped_told := {} ## skills already told they are at their rank's cap (this session)
var spells: Array = [] ## class spells learned from a trainer
var all_spells := false ## a test hook: every class spell


func _init(g) -> void:
	game = g


func reset() -> void:
	ranks = {}
	xp = {}
	tiers = {}
	perks = {}
	capped_told = {}
	spells = []


func has(id: String) -> bool:
	return ranks.has(id)


func rank(id: String) -> int:
	return ranks.get(id, 0)


## What the best tool carried adds to a skill: an item's `<skill>Skill`
## (fishingSkill, skinningSkill) counts while it is in the bags, the tool
## pack or equipped. Only the best one counts, as in WoW. A tool with a
## `reqSkill` counts only once your skill is that high.
func tool_bonus(id: String) -> int:
	var key := id + "Skill"
	var best := 0
	for item in DB.items:
		var d: Dictionary = DB.items[item]
		if d.has(key) and int(d[key]) > best and rank(id) >= int(d.get("reqSkill", 0)) and game.inventory.has(item):
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
	if laddered(id):
		tiers[id] = 0
		xp[id] = 0
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
## A laddered skill takes this as a yellow task.
func raise(id: String) -> bool:
	if laddered(id):
		return gain(id, "yellow") > 0
	var s = DB.skills.get(id)
	if s == null or not s.get("maxRank") or not has(id) or rank(id) >= s.maxRank:
		return false
	ranks[id] = rank(id) + 1
	game.events.emit("log", {"text": "Your skill in %s rises to %d." % [s.name, rank(id)], "kind": "level"})
	game.events.emit("skillsChanged", {"id": id})
	return true


# ------------------------------------------------------------ the ladder
## The profession ladder (skills.json `ladder`, Dan 2026-10-27): a skill
## with `train` runs from 1 to 60 like a character, capped by the trainer
## rank reached. Tasks pay skill experience by their colour; every level
## pays a share of a character level's experience; at the perk levels you
## choose one of two perks.

static func ladder() -> Dictionary:
	return DB.skill_ladder


func laddered(id: String) -> bool:
	return DB.skills.get(id, {}).has("train")


## the highest the skill can rise now: its rank's cap, or its maxRank
func cap(id: String) -> int:
	if not laddered(id):
		return int(DB.skills.get(id, {}).get("maxRank", 1))
	var rs: Array = ladder().ranks
	return int(rs[mini(tiers.get(id, 0), rs.size() - 1)].cap)


func rank_name(id: String) -> String:
	var rs: Array = ladder().get("ranks", [])
	return rs[mini(tiers.get(id, 0), rs.size() - 1)].name if laddered(id) and not rs.is_empty() else ""


## skill experience a level needs
static func xp_needed(level: int) -> int:
	var l := ladder()
	return int(l.get("xpBase", 30)) + int(l.get("xpPerLevel", 10)) * level


## 'red' (beyond you), 'orange', 'yellow', 'green' or 'grey' for a task that
## needs `need` skill
func colour_for(id: String, need: int) -> String:
	var over := rank(id) - need
	if over < 0:
		return "red"
	var b: Array = ladder().get("bands", [3, 6, 10])
	return "orange" if over < b[0] else "yellow" if over < b[1] else "green" if over < b[2] else "grey"


## Skill experience for a task of this colour. Returns the levels gained.
func gain(id: String, colour: String) -> int:
	var s = DB.skills.get(id)
	if s == null or not has(id):
		return 0
	if not laddered(id):
		return 1 if colour != "grey" and colour != "red" and raise(id) else 0
	var amount := int(ladder().get("actionXp", {}).get(colour, 0))
	if amount <= 0:
		return 0
	if rank(id) >= cap(id):
		_tell_capped(id)
		return 0
	xp[id] = int(xp.get(id, 0)) + amount
	var levels := 0
	while xp[id] >= xp_needed(rank(id)) and rank(id) < cap(id):
		xp[id] -= xp_needed(rank(id))
		ranks[id] = rank(id) + 1
		levels += 1
		_levelled(id)
	if rank(id) >= cap(id):
		xp[id] = 0
	game.events.emit("skillsChanged", {"id": id})
	return levels


func _levelled(id: String) -> void:
	var s: Dictionary = DB.skills[id]
	var events: Events = game.events
	events.emit("log", {"text": "Your skill in %s rises to %d." % [s.name, rank(id)], "kind": "level"})
	var share: float = ladder().get("charXpShare", 0.0)
	if share > 0 and game.progression:
		game.progression.add_xp(int(round(DB.xp_for_next_level(rank(id)) * share)))
	if not perk_choices(id).is_empty():
		events.emit("log", {"text": "A new %s perk is yours to choose. Open Professions (U)." % s.name, "kind": "level"})
		if game.hud:
			game.hud.toast("%s perk ready" % s.name)
	if rank(id) >= cap(id):
		_tell_capped(id)


func _tell_capped(id: String) -> void:
	if capped_told.has(id):
		return
	capped_told[id] = true
	var nxt := next_rank(id)
	var s: Dictionary = DB.skills[id]
	var text := "Your %s has reached the %s's limit (%d)." % [s.name, rank_name(id), cap(id)]
	if not nxt.is_empty():
		text += " Find a trainer to become %s %s." % [U.article(nxt.name), nxt.name]
	game.events.emit("log", {"text": text, "kind": "level", "throttle": "cap-" + id})


## the next trainer rank for a skill: its `train` entry with the rank's
## `name` and `cap`, or {} at the top of what the world offers
func next_rank(id: String) -> Dictionary:
	if not laddered(id) or not has(id):
		return {}
	var rs: Array = ladder().ranks
	var t: int = tiers.get(id, 0) + 1
	if t >= rs.size():
		return {}
	for e in DB.skills[id].train:
		if e.rank == rs[t].id:
			var out: Dictionary = e.duplicate()
			out.name = rs[t].name
			out.cap = rs[t].cap
			return out
	return {}


## Why the next rank cannot be trained yet ("" when it can).
func rank_blocked(id: String) -> String:
	var e := next_rank(id)
	if e.is_empty():
		return "No higher rank to train yet"
	if rank(id) < int(e.get("level", 0)):
		return "Requires %s %d" % [DB.skills[id].name, e.level]
	if e.get("quest") and game.quests.status(e.quest) != "done":
		return "Requires %s" % DB.quests.get(e.quest, {}).get("name", e.quest)
	return ""


## Pay the trainer for the next rank; false (with a word why) if not.
func train_rank(id: String) -> bool:
	var e := next_rank(id)
	var events: Events = game.events
	var why := rank_blocked(id)
	if why != "":
		events.emit("log", {"text": "%s." % why, "kind": "muted", "throttle": "rank-block"})
		return false
	if game.inventory.coins < int(e.cost):
		events.emit("log", {"text": "You need %s to train as %s." % [U.money(e.cost), e.name], "kind": "muted", "throttle": "train-coins"})
		return false
	game.inventory.lose_coins(int(e.cost))
	tiers[id] = tiers.get(id, 0) + 1
	capped_told.erase(id)
	var s: Dictionary = DB.skills[id]
	events.emit("log", {"text": "You are now %s %s in %s. Your skill can rise to %d." % [U.article(e.name), e.name, s.name, cap(id)], "kind": "level"})
	if game.hud:
		game.hud.toast("%s %s" % [e.name, s.name])
	if game.reputation:
		game.reputation.add_renown(DB.renown.get("perProfessionRank", 10), "as word of your %s spreads" % s.name.to_lower())
	events.emit("skillsChanged", {"id": id})
	return true


## Perk levels reached with no choice made yet: [{ level, choices }]
func perk_choices(id: String) -> Array:
	var out := []
	for p in DB.skills.get(id, {}).get("perks", []):
		if rank(id) >= int(p.level) and not perks.get(id, {}).has(str(int(p.level))):
			out.append(p)
	return out


func choose_perk(id: String, level: int, perk: String) -> bool:
	for p in perk_choices(id):
		if int(p.level) == level and p.choices.any(func(c): return c.id == perk):
			if not perks.has(id):
				perks[id] = {}
			perks[id][str(level)] = perk
			var c: Dictionary = p.choices.filter(func(x): return x.id == perk)[0]
			game.events.emit("log", {"text": "%s perk: %s. %s" % [DB.skills[id].name, c.name, c.desc], "kind": "level"})
			game.events.emit("skillsChanged", {"id": id})
			return true
	return false


## the chosen perk at a level (its definition), or {}
func chosen_perk(id: String, level: int) -> Dictionary:
	var pid = perks.get(id, {}).get(str(level))
	for p in DB.skills.get(id, {}).get("perks", []):
		if int(p.level) == level:
			for c in p.choices:
				if c.id == pid:
					return c
	return {}


## the sum of an effect over a skill's chosen perks (0 if none)
func perk(id: String, key: String) -> float:
	var n := 0.0
	for level in perks.get(id, {}):
		n += float(chosen_perk(id, int(level)).get("effect", {}).get(key, 0.0))
	return n


func serialize_ladder() -> Dictionary:
	return {"xp": xp.duplicate(), "tiers": tiers.duplicate(), "perks": perks.duplicate(true)}


## After apply(): the ladder's state. An old save (ranks to 50, no tiers)
## keeps its skill up to the Apprentice's cap.
func apply_ladder(data) -> void:
	var d: Dictionary = data if typeof(data) == TYPE_DICTIONARY else {}
	var rs: Array = ladder().get("ranks", [])
	for id in ranks.keys():
		if not laddered(id):
			continue
		var t = d.get("tiers", {}).get(id)
		if typeof(t) == TYPE_INT or typeof(t) == TYPE_FLOAT:
			tiers[id] = clampi(int(t), 0, rs.size() - 1)
		else:
			tiers[id] = 0 if ranks[id] <= int(rs[0].cap) else 1
		ranks[id] = mini(ranks[id], cap(id))
		var x = d.get("xp", {}).get(id, 0)
		xp[id] = clampi(int(x), 0, xp_needed(ranks[id])) if typeof(x) == TYPE_INT or typeof(x) == TYPE_FLOAT else 0
		var p = d.get("perks", {}).get(id)
		if typeof(p) == TYPE_DICTIONARY:
			perks[id] = {}
			for level in p:
				if typeof(p[level]) == TYPE_STRING:
					perks[id][str(level)] = p[level]


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
			ranks[id] = mini(int(r), int(DB.skills[id].get("maxRank", 60 if DB.skills[id].has("train") else 1)))

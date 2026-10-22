class_name Titles
extends RefCounted
## Titles, Fable style (data/titles.json; src/systems/titles.js). You start
## a nobody, and townsfolk greet you with "Hello there." or "Hey you!".
## Once renown (and a title's own conditions) allows it, you may choose a
## title in the character window, and NPCs then call you by it, now and
## then mockingly.

var game
var chosen = null ## title id, or null for none
var slain := {} ## enemy types beaten at least once
var known := {} ## titles already announced as available


func _init(g) -> void:
	game = g
	reset()
	var ev: Events = game.events
	ev.on("enemyDefeated", func(e): _slay(e.enemy.type, e.enemy.cfg))
	ev.on("dummyBeaten", func(e): _slay(e.enemy.type, e.enemy.cfg))
	for e in ["skillsChanged", "reputationChanged", "lawChanged"]:
		ev.on(e, func(_e): _check_new())


func reset() -> void:
	chosen = null
	slain = {}
	known = {}


func _slay(type: String, cfg: Dictionary) -> void:
	if slain.has(type):
		return
	slain[type] = true
	if cfg.get("elite"):
		game.reputation.add_renown(DB.renown.firstEliteKill, "for felling the %s" % cfg.name)
	_check_new()


static func _standing_index(id) -> int:
	for i in DB.standings.size():
		if DB.standings[i].id == id:
			return i
	return -1


## Why a title cannot be chosen yet ('' when it can).
func locked_because(id: String) -> String:
	var t: Dictionary = DB.titles[id]
	var rep = game.reputation
	if rep.renown < t.get("renown", 0):
		return "Requires %s renown" % U.n(t.renown)
	for r in t.get("requires", []):
		if r.get("skill") and game.skills.rank(r.skill) < r.rank:
			return "Requires %s %s" % [DB.skills[r.skill].name, U.n(r.rank)]
		if r.get("slain") and not slain.has(r.slain):
			return "Defeat %s" % DB.enemies[r.slain].name
		if r.get("faction"):
			var need := _standing_index(r.standing)
			if _standing_index(rep.standing(r.faction).id) < need:
				return "Requires %s with %s" % [DB.standings[need].name, DB.factions[r.faction].name]
		if r.get("quest") and not game.quests.done.has(r.quest):
			return "Complete %s" % DB.quests[r.quest].name
		if r.get("level") and game.progression.level < r.level:
			return "Requires level %s" % U.n(r.level)
		if r.has("infamy") and game.law.infamy < r.infamy:
			return "Requires %s Infamy" % U.n(r.infamy)
		if r.has("crime") and not game.law.crimes.has(r.crime):
			return "Be seen %s" % Law.crime_def(r.crime).get("name", r.crime)
	return ""


func available(id) -> bool:
	return DB.titles.has(id) and locked_because(id) == ""


## every title in data order: { id, name, desc, locked, chosen }
var list: Array:
	get:
		var out := []
		for id in DB.titles:
			var t: Dictionary = DB.titles[id]
			out.append({"id": id, "name": t.name, "desc": t.get("desc", ""), "locked": locked_because(id), "chosen": chosen == id})
		return out

## the chosen title's name, or '' for none
var name: String:
	get:
		return DB.titles[chosen].name if chosen else ""


func choose(id) -> bool:
	if id and not available(id):
		return false
	chosen = id if id else null
	game.events.emit("log", {"text": "You are now known as %s." % name if id else "You go without a title.", "kind": "level"})
	game.events.emit("titlesChanged", {})
	return true


func _check_new() -> void:
	for id in DB.titles:
		if known.has(id) or not available(id):
			continue
		known[id] = true
		game.events.emit("log", {"text": "New title available: %s. Choose it in the character window (Titles)." % DB.titles[id].name, "kind": "level"})
		if game.hud:
			game.hud.toast("Title available: %s" % DB.titles[id].name)
		game.events.emit("titlesChanged", {})


## What an NPC calls out: kind 'greetings' or 'farewells'. Untitled folk get
## a plain line; a title is used, and sometimes mocked.
func address(kind: String) -> String:
	var lines: Dictionary = DB.title_lines[kind]
	var pick := func(l: Array): return l[int(floor(randf() * l.size())) % l.size()]
	if not chosen:
		return pick.call(lines.untitled)
	var t: Dictionary = DB.titles[chosen]
	var mock: bool = randf() < t.get("mock", DB.mock_chance)
	var line: String
	if not mock:
		line = pick.call(lines.titled)
	elif kind == "greetings" and not t.get("mocks", []).is_empty() and randf() < 0.5:
		line = pick.call(t.mocks)
	else:
		line = pick.call(lines.mocking)
	return line.replace("{title}", t.name)


func serialize() -> Dictionary:
	return {"chosen": chosen, "slain": slain.keys(), "known": known.keys()}


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data.get("slain", []):
		if DB.enemies.has(id):
			slain[id] = true
	for id in data.get("known", []):
		if DB.titles.has(id):
			known[id] = true
	var c = data.get("chosen")
	chosen = c if c and DB.titles.has(c) else null

class_name Reputation
extends RefCounted
## Reputation, WoW style (src/systems/reputation.js): points with each
## faction, earned from quests and from what the player does in a faction's
## area. Standings are named tiers; a faction's vendors give a discount from
## Friendly up. Renown (Fable style) is the standing that spans every
## faction: how known you are at all. Titles unlock from it.

var game
var points := {}
var renown := 0.0
var carry := 0.0 ## reputation earned toward the next point of renown


func _init(g) -> void:
	game = g
	reset()
	game.events.on("questComplete", func(_e): add_renown(DB.renown.perQuest, "for your deeds"))
	game.events.on("levelUp", func(_e): add_renown(DB.renown.perLevel, "as you grow in strength"))


func reset() -> void:
	points = {}
	renown = 0.0
	carry = 0.0


## how known you are: { id, name, desc, min, next, into, span }
var renown_tier: Dictionary:
	get:
		var tiers: Array = DB.renown.tiers
		var i := 0
		while i + 1 < tiers.size() and renown >= tiers[i + 1].min:
			i += 1
		var next = tiers[i + 1] if i + 1 < tiers.size() else null
		var t: Dictionary = tiers[i].duplicate()
		t.next = next.name if next else null
		t.into = renown - tiers[i].min
		t.span = next.min - tiers[i].min if next else 0
		return t


func add_renown(n: float, why := "") -> void:
	if not n:
		return
	var before = renown_tier.id
	renown += n
	game.events.emit("log", {"text": "Your renown grows by %s%s." % [U.n(n), " " + why if why != "" else ""], "kind": "rep"})
	var t := renown_tier
	if t.id != before:
		game.events.emit("log", {"text": "You are now %s. %s" % [t.name, t.desc], "kind": "level"})
		if game.hud:
			game.hud.toast("Renown: %s" % t.name)
	game.events.emit("reputationChanged", {"id": "renown"})


func get_points(id: String) -> float:
	return points.get(id, 0.0)


## the standing tier for a faction, plus progress through it
func standing(id: String) -> Dictionary:
	var tiers: Array = DB.standings
	var p := get_points(id)
	var i := 0
	while i + 1 < tiers.size() and p >= tiers[i + 1].min:
		i += 1
	var tier: Dictionary = tiers[i]
	var next = tiers[i + 1] if i + 1 < tiers.size() else null
	var out := tier.duplicate()
	out.points = p
	out.into = p - tier.min
	out.span = next.min - tier.min if next else 0
	out.next = next.name if next else null
	return out


## percent off at this faction's vendors
func discount(id) -> float:
	return standing(id).get("discount", 0) if id else 0.0


func add(id: String, n: float, quiet := false) -> void:
	var f = DB.factions.get(id)
	if f == null or not n:
		return
	var before = standing(id).id
	points[id] = get_points(id) + n
	if not quiet:
		game.events.emit("log", {"text": "Reputation with %s %s by %s." % [f.name, "increased" if n > 0 else "decreased", U.n(absf(n))], "kind": "rep"})
	# word spreads: reputation earned with anyone adds to renown
	if n > 0:
		carry += n
		var whole := floorf(carry / DB.renown.perReputation)
		carry -= whole * DB.renown.perReputation
		if whole:
			add_renown(whole, "as word of you spreads")
	var after := standing(id)
	if after.id != before:
		game.events.emit("log", {"text": "You are now %s with %s." % [after.name, f.name], "kind": "level"})
		game.hud.toast("%s: %s" % [f.name, after.name])
	game.events.emit("reputationChanged", {"id": id})


func add_all(map, quiet := false) -> void:
	if typeof(map) != TYPE_DICTIONARY:
		return
	for id in map:
		add(id, map[id], quiet)


func serialize() -> Dictionary:
	return points.duplicate()


func serialize_renown() -> Dictionary:
	return {"points": renown, "carry": carry}


func apply(data, ren) -> void:
	points = {}
	if typeof(data) == TYPE_DICTIONARY:
		for id in data:
			if DB.factions.has(id) and (typeof(data[id]) == TYPE_INT or typeof(data[id]) == TYPE_FLOAT) and is_finite(data[id]):
				points[id] = data[id]
	renown = ren.get("points", 0) if typeof(ren) == TYPE_DICTIONARY else 0.0
	carry = ren.get("carry", 0) if typeof(ren) == TYPE_DICTIONARY else 0.0

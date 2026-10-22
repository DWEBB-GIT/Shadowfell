class_name Progression
extends RefCounted
## Experience and levels (src/systems/progression.js).

var game
var level := 1
var xp := 0 ## experience towards the next level
var rested := 0.0 ## rested experience (built at a camp): kills pay double until it is spent
var last_gains = null ## { level, gains } from the last level-up


func _init(g) -> void:
	game = g


var xp_to_next: int:
	get:
		return DB.xp_for_next_level(level)


## `kill`: experience from a kill, which rested experience doubles.
func add_xp(amount: int, kill := false) -> void:
	var events = game.events
	var bonus := mini(int(floor(rested)), amount) if kill else 0
	rested = maxf(0, rested - bonus)
	# Inspired (boons.gd): a share more, on the base amount, beside rested
	var inspired := U.jround(amount * game.boons.xp_bonus / 100.0) if game.boons != null else 0
	amount += bonus + inspired
	xp += amount
	var extra := []
	if bonus:
		extra.append("%d rested bonus" % bonus)
	if inspired:
		extra.append("%d inspired" % inspired)
	events.emit("log", {"text": "+%d experience (%s)." % [amount, ", ".join(extra)] if not extra.is_empty() else "+%d experience." % amount, "kind": "xp"})
	while xp >= xp_to_next:
		var before: Dictionary = game.stats.snapshot()
		xp -= xp_to_next
		level += 1
		game.recompute_max_health()
		game.player.health = game.player.max_health
		var after: Dictionary = game.stats.snapshot()
		var gains := []
		for k in after:
			if after[k].v > before[k].v:
				gains.append({"id": k, "label": after[k].label, "from": before[k].get("text", U.n(before[k].v)), "to": after[k].get("text", U.n(after[k].v)), "diff": snappedf(after[k].v - before[k].v, 0.1)})
		last_gains = {"level": level, "gains": gains}
		events.emit("levelUp", {"level": level, "gains": gains})
		var parts := []
		for g in gains:
			parts.append("%s +%s" % [g.label, U.n(g.diff)])
		events.emit("log", {"text": "You feel steadier. Level %d: %s." % [level, ", ".join(parts)], "kind": "level"})
	events.emit("statsChanged")


func serialize() -> Dictionary:
	return {"level": level, "xp": xp, "rested": int(floor(rested))}


func apply(data: Dictionary) -> void:
	level = int(data.level)
	xp = int(data.xp)
	var r = data.get("rested", 0)
	rested = float(r) if (typeof(r) == TYPE_FLOAT or typeof(r) == TYPE_INT) and r > 0 else 0.0

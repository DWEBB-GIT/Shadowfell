class_name WorldState
extends RefCounted
## Persistent facts about the world, keyed by stable ids so a save written
## today still means the same thing after the layout is tweaked
## (src/systems/worldState.js). Sets are Dictionaries of id -> true.

var game
var defeated := {}
var collected := {}
var examined := {}
var drops := {} ## itemId -> { x, z } for loot dropped by enemies
var shrine_activated = null
var respawn = null ## { x, z } or null
var ground := [] ## items the player dropped: { uid, id, count, x, z }
var corpses := {} ## enemyId -> { x, z, coins } for bodies not yet looted
var next_ground_uid := 1
var flags := {} ## story facts, e.g. 'manifest_delivered'
var camp = null ## { x, z } of the camp, if one is pitched
var rest_point := "shrine" ## 'camp', 'shrine' or 'inn:<npc>'
var nemesis = null ## the enemy spawn id that last killed you
var time := 0.0 ## seconds of play in this world (respawn timers run on it)
var respawn_at := {} ## enemy spawn id -> world time it comes back


func _init(g) -> void:
	game = g
	reset()


func reset() -> void:
	defeated = {}
	collected = {}
	examined = {}
	drops = {}
	shrine_activated = null
	respawn = null
	ground = []
	corpses = {}
	next_ground_uid = 1
	flags = {}
	camp = null
	rest_point = "shrine"
	nemesis = null
	time = 0.0
	respawn_at = {}


func is_defeated(id: String) -> bool:
	return defeated.has(id)


func mark_defeated(id: String) -> void:
	defeated[id] = true


func is_collected(id: String) -> bool:
	return collected.has(id)


func mark_collected(id: String) -> void:
	collected[id] = true
	drops.erase(id)


func serialize() -> Dictionary:
	return {
		"defeated": defeated.keys(),
		"collected": collected.keys(),
		"examined": examined.keys(),
		"drops": drops.duplicate(true),
		"shrineActivated": shrine_activated,
		"respawn": respawn.duplicate() if respawn else null,
		"manifestCollected": collected.has("manifest"),
		"ground": ground.duplicate(true),
		"corpses": corpses.duplicate(true),
		"flags": flags.keys(),
		"camp": camp.duplicate() if camp else null,
		"restPoint": rest_point,
		"nemesis": nemesis,
		"time": U.jround(time),
		"respawnAt": respawn_at.duplicate(),
	}


static func _set_of(list) -> Dictionary:
	var out := {}
	for id in (list if list is Array else []):
		if typeof(id) == TYPE_STRING:
			out[id] = true
	return out


func apply(data: Dictionary) -> void:
	defeated = _set_of(data.get("defeated"))
	collected = _set_of(data.get("collected"))
	examined = _set_of(data.get("examined"))
	drops = data.get("drops", {}).duplicate(true)
	shrine_activated = data.get("shrineActivated")
	respawn = data.respawn.duplicate() if data.get("respawn") else null
	ground = []
	for g in data.get("ground", []):
		var c: Dictionary = g.duplicate(true)
		c.uid = int(c.uid)
		c.count = int(c.count)
		ground.append(c)
	corpses = data.get("corpses", {}).duplicate(true)
	next_ground_uid = 1
	for g in ground:
		next_ground_uid = maxi(next_ground_uid, g.uid + 1)
	flags = _set_of(data.get("flags"))
	camp = data.camp.duplicate() if data.get("camp") else null
	var rp = data.get("restPoint")
	rest_point = "camp" if rp == "camp" and camp else rp if typeof(rp) == TYPE_STRING and rp.begins_with("inn:") else "shrine"
	nemesis = data.get("nemesis") if typeof(data.get("nemesis")) == TYPE_STRING else null
	time = float(data.get("time", 0.0))
	respawn_at = {}
	var ra = data.get("respawnAt", {})
	if typeof(ra) == TYPE_DICTIONARY:
		for k in ra:
			respawn_at[k] = float(ra[k])

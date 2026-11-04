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
var ground := [] ## items on the ground: { uid, id, count, x, z }; id "coins" is a pile of `count` coins
var corpses := {} ## enemyId -> { x, z, coins } for bodies not yet looted
var next_ground_uid := 1
var flags := {} ## story facts, e.g. 'manifest_delivered'
var puzzles := {} ## mechanism id -> dial values / sequence progress / solved
var camp = null ## { x, z } of the camp, if one is pitched
var rest_point := "shrine" ## 'camp', 'shrine' or 'inn:<npc>'
var home := "" ## 'inn:<npc>' once an innkeeper keeps a bed for you (Return Home goes there)
var portal_ready := {} ## portal ability id -> world time it can be cast again
var nemesis = null ## the enemy spawn id that last killed you
var time := 0.0 ## seconds of play in this world (respawn timers run on it)
var respawn_at := {} ## enemy spawn id -> world time it comes back
var grave = null ## your belongings where you fell (grave.gd)
var discovered := {} ## POI ids (WorldMap.pois) the player has been to
## The world clock: the hour of the day (0 to 24) and which day it is. It is a
## fact about the shared world, not the player (a server would keep one for
## everyone); DayNight lights the world from it and townsfolk keep their
## routines by it (Npcs). CONFIG.clock sets how fast it runs.
var hour := 9.0
var day := 1


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
	puzzles = {}
	camp = null
	rest_point = "shrine"
	home = ""
	portal_ready = {}
	nemesis = null
	time = 0.0
	respawn_at = {}
	grave = null
	hour = float(DB.CONFIG.clock.startHour)
	day = 1


## run the clock on by `dt` seconds of play
func advance_clock(dt: float) -> void:
	hour += dt * 24.0 / (float(DB.CONFIG.clock.dayMinutes) * 60.0)
	while hour >= 24.0:
		hour -= 24.0
		day += 1


## jump the clock on to the next `h` o'clock (a night's sleep): today if it is
## still to come, else tomorrow
func skip_to(h: float) -> void:
	if h <= hour:
		day += 1
	hour = h


func is_defeated(id: String) -> bool:
	return defeated.has(id)


func mark_defeated(id: String) -> void:
	defeated[id] = true


func is_collected(id: String) -> bool:
	return collected.has(id)


func mark_collected(id: String) -> void:
	collected[id] = true
	drops.erase(id)


## Saves from the old 72 x 225 m map: places on it mean nothing in the big
## world, so the camp, drops, bodies and dropped items are let go.
func forget_places() -> void:
	camp = null
	respawn = null
	ground = []
	drops = {}
	corpses = {}
	if rest_point == "camp":
		rest_point = "shrine"


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
		"puzzles": puzzles.duplicate(true),
		"camp": camp.duplicate() if camp else null,
		"restPoint": rest_point,
		"home": home,
		"portalReady": portal_ready.duplicate(),
		"nemesis": nemesis,
		"time": U.jround(time),
		"respawnAt": respawn_at.duplicate(),
		"discovered": discovered.keys(),
		"grave": grave.duplicate(true) if grave != null else null,
		"clock": {"hour": snappedf(hour, 0.001), "day": day},
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
	puzzles = data.get("puzzles", {}).duplicate(true) if WorldPuzzles.valid_saved_states(data.get("puzzles", {})) else {}
	camp = data.camp.duplicate() if data.get("camp") else null
	var rp = data.get("restPoint")
	rest_point = "camp" if rp == "camp" and camp else rp if typeof(rp) == TYPE_STRING and rp.begins_with("inn:") else "shrine"
	# saves from before homes: an inn you rest at is your home too
	var h = data.get("home", rp)
	home = h if typeof(h) == TYPE_STRING and h.begins_with("inn:") else ""
	portal_ready = {}
	var pr = data.get("portalReady", {})
	if typeof(pr) == TYPE_DICTIONARY:
		for k in pr:
			portal_ready[k] = float(pr[k])
	nemesis = data.get("nemesis") if typeof(data.get("nemesis")) == TYPE_STRING else null
	time = float(data.get("time", 0.0))
	discovered = _set_of(data.get("discovered"))
	# saves from before the clock start the day at the usual hour
	var ck = data.get("clock")
	hour = float(DB.CONFIG.clock.startHour)
	day = 1
	if typeof(ck) == TYPE_DICTIONARY:
		hour = fposmod(float(ck.get("hour", hour)), 24.0)
		day = maxi(1, int(ck.get("day", 1)))
	var gv = data.get("grave")
	grave = null
	if typeof(gv) == TYPE_DICTIONARY and ["grave", "stolen", "dropped"].has(gv.get("phase")) and typeof(gv.get("items")) == TYPE_ARRAY:
		grave = gv.duplicate(true)
		grave.items = grave.items.filter(func(s): return SaveManager._is_stack(s))
		grave.coins = int(grave.get("coins", 0))
		grave.until = float(grave.get("until", 0))
		grave.x = float(grave.x)
		grave.z = float(grave.z)
		grave.scavengers = grave.get("scavengers", []).filter(func(s): return typeof(s) == TYPE_STRING)
	respawn_at = {}
	var ra = data.get("respawnAt", {})
	if typeof(ra) == TYPE_DICTIONARY:
		for k in ra:
			respawn_at[k] = float(ra[k])

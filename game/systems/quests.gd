class_name Quests
extends RefCounted
## Quests, WoW style (data/quests.json; src/systems/quests.js). A quest is
## offered by its giver once the quests it requires are done, accepted into
## the quest log, and handed in to its turn-in npc once every objective is
## met. Kills are counted per quest from the moment it is taken. Items are
## read from the bags and examine points from what has been looked at. A
## `talk` objective is met at once. Quests sharing a `choice` are one
## decision: once one of them is taken (or done) the others are locked.
##
## Status: 'done' | 'ready' | 'active' | 'available' | 'locked'.

const MAX_TRACKED := 4

var game
var accepted: Array = [] ## quest ids, in the order taken
var done := {}
var tracked := {}
var focus := "" ## the quest being followed: the minimap and world map point the way to it
var kills := {} ## questId -> { objectiveId: kills since it was taken }
var _last := {} ## questId -> progress text, to announce changes


## Conditions in dialogue and gate data: { quest, status } | { flag } | { examined } | { level } (at least).
static func condition_holds(g, when) -> bool:
	if when == null or (typeof(when) == TYPE_DICTIONARY and when.is_empty()):
		return true
	if when.get("quest"):
		var s: String = g.quests.status(when.quest)
		var status := s
		if s == "locked" or s == "available":
			status = "not_started" if when.get("status") == "not_started" else s
		if status != when.get("status"):
			return false
	if when.get("flag") and not g.world_state.flags.has(when.flag):
		return false
	if when.get("examined") and not g.world_state.examined.has(when.examined):
		return false
	if when.get("level") and g.progression.level < when.level:
		return false
	return true


func _init(g) -> void:
	game = g
	reset()
	for ev in ["inventoryChanged", "examined", "levelUp"]:
		game.events.on(ev, func(_e): refresh())
	game.events.on("enemyDefeated", func(e):
		count_kill(e.enemy.type)
		refresh())


func reset() -> void:
	accepted = []
	done = {}
	tracked = {}
	focus = ""
	kills = {}
	_last = {}


## An enemy of this type fell: every active quest that wants it counts one.
func count_kill(type: String) -> void:
	for id in active:
		for o in DB.quests[id].objectives:
			if o.type != "kill" or o.get("target") != type:
				continue
			if not kills.has(id):
				kills[id] = {}
			var k: Dictionary = kills[id]
			k[o.id] = mini(int(o.get("count", 1)), int(k.get(o.id, 0)) + 1)


## A brand-new game takes the opening quest (the intro sets it).
func start_new() -> void:
	reset()
	for q in DB.quests.values():
		if q.get("autoAccept") and status(q.id) == "available":
			accept(q.id, true)
	_snapshot()


# ------------------------------------------------------------ state
func status(id: String) -> String:
	var q = DB.quests.get(id)
	if q == null:
		return "locked"
	if done.has(id):
		return "done"
	if accepted.has(id):
		return "ready" if objectives(id).all(func(o): return o.done) else "active"
	if q.get("choice") and chosen(q.choice) != "":
		return "locked"
	for r in q.get("requires", []):
		if not done.has(r):
			return "locked"
	return "available"


## The quest taken (or done) for a choice, or "" while it is still open.
func chosen(choice: String) -> String:
	for id in accepted + done.keys():
		if DB.quests.get(id, {}).get("choice") == choice:
			return id
	return ""


## Each objective with how far along it is: { id, type, label, have, need, done, location }
func objectives(id: String) -> Array:
	var out := []
	for o in DB.quests[id].objectives:
		var need := int(o.get("count", 1))
		var have := 0
		match o.type:
			"kill":
				have = int(kills.get(id, {}).get(o.id, 0))
			"collect":
				have = game.inventory.count(o.target)
			"examine":
				have = 1 if game.world_state.examined.has(o.target) else 0
			"talk":
				have = need
		have = mini(have, need)
		out.append({"id": o.id, "type": o.type, "target": o.get("target", ""), "label": o.label, "have": have, "need": need, "done": have >= need, "location": o.get("location")})
	return out


## Does a quest the player has taken still need this item? (a quest drop
## only falls while it does)
func needs_item(id: String, item: String) -> bool:
	if status(id) != "active":
		return false
	var objs := objectives(id)
	for i in objs.size():
		var o: Dictionary = DB.quests[id].objectives[i]
		if not objs[i].done and o.type == "collect" and o.target == item:
			return true
	return false


## "Barrow Wolves slain: 2/3", or the bare label for one-off objectives
static func line(o: Dictionary) -> String:
	return "%s: %d/%d" % [o.label, o.have, o.need] if o.need > 1 or o.type == "kill" else o.label


var active: Array:
	get:
		return accepted.filter(func(id): return not done.has(id))


## The quests an npc has something to say about, best first: ready to hand
## in, then new ones to offer, then ones still in hand.
func for_npc(npc_id: String) -> Array:
	var out := []
	for q in DB.quests.values():
		var s := status(q.id)
		if (s == "ready" and q.get("turnIn") == npc_id) or (s == "available" and q.get("giver") == npc_id) or (s == "active" and q.get("turnIn") == npc_id):
			out.append({"id": q.id, "status": s})
	var order := {"ready": 0, "available": 1, "active": 2}
	out.sort_custom(func(a, b): return order[a.status] < order[b.status])
	return out


## What floats over an npc: 'ready' gold ?, 'available' gold !, 'active' grey ?.
func marker_for(npc_id: String) -> String:
	var list := for_npc(npc_id)
	return list[0].status if not list.is_empty() else ""


# ---------------------------------------------------------- actions
func accept(id: String, quiet := false) -> bool:
	if status(id) != "available":
		return false
	var q: Dictionary = DB.quests[id]
	accepted.append(id)
	kills.erase(id)
	if tracked.size() < MAX_TRACKED:
		tracked[id] = true
	_last[id] = _text(id)
	if not quiet:
		game.events.emit("log", {"text": "Quest accepted: %s." % q.name, "kind": "quest"})
		if game.hud:
			game.hud.toast("Quest accepted: %s" % q.name)
	game.events.emit("questAccepted", {"id": id})
	_changed()
	return true


func abandon(id: String) -> bool:
	var s := status(id)
	if s != "active" and s != "ready":
		return false
	if DB.quests[id].get("autoAccept"):
		return false # the story quest cannot be dropped
	accepted.erase(id)
	tracked.erase(id)
	if focus == id:
		focus = ""
	_last.erase(id)
	kills.erase(id)
	game.events.emit("log", {"text": "Quest abandoned: %s." % DB.quests[id].name, "kind": "muted"})
	_changed()
	return true


## Hand the quest in: take collected items, pay the reward. Returns false
## (and says why) if it cannot be done yet.
func complete(id: String) -> bool:
	var inventory = game.inventory
	var events: Events = game.events
	if status(id) != "ready":
		return false
	var q: Dictionary = DB.quests[id]
	var r: Dictionary = q.get("reward", {})
	var gifts: Array = r.get("items", [])
	for g in gifts:
		if inventory.room_for(g.item) < g.get("count", 1):
			events.emit("log", {"text": "Make room in your bags for the reward first.", "kind": "muted", "throttle": "quest-room"})
			return false
	for o in q.objectives:
		if o.type == "collect" and not o.get("keep"):
			inventory.remove_count(o.target, o.get("count", 1))
	done[id] = true
	tracked.erase(id)
	if focus == id:
		focus = ""
	_last.erase(id)
	kills.erase(id)
	if q.get("setsFlag"):
		game.world_state.flags[q.setsFlag] = true
	if q.get("turnInLog"):
		events.emit("log", {"text": q.turnInLog, "kind": "lore"})
	events.emit("log", {"text": "Quest complete: %s." % q.name, "kind": "quest"})
	var coins := U.roll_coins(r.get("coins"), game.random)
	if coins:
		inventory.add_coins(coins, "from %s" % DB.npcs[q.turnIn].name)
	for g in gifts:
		inventory.add_item(g.item, g.get("count", 1))
	if r.get("xp"):
		game.progression.add_xp(r.xp)
	if r.get("reputation"):
		game.reputation.add_all(r.reputation)
	# a dark choice is remembered (data/infamy.json)
	if r.get("infamy"):
		game.law.add_infamy(r.infamy, "for what you did")
	events.emit("questComplete", {"id": id})
	_changed()
	return true


func set_tracked(id: String, on: bool) -> bool:
	if not active.has(id):
		return false
	if on and tracked.size() >= MAX_TRACKED and not tracked.has(id):
		game.events.emit("log", {"text": "You can track up to %d quests." % MAX_TRACKED, "kind": "muted", "throttle": "track-max"})
		return false
	if on:
		tracked[id] = true
	else:
		tracked.erase(id)
		if focus == id:
			focus = ""
	_changed()
	return true


## Follow a quest (or stop, with ""): the minimap points the way to its
## next step whatever the distance. A followed quest is always tracked.
func set_focus(id: String) -> void:
	if id != "" and not active.has(id):
		return
	if id != "" and not tracked.has(id) and not set_tracked(id, true):
		return
	focus = id
	_changed()


# ------------------------------------------------- where and how hard
## Where a quest sends you next: the turn-in npc once it is ready, else the
## first unmet objective's place (its `location`, the nearest spawn of what
## it wants killed, or whom it wants spoken to). { x, z, r, label } or {}.
func goal(id: String) -> Dictionary:
	if status(id) == "ready":
		return npc_goal(DB.quests[id].turnIn)
	for o in objectives(id):
		if o.done:
			continue
		if o.location and DB.locations.has(o.location):
			var l: Dictionary = DB.locations[o.location]
			return {"x": l.position[0], "z": l.position[1], "r": l.get("radius", 0), "label": l.name}
		if o.type == "talk":
			return npc_goal(o.target)
		if o.type == "kill":
			var p: Vector3 = game.player.position if game.player else Vector3.ZERO
			var best := {}
			for e in Layout.enemies:
				if e.type != o.target or game.world_state.defeated.has(e.id):
					continue
				var d := U.hyp(e.position[0] - p.x, e.position[1] - p.z)
				if best.is_empty() or d < best.d:
					best = {"x": e.position[0], "z": e.position[1], "r": 0, "label": DB.enemies[o.target].name, "d": d}
			if not best.is_empty():
				return best
	return {}


## Where a townsperson is: where they stand now, else where they spawn.
func npc_goal(npc_id: String) -> Dictionary:
	var n = game.npcs.by_id(npc_id) if game.npcs else null
	if n != null:
		return {"x": n.position.x, "z": n.position.z, "r": 0, "label": n.name, "npc": npc_id}
	var at := Quests.npc_spot(npc_id)
	if at == Vector2.INF:
		return {}
	return {"x": at.x, "z": at.y, "r": 0, "label": DB.npcs.get(npc_id, {}).get("name", npc_id), "npc": npc_id}


static func npc_spot(npc_id: String) -> Vector2:
	for sp in DB.world.get("npcSpawns", []):
		if sp.npc == npc_id:
			return Vector2(sp.position[0], sp.position[1])
	return Vector2.INF


## "Mara Venn, Brackenford": who takes a quest in, and where to find them
## (the building they stand in, else the region).
static func hand_in(id: String) -> String:
	var npc_id: String = DB.quests[id].turnIn
	var who: String = DB.npcs.get(npc_id, {}).get("name", npc_id)
	var at := npc_spot(npc_id)
	if at == Vector2.INF:
		return who
	for b in DB.world.get("buildings", []):
		if absf(at.x - b.position[0]) <= b.size[0] / 2.0 and absf(at.y - b.position[1]) <= b.size[1] / 2.0:
			return "%s, %s" % [who, b.name]
	var place: String = DB.region_at(at.x, at.y).get("name", "")
	return "%s, %s" % [who, place] if place != "" else who


## The level range a quest suits: its `level` (a number or [min, max]) if
## set, else the levels of what its objectives send you to fight (or of the
## foes round the places they send you), else that of the quests it follows.
static func levels(id: String, _seen := {}) -> Vector2i:
	var q: Dictionary = DB.quests[id]
	var l = q.get("level")
	if l is Array and not l.is_empty():
		return Vector2i(int(l[0]), int(l[l.size() - 1]))
	if l is int or l is float:
		return Vector2i(int(l), int(l))
	var lo := 0
	var hi := 0
	for o in q.objectives:
		var found := []
		if o.type == "kill" and DB.enemies.has(o.get("target", "")):
			found.append(_enemy_level(o.target))
		elif o.get("location") and DB.locations.has(o.location):
			var loc: Dictionary = DB.locations[o.location]
			for e in Layout.enemies:
				var def: Dictionary = DB.enemies.get(e.type, {})
				# the hostile ones: not dummies, watchmen or livestock
				if not def.is_empty() and not def.get("dummy") and not def.get("lawful") \
						and U.hyp(e.position[0] - loc.position[0], e.position[1] - loc.position[1]) <= loc.get("radius", 0) + 15:
					found.append(_enemy_level(e.type))
		for v in found:
			lo = v if lo == 0 else mini(lo, v)
			hi = maxi(hi, v)
	if hi > 0:
		return Vector2i(lo, hi)
	_seen[id] = true
	for r in q.get("requires", []):
		if DB.quests.has(r) and not _seen.has(r):
			var v := levels(r, _seen)
			lo = v.x if lo == 0 else mini(lo, v.x)
			hi = maxi(hi, v.y)
	return Vector2i(lo, hi) if hi > 0 else Vector2i(1, 1)


## an enemy type's level (a level variant without one copies its `base`)
static func _enemy_level(type: String) -> int:
	var def: Dictionary = DB.enemies.get(type, {})
	while not def.has("level") and def.get("base") and DB.enemies.has(def.base) and def.base != type:
		type = def.base
		def = DB.enemies[type]
	return int(def.get("level", 1))


## WoW's quest colours for a level against yours: grey (too easy to be worth
## much), green, yellow (your level), orange, red (dangerous).
static func level_colour(level: int, player_level: int) -> Color:
	var d := level - player_level
	if d >= 5:
		return Color("ff4a3a")
	if d >= 3:
		return Color("ff9a40")
	if d >= -2:
		return Color("ffd23c")
	if d > -int(DB.CONFIG.progression.greyGap):
		return Color("5ec85e")
	return Color("9a9a9a")


## The zone a quest belongs to, for the quest log's groups: its `dungeon`
## (a dungeon's name) or `zone` (a region id) if set, else the region of
## the first place it sends you, else of whoever takes it in.
## { name, dungeon: bool }
static func zone(id: String) -> Dictionary:
	var q: Dictionary = DB.quests[id]
	if q.get("dungeon"):
		return {"name": str(q.dungeon), "dungeon": true}
	if q.get("zone"):
		var r := DB.region_by_id(q.zone)
		return {"name": r.get("name", str(q.zone)), "dungeon": false}
	var at := Vector2.INF
	for o in q.objectives:
		if o.get("location") and DB.locations.has(o.location):
			at = Vector2(DB.locations[o.location].position[0], DB.locations[o.location].position[1])
			break
	if at == Vector2.INF:
		at = npc_spot(q.turnIn)
	var place: String = DB.region_at(at.x, at.y).get("name", "") if at != Vector2.INF else ""
	return {"name": place if place != "" else "Elsewhere", "dungeon": false}


# ---------------------------------------------------- progress news
func _text(id: String) -> String:
	return " ".join(objectives(id).map(func(o): return "%d/%d" % [o.have, o.need]))


func _snapshot() -> void:
	_last = {}
	for id in active:
		_last[id] = _text(id)


## Called when anything a quest counts may have moved. Announces each
## objective that advanced, and a quest that has become ready.
func refresh() -> void:
	var changed := false
	for id in active:
		var now := _text(id)
		if now == _last.get(id):
			continue
		var before: PackedStringArray = str(_last.get(id, "")).split(" ")
		_last[id] = now
		changed = true
		var objs := objectives(id)
		for i in objs.size():
			var o: Dictionary = objs[i]
			var was := int(before[i].split("/")[0]) if i < before.size() and before[i] != "" else 0
			if o.have > was:
				game.events.emit("log", {"text": line(o) + (" (done)" if o.done else ""), "kind": "quest"})
		if objs.all(func(o): return o.done):
			var q: Dictionary = DB.quests[id]
			game.events.emit("log", {"text": "%s: complete. Return to %s." % [q.name, DB.npcs[q.turnIn].name], "kind": "quest"})
			if game.hud:
				game.hud.toast("%s: complete" % q.name)
	if changed:
		_changed()


func _changed() -> void:
	game.events.emit("questsChanged", {})
	game.events.emit("objectiveChanged", {})


# ------------------------------------------------------------- save
func serialize() -> Dictionary:
	return {"accepted": accepted.duplicate(), "done": done.keys(), "tracked": tracked.keys(), "focus": focus, "kills": kills.duplicate(true)}


## Saves from before the quest log carry only the story flag.
func apply(data, flags: Dictionary) -> void:
	reset()
	if typeof(data) == TYPE_DICTIONARY:
		for id in data.get("done", []):
			if DB.quests.has(id):
				done[id] = true
		for id in data.get("accepted", []):
			if DB.quests.has(id) and not done.has(id):
				accepted.append(id)
		for id in data.get("tracked", []):
			if accepted.has(id):
				tracked[id] = true
		if tracked.has(str(data.get("focus", ""))):
			focus = data.focus
		# kill counts; a save from before them counts the bodies still down
		var type_of := {}
		for e in Layout.enemies:
			type_of[e.id] = e.type
		var fallen: Array = game.world_state.defeated.keys().map(func(s): return type_of.get(s))
		for id in accepted:
			var saved
			if data.has("kills"):
				saved = data.kills.get(id)
			else:
				saved = {}
				for o in DB.quests[id].objectives:
					saved[o.id] = fallen.count(o.get("target"))
			if typeof(saved) != TYPE_DICTIONARY:
				continue
			for o in DB.quests[id].objectives:
				var n = saved.get(o.id)
				if o.type == "kill" and (typeof(n) == TYPE_INT or typeof(n) == TYPE_FLOAT) and n == floor(n) and n > 0:
					if not kills.has(id):
						kills[id] = {}
					kills[id][o.id] = mini(int(n), int(o.get("count", 1)))
	elif flags.has("manifest_delivered"):
		done["missing_delivery"] = true
	else:
		accepted.append("missing_delivery")
		tracked["missing_delivery"] = true
	_snapshot()
	_changed()

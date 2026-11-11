class_name Interaction
extends RefCounted
## Finds the nearest thing the player can act on and runs it when E is
## pressed (src/systems/interaction.js). The HUD shows `current.prompt`.

var game
var current = null
## how far to look for fixed points: Space reaches a few metres (a station's
## radius at most); a click reaches what is on screen
const REACH_NEAR := 12.0
const CLICK_NEAR := 70.0
## how a station shows itself (Dan, 2026-11-03: tell the rune forge from the
## refining altar without clicking): the cursor over it, its colour on the
## minimap and over it in the world, and the minimap letter
const STATION_LOOK := {
	"forge": {"cursor": "anvil", "colour": "#d0d6e0", "letter": "F"},
	"runeforge": {"cursor": "runeAnvil", "colour": "#b08cff", "letter": "R"},
	"refining": {"cursor": "gem", "colour": "#ffd060", "letter": "A"},
	"fire": {"cursor": "pot", "colour": "#ff9a50", "letter": "H"},
	"workbench": {"cursor": "loot", "colour": "#c89a60", "letter": "W"},
	"alchemy": {"cursor": "flask", "colour": "#8fe08a", "letter": "B"},
}


static func look(kind: String) -> Dictionary:
	return STATION_LOOK.get(kind, {"cursor": "loot", "colour": "#e8d8a0", "letter": "?"})


## "the rune forge" -> "The rune forge", for tooltips and labels
static func title(text: String) -> String:
	return text.substr(0, 1).to_upper() + text.substr(1) if text != "" else ""


func _init(g) -> void:
	game = g


## Everything further than `near` metres (along x or z) is left out: there
## are hundreds of points across the world, and building them all, with
## each lootable's area count, twice a frame cost ~6 ms.
## `fixed` keeps only the points that never move (shrines, the grave,
## stations, puzzles, things to examine): all a click needs (click_points).
func _candidates(near := INF, fixed := false) -> Array:
	var loot = game.loot
	var list := []
	var pp: Vector3 = game.player.position
	var far := func(x: float, z: float) -> bool: return absf(x - pp.x) > near or absf(z - pp.z) > near
	if fixed:
		list.append_array(game.grave.interactions())
		_fixed_points(list, far)
		list.append_array(game.puzzles.interactions())
		_examine_points(list, far)
		return list
	# bodies and loot: using one loots everything close by
	var lootables: Array = loot.lootables()
	for l in lootables:
		if far.call(l.x, l.z):
			continue
		var n: int = loot.area_count(l, lootables)
		var own: String = "Loot the %s" % l.name if l.kind == "corpse" else l.entry.def.prompt
		list.append({"key": "loot:" + l.id, "x": l.x, "z": l.z, "bias": -0.4, "loot": l, "prompt": "%s (and %d more nearby)" % [own, n - 1] if n > 1 else own, "run": func(): loot.loot_area(l)})
	# a beast's empty body, for a skinner
	for s in loot.skinnables():
		var why: String = loot.skin_block(s)
		list.append({"key": "skin:" + s.id, "x": s.x, "z": s.z, "bias": -0.3, "prompt": "Skin the %s%s" % [s.name, " (%s)" % why if why != "" else ""], "run": func(): loot.start_skin(s)})
	list.append_array(game.npcs.interactions(near))
	list.append_array(game.chests.interactions())
	list.append_array(game.grave.interactions())
	_fixed_points(list, far)
	# a glinting ore vein, for a miner
	list.append_array(game.mining.interactions(near))
	list.append_array(game.gathering.interactions(near))
	list.append_array(game.discovery.interactions())
	list.append_array(game.puzzles.interactions())
	for sp in Layout.signposts:
		if far.call(sp.position[0], sp.position[1]):
			continue
		list.append({"key": "sign:" + sp.id, "x": sp.position[0], "z": sp.position[1], "bias": 0.3, "reach": 2.6, "prompt": "Read the signpost", "run": func(): game.hud.show_signpost(sp)})
	_examine_points(list, far)
	return list


## shrines and crafting stations
func _fixed_points(list: Array, far: Callable) -> void:
	var from := list.size()
	for sh in Layout.shrines:
		if far.call(sh.position[0], sh.position[1]):
			continue
		list.append({"key": "shrine" if sh.id == "shrine_road" else "shrine:" + sh.id, "x": sh.position[0], "z": sh.position[1], "bias": 0.0, "reach": 2.6, "prompt": "Rest at the shrine", "name": "Shrine", "run": func(): game.rest_at_shrine(sh)})
	# a hearth prompts Cooking, a forge Smithing, a workbench Woodcraft, an alchemy bench Alchemy
	# (the skill whose `craft.kind` is the station's kind); without the
	# skill the prompt still shows and says where to learn it
	for st in Layout.stations:
		if far.call(st.position[0], st.position[1]):
			continue
		# the rune forge: its own window, no skill needed (Dan, 2026-11-03)
		if st.kind == RuneForge.KIND:
			list.append({"key": "station:" + st.id, "x": st.position[0], "z": st.position[1], "bias": 0.3, "reach": st.radius,
				"prompt": "Use %s" % st.name, "run": func(): game.rune_forge.open_at(st)})
			continue
		# a waystone (`to`: [x, z]): step through to the other stone
		if st.kind == "waystone":
			list.append({"key": "station:" + st.id, "x": st.position[0], "z": st.position[1], "bias": 0.3, "reach": st.radius,
				"prompt": "Travel to %s" % st.get("toName", "the other stone"), "name": title(st.name),
				"run": func():
					if not game.travel_to(st.to[0], st.to[1], st.get("toFacing"), "Travelling to %s…" % st.get("toName", "the other stone")):
						game.hud.error("You can't travel while fighting.")})
			continue
		if st.kind == Refinery.KIND:
			list.append({"key": "station:" + st.id, "x": st.position[0], "z": st.position[1], "bias": 0.3, "reach": st.radius,
				"prompt": "Refine gear at %s" % st.name, "run": func(): game.refinery.open_at(st)})
			continue
		var sk := ""
		for s in DB.skills.values():
			if s.get("craft", {}).get("kind") == st.kind:
				sk = s.id
		if sk == "":
			continue
		var verb: String = DB.skills[sk].craft.get("button", "Use")
		var win: String = "craft:" + sk
		var known: bool = game.skills.has(sk)
		var skill_name: String = DB.skills.get(sk, {}).get("name", sk.capitalize())
		list.append({"key": "station:" + st.id, "x": st.position[0], "z": st.position[1], "bias": 0.3, "reach": st.radius,
			"prompt": "%s at %s" % [verb, st.name] if known else "%s at %s (learn %s first)" % [verb, st.name, skill_name],
			"run": func():
				if game.skills.has(sk):
					game.hud.show_window(win)
				else:
					game.hud.error("You need to learn %s from a trainer first." % skill_name)})
	# each station's name and cursor, for the hover tooltip (game.gd)
	for i in range(from, list.size()):
		var c = list[i]
		if c.key.begins_with("station:") and not c.has("name"):
			var st = Layout.station(c.key.substr(8))
			if st != null:
				c.name = title(st.name)
				c.cursor = look(st.kind).cursor


func _examine_points(list: Array, far: Callable) -> void:
	for p in game.world.examine_points:
		if far.call(p.x, p.z):
			continue
		var seen: bool = game.world_state.examined.has(p.id)
		var c := {"key": "examine:" + p.id, "x": p.x, "z": p.z, "bias": 0.6 if seen else 0.2, "prompt": "Examine the cart" if p.id == "cart" else "Look around %s" % WorldMap.poi(p.id.substr(4)).get("name", "") if p.id.begins_with("poi:") else "Examine", "run": func(): examine(p.id)}
		if p.id == "watch_post":
			c.reach = 3.2
		list.append(c)


## What Space reaches that has no clickable body of its own (shrines,
## hearths, forges, things to examine; a ghost's body and rest point), so a
## mouse click reaches it too (game.gd).
func click_points() -> Array:
	if game.player.ghost:
		return game.afterlife.interactions()
	if game.player.dead:
		return []
	# the cursor asks every frame; these points stand still, so a list a
	# quarter second old is as good (it cost ~2 ms a frame)
	var now := Time.get_ticks_msec()
	if now - _click_at > CLICK_CACHE_MS:
		_click_at = now
		_click_cache = _candidates(CLICK_NEAR, true).filter(func(c): return c.key.begins_with("shrine") or c.key == "grave" or c.key.begins_with("station:") or c.key.begins_with("examine:") or c.key.begins_with("puzzle:"))
	return _click_cache


const CLICK_CACHE_MS := 250
var _click_at := -100000
var _click_cache: Array = []


const EXAMINE_REPEAT_MS := 10000
var _examined_at := {}


func examine(id: String) -> void:
	# the same thing again soon after says nothing new: one line, not a
	# chat box full of it (Dan, 2026-10-27)
	var now := Time.get_ticks_msec()
	if now - int(_examined_at.get(id, -EXAMINE_REPEAT_MS)) < EXAMINE_REPEAT_MS:
		return
	_examined_at[id] = now
	var ws = game.world_state
	var first: bool = not ws.examined.has(id)
	ws.examined[id] = true
	game.events.emit("log", {"text": DB.examine_text(id), "kind": "lore"})
	if first:
		game.events.emit("examined", {"id": id})


## The prompt is looked for ten times a second (`force` now, as a key press
## does): building every nearby point each frame was a millisecond or two.
func update(force := false) -> void:
	var now := Time.get_ticks_msec()
	if not force and now - _update_at < UPDATE_MS:
		return
	_update_at = now
	var player = game.player
	if player.dead and not player.ghost:
		current = null
		return
	var best = null
	var best_score := INF
	for c in (game.afterlife.interactions() if player.ghost else _candidates(REACH_NEAR)):
		var d := U.hyp(c.x - player.position.x, c.z - player.position.z)
		if d > c.get("reach", DB.CONFIG.interaction.radius):
			continue
		# nothing through a wall
		if game.collision.wall_between(player.position.x, player.position.z, c.x, c.z):
			continue
		var score: float = d + c.bias
		if score < best_score:
			best_score = score
			best = c
	current = best


const UPDATE_MS := 100
var _update_at := -100000


func interact() -> bool:
	update(true) # use the player's position this frame, not last frame's
	if current == null:
		return false
	current.run.call()
	update()
	return true

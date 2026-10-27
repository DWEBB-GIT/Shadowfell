class_name Interaction
extends RefCounted
## Finds the nearest thing the player can act on and runs it when E is
## pressed (src/systems/interaction.js). The HUD shows `current.prompt`.

var game
var current = null


func _init(g) -> void:
	game = g


func _candidates() -> Array:
	var loot = game.loot
	var list := []
	# bodies and loot: using one loots everything close by
	for l in loot.lootables():
		var n: int = loot.area_count(l)
		var own: String = "Loot the %s" % l.name if l.kind == "corpse" else l.entry.def.prompt
		list.append({"key": "loot:" + l.id, "x": l.x, "z": l.z, "bias": -0.4, "loot": l, "prompt": "%s (and %d more nearby)" % [own, n - 1] if n > 1 else own, "run": func(): loot.loot_area(l)})
	# a beast's empty body, for a skinner
	for s in loot.skinnables():
		var why: String = loot.skin_block(s)
		list.append({"key": "skin:" + s.id, "x": s.x, "z": s.z, "bias": -0.3, "prompt": "Skin the %s%s" % [s.name, " (%s)" % why if why != "" else ""], "run": func(): loot.start_skin(s)})
	list.append_array(game.npcs.interactions())
	list.append_array(game.chests.interactions())
	for sh in Layout.shrines:
		list.append({"key": "shrine" if sh.id == "shrine_road" else "shrine:" + sh.id, "x": sh.position[0], "z": sh.position[1], "bias": 0.0, "reach": 2.6, "prompt": "Rest at the shrine", "run": func(): game.rest_at_shrine(sh)})
	# a hearth prompts Cooking, a forge Smelting, an alchemy bench Alchemy
	# (the skill whose `craft.kind` is the station's kind); without the
	# skill the prompt still shows and says where to learn it
	for st in Layout.stations:
		var sk := ""
		for s in DB.skills.values():
			if s.get("craft", {}).get("kind") == st.kind:
				sk = s.id
		if sk == "":
			continue
		var verb: String = DB.skills[sk].craft.get("button", "Use")
		var win: String = "smelting" if sk == "mining" else "craft:" + sk
		var known: bool = game.skills.has(sk)
		var skill_name: String = DB.skills.get(sk, {}).get("name", sk.capitalize())
		list.append({"key": "station:" + st.id, "x": st.position[0], "z": st.position[1], "bias": 0.3, "reach": st.radius,
			"prompt": "%s at %s" % [verb, st.name] if known else "%s at %s (learn %s first)" % [verb, st.name, skill_name],
			"run": func():
				if game.skills.has(sk):
					game.hud.show_window(win)
				else:
					game.hud.error("You need to learn %s from a trainer first." % skill_name)})
	# a glinting ore vein, for a miner
	list.append_array(game.mining.interactions())
	list.append_array(game.gathering.interactions())
	list.append_array(game.discovery.interactions())
	for sp in Layout.signposts:
		list.append({"key": "sign:" + sp.id, "x": sp.position[0], "z": sp.position[1], "bias": 0.3, "reach": 2.6, "prompt": "Read the signpost", "run": func(): game.hud.show_signpost(sp)})
	for p in game.world.examine_points:
		var seen: bool = game.world_state.examined.has(p.id)
		var c := {"key": "examine:" + p.id, "x": p.x, "z": p.z, "bias": 0.6 if seen else 0.2, "prompt": "Examine the cart" if p.id == "cart" else "Look around %s" % WorldMap.poi(p.id.substr(4)).get("name", "") if p.id.begins_with("poi:") else "Examine", "run": func(): examine(p.id)}
		if p.id == "watch_post":
			c.reach = 3.2
		list.append(c)
	return list


## What Space reaches that has no clickable body of its own (shrines,
## hearths, forges, things to examine; a ghost's body and rest point), so a
## mouse click reaches it too (game.gd).
func click_points() -> Array:
	if game.player.ghost:
		return game.afterlife.interactions()
	if game.player.dead:
		return []
	return _candidates().filter(func(c): return c.key.begins_with("shrine") or c.key.begins_with("station:") or c.key.begins_with("examine:"))


func examine(id: String) -> void:
	var ws = game.world_state
	var first: bool = not ws.examined.has(id)
	ws.examined[id] = true
	game.events.emit("log", {"text": DB.examine_text(id), "kind": "lore"})
	if first:
		game.events.emit("examined", {"id": id})


func update() -> void:
	var player = game.player
	if player.dead and not player.ghost:
		current = null
		return
	var best = null
	var best_score := INF
	for c in (game.afterlife.interactions() if player.ghost else _candidates()):
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


func interact() -> bool:
	update() # use the player's position this frame, not last frame's
	if current == null:
		return false
	current.run.call()
	update()
	return true

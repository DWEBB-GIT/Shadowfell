class_name Dialogue
extends RefCounted
## Talking to townsfolk, in the WoW gossip style (src/systems/dialogue.js):
## a greeting with its choices grouped and marked by kind: quests, things to
## ask, then services (the shop, the trainer, the inn) and Goodbye. A quest
## opens its own page. Topics open small dialogue trees from
## data/dialogue.json. Training opens the trainer window (view 'train').
##
## This system owns where the conversation is; the HUD shows it and passes
## choices back. Walking away ends it, as with a shop.

var game
var npc = null ## the Npc spoken to
var view = null ## { kind: 'menu' } | { kind: 'node', id } | { kind: 'quest', id } | { kind: 'train' }
var salutation := ""


func _init(g) -> void:
	game = g


var is_open: bool:
	get:
		return npc != null


func open(n) -> void:
	game.merchant.close()
	npc = n
	view = {"kind": "menu"}
	# how they hail you: "Hey you!" while you are nobody, your title once you
	# have chosen one (the notice board says nothing)
	salutation = "" if DB.npcs[n.id].get("board") else game.titles.address("greetings")
	game.events.emit("dialogueChanged", {})


func close() -> bool:
	if npc == null:
		return false
	npc = null
	view = null
	game.events.emit("dialogueChanged", {})
	return true


func back() -> bool:
	if npc == null:
		return false
	if view.kind == "menu":
		return close()
	view = {"kind": "menu"}
	game.events.emit("dialogueChanged", {})
	return true


func update() -> void:
	if npc == null:
		return
	var p: Vector3 = game.player.position
	if game.player.dead or U.hyp(p.x - npc.position.x, p.z - npc.position.z) > DB.CONFIG.shop.leaveRange:
		close()


var _data:
	get:
		var id = DB.npcs[npc.id].get("dialogue") if npc != null else null
		return DB.dialogues.get(id) if id else null


## Everything this person teaches, for the trainer window:
## [{ id: 'train:x' | 'recipe:y', name, kind, need, cost, state }],
## state 'learn' | 'known' | 'locked' | 'poor'.
func train_rows(npc_id = null) -> Array:
	if npc_id == null:
		npc_id = npc.id if npc != null else ""
	var skills = game.skills
	var cooking = game.cooking
	var coins: int = game.inventory.coins
	var rows := []
	for s in DB.skills.values():
		if s.get("trainer") != npc_id:
			continue
		var known: bool = skills.has(s.id)
		var teaches: Array = s.get("teaches", [])
		rows.append({"id": "train:" + s.id, "name": s.name, "kind": "Skill", "ability": teaches[0] if not teaches.is_empty() else null, "desc": s.get("desc", ""), "need": "" if known else "Teaches a new skill", "cost": s.cost, "state": "known" if known else "poor" if coins < s.cost else "learn"})
	# class spells this trainer teaches the character's class
	for t in game.stats.archetype.get("trained", []):
		if t.get("trainer") != npc_id or not DB.abilities.has(t.get("ability")):
			continue
		var a: Dictionary = DB.abilities[t.ability]
		var known: bool = skills.spells.has(t.ability)
		var lvl := int(t.get("level", 1))
		var cost := int(t.get("cost", 0))
		var low: bool = game.progression.level < lvl
		rows.append({"id": "spell:" + t.ability, "name": a.name, "kind": "%s spell" % game.stats.archetype.name, "ability": t.ability, "desc": a.get("desc", ""), "need": "Requires level %d" % lvl if low else "Level %d" % lvl, "cost": cost, "state": "known" if known else "locked" if low else "poor" if coins < cost else "learn"})
	for r in DB.recipes.values():
		if r.get("trainer") != npc_id:
			continue
		var skill: Dictionary = DB.skills[r.skill]
		var known: bool = cooking.learned.has(r.id)
		var locked := ""
		if not skills.has(r.skill):
			locked = "Requires %s" % skill.name
		elif cooking.rank(r.skill) < r.rank:
			locked = "Requires %s %d" % [skill.name, r.rank]
		rows.append({"id": "recipe:" + r.id, "name": Items.get_def(r.output.item).name, "kind": "%s recipe" % skill.name, "item": r.output.item, "need": locked if locked != "" else "%s %d" % [skill.name, r.rank], "cost": r.cost, "state": "known" if known else "locked" if locked != "" else "poor" if coins < r.cost else "learn"})
	return rows


## What the window shows now: { name, title, text, quest?, options: [{ id, text, icon, group }] }
var page:
	get:
		if npc == null:
			return null
		var def: Dictionary = DB.npcs[npc.id]
		var pg := {"name": def.name, "title": def.get("title", ""), "text": "", "options": []}
		var v: Dictionary = view
		var d = _data
		match v.kind:
			"menu":
				var greet: Array = d.greetings.filter(func(g): return Quests.condition_holds(game, g.get("when"))) if d else []
				pg.text = greet[-1].text if not greet.is_empty() else ""
				pg.salutation = salutation
				for q in game.quests.for_npc(npc.id):
					pg.options.append({"id": "quest:" + q.id, "text": DB.quests[q.id].name, "icon": q.status, "group": "quest"})
				for t in (d.get("topics", []) if d else []):
					if Quests.condition_holds(game, t.get("when")):
						pg.options.append({"id": "node:" + t.node, "text": t.prompt, "icon": "talk", "group": "talk"})
				if def.get("shop"):
					pg.options.append({"id": "shop", "text": "Browse goods", "icon": "shop", "group": "service"})
				# a trainer: one way in to the trainer window, saying what is new
				var rows := train_rows()
				if not rows.is_empty():
					var n := rows.filter(func(r): return r.state == "learn" or r.state == "poor").size()
					pg.options.append({"id": "train", "text": "Train (%d to learn)" % n if n else "Train", "icon": "train", "group": "service"})
				if DB.builds.get("forge", {}).get("npc") == npc.id and not _power_items().is_empty():
					pg.options.append({"id": "forge", "text": "Move a legendary power", "icon": "shop", "group": "service"})
				if def.get("innkeeper") and game.world_state.rest_point != "inn:" + npc.id:
					pg.options.append({"id": "home", "text": "Make this inn your home", "icon": "home", "group": "service"})
				pg.options.append({"id": "bye", "text": "Goodbye", "icon": "bye", "group": "bye"})
			"train":
				pg.train = train_rows()
				pg.text = "What would you learn?" if pg.train.any(func(r): return r.state == "learn") else "There is nothing more I can teach you just now."
				for r in pg.train:
					pg.options.append({"id": r.id, "text": r.name, "icon": "train", "disabled": r.state != "learn"})
				pg.options.append({"id": "menu", "text": "Back", "icon": "back"})
			"forge":
				pg.text = "Bring me the piece with the power in it. I melt it down, and the power goes into another piece that sits in the same place on you. %s a time." % U.money(_forge_price())
				for loc in _power_items():
					var st = game.inventory.get_at(loc)
					pg.options.append({"id": "forge:" + loc, "text": "%s (%s)" % [Items.view(st).name, Builds.power_def(Items.power_of(st)).name], "icon": "talk"})
				pg.options.append({"id": "menu", "text": "Back", "icon": "back"})
			"forgeOnto":
				var src = game.inventory.get_at(v.src)
				pg.text = "%s goes into which piece? The %s is lost in the fire." % [Builds.power_def(Items.power_of(src)).name, Items.view(src).name] if src else ""
				for loc in _forge_targets(v.src):
					var st = game.inventory.get_at(loc)
					pg.options.append({"id": "imprint:" + loc, "text": "%s (%s)" % [Items.view(st).name, U.money(_forge_price())], "icon": "accept", "disabled": game.inventory.coins < _forge_price()})
				if pg.options.is_empty():
					pg.text = "You have nothing else that goes there. Bring me a piece for that place and I'll do it."
				pg.options.append({"id": "forge", "text": "Back", "icon": "back"})
			"node":
				var node = null
				for n in d.nodes:
					if n.id == v.id:
						node = n
				pg.text = node.text
				for r in node.replies:
					pg.options.append({"id": "node:" + r.node if r.get("node") else "menu", "text": r.text, "icon": "talk"})
			"quest":
				var q: Dictionary = DB.quests[v.id]
				var status: String = game.quests.status(v.id)
				pg.quest = {"id": q.id, "name": q.name, "status": status, "objectives": game.quests.objectives(q.id), "reward": q.get("reward", {}), "choice": q.has("choice")}
				if status == "available":
					pg.text = q.offer
					pg.options.append_array([{"id": "accept", "text": "Accept", "icon": "accept"}, {"id": "menu", "text": "Decline", "icon": "back"}])
				elif status == "ready":
					pg.text = q.complete
					pg.options.append_array([{"id": "complete", "text": "Complete quest", "icon": "accept"}, {"id": "menu", "text": "Back", "icon": "back"}])
				else:
					pg.text = q.get("progress", "")
					pg.options.append({"id": "menu", "text": "Back", "icon": "back"})
		return pg


# ------------------------------------------------------------ the forge
## Mara moves a legendary power (data/builds.json `forge`): the item that
## carries it is melted down, and the power goes onto another piece for the
## same place (any weapon for a weapon).

func _forge_price() -> int:
	return int(DB.builds.get("forge", {}).get("price", 50))


## Where you carry or wear something with a power: bag and equipment locations
func _power_items() -> Array:
	var inv = game.inventory
	var out := []
	for loc in inv.bag_locations() + inv.equipment.keys().map(func(k): return "e:" + k):
		var st = inv.get_at(loc)
		if st != null and Items.power_of(st) != "":
			out.append(loc)
	return out


static func _place_of(def: Dictionary) -> String:
	if def.get("kind") == "weapon" and def.get("slot") in ["mainHand", "oneHand"]:
		return "weapon"
	return def.get("slot", "")


## What the power at `src` could go onto
func _forge_targets(src: String) -> Array:
	var inv = game.inventory
	var from = inv.get_at(src)
	if from == null:
		return []
	var place := _place_of(Items.get_def(from.id))
	var out := []
	for loc in inv.bag_locations() + inv.equipment.keys().map(func(k): return "e:" + k):
		var st = inv.get_at(loc)
		if loc == src or st == null:
			continue
		var d := Items.get_def(st.id)
		if Items.ROLLED_KINDS.has(d.get("kind")) and _place_of(d) == place and Items.power_of(st) == "":
			out.append(loc)
	return out


func _imprint(src: String, dst: String) -> bool:
	var inv = game.inventory
	if not _forge_targets(src).has(dst):
		return false
	if inv.coins < _forge_price():
		game.hud.error("You cannot afford that")
		return false
	var from = inv.get_at(src)
	var power := Items.power_of(from)
	var name_was: String = Items.view(from).name
	inv.lose_coins(_forge_price())
	inv.take(src)
	var to = inv.get_at(dst)
	var rolls: Dictionary = to.get("rolls", {}) if typeof(to.get("rolls")) == TYPE_DICTIONARY else {}
	rolls = rolls.duplicate()
	rolls.power = power
	to.rolls = rolls
	if dst.begins_with("e:"):
		inv._equipment_changed()
	inv._changed()
	game.events.emit("anvilStrike", {"x": npc.position.x, "z": npc.position.z})
	game.events.emit("log", {"text": "Mara melts down the %s. %s now carries %s." % [name_was, Items.view(to).name, Builds.power_def(power).name], "kind": "level"})
	game.events.emit("buildChanged", {})
	return true


## Act on an option id from `page.options`.
func choose(id: String) -> bool:
	if npc == null:
		return false
	var events: Events = game.events
	var v: Dictionary = view
	var def: Dictionary = DB.npcs[npc.id]
	if id == "bye":
		if not def.get("board"):
			events.emit("log", {"text": '%s: "%s"' % [def.name, game.titles.address("farewells")], "kind": "say"})
		return close()
	if id == "menu":
		view = {"kind": "menu"}
	elif id == "train":
		view = {"kind": "train"}
	elif id == "shop":
		var n = npc
		close()
		game.merchant.open(def.shop, n)
		return true
	elif id.begins_with("train:"):
		if not game.skills.learn(id.substr(6)):
			return false
	elif id.begins_with("recipe:"):
		if not game.cooking.learn_recipe(id.substr(7)):
			return false
	elif id.begins_with("spell:"):
		if not game.skills.learn_spell(id.substr(6)):
			return false
	elif id == "forge":
		view = {"kind": "forge"}
	elif id.begins_with("forge:"):
		view = {"kind": "forgeOnto", "src": id.substr(6)}
	elif id.begins_with("imprint:") and v.kind == "forgeOnto":
		if not _imprint(v.src, id.substr(8)):
			return false
		view = {"kind": "menu"}
	elif id == "home":
		game.world_state.rest_point = "inn:" + npc.id
		events.emit("log", {"text": "%s keeps a bed for you. If you fall, you will wake at the inn." % def.name, "kind": "heal"})
		game.hud.toast("This inn is now your home")
	elif id.begins_with("quest:"):
		view = {"kind": "quest", "id": id.substr(6)}
	elif id.begins_with("node:"):
		view = {"kind": "node", "id": id.substr(5)}
	elif id == "accept" and v.kind == "quest":
		if not game.quests.accept(v.id):
			return false
		view = {"kind": "menu"}
	elif id == "complete" and v.kind == "quest":
		if not game.quests.complete(v.id):
			return false
		view = {"kind": "menu"}
	else:
		return false
	events.emit("dialogueChanged", {})
	return true

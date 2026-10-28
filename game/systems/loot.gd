class_name Loot
extends RefCounted
## Loot represented in the world (src/systems/loot.js). Collected loot is
## removed from the scene and recorded in the world state so it never
## reappears.
##
## Items the player drops (RuneScape style) become ground items: they stay
## where they fell, are saved with the world, and can be picked up again.
##
## Defeated enemies leave a body holding their coins. Looting anything also
## loots every body and drop within CONFIG.loot.areaRadius.
##
## Quest gathering nodes (world.json placedLoot with `quest`) are never
## area-looted, each takes CONFIG.loot.gatherTime to gather (a cast bar shows
## it; moving or being hit stops it), and they stay in sight at all times.
##
## Beasts (enemies.json `skin`) can be skinned once their body holds no more
## coins, if the player knows Skinning: see skinnables() below.

var game
var active: Array = [] ## { def, x, z, group, glint, base_y, seed, depleted }
var regrow: Array = [] ## { entry, at }: gathering nodes waiting to grow back
var gathering = null ## { entry, t, total, from } or, skinning, { skin, name, t, total, from }
var unique := {}


## The Skinning rank a beast of this level needs (by level, not by kind).
static func skin_rank(level: float) -> int:
	var t: Dictionary = DB.CONFIG.skinning
	return maxi(1, int((level - t.freeLevel) * t.rankPerLevel))


func _init(g) -> void:
	game = g
	unique = Items.unique_drops()
	game.events.on("playerHurt", func(_e): stop_gathering("Interrupted."))


## the cast bar while gathering: { t, total, name }
var gather_bar:
	get:
		var g = gathering
		if g == null:
			return null
		return {"t": g.t, "total": g.total, "name": "Skinning %s" % g.name if g.has("skin") else "Gathering %s" % describe(g.entry)}


## Start gathering a quest node; it is taken when the bar fills.
func start_gather(entry: Dictionary) -> bool:
	var player = game.player
	if (gathering != null and gathering.get("entry") == entry) or not available(entry):
		return false
	if player.casting != null or player.dead:
		return false
	var item = entry.def.get("reward", {}).get("item")
	if item and game.inventory.room_for(item) <= 0:
		game.hud.error("Bags are full.")
		return false
	if game.fishing:
		game.fishing.stop(true)
	var total: float = DB.CONFIG.loot.gatherTime
	gathering = {"entry": entry, "t": 0.0, "total": total, "from": player.position}
	player.face_towards(entry.x, entry.z)
	player.rig.play("brace", total, 0.9)
	return true


func stop_gathering(reason := "") -> void:
	if gathering == null:
		return
	gathering = null
	if reason != "" and game.hud:
		game.hud.error(reason)


## can this entry be taken right now? (a gathered node waits to grow back)
func available(entry: Dictionary) -> bool:
	return not entry.get("depleted", false) and gatherable(entry.def)


func spawn_all() -> void:
	clear()
	var ws = game.world_state
	for def in DB.world.placedLoot:
		if not ws.is_collected(def.id):
			_spawn(def, def.position[0], def.position[1])
	for id in ws.drops:
		if unique.has(id) and not ws.is_collected(id):
			_spawn(unique[id], ws.drops[id].x, ws.drops[id].z)
	for g in ws.ground:
		_spawn_ground(g)


func _ground_def(g: Dictionary) -> Dictionary:
	var item := Items.get_def(g.id)
	return {
		"id": "ground:%d" % int(g.uid),
		"ground": g,
		"model": item.get("model", ""),
		"prompt": "Pick up %s%s" % [Items.view(g).name, " ×%d" % g.count if g.count > 1 else ""],
		"reward": {"item": g.id, "count": g.count, "rolls": g.get("rolls")},
	}


func _spawn_ground(g: Dictionary) -> Dictionary:
	var entry := _spawn(_ground_def(g), g.x, g.z)
	entry.group.rotation.y = g.uid * 2.39
	return entry


## Drop the stack at an inventory location at the player's feet.
func drop_from_inventory(loc: String):
	var inventory = game.inventory
	var player = game.player
	var ws = game.world_state
	var events: Events = game.events
	if player.dead:
		return null
	var stack = inventory.get_at(loc)
	if stack == null or loc == Inventory.AMMO_LOC: # the ammo slot only names arrows
		return null
	var d := Items.get_def(stack.id)
	if d.get("quest"):
		events.emit("log", {"text": "You keep hold of the %s. Someone will want it." % d.name, "kind": "muted", "throttle": "inv-refuse"})
		return null
	if d.get("toolPack"):
		events.emit("log", {"text": "You keep the %s. It was hard earned." % d.name.to_lower(), "kind": "muted", "throttle": "inv-refuse"})
		return null
	var taken = inventory.take(loc)
	if taken == null:
		events.emit("log", {"text": "Empty that bag before dropping it.", "kind": "muted", "throttle": "inv-refuse"})
		return null
	# scatter drops a little in front of the player so they don't stack exactly
	var n: int = ws.ground.size()
	var a: float = player.facing + ((n % 5) - 2) * 0.5
	var pos: Vector3 = game.collision.resolve(Vector3(player.position.x + sin(a) * 0.9, 0, player.position.z + cos(a) * 0.9), 0.2)
	var g := _add_ground(taken, pos)
	var entry := _spawn_ground(g)
	events.emit("itemDropped", {"item": g})
	events.emit("log", {"text": "Dropped: %s%s." % [Items.view(g).name, " ×%d" % g.count if g.count > 1 else ""], "kind": "muted"})
	return entry


## Leave a stack on the ground at a point (a chest's overflow).
func drop_at(stack: Dictionary, pos: Vector3) -> Dictionary:
	pos = game.collision.resolve(pos, 0.2)
	return _spawn_ground(_add_ground(stack, pos))


func _add_ground(stack: Dictionary, pos: Vector3) -> Dictionary:
	var ws = game.world_state
	var g := {"uid": ws.next_ground_uid, "id": stack.id, "count": stack.get("count", 1), "x": snappedf(pos.x, 0.01), "z": snappedf(pos.z, 0.01)}
	ws.next_ground_uid += 1
	if stack.get("rolls") != null:
		g.rolls = stack.rolls
	ws.ground.append(g)
	return g


## Roll the enemy's own loot table, then the world drops for its level
## (rarity first, then the item), and lay what drops around the body. Gear rolls its stats as it drops.
func drop_from_enemy(enemy) -> Array:
	var rand: Callable = game.random
	var out := []
	var drops := Items.roll_loot(DB.loot_tables.get(enemy.cfg.get("lootTable", ""), {}), rand)
	drops.append_array(Items.roll_loot(DB.world_drop_band(enemy.cfg), rand))
	# quest drops: only while one of the player's quests still needs the item
	for qd in DB.loot_tables.get(enemy.cfg.get("lootTable", ""), {}).get("questDrops", []):
		if game.quests.needs_item(qd.quest, qd.item) and rand.call() < qd.chance:
			drops.append({"id": qd.item, "count": 1, "rarity": Items.get_def(qd.item).get("rarity")})
	for drop in drops:
		var a: float = out.size() * 2.1 + enemy.facing
		var pos: Vector3 = game.collision.resolve(Vector3(enemy.position.x + sin(a) * 0.8, 0, enemy.position.z + cos(a) * 0.8), 0.2)
		var rolls = Items.roll_item(drop.id, rand, drop.rarity)
		var stack := {"id": drop.id, "count": drop.count}
		if rolls != null:
			stack.rolls = rolls
		var g := _add_ground(stack, pos)
		_spawn_ground(g)
		out.append(g)
	for g in out:
		var v := Items.view(g)
		if Items.get_def(g.id).kind == "material":
			continue
		var tag := "" if v.rarity == "common" or v.rarity == "junk" else " (%s)" % DB.rarities[v.rarity].name
		game.events.emit("log", {"text": "The %s drops %s %s%s." % [enemy.cfg.name, U.article(v.name), v.name, tag], "kind": "loot", "rarity": v.rarity})
	return out


func clear() -> void:
	for l in active:
		l.group.queue_free()
	active = []
	regrow = []
	gathering = null


func _spawn(def: Dictionary, x: float, z: float) -> Dictionary:
	var group := Node3D.new()
	var model := Assets.instance(def.get("model", ""))
	if def.get("scale"):
		model.scale *= def.scale
	if def.get("kind") == "weapon":
		model.rotation = Vector3(PI / 2, 0, 0.6) # lying on the ground
		model.position.y = 0.06
	if def.get("model") == "kite_shield" or def.get("model") == "iron_shield":
		model.rotation = Vector3(-PI / 2 + 0.12, 0, 0.4) # lying face up
		model.position.y = 0.05
	group.add_child(model)
	var beam: MeshInstance3D = null
	var glint := Tex.sprite(Tex.fx_material(Tex.glint(), Color(1, 1, 1, 0.6), true, true))
	glint.scale = Vector3.ONE * 0.7
	glint.position.y = 0.35
	# gear above common glints in its rarity's colour, and rare and better glint brighter
	var item = def.get("reward", {}).get("item")
	if item and DB.items.has(item):
		var rarity: String = Items.view({"id": item, "rolls": def.ground.get("rolls") if def.has("ground") else null}).rarity
		if ["rare", "epic", "legendary"].has(rarity):
			glint.scale = Vector3.ONE * 1.1
		if not ["junk", "common", "quest"].has(rarity):
			glint.material_override.albedo_color = Color(Items.rarity_colour(rarity), 0.6)
			beam = _beam(group, Items.rarity_colour(rarity), ["junk", "common", "quest", "enhanced", "rare"].find(rarity))
	group.add_child(glint)
	var base_y: float = Terrain.height_at(x, z) + def.get("heightOffset", 0.0)
	group.position = Vector3(x, base_y, z)
	group.rotation.y = fmod(x * 13.7 + z * 7.1, TAU)
	game.scene.add_child(group)
	var entry := {"def": def, "x": x, "z": z, "group": group, "glint": glint, "beam": beam, "base_y": base_y, "seed": randf() * 6, "depleted": false}
	active.append(entry)
	return entry


## Green and better gear on the ground: a column of its colour rising off
## it and motes drifting up it, as Diablo marks a good drop. `tier` (-1 for
## epic and up) makes it taller and brighter.
func _beam(group: Node3D, colour: Color, tier: int) -> MeshInstance3D:
	var big := tier < 0 or tier > 3
	var beam := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.5 if not big else 0.7, 2.6 if tier == 3 else (3.4 if tier == 4 else 4.4))
	beam.mesh = q
	var m := Tex.fx_material(Tex.beam(), Color(colour, 0.85))
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	beam.material_override = m
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = q.size.y / 2
	group.add_child(beam)
	var motes := CPUParticles3D.new()
	var dot := QuadMesh.new()
	dot.size = Vector2(0.09, 0.09)
	motes.mesh = dot
	var dm := Tex.fx_material(Tex.glint(), Color(colour.lightened(0.3), 0.9))
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	motes.material_override = dm
	motes.amount = 10 if big else 6
	motes.lifetime = 1.8
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	motes.emission_sphere_radius = 0.18
	motes.direction = Vector3.UP
	motes.spread = 8
	motes.gravity = Vector3.ZERO
	motes.initial_velocity_min = 0.6
	motes.initial_velocity_max = 1.1
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	motes.color_ramp = fade
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes.position.y = 0.1
	group.add_child(motes)
	return beam


# ------------------------------------------------------------ corpses
func add_corpse(enemy, coins: float) -> void:
	game.world_state.corpses[enemy.id] = {"x": snappedf(enemy.position.x, 0.01), "z": snappedf(enemy.position.z, 0.01), "coins": coins}
	enemy.corpse = true


## A gathering node tied to a quest (`quest`) can only be taken, and only
## sparkles, while that quest is active and still needs its item.
func gatherable(def: Dictionary) -> bool:
	if not def.get("quest"):
		return true
	var q = game.quests
	if q.status(def.quest) != "active":
		return false
	for o in q.objectives(def.quest):
		if o.done or o.type != "collect":
			continue
		for d in DB.quests[def.quest].objectives:
			if d.id == o.id and d.get("target") == def.reward.item:
				return true
	return false


## Everything that can be looted right now: bodies and loot in the world.
func lootables() -> Array:
	var ws = game.world_state
	var out := []
	for id in ws.corpses:
		var c: Dictionary = ws.corpses[id]
		if not (c.coins > 0):
			continue # a looted beast waiting for the knife (skinnables)
		var e = game.enemies.by_id(id)
		out.append({"kind": "corpse", "id": id, "x": c.x, "z": c.z, "name": e.cfg.name if e else "body", "coins": c.coins})
	# only what fell in a fight (or was dropped) is area-looted; things placed
	# in the world, like the manifest, are taken one at a time
	for l in active:
		if available(l):
			var area: bool = not l.def.get("quest") and (l.def.has("ground") or is_same(unique.get(l.def.id), l.def))
			out.append({"kind": "item", "id": l.def.id, "x": l.x, "z": l.z, "entry": l, "area": area})
	return out


## `all`: lootables(), when the caller already has it
func _area(origin: Dictionary, all = null) -> Array:
	var r: float = DB.CONFIG.loot.areaRadius
	if all == null:
		all = lootables()
	var own: Array = all.filter(func(l): return l.id == origin.id)
	if origin.kind == "item" and not origin.area:
		return own
	return own + all.filter(func(l): return l.id != origin.id and (l.kind == "corpse" or l.get("area", false)) and U.hyp(l.x - origin.x, l.z - origin.z) <= r)


## Loot `origin` and everything else lootable within the area radius of it.
func loot_area(origin: Dictionary) -> int:
	# a quest node is gathered on its own, over a moment
	if origin.kind == "item" and origin.entry.def.get("quest"):
		return 1 if start_gather(origin.entry) else 0
	var n := 0
	for l in _area(origin):
		if (loot_corpse(l.id) if l.kind == "corpse" else collect(l.entry)):
			n += 1
	if n > 1:
		game.events.emit("log", {"text": "You loot %d things nearby." % n, "kind": "loot"})
	return n


## How many things a loot at `origin` would take (for the prompt).
func area_count(origin: Dictionary, all = null) -> int:
	return _area(origin, all).size()


func loot_corpse(id: String) -> bool:
	var ws = game.world_state
	var c = ws.corpses.get(id)
	if c == null:
		return false
	var e = game.enemies.by_id(id)
	var coins: float = c.coins
	# a beast's body stays down, empty, for a skinner's knife
	var skin := keep_for_skinning(e)
	if skin:
		c.coins = 0
	else:
		ws.corpses.erase(id)
	if coins > 0:
		game.inventory.add_coins(coins, "from the %s" % (e.cfg.name if e else "body"))
	if e and not skin:
		e.corpse = false # the body can now sink away
		e.rig.death = maxf(e.rig.death, 2.5)
	game.events.emit("corpseLooted", {"id": id})
	return true


## An enemy's unique drop (data/enemies.json uniqueDrop), left once where it fell.
func drop_unique(enemy) -> void:
	var ws = game.world_state
	var def = unique.get(enemy.cfg.uniqueDrop)
	if def == null or ws.is_collected(def.id) or ws.drops.has(def.id):
		return
	var x: float = enemy.position.x
	var z: float = enemy.position.z
	ws.drops[def.id] = {"x": x, "z": z}
	_spawn(def, x, z)
	game.events.emit("log", {"text": "Something glints where the %s fell." % def.droppedBy, "kind": "loot"})


func collect(entry: Dictionary) -> bool:
	var ws = game.world_state
	var inventory = game.inventory
	var events: Events = game.events
	var def: Dictionary = entry.def
	if not def.has("ground") and ws.is_collected(def.id):
		return false
	if not available(entry):
		return false
	var r: Dictionary = def.reward
	# a full bag leaves the item where it lies
	if r.get("item") and not inventory.add_item(r.item, r.get("count", 1), false, r.get("rolls")):
		return false
	if r.get("coins"):
		inventory.add_coins(r.coins, "in a purse")
	if def.has("ground"):
		ws.ground.erase(def.ground)
	elif def.get("respawn"):
		# a gathering node stays in sight, spent, and grows back; a quest's
		# (the deadfall logs) keeps its size and only loses its sparkle
		regrow.append({"entry": entry, "at": game.time + def.respawn})
		entry.depleted = true
		if not def.get("quest"):
			entry.group.scale = Vector3.ONE * 0.6
		entry.glint.visible = false
		events.emit("lootCollected", {"id": def.id, "item": r.get("item", ""), "node": true})
		return true
	else:
		ws.mark_collected(def.id)
	entry.group.queue_free()
	active.erase(entry)
	events.emit("lootCollected", {"id": def.id, "item": r.get("item", "")})
	if def.get("opensDocument") and not def.has("ground"):
		game.hud.open_document(def.opensDocument)
		events.emit("objectiveChanged", {})
	return true


func update(dt: float, time: float) -> void:
	for i in range(regrow.size() - 1, -1, -1):
		var r: Dictionary = regrow[i]
		if time < r.at:
			continue
		regrow.remove_at(i)
		r.entry.depleted = false
		r.entry.group.scale = Vector3.ONE
		r.entry.glint.visible = true # a quest node's follows its quest below
	var g = gathering
	if g != null:
		var p = game.player
		var ok: bool = _skinnable(g.skin) if g.has("skin") else available(g.entry)
		if p.dead or p.casting != null or p.position.distance_to(g.from) > 0.3 or not ok:
			stop_gathering("" if p.dead else "Interrupted.")
		else:
			g.t += dt
			if g.t >= g.total:
				gathering = null
				if g.has("skin"):
					skin(g.skin)
				else:
					collect(g.entry)
	for l in active:
		if l.def.get("quest"):
			l.glint.visible = available(l)
		l.glint.material_override.albedo_color.a = 0.45 + sin(time * 2.2 + l.seed) * 0.2
		l.glint.position.y = 0.3 + sin(time * 1.5 + l.seed) * 0.05
		if l.get("beam"):
			l.beam.material_override.albedo_color.a = 0.75 + sin(time * 1.8 + l.seed) * 0.15


# ------------------------------------------------------------ skinning
## Should this body wait to be skinned? Only if the player could learn to.
func keep_for_skinning(enemy) -> bool:
	return enemy != null and enemy.cfg.get("skin", "") != "" and game.skills.has("skinning")


func _skinnable(id: String) -> bool:
	var c = game.world_state.corpses.get(id)
	var e = game.enemies.by_id(id)
	return c != null and not (c.coins > 0) and e != null and e.cfg.get("skin", "") != ""


## Bodies that can be skinned now: [{ kind: 'skin', id, x, z, name, rank }]
func skinnables() -> Array:
	if not game.skills.has("skinning"):
		return []
	var out := []
	var ws = game.world_state
	for id in ws.corpses:
		if not _skinnable(id):
			continue
		var c: Dictionary = ws.corpses[id]
		var e = game.enemies.by_id(id)
		out.append({"kind": "skin", "id": id, "x": c.x, "z": c.z, "name": e.cfg.name, "rank": skin_rank(e.cfg.level)})
	return out


## the best knife carried, or null
var knife:
	get:
		var inv = game.inventory
		var best = null
		for id in DB.items:
			var d: Dictionary = DB.items[id]
			if d.get("skinningKnife") and inv.has(id) and (best == null or d.get("skinningSkill", 0) > best.get("skinningSkill", 0)):
				best = d
		return best

## Skinning rank with the knife's bonus
var skinning_skill: int:
	get:
		return game.skills.effective("skinning")


## What stops this body being skinned ('needs ...'), or "".
func skin_block(s: Dictionary) -> String:
	if knife == null:
		return "needs a skinning knife"
	if skinning_skill < s.rank:
		return "needs Skinning %d" % s.rank
	return ""


func start_skin(s: Dictionary) -> bool:
	var player = game.player
	if (gathering != null and gathering.get("skin") == s.id) or not _skinnable(s.id):
		return false
	if player.casting != null or player.dead:
		return false
	var why := skin_block(s)
	if why != "":
		game.hud.error("That %s." % why)
		return false
	if game.fishing:
		game.fishing.stop(true)
	var total: float = DB.CONFIG.skinning.time
	gathering = {"skin": s.id, "name": s.name, "t": 0.0, "total": total, "from": player.position}
	player.face_towards(s.x, s.z)
	player.rig.play("brace", total, 0.9)
	return true


func skin(id: String) -> bool:
	var ws = game.world_state
	if not _skinnable(id):
		return false
	var c: Dictionary = ws.corpses[id]
	var e = game.enemies.by_id(id)
	var table: String = e.cfg.skin
	var rank := skin_rank(e.cfg.level)
	ws.corpses.erase(id)
	e.corpse = false # the body can now sink away
	e.rig.death = maxf(e.rig.death, 2.5)
	# full bags: what will not fit lies by the body
	for drop in Items.roll_loot(DB.loot_tables.get(table, {}), game.random):
		if not game.inventory.add_item(drop.id, drop.count):
			drop_at({"id": drop.id, "count": drop.count}, Vector3(c.x, 0, c.z))
	var over: int = game.skills.rank("skinning") - rank
	var t: Dictionary = DB.CONFIG.skinning
	if over < t.easyAfter or (over < t.trivialAfter and game.random.call() < t.easyChance):
		game.skills.raise("skinning")
	game.events.emit("skinned", {"id": id, "enemy": e.type})
	return true


func describe(entry: Dictionary) -> String:
	var r: Dictionary = entry.def.reward
	return Items.view({"id": r.item, "rolls": r.get("rolls")}).name if r.get("item") else ""

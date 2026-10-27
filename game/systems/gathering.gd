class_name Gathering
extends RefCounted
## Gathering nodes (data/nodes.json): herb patches now, and whatever else is
## picked off the land later (Woodcutting's trees, say). A node kind needs
## its skill at its level; one gather gives its yield, maybe a rare bonus,
## and skill experience by the colour of the task (Skills.gain).
##
## Patches move, as Mining's veins do: each group has a few live nodes among
## its spots, and a picked node goes bare until another spot in the group
## grows one. The world decides what is live (the same for every player in a
## shared world); the screen draws only what is near.

var game
var nodes: Array = [] ## { group, i, x, z, node, mats, kind, seed }
var regrow: Array = [] ## { group, was, at }
var picking = null ## { n, t, total, from }


func _init(g) -> void:
	game = g
	game.events.on("playerHurt", func(_e): stop("Interrupted."))
	_build()


static func tuning() -> Dictionary:
	return DB.nodes.get("tuning", {})


static func kind_def(id: String) -> Dictionary:
	for k in DB.nodes.get("nodeKinds", []):
		if k.id == id:
			return k
	return {}


# ------------------------------------------------------------ the world
func _build() -> void:
	var t := tuning()
	for g in DB.nodes.get("nodeGroups", []):
		for i in g.spots.size():
			var p: Array = g.spots[i]
			var node := Node3D.new()
			node.name = "Herb_%s_%d" % [g.id, i]
			var model := Assets.instance(t.get("model", "pine"))
			model.scale *= t.get("scale", 0.16)
			node.add_child(model)
			node.position = Vector3(p[0], Terrain.height_at(p[0], p[1]), p[1])
			node.rotation.y = fmod(p[0] * 11.3 + p[1] * 5.7, TAU)
			node.visible = false
			game.scene.add_child(node)
			var mats := Rig.isolate_materials(model)
			for m in mats:
				if m is BaseMaterial3D:
					m.set_meta("base", m.albedo_color)
			nodes.append({"group": g, "i": i, "x": float(p[0]), "z": float(p[1]), "node": node, "mats": mats, "kind": "", "seed": randf() * 6})
	# a station that names a model (an alchemy bench) stands where it is
	for st in Layout.stations:
		if st.has("model"):
			var m := Assets.instance(st.model)
			m.position = Vector3(st.position[0], Terrain.height_at(st.position[0], st.position[1]), st.position[1])
			m.scale *= st.get("scale", 0.8)
			game.scene.add_child(m)
			game.collision.add(st.position[0], st.position[1], 0.5)


## A new game or a load: every node bare, then each group grows its live
## nodes afresh (the world's state, not the save's).
func spawn_all() -> void:
	regrow = []
	picking = null
	for n in nodes:
		n.kind = ""
		_paint(n)
	for g in DB.nodes.get("nodeGroups", []):
		for i in int(g.get("live", 1)):
			_grow(g)


func _grow(g: Dictionary, not_this = null) -> void:
	var bare := nodes.filter(func(n): return n.group == g and n.kind == "" and not is_same(n, not_this))
	if bare.is_empty():
		bare = nodes.filter(func(n): return n.group == g and n.kind == "")
	if bare.is_empty():
		return
	var rand: Callable = game.random
	var n: Dictionary = bare[mini(bare.size() - 1, int(rand.call() * bare.size()))]
	var total := 0.0
	for k in g.kinds:
		total += k.weight
	var pick: float = rand.call() * total
	n.kind = g.kinds[0].kind
	for k in g.kinds:
		pick -= k.weight
		if pick < 0:
			n.kind = k.kind
			break
	_paint(n)


func _paint(n: Dictionary) -> void:
	n.node.visible = n.kind != ""
	if n.kind == "":
		return
	var colour := Color(kind_def(n.kind).get("tint", "#ffffff"))
	for m in n.mats:
		if m is BaseMaterial3D:
			m.albedo_color = m.get_meta("base", Color.WHITE) * colour


## Live nodes: { n, x, z, name, level, skill }
func live() -> Array:
	var out := []
	for n in nodes:
		if n.kind != "":
			var k := kind_def(n.kind)
			out.append({"n": n, "x": n.x, "z": n.z, "name": k.name, "level": int(k.get("level", 1)), "skill": k.get("skill", "herbalism")})
	return out


# ------------------------------------------------------------ the picker
## What stops this node being gathered ('needs ...'), or "".
func block(v: Dictionary) -> String:
	var sk: String = v.skill
	var name: String = DB.skills.get(sk, {}).get("name", sk)
	if not game.skills.has(sk):
		return "needs %s" % name
	if game.skills.rank(sk) < v.level:
		return "needs %s %d" % [name, v.level]
	return ""


func interactions() -> Array:
	var out := []
	var reach: float = tuning().get("reach", 2.2)
	for v in live():
		var why := block(v)
		out.append({"key": "node:%s:%d" % [v.n.group.id, v.n.i], "x": v.x, "z": v.z, "bias": -0.2, "reach": reach, "prompt": "Pick the %s%s" % [v.name.to_lower(), " (%s)" % why if why != "" else ""], "run": func(): start(v.n)})
	return out


func _view(n: Dictionary) -> Dictionary:
	var k := kind_def(n.kind)
	return {"n": n, "level": int(k.get("level", 1)), "skill": k.get("skill", "herbalism"), "name": k.get("name", "")}


func start(n: Dictionary) -> bool:
	var player = game.player
	if n.kind == "" or (picking != null and is_same(picking.n, n)):
		return false
	if player.casting != null or player.dead:
		return false
	var v := _view(n)
	var why := block(v)
	if why != "":
		game.hud.error("That %s %s." % [v.name.to_lower(), why])
		return false
	if game.fishing:
		game.fishing.stop(true)
	game.mining.stop()
	game.loot.stop_gathering()
	var sk: String = v.skill
	# a knife or sickle (tool bonus) and the Quick Hands perk make it quicker
	var quick := minf(0.6, game.skills.tool_bonus(sk) * 0.02 + game.skills.perk(sk, "speed"))
	var total: float = tuning().get("gatherTime", 1.8) * (1.0 - quick)
	picking = {"n": n, "t": 0.0, "total": total, "from": player.position}
	player.face_towards(n.x, n.z)
	player.rig.play("brace", total, 0.6)
	return true


func stop(reason := "") -> void:
	if picking == null:
		return
	picking = null
	game.player.rig.action = null
	if reason != "" and game.hud:
		game.hud.error(reason)


## the cast bar while picking: { t, total, name }
var bar:
	get:
		if picking == null:
			return null
		return {"t": picking.t, "total": picking.total, "name": "Picking %s" % kind_def(picking.n.kind).get("name", "").to_lower()}


func update(dt: float, time: float) -> void:
	for i in range(regrow.size() - 1, -1, -1):
		if time >= regrow[i].at:
			var r: Dictionary = regrow[i]
			regrow.remove_at(i)
			_grow(r.group, r.get("was"))
	var p = picking
	if p == null:
		return
	var player = game.player
	if player.dead or player.casting != null or player.position.distance_to(p.from) > 0.3 or p.n.kind == "":
		stop("" if player.dead or p.n.kind != "" else "Someone got there first.")
		return
	p.t += dt
	if p.t < p.total:
		return
	picking = null
	_pick(p.n, time)


## One gather: the yield, maybe more (Green Thumb) and a rare bonus; the
## skill learns by the task's colour; the node goes bare.
func _pick(n: Dictionary, time: float) -> void:
	var k := kind_def(n.kind)
	var sk: String = k.get("skill", "herbalism")
	var skills = game.skills
	var rand: Callable = game.random
	var y: Dictionary = k.yields
	var count := int(y.get("min", 1)) + int(rand.call() * (int(y.get("max", 1)) - int(y.get("min", 1)) + 1))
	if rand.call() < skills.perk(sk, "extraHerb"):
		count += 1
	var got := [{"id": y.item, "count": count}]
	var bonus = k.get("bonus")
	if bonus != null and rand.call() < float(bonus.chance) * maxf(1.0, skills.perk(sk, "bonusChance")):
		got.append({"id": bonus.item, "count": 1})
		game.events.emit("log", {"text": "Something rare among the leaves: %s." % Items.get_def(bonus.item).name.to_lower(), "kind": "loot", "rarity": Items.get_def(bonus.item).get("rarity", "rare")})
	for g in got:
		if not game.inventory.add_item(g.id, g.count):
			game.loot.drop_at({"id": g.id, "count": g.count}, Vector3(n.x, 0, n.z))
	var heal: float = skills.perk(sk, "healPercent")
	if heal > 0:
		game.player.heal(game.player.max_health * heal / 100.0)
	skills.gain(sk, skills.colour_for(sk, int(k.get("level", 1))))
	game.events.emit("gathered", {"kind": n.kind, "items": got})
	n.kind = ""
	_paint(n)
	var rs: Array = n.group.get("respawn", [60, 120])
	regrow.append({"group": n.group, "was": n, "at": time + float(rs[0]) + rand.call() * (float(rs[1]) - float(rs[0]))})

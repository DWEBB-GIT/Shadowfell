class_name Mining
extends RefCounted
## Mining (data/mining.json), a gathering profession like Skinning: a
## trainer, a pick in the tool pack, and a rank that rises with every swing
## that is not yet easy for you (5 ranks an ore level).
##
## Veins move. Rock outcrops stand in groups all over the map, and only a few
## of a group hold ore at once. A mined-out vein goes bare, and after a while
## a different, random outcrop in the same group starts to glint, so players
## learn the good ridges rather than one stone. Now and then a vein is rich:
## more swings and a better chance of gem shards.
##
## The world decides which outcrops are live (simulated everywhere, so in a
## shared world every player would see the same veins); each screen only
## draws the outcrops near it, as with everything else.

var game
var outcrops: Array = [] ## { group, i, x, z, node, mats, glint, rock, swings, rich, seed }
var regrow: Array = [] ## { group, at }: a group waiting to light another vein
var mining = null ## { o, t, total, from }


func _init(g) -> void:
	game = g
	game.events.on("playerHurt", func(_e): stop("Interrupted."))
	_build()


static func tuning() -> Dictionary:
	return DB.mining.get("tuning", {})


static func rock_def(id: String) -> Dictionary:
	for r in DB.mining.get("rocks", []):
		if r.id == id:
			return r
	return {}


# ------------------------------------------------------------ the world
## The outcrops stand for good: built once, each solid like a rock.
func _build() -> void:
	var t := tuning()
	for g in DB.mining.get("veinGroups", []):
		for i in g.outcrops.size():
			var p: Array = g.outcrops[i]
			var node := Node3D.new()
			node.name = "Outcrop_%s_%d" % [g.id, i]
			var model := Assets.instance(t.get("model", "rock1"))
			model.scale *= t.get("scale", 0.5)
			node.add_child(model)
			var glint := Tex.sprite(Tex.fx_material(Tex.glint(), Color(1, 0.95, 0.8, 0.6), true, true))
			glint.scale = Vector3.ONE * 0.8
			glint.position.y = 0.6
			glint.visible = false
			node.add_child(glint)
			node.position = Vector3(p[0], Terrain.height_at(p[0], p[1]), p[1])
			node.rotation.y = fmod(p[0] * 13.7 + p[1] * 7.1, TAU)
			game.scene.add_child(node)
			var mats := Rig.isolate_materials(model)
			for m in mats:
				if m is BaseMaterial3D:
					m.set_meta("base", m.albedo_color)
			game.collision.add(p[0], p[1], t.get("radius", 0.55))
			var o := {"group": g, "i": i, "x": float(p[0]), "z": float(p[1]), "node": node, "mats": mats, "glint": glint, "rock": "", "swings": 0, "rich": false, "seed": randf() * 6}
			outcrops.append(o)
			_paint(o)


## A new game or a load: every outcrop bare, then each group lights its
## live veins afresh (vein state is the world's, not the save's).
func spawn_all() -> void:
	regrow = []
	mining = null
	for o in outcrops:
		o.rock = ""
		o.rich = false
		_paint(o)
	for g in DB.mining.get("veinGroups", []):
		for n in int(g.get("live", 1)):
			_light(g)


func _of_group(g: Dictionary) -> Array:
	return outcrops.filter(func(o): return o.group == g)


## Light a vein on a random bare outcrop of the group (not `not_this`).
func _light(g: Dictionary, not_this = null) -> void:
	var bare := _of_group(g).filter(func(o): return o.rock == "" and not is_same(o, not_this))
	if bare.is_empty():
		bare = _of_group(g).filter(func(o): return o.rock == "")
	if bare.is_empty():
		return
	var rand: Callable = game.random
	var o: Dictionary = bare[mini(bare.size() - 1, int(rand.call() * bare.size()))]
	var total := 0.0
	for r in g.rocks:
		total += r.weight
	var pick: float = rand.call() * total
	var rock: String = g.rocks[0].rock
	for r in g.rocks:
		pick -= r.weight
		if pick < 0:
			rock = r.rock
			break
	var def := rock_def(rock)
	var sw: Array = def.get("swings", [2, 3])
	var rich: Dictionary = DB.mining.get("rich", {})
	o.rock = rock
	o.rich = rand.call() < rich.get("chance", 0.0)
	o.swings = int(sw[0]) + int(rand.call() * (int(sw[1]) - int(sw[0]) + 1)) + (int(rich.get("extraSwings", 0)) if o.rich else 0)
	_paint(o)


func _paint(o: Dictionary) -> void:
	var colour := Color(tuning().get("bareTint", "#6a665e"))
	if o.rock != "":
		colour = Color(rock_def(o.rock).get("tint", "#ffffff"))
	for m in o.mats:
		if m is BaseMaterial3D:
			m.albedo_color = m.get_meta("base", Color.WHITE) * colour
	o.glint.visible = o.rock != ""
	o.glint.scale = Vector3.ONE * (1.2 if o.rich else 0.8)


func name_of(o: Dictionary) -> String:
	var n: String = rock_def(o.rock).get("name", "Rock")
	return ("Rich " + n.to_lower()) if o.rich else n


## Live veins: { o, x, z, name, rank }
func veins() -> Array:
	var out := []
	for o in outcrops:
		if o.rock != "":
			out.append({"o": o, "x": o.x, "z": o.z, "name": name_of(o), "rank": int(rock_def(o.rock).get("rank", 1))})
	return out


# ------------------------------------------------------------ the miner
## the best pick carried, or null
var pick:
	get:
		var inv = game.inventory
		var best = null
		for id in DB.items:
			var d: Dictionary = DB.items[id]
			if d.get("miningPick") and inv.has(id) and (best == null or d.get("miningSkill", 0) > best.get("miningSkill", 0)):
				best = d
		return best


## What stops this vein being mined ('needs ...'), or "".
func block(v: Dictionary) -> String:
	if not game.skills.has("mining"):
		return "needs Mining"
	if pick == null:
		return "needs a mining pick"
	if game.skills.effective("mining") < v.rank:
		return "needs Mining %d" % v.rank
	return ""


## what the interaction system offers: a glinting vein close by
func interactions() -> Array:
	var out := []
	var reach: float = tuning().get("reach", 2.6)
	for v in veins():
		var why := block(v)
		out.append({"key": "vein:%s:%d" % [v.o.group.id, v.o.i], "x": v.x, "z": v.z, "bias": -0.2, "reach": reach, "prompt": "Mine the %s%s" % [v.name.to_lower(), " (%s)" % why if why != "" else ""], "run": func(): start(v.o)})
	return out


func start(o: Dictionary) -> bool:
	var player = game.player
	if o.rock == "" or (mining != null and is_same(mining.o, o)):
		return false
	if player.casting != null or player.dead:
		return false
	var why := block({"rank": int(rock_def(o.rock).get("rank", 1))})
	if why != "":
		game.hud.error("That vein %s." % why)
		return false
	if game.fishing:
		game.fishing.stop(true)
	game.loot.stop_gathering()
	if game.gathering:
		game.gathering.stop()
	_swing(o)
	return true


func _swing(o: Dictionary) -> void:
	var player = game.player
	var total: float = tuning().get("swingTime", 2.4)
	mining = {"o": o, "t": 0.0, "total": total, "from": player.position}
	player.face_towards(o.x, o.z)
	player.rig.play("strike", total, 0.7)


func stop(reason := "") -> void:
	if mining == null:
		return
	mining = null
	game.player.rig.action = null
	if reason != "" and game.hud:
		game.hud.error(reason)


## the cast bar while mining: { t, total, name }
var bar:
	get:
		if mining == null:
			return null
		return {"t": mining.t, "total": mining.total, "name": "Mining %s (%d)" % [name_of(mining.o).to_lower(), mining.o.swings]}


func update(dt: float, time: float) -> void:
	for i in range(regrow.size() - 1, -1, -1):
		if time >= regrow[i].at:
			var r: Dictionary = regrow[i]
			regrow.remove_at(i)
			_light(r.group, r.get("was"))
	for o in outcrops:
		if o.rock != "":
			o.glint.material_override.albedo_color.a = 0.5 + sin(time * 2.4 + o.seed) * 0.25
	var m = mining
	if m == null:
		return
	var p = game.player
	if p.dead or p.casting != null or p.position.distance_to(m.from) > 0.3 or m.o.rock == "":
		stop("" if p.dead or m.o.rock != "" else "The vein is spent.")
		return
	m.t += dt
	if m.t < m.total:
		return
	var o: Dictionary = m.o
	_yield(o)
	o.swings -= 1
	if o.swings <= 0:
		_deplete(o, time)
		mining = null
		game.events.emit("log", {"text": "The vein is mined out. Another will glint somewhere along %s before long." % o.group.get("name", "the rock"), "kind": "muted"})
	elif block({"rank": int(rock_def(o.rock).get("rank", 1))}) == "":
		_swing(o) # keep swinging until it is bare, as long as you stand there
	else:
		mining = null


## One swing's worth: stone, ore and maybe a gem shard; the skill may rise.
func _yield(o: Dictionary) -> void:
	var def := rock_def(o.rock)
	var rand: Callable = game.random
	var got := []
	for k in ["stone", "ore"]:
		var y = def.get(k)
		if y != null and rand.call() < y.get("chance", 1.0):
			got.append(y.item)
	var gems = def.get("gems")
	if gems != null:
		var chance: float = gems.chance * (DB.mining.get("rich", {}).get("gemChance", 1.0) if o.rich else 1.0)
		if rand.call() < chance:
			var total := 0.0
			for s in gems.shards:
				total += s.weight
			var pick_: float = rand.call() * total
			for s in gems.shards:
				pick_ -= s.weight
				if pick_ < 0:
					got.append(s.item)
					game.events.emit("log", {"text": "Something glitters in the rubble: %s." % Items.get_def(s.item).name.to_lower(), "kind": "loot", "rarity": "enhanced"})
					break
	for id in got:
		if not game.inventory.add_item(id, 1):
			game.loot.drop_at({"id": id, "count": 1}, Vector3(o.x, 0, o.z))
	var t := tuning()
	var over: int = game.skills.rank("mining") - int(def.get("rank", 1))
	if over < t.get("easyAfter", 10) or (over < t.get("trivialAfter", 20) and rand.call() < t.get("easyChance", 0.5)):
		game.skills.raise("mining")
	game.events.emit("mined", {"rock": o.rock, "items": got})


func _deplete(o: Dictionary, time: float) -> void:
	o.rock = ""
	o.rich = false
	o.swings = 0
	_paint(o)
	var rs: Array = o.group.get("respawn", [60, 120])
	regrow.append({"group": o.group, "was": o, "at": time + float(rs[0]) + game.random.call() * (float(rs[1]) - float(rs[0]))})

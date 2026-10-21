class_name Fishing
extends RefCounted
## Fishing, WoW style (src/systems/fishing.js). With the Fishing skill (from
## Old Tam) and a rod in the bags, the Fishing ability casts a bob into the
## water you face, and the fishing bar runs for `duration` seconds. Whether
## anything bites is rolled at the cast: the chance rises with your fishing
## skill (rank + best rod + bait). If something bites, the bob dips at some
## moment in the cast: strike then (click the bob, or E / A) for a chance to
## land a fish from that water's loot table. Skill comes only from a real
## attempt: landing something or a strike on a real bite that slips the hook.
##
## Phases: 'cast' (the bob flies) -> 'wait' -> 'bite' (strike now) -> done.

var game
var state = null ## { phase, t, elapsed, wait, skill, x, z, water, bob, line, from }


func _init(g) -> void:
	game = g


var active: bool:
	get:
		return state != null

var biting: bool:
	get:
		return state != null and state.phase == "bite"


func _say(text: String, key: String) -> bool:
	game.events.emit("log", {"text": text, "kind": "muted", "throttle": key})
	return false


## Cast towards the aim point (or straight ahead) if it is water within reach.
func cast(aim) -> bool:
	var player = game.player
	if not game.skills.has("fishing"):
		return _say("You do not know how to fish. Old Tam by the mere can teach you.", "fish-skill")
	if not has_rod:
		return _say("You need a fishing rod in your bags.", "fish-rod")
	if player.casting != null or player.pending != null:
		return false
	stop(true)
	var range_: float = DB.abilities.fish.range
	var p: Vector3 = player.position
	var spot = null
	if aim != null and U.hyp(aim.x - p.x, aim.z - p.z) <= range_ and Terrain.water_at(aim.x, aim.z, 0.6) != null:
		spot = Vector2(aim.x, aim.z)
	else:
		var fx := sin(player.facing)
		var fz := cos(player.facing)
		var d := 2.5
		while d <= range_ and spot == null:
			if Terrain.water_at(p.x + fx * d, p.z + fz * d, 0.6) != null:
				spot = Vector2(p.x + fx * (d + 1), p.z + fz * (d + 1))
			d += 0.5
	var water = Terrain.water_at(spot.x, spot.y, 0.3) if spot != null else null
	if water == null:
		return _say("Face open water to fish.", "fish-water")
	player.face_towards(spot.x, spot.y)
	player.hold_rod(true)
	player.rig.play("castLine", 0.7, 0.45)
	var cfg: Dictionary = DB.CONFIG.fishing
	# bait goes on the hook now, and counts for this cast
	var bait = _bait()
	var sk := skill
	if bait:
		game.inventory.remove_count(bait, 1)
	var bites: bool = game.random.call() * 100 < bite_chance_for(sk)
	var wait: float = cfg.biteMin + (cfg.biteMax - cfg.biteMin) * game.random.call() if bites else INF
	state = {"phase": "cast", "t": 0.0, "elapsed": 0.0, "wait": wait, "skill": sk, "x": spot.x, "z": spot.y, "water": water, "bob": _make_bob(), "line": _make_line(), "from": p}
	game.events.emit("fishCast", {"x": spot.x, "z": spot.y})
	return true


## any rod carried
var has_rod: bool:
	get:
		for id in DB.items:
			if DB.items[id].get("rod") and game.inventory.count(id) > 0:
				return true
		return false

## Fishing skill: rank, plus the best rod in your bags, plus bait if you
## have some (it is used up when you cast)
var skill: int:
	get:
		var rod := 0
		for id in DB.items:
			var d: Dictionary = DB.items[id]
			if d.get("rod") and d.get("fishingSkill") and game.inventory.count(id) > 0:
				rod = maxi(rod, int(d.fishingSkill))
		var bait = _bait()
		return game.skills.rank("fishing") + rod + (int(DB.items[bait].bait) if bait else 0)


## percent chance that a cast gets a bite
func bite_chance_for(sk: float) -> float:
	var cfg: Dictionary = DB.CONFIG.fishing
	return minf(cfg.biteCap, cfg.biteBase + sk * cfg.bitePerSkill)


## The catch chance in percent for a timely strike.
var chance: float:
	get:
		var cfg: Dictionary = DB.CONFIG.fishing
		var sk: float = state.skill if state != null else skill
		return minf(100, cfg.baseChance + sk * cfg.chancePerRank)


## the best bait in your bags
func _bait():
	var best = null
	for id in DB.items:
		var d: Dictionary = DB.items[id]
		if d.get("bait") and game.inventory.count(id) > 0 and (best == null or d.bait > DB.items[best].bait):
			best = id
	return best


## the fishing bar: { t, total }
var bar:
	get:
		return {"t": state.elapsed, "total": DB.CONFIG.fishing.duration} if state != null else null


## Click the bob, or E / A: strike.
func strike() -> bool:
	var s = state
	if s == null:
		return false
	var events: Events = game.events
	var inventory = game.inventory
	if s.phase != "bite":
		events.emit("log", {"text": "You strike too soon. Whatever was there is gone.", "kind": "muted"})
		stop()
		return true
	if game.random.call() * 100 >= chance:
		events.emit("log", {"text": "The fish slips the hook.", "kind": "muted"})
		game.skills.raise("fishing") # a real bite still teaches you something
		stop()
		return true
	var caught := Items.roll_loot(DB.loot_tables.get(s.water.get("fishTable", ""), {}), game.random)
	for c in caught:
		if inventory.room_for(c.id) < c.count:
			events.emit("log", {"text": "Your bags are full. You let it go.", "kind": "muted"})
			continue
		inventory.add_item(c.id, c.count)
		var name: String = Items.get_def(c.id).name
		events.emit("log", {"text": "You catch %s %s." % [U.article(name), name], "kind": "loot", "rarity": c.rarity})
	events.emit("fishCaught", {"items": caught})
	game.skills.raise("fishing")
	stop()
	return true


## Reel in (moving, fighting or a new cast ends it).
func stop(quiet := false) -> void:
	if state == null:
		return
	state.bob.queue_free()
	state.line.queue_free()
	state = null
	game.player.hold_rod(false)
	if not quiet:
		game.events.emit("fishEnd", {})


func update(dt: float) -> void:
	var s = state
	if s == null:
		return
	var player = game.player
	var events: Events = game.events
	if player.dead or player.pending != null or player.casting != null or player.position.distance_to(s.from) > 0.6:
		stop()
		return
	s.t += dt
	s.elapsed += dt
	var cfg: Dictionary = DB.CONFIG.fishing
	# the fishing bar has run out with nothing on the line
	if s.elapsed >= cfg.duration and s.phase != "bite":
		events.emit("log", {"text": "Nothing is biting. You reel in your line.", "kind": "muted"})
		game.hud.error("Nothing is biting")
		stop()
		return
	var level := Terrain.water_level(s.water)
	var bob: Node3D = s.bob
	if s.phase == "cast":
		# the bob arcs out from the rod tip and lands
		var k: float = minf(1, s.t / cfg.castTime)
		bob.position = Vector3(lerpf(s.from.x, s.x, k), lerpf(s.from.y + 2, level, k) + sin(k * PI) * 1.5, lerpf(s.from.z, s.z, k))
		if k >= 1:
			s.phase = "wait"
			s.t = 0.0
			events.emit("splash", {"x": s.x, "y": level, "z": s.z, "small": true})
	elif s.phase == "wait":
		bob.position = Vector3(s.x, level + 0.04 + sin(s.t * 2.2) * 0.02, s.z)
		if s.t >= s.wait:
			s.phase = "bite"
			s.t = 0.0
			events.emit("splash", {"x": s.x, "y": level, "z": s.z})
			events.emit("fishBite", {})
	elif s.phase == "bite":
		bob.position = Vector3(s.x, level - 0.06 + sin(s.t * 28) * 0.05, s.z)
		if s.t >= cfg.biteWindow:
			events.emit("log", {"text": "The bob rises again. It got away.", "kind": "muted"})
			stop()
			return
	_draw_line(s, 0.1 if s.phase == "cast" else 0.05 if s.phase == "bite" else 0.35)


## the line, from the rod tip to the bob, sagging a little when slack
func _draw_line(s: Dictionary, sag: float) -> void:
	var a: Vector3 = game.player.rod_tip_position()
	var b: Vector3 = s.bob.position
	var im: ImmediateMesh = s.line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := 15
	for i in n + 1:
		var k := float(i) / n
		var droop := sin(k * PI) * sag * a.distance_to(b) * 0.25
		im.surface_add_vertex(Vector3(a.x + (b.x - a.x) * k, a.y + (b.y + 0.08 - a.y) * k - droop, a.z + (b.z - a.z) * k))
	im.surface_end()


func _make_line() -> MeshInstance3D:
	var line := MeshInstance3D.new()
	line.name = "FishingLine"
	line.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(Color("d8d2c0"), 0.75)
	line.material_override = mat
	line.extra_cull_margin = 100
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.scene.add_child(line)
	return line


## the bob's place, for clicking it
var bob_position:
	get:
		return state.bob.position if state != null else null


func _make_bob() -> Node3D:
	var g := Node3D.new()
	g.name = "FishingBob"
	for top in [true, false]:
		var m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.09
		sm.is_hemisphere = true
		sm.radial_segments = 8
		sm.rings = 3
		m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("c83a2a") if top else Color("e8e0d0")
		if top:
			mat.emission_enabled = true
			mat.emission = Color("3a0a06")
		m.material_override = mat
		m.position.y = 0.04
		if not top:
			m.rotation.x = PI
		g.add_child(m)
	game.scene.add_child(g)
	return g

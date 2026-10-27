class_name Grave
extends RefCounted
## Your grave (Dan, 2026-10-27), RuneScape and Dark Souls style. When you
## fall, everything in your bags and your coins stay in a grave where you
## fell; your worn gear stays on you. Get back to it before `graveSeconds`
## of play run out. After that, scavengers find it and carry it off: they
## linger nearby, and killing the last of them gives it all back, with no
## bonus on top. Falling again before you take it back loses the old one.
##
## The state lives in world_state.grave and is saved:
## { phase: "grave" | "stolen" | "dropped", x, z, until, items: [stacks],
##   coins, scavengers: [enemy ids], next }

const KEEP_KINDS := ["key", "document"] ## stay in your bags when you fall

var game
var mesh: Node3D = null


func _init(g) -> void:
	game = g


var state:
	get:
		return game.world_state.grave


func _cfg() -> Dictionary:
	return DB.CONFIG.death


## Seconds of play before scavengers come, or -1 if the grave is not waiting.
var time_left: float:
	get:
		var g = state
		return maxf(0, g.until - game.world_state.time) if g != null and g.phase == "grave" else -1.0


# --------------------------------------------------------------- falling
func on_death(at: Vector3) -> void:
	var ws = game.world_state
	if ws.grave != null:
		game.events.emit("log", {"text": "Your old grave is lost for good.", "kind": "hurt"})
		_clear()
	var inv = game.inventory
	var items := []
	for i in mini(inv.sockets.size(), Items.BAG_SOCKETS):
		var s = inv.sockets[i]
		if s == null:
			continue
		for j in s.slots.size():
			var st = s.slots[j]
			if st == null:
				continue
			var def := Items.get_def(st.id)
			if KEEP_KINDS.has(def.get("kind")) or def.get("rarity") == "quest":
				continue
			items.append(st.duplicate(true))
			s.slots[j] = null
	var coins: int = inv.coins
	inv.coins = 0
	inv._changed()
	if items.is_empty() and coins == 0:
		return
	ws.grave = {"phase": "grave", "x": snappedf(at.x, 0.01), "z": snappedf(at.z, 0.01), "until": ws.time + _cfg().graveSeconds, "items": items, "coins": coins, "scavengers": [], "next": 0}
	_show()
	game.events.emit("log", {"text": "What you carried lies in a grave where you fell. Reach it within %d minutes, before scavengers find it." % roundi(_cfg().graveSeconds / 60.0), "kind": "hurt"})


# ----------------------------------------------------------- each frame
func update(_dt: float) -> void:
	var g = state
	if g != null and g.phase == "grave" and game.world_state.time >= g.until:
		_steal()


## the timer ran out: scavengers take it and stay near the grave
func _steal() -> void:
	var g: Dictionary = state
	g.phase = "stolen"
	_hide()
	var n := int(_cfg().scavengers)
	for i in n:
		g.scavengers.append("grave_scavenger_%d_%d" % [int(game.world_state.time), i])
	_spawn_scavengers()
	game.events.emit("log", {"text": "Scavengers have dug up your grave. They will not have gone far.", "kind": "hurt"})


func _spawn_scavengers() -> void:
	var g: Dictionary = state
	var ws = game.world_state
	var level: int = game.progression.level
	for i in g.scavengers.size():
		var id: String = g.scavengers[i]
		if ws.is_defeated(id) or game.enemies.by_id(id) != null:
			continue
		var a: float = TAU * i / maxf(1, g.scavengers.size())
		var spawn := {"id": id, "type": "grave_scavenger", "level": level, "position": [g.x + cos(a) * 2.5, g.z + sin(a) * 2.5]}
		var e := Enemy.new(game, spawn)
		game.enemies.list.append(e)
		game.scene.add_child(e.group)


## called when an enemy falls: the last scavenger drops what they took
func on_enemy_defeated(enemy) -> void:
	var g = state
	if g == null or g.phase != "stolen" or not g.scavengers.has(enemy.id):
		return
	for id in g.scavengers:
		if not game.world_state.is_defeated(id):
			return
	g.phase = "dropped"
	g.x = snappedf(enemy.position.x, 0.01)
	g.z = snappedf(enemy.position.z, 0.01)
	_show()
	game.events.emit("log", {"text": "The last scavenger drops your bundle.", "kind": "loot"})


# ------------------------------------------------------------ taking back
func interactions() -> Array:
	var g = state
	if g == null or g.phase == "stolen":
		return []
	var prompt := "Take back your belongings" if g.phase == "dropped" else "Take back your belongings (%s left)" % _clock(time_left)
	return [{"key": "grave", "x": g.x, "z": g.z, "bias": -0.5, "reach": 2.4, "prompt": prompt, "run": func(): recover()}]


func recover() -> void:
	var g = state
	if g == null or g.phase == "stolen":
		return
	var inv = game.inventory
	var dropped := 0
	for st in g.items:
		if not DB.items.has(st.get("id", "")):
			continue
		if not _put_back(st):
			game.loot.drop_at(st, game.player.position)
			dropped += 1
	if g.coins > 0:
		inv.add_coins(int(g.coins), "from your grave")
	inv._changed()
	_clear()
	game.events.emit("log", {"text": "You take back what was yours.%s" % (" Your bags are full: the rest lies at your feet." if dropped else ""), "kind": "loot"})


## into the first free slot that takes it, keeping its rolls and wear;
## plain stacks top up what you already carry first
func _put_back(st: Dictionary) -> bool:
	var inv = game.inventory
	if st.get("rolls") == null and st.get("dur") == null:
		var left: int = inv._insert(st.id, int(st.count))
		if left <= 0:
			return true
		st = st.duplicate()
		st.count = left
	for loc in inv._slots_for(st.id):
		if inv.get_at(loc) == null and inv.accepts(loc, st):
			inv._put(loc, st)
			return true
	return false


func _clear() -> void:
	var ws = game.world_state
	var g = ws.grave
	if g != null:
		for id in g.scavengers:
			var e = game.enemies.by_id(id)
			if e != null:
				e.group.queue_free()
				game.enemies.list.erase(e)
			ws.defeated.erase(id)
			ws.corpses.erase(id)
	ws.grave = null
	_hide()


# ----------------------------------------------------------------- load
## after the world is built (a new game or a load)
func spawn() -> void:
	_hide()
	var g = state
	if g == null:
		return
	if g.phase == "stolen":
		_spawn_scavengers()
	else:
		_show()


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# --------------------------------------------------------------- looks
func _show() -> void:
	_hide()
	var g: Dictionary = state
	mesh = Node3D.new()
	mesh.name = "Grave"
	var stone := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("6b6a66") if g.phase == "grave" else Color("6a5238")
	var bm := BoxMesh.new()
	if g.phase == "grave":
		bm.size = Vector3(0.55, 0.8, 0.14)
		stone.position.y = 0.4
	else:
		# the scavengers' bundle: a rough sack
		bm.size = Vector3(0.5, 0.35, 0.4)
		stone.position.y = 0.18
	bm.material = mat
	stone.mesh = bm
	mesh.add_child(stone)
	if g.phase == "grave":
		var mound := MeshInstance3D.new()
		var mm := BoxMesh.new()
		mm.size = Vector3(0.9, 0.12, 1.6)
		var dirt := StandardMaterial3D.new()
		dirt.albedo_color = Color("4a3a2a")
		mm.material = dirt
		mound.mesh = mm
		mound.position = Vector3(0, 0.06, 0.85)
		mesh.add_child(mound)
	var light := OmniLight3D.new()
	light.light_color = Color("e8c070")
	light.light_energy = 1.6
	light.omni_range = 4.0
	light.position.y = 1.0
	mesh.add_child(light)
	mesh.position = Vector3(g.x, Terrain.height_at(g.x, g.z), g.z)
	game.scene.add_child(mesh)


func _hide() -> void:
	if mesh != null and is_instance_valid(mesh):
		mesh.queue_free()
	mesh = null

class_name Enemies
extends RefCounted
## Spawns and updates the region's enemies (src/systems/enemies.js). A defeat
## lives in the world state and is saved; enemies whose type has a `respawn`
## time come back at their spawn point once it has passed, WoW style. Those
## with 0 (bosses, story enemies) stay dead.

var game
var list: Array = []
## Enemies out of their `activeHours` (night things by day): not in the world
## at all until their hours come round again, when they wait at home, whole.
var dormant: Array = []
var _hours_check := 0.0


func _init(g) -> void:
	game = g


func spawn_all() -> void:
	clear()
	var ws = game.world_state
	for spawn in Layout.enemies:
		var corpse = ws.corpses.get(spawn.id)
		if ws.is_defeated(spawn.id) and corpse == null:
			continue
		var e := Enemy.new(game, spawn)
		if ws.is_defeated(spawn.id):
			# a body from a saved game, still waiting to be looted
			e.position = Vector3(corpse.x, Terrain.height_at(corpse.x, corpse.z), corpse.z)
			e.dead = true
			e.health = 0
			e.state = "dead"
			e.corpse = true
			e.rig.die()
			e.rig.death = 2.0
			e._sync()
		list.append(e)
		_show(e, e.position.distance_squared_to(game.player.position))


func clear() -> void:
	for e in list + dormant:
		e.group.queue_free()
	list = []
	dormant = []


func by_id(id: String):
	for e in list:
		if e.id == id:
			return e
	return null


func reset_survivors() -> void:
	for e in list:
		e.reset()


## after the player dies: only the enemies that were fighting them go back
## to their posts, whole again (as in WoW); the rest of the world stays as it is
func reset_engaged() -> void:
	for e in list:
		if e.state != "idle":
			e.reset()


## The simulation and the drawing are separate: every enemy's AI runs from
## its own position and state (an idle one far from anyone waits, as it
## always has), and its body is in the scene only near the player or while
## it is fighting (WorldStream.VIEW_IN / VIEW_OUT). A multiplayer server
## would run update() for every enemy near any player and attach no bodies.
var _tick := 0
const CLOSE := 45.0 ## idle ones within this (Enemy.ANIMATE_RANGE) update every frame
const FAR_SKIP := 20 ## idle ones past 180 m are measured again after this many frames
const FAR_EVERY := 6 ## idle ones further out update every 6th frame


func update(dt: float) -> void:
	var player = game.player
	_respawn(dt)
	_hours_check -= dt
	if _hours_check <= 0.0:
		_hours_check = 1.0
		_keep_hours()
	_tick += 1
	for e in list:
		# idle ones far beyond the view are not even measured every frame:
		# the player cannot cover the gap to VIEW_IN in FAR_SKIP frames
		if e.far_skip > 0 and e.state == "idle":
			e.far_skip -= 1
			continue
		var d2: float = e.position.distance_squared_to(player.position)
		var near: bool = d2 < 180.0 * 180.0
		if not near and e.state == "idle" and e.group.get_parent() == null:
			e.far_skip = FAR_SKIP
		_show(e, d2)
		if e.state != "idle" or (d2 < CLOSE * CLOSE and e.group.get_parent() != null):
			e.update(dt + e.idle_dt, player)
			e.idle_dt = 0.0
		elif near:
			# idle and past what the camera shows (and far past any aggro
			# reach): looked at a few times a second, with the time saved up,
			# the way MMO servers tick the mobs nobody is near. Staggered so
			# they do not all wake on the same frame.
			e.idle_dt += dt
			if (_tick + e.get_instance_id()) % FAR_EVERY == 0:
				e.update(e.idle_dt, player)
				e.idle_dt = 0.0
	_separate()
	# a body with loot stays down until looted; then it sinks away
	for i in range(list.size() - 1, -1, -1):
		var e = list[i]
		if not e.dead:
			continue
		if e.corpse and e.rig.death > 2.0:
			e.rig.death = 2.0
		if not e.corpse and e.rig.death > 5.5:
			e.group.queue_free()
			list.remove_at(i)


## put an enemy's body in the scene, or take it out, by distance
func _show(e, d2: float) -> void:
	var shown: bool = e.group.get_parent() != null
	var want: bool = e.state != "idle" or d2 < WorldStream.VIEW_IN * WorldStream.VIEW_IN \
		or (shown and d2 < WorldStream.VIEW_OUT * WorldStream.VIEW_OUT)
	if want == shown:
		return
	if want:
		game.scene.add_child(e.group)
	else:
		e.group.get_parent().remove_child(e.group)


## bodies in the scene now (checks and the F3 readout)
func shown_count() -> int:
	var n := 0
	for e in list:
		if e.group.get_parent() != null:
			n += 1
	return n


## Night things go at dawn and come back at dusk (`activeHours`, by the world
## clock). One that is fighting finishes first; a body stays to be looted.
func _keep_hours() -> void:
	var h: float = game.world_state.hour
	for e in list.duplicate():
		if e.active_hours != null and e.alive and e.state == "idle" and not DayNight.in_hours(h, e.active_hours):
			list.erase(e)
			dormant.append(e)
			if e.group.get_parent():
				e.group.get_parent().remove_child(e.group)
	for e in dormant.duplicate():
		if DayNight.in_hours(h, e.active_hours):
			dormant.erase(e)
			e.reset()
			list.append(e)
			_show(e, e.position.distance_squared_to(game.player.position))


func _respawn(dt: float) -> void:
	var ws = game.world_state
	ws.time += dt
	for id in ws.respawn_at.keys():
		if ws.time < ws.respawn_at[id]:
			continue
		ws.respawn_at.erase(id)
		var spawn = Layout.enemy_spawn(id)
		if spawn == null:
			continue
		# an unlooted body goes when its enemy comes back
		var old = by_id(id)
		if old:
			old.group.queue_free()
			list.erase(old)
		ws.corpses.erase(id)
		ws.defeated.erase(id)
		var e := Enemy.new(game, spawn)
		# back from a respawn, it lets you be for a moment (Dan, 2026-11-04)
		e.calm = DB.CONFIG.chase.spawnGrace
		list.append(e)
		game.scene.add_child(e.group)
		game.events.emit("enemyRespawned", {"enemy": e})


func _separate() -> void:
	# only bodies in view can be seen to overlap; idle ones far off stand still
	var pp: Vector3 = game.player.position
	# (idle ones past CLOSE are off camera and barely shuffle)
	var view2 := CLOSE * CLOSE
	var living := []
	for e in list:
		if e.alive and (e.state != "idle" or e.position.distance_squared_to(pp) < view2):
			living.append(e)
	# sweep along x: once the next enemy is further off in x than any two
	# could reach, none after it can touch this one (was every pair: 5 ms
	# a frame for 85 enemies)
	living.sort_custom(func(a, b): return a.position.x < b.position.x)
	var n := living.size()
	var reach := 0.0
	for e in living:
		reach = maxf(reach, e.radius)
	reach *= 2
	for i in n:
		var a = living[i]
		# the training dummy is planted: whoever bumps it does all the moving
		var a_dummy: bool = a.cfg.get("dummy", false)
		for j in range(i + 1, n):
			var b = living[j]
			var dx: float = b.position.x - a.position.x
			if dx >= reach:
				break
			var mn: float = a.radius + b.radius
			if absf(dx) >= mn or absf(b.position.z - a.position.z) >= mn:
				continue
			var r := push_apart(a.position, a.radius, b.position, b.radius, 1.0 if a_dummy else 0.0 if b.cfg.get("dummy", false) else 0.5)
			a.position = r[0]
			b.position = r[1]
		# the player walks straight through enemies: no shove either way (Dan, 2026-11-04)


## Move two circles apart; `bias` is the share of the correction given to b.
## Returns the two positions.
static func push_apart(pa: Vector3, ra: float, pb: Vector3, rb: float, bias: float) -> Array:
	var dx := pb.x - pa.x
	var dz := pb.z - pa.z
	var mn := ra + rb
	var d2 := dx * dx + dz * dz
	if d2 >= mn * mn or d2 == 0:
		return [pa, pb]
	var d := sqrt(d2)
	var push := mn - d
	pa.x -= (dx / d) * push * (1 - bias)
	pa.z -= (dz / d) * push * (1 - bias)
	pb.x += (dx / d) * push * bias
	pb.z += (dz / d) * push * bias
	return [pa, pb]

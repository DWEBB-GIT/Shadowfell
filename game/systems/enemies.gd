class_name Enemies
extends RefCounted
## Spawns and updates the region's enemies (src/systems/enemies.js). A defeat
## lives in the world state and is saved; enemies whose type has a `respawn`
## time come back at their spawn point once it has passed, WoW style. Those
## with 0 (bosses, story enemies) stay dead.

var game
var list: Array = []


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
		game.scene.add_child(e.group)


func clear() -> void:
	for e in list:
		e.group.queue_free()
	list = []


func by_id(id: String):
	for e in list:
		if e.id == id:
			return e
	return null


func reset_survivors() -> void:
	for e in list:
		e.reset()


func update(dt: float) -> void:
	var player = game.player
	_respawn(dt)
	for e in list:
		e.update(dt, player)
	_separate()
	# a body with loot stays down until looted; then it sinks away
	for e in list.duplicate():
		if e.dead and e.corpse and e.rig.death > 2.0:
			e.rig.death = 2.0
		if e.dead and not e.corpse and e.rig.death > 5.5:
			e.group.queue_free()
			list.erase(e)


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
		list.append(e)
		game.scene.add_child(e.group)
		game.events.emit("enemyRespawned", {"enemy": e})


func _separate() -> void:
	var player = game.player
	var living := list.filter(func(e): return e.alive)
	for i in living.size():
		var a = living[i]
		# the training dummy is planted: whoever bumps it does all the moving
		for j in range(i + 1, living.size()):
			var b = living[j]
			var r := push_apart(a.position, a.radius, b.position, b.radius, 1.0 if a.cfg.get("dummy") else 0.0 if b.cfg.get("dummy") else 0.5)
			a.position = r[0]
			b.position = r[1]
		if not player.dead:
			var r := push_apart(player.position, player.radius, a.position, a.radius, 0.0 if a.cfg.get("dummy") else 0.85)
			player.position = r[0]
			a.position = r[1]


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

extends SceneTree
## Dan's 2026-11-09 melee pass: a swing reaches a mob from a step away (lag
## allowance), and pushing back towards a foe you walked past turns you to
## face it first (then you can walk on through it: bodies are not solid):
##   godot --headless --path . --script res://game/tests/melee_reach_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_melee_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Reach", "warden")
		game.enter_world(made.character.id)
	if frame <= 2:
		return false
	if t0 == 0:
		if game.hud.modal == "loading" or game.hud.blocks_gameplay:
			if frame > 3000:
				check(false, "the world loads")
				quit(1)
			return false
		t0 = frame
		game.set_process(false)
		_run()
		print("melee reach checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _run() -> void:
	var dt := 1.0 / 60.0
	var pl = game.player
	var tg = game.targeting
	var foe = null
	for e in game.enemies.list:
		if e.alive and not e.protected and not game.law.protected(e):
			foe = e
			break
	check(foe != null, "found a foe")
	if foe == null:
		return
	var at: Vector3 = foe.position
	# a body and a half away from the mob's edge still counts as in reach
	pl.position = at + Vector3(foe.radius + 1.8, 0, 0)
	pl.moving = false
	tg.engage(foe)
	tg.target_moving = false
	check(tg.target_in_reach, "a swing reaches from %.1f m (reach %.2f m)" % [pl.position.distance_to(at), Targeting.melee_reach(foe)])
	pl.position = at + Vector3(Targeting.melee_reach(foe) + 0.3, 0, 0)
	check(not tg.target_in_reach and tg.in_reach(DB.attack.impactGrace), "a blow already begun lands a little beyond reach")
	# walked past: the foe is behind, 1.4 m off; push back towards it
	pl.position = at + Vector3(1.4, 0, 0)
	pl.facing = atan2(1.0, 0.0) # facing +x, away from it
	var start: Vector3 = pl.position
	var steps := 0
	while not pl.facing_point(at.x, at.z, 30) and steps < 60:
		pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
		steps += 1
	check(pl.facing_point(at.x, at.z, 30), "pressing towards it turns you to it (%d frames)" % steps)
	check(Vector2(pl.position.x - start.x, pl.position.z - start.z).length() < 0.05, "on the spot, not walking on past it")
	for i in 30:
		pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
	check(pl.position.x < at.x, "and holding the key you walk on through its body (bodies are not solid, %.2f)" % (pl.position.x - at.x))
	# moving away is untouched
	var was: float = pl.position.x
	pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
	check(pl.position.x < was, "walking on away from it moves you at once")
	# Lost Ark / D4 facing (Dan 2026-11-09): standing, a swing snaps you to it
	pl.position = at + Vector3(1.6, 0, 0)
	pl.facing = atan2(1.0, 0.0)
	pl.moving = false
	pl.pending = null
	pl.cooldowns.attack = 0.0
	check(pl.try_strike(at), "standing with the foe behind you, a swing still starts")
	check(pl.facing_point(at.x, at.z, 10), "and turns you to face it at once")
	# running away, auto attack does not turn you back or hold you
	pl.pending = null
	pl.cooldowns.attack = 0.0
	pl.facing = atan2(1.0, 0.0)
	pl.moving = true
	check(not pl.try_strike(at), "running away, auto attack does not swing at a foe behind you")
	check(pl.root == 0.0, "and never roots you")
	# an ability pressed on the move snaps you round and holds you briefly
	pl.square_up(at.x, at.z)
	check(pl.facing_point(at.x, at.z, 10) and pl.root > 0.0, "an attack used on the move faces the foe and roots you (%.2f s)" % pl.root)
	var p0: Vector3 = pl.position
	pl.update(dt, {"move": {"x": 1.0, "z": 0.0}, "actions": {}})
	var slid := Vector2(pl.position.x - p0.x, pl.position.z - p0.z).length()
	check(slid < 0.01, "rooted, you do not move (%.3f m)" % slid)
	for i in 30:
		pl.update(dt, {"move": {"x": 1.0, "z": 0.0}, "actions": {}})
	check(pl.position.x > p0.x + 0.5, "then you run on")

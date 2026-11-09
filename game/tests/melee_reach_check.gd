extends SceneTree
## Dan's 2026-11-09 melee pass: a swing reaches a mob from a step away (lag
## allowance), and pushing back towards a foe you walked past turns you to
## face it without carrying you through it:
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
	var d: float = Vector2(pl.position.x - at.x, pl.position.z - at.z).length()
	check(d >= pl.radius + foe.radius and pl.position.x > at.x, "and holding the key you stop at its body (%.2f m), never through it" % d)
	check(pl.facing_point(at.x, at.z, DB.attack.coneDegrees / 2.0), "still facing it to swing")
	# moving away is untouched
	pl.update(dt, {"move": {"x": 1.0, "z": 0.0}, "actions": {}})
	check(pl.position.x > at.x + d, "stepping away moves you at once")

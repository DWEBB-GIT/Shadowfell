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
	# walked past: the foe is behind, 1.4 m off; push back towards it. As
	# in Diablo 3 / Lost Ark you set off at once and turn as you go: no
	# turn-on-the-spot stop (Dan, 2026-11-11)
	pl.position = at + Vector3(1.4, 0, 0)
	pl.facing = atan2(1.0, 0.0) # facing +x, away from it
	var start: Vector3 = pl.position
	pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
	check(start.x - pl.position.x > DB.CONFIG.player.speed * dt * 0.9, "pressing back towards it moves you the first frame")
	var steps := 1
	while not pl.facing_point(at.x, at.z, 30) and steps < 60:
		pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
		steps += 1
	check(steps <= 8, "and you face it within %d frames" % steps)
	for i in 30:
		pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {}})
	check(pl.position.x < at.x, "and holding the key you walk on through its body (bodies are not solid, %.2f)" % (pl.position.x - at.x))
	# left button held (mouse aim) walking past a foe at your side
	pl.position = at + Vector3(1.4, 0, 0)
	pl.facing = atan2(0.3, 1.0)
	var walk := Vector2(-1.0, 0.6).normalized()
	var cursor: Vector3 = pl.position + Vector3(walk.x, 0, walk.y) * 6.0
	start = pl.position
	for i in 30:
		pl.update(dt, {"move": {"x": walk.x, "z": walk.y}, "actions": {}, "faceAim": cursor})
	check(Vector2(pl.position.x - start.x, pl.position.z - start.z).length() > 1.0, "holding the left button you turn and walk on (%.2f m)" % Vector2(pl.position.x - start.x, pl.position.z - start.z).length())
	# click to move, the left button held after clicking a foe (Diablo 3):
	# on the foe in reach you stand and fight; dragged off it you walk to
	# the cursor (it used to leave you stuck in place, Dan 2026-11-11)
	pl.position = at + Vector3(1.6, 0, 0)
	tg.engage(foe)
	game.input.mouse.leftHeld = true
	game.move_to = {"follow": foe, "reach": 0.0, "hold": "left"}
	var on_foe: Vector2 = game.camera.unproject_position(at)
	game.input.mouse.x = on_foe.x
	game.input.mouse.y = on_foe.y
	check(game._click_move({"x": 0.0, "z": 0.0}, dt) == null and game.move_to != null, "held on the foe in reach: stand and swing, the hold stays live")
	var away: Vector3 = pl.position + Vector3(0, 0, 8)
	var off_foe: Vector2 = game.camera.unproject_position(away)
	game.input.mouse.x = off_foe.x
	game.input.mouse.y = off_foe.y
	var go = game._click_move({"x": 0.0, "z": 0.0}, dt)
	check(go != null and go.z > 0.8, "dragged off the foe: you walk to the cursor (%s)" % str(go))
	game.input.mouse.x = on_foe.x
	game.input.mouse.y = on_foe.y
	check(game._click_move({"x": 0.0, "z": 0.0}, dt) != null and not game.move_to.has("follow"), "once dragged off, the cursor back over the foe does not plant you again")
	# a blow landing on the move never freezes your stride (no hit-stop on you)
	pl.rig.held = 0.0
	pl.moving = true
	game.events.emit("enemyHit", {"enemy": foe, "damage": 5, "kind": "strike", "swing": true})
	check(pl.rig.held == 0.0, "a blow on the move does not hold your body still")
	pl.moving = false
	game.events.emit("enemyHit", {"enemy": foe, "damage": 5, "kind": "strike", "swing": true})
	check(pl.rig.held > 0.0, "standing, a blow still holds you a moment")
	pl.rig.held = 0.0
	game.input.mouse.leftHeld = false
	game.move_to = null
	# a right click on a foe behind you, standing: a quick turn, then swings
	pl.position = at + Vector3(1.6, 0, 0)
	pl.facing = atan2(1.0, 0.0)
	pl.face_goal = foe
	var turn_frames := 0
	while pl.face_goal != null and turn_frames < 60:
		pl.update(dt, {"move": {"x": 0.0, "z": 0.0}, "actions": {}})
		turn_frames += 1
	check(pl.facing_point(at.x, at.z, 5) and turn_frames <= 8, "a right click turns you to a foe behind you (%d frames)" % turn_frames)
	# no aim assist, no forced snap (Dan 2026-11-11)
	pl.moving = false
	pl.pending = null
	pl.cooldowns.attack = 0.0
	pl.position = at + Vector3(1.6, 0, 0)
	pl.facing = atan2(1.0, 0.0)
	check(not pl.try_strike(at), "a foe right behind you is not hit until you turn")
	check(not pl.facing_point(at.x, at.z, 90), "and you are not snapped round to it")
	pl.facing = atan2(-1.0, 0.0) + deg_to_rad(30)
	check(pl.try_strike(at), "a foe roughly ahead is hit")
	check(not pl.facing_point(at.x, at.z, 20), "and nothing nudges you onto it (no aim assist)")
	pl.pending = null
	pl.cooldowns.attack = 0.0
	pl.facing = atan2(-1.0, 0.0) + deg_to_rad(70)
	check(pl.try_strike(at) and not pl.facing_point(at.x, at.z, 45), "off to the side but in front: hit, not turned")
	# running straight through a foe while swinging: facing holds, full speed
	pl.pending = null
	pl.cooldowns.attack = 0.0
	pl.position = at + Vector3(3.0, 0, 0.3)
	pl.facing = atan2(-1.0, 0.0)
	tg.engage(foe)
	var f0: float = pl.facing
	var x0: float = pl.position.x
	var wobble := 0.0
	for i in 40:
		pl.update(dt, {"move": {"x": -1.0, "z": 0.0}, "actions": {"strike": true}, "aim": {"x": at.x, "z": at.z}})
		wobble = maxf(wobble, absf(angle_difference(pl.facing, f0)))
	check(wobble < 0.01, "running through a foe while attacking, facing never flicks (%.3f rad)" % wobble)
	check(x0 - pl.position.x > DB.CONFIG.player.speed * 40 * dt * 0.9, "and you keep full speed through it")
	# turning is quick: left to right in a few frames
	pl.pending = null
	pl.position = at + Vector3(30, 0, 30)
	tg.select(null)
	pl.facing = atan2(-1.0, 0.0)
	var frames := 0
	while absf(angle_difference(pl.facing, atan2(1.0, 0.0))) > 0.01 and frames < 60:
		pl.update(dt, {"move": {"x": 1.0, "z": 0.0}, "actions": {}})
		frames += 1
	check(frames <= 8, "running left then right turns you round in %d frames" % frames)

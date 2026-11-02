extends SceneTree
## Dan's 2026-11-02 combat feel batch: a running hop carries the player over
## a fence, low props are measured as jumpable, jumping and landing kick up
## dust, and blows bleed red (the undead throw bone chips, never a yellow flash):
##   godot --headless --path . --script res://game/tests/combat_feel_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_feel_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Feel Tester", "warden")
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
		print("combat feel checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _named(n: String) -> int:
	return game.fx.items.filter(func(it): return it.tag == n).size()


func _run() -> void:
	var pl = game.player
	var dt := 1.0 / 60.0
	# a fence across the path, 2 m ahead: walking stops at it...
	var start: Vector3 = pl.position
	var row_x: float = start.x + 2.0
	for i in 7:
		game.collision.add(row_x, start.z - 1.5 + i * 0.5, 0.3, false, 1.05)
	var walk := {"move": {"x": 1.0, "z": 0.0}, "actions": {}}
	for i in 120:
		pl.update(dt, walk)
	check(pl.position.x < row_x, "walking into the fence stops at it (x %.2f, fence %.2f)" % [pl.position.x, row_x])
	# ...a hop from a run-up carries you over
	pl.position = start
	pl._reset_jump()
	var dust_before := _named("JumpDust")
	var hop := {"move": {"x": 1.0, "z": 0.0}, "actions": {}, "jump": false}
	var jumped := false
	for i in 120:
		hop.jump = not jumped and pl.position.x > row_x - 1.6
		if hop.jump:
			jumped = true
		pl.update(dt, hop)
	check(pl.position.x > row_x + 0.5, "a running hop clears the fence (x %.2f, fence %.2f)" % [pl.position.x, row_x])
	check(_named("JumpDust") > dust_before, "jumping and landing kick up dust (%d, %d)" % [dust_before, _named("JumpDust")])

	# props measured from their models: a crate is low, a pine is not
	var low := 0
	for c in game.collision.circles:
		if c.h < INF:
			low += 1
	check(low > 20, "low props (fences, crates, graves) can be hopped (%d circles)" % low)

	# blood: a bandit bleeds red, the undead throw chips, nobody gets a yellow flash
	game.settings.set_value("bloodEffects", true)
	var bandit = null
	var undead = null
	for e in game.enemies.list:
		var kind: String = Fx.blood_of(e)
		if bandit == null and kind == "red" and not e.cfg.get("dummy"):
			bandit = e
		if undead == null and kind == "bone":
			undead = e
	check(bandit != null and undead != null, "found a living foe and an undead one")
	if bandit and undead:
		game.events.emit("enemyHit", {"enemy": bandit, "damage": 5, "kind": "strike", "swing": false})
		check(_named("BloodDroplet") >= 8, "a blow on the living throws a spray of blood (%d)" % _named("BloodDroplet"))
		check(_named("BloodSplat") >= 1, "and leaves a splash on the ground")
		var yellow: bool = game.fx.items.any(func(it):
			var m = it.obj.get("material_override")
			return it.tag == "HitContact" and m and m.albedo_color.b < m.albedo_color.r * 0.9)
		check(not yellow, "the contact pop is white, not yellow")
		var reds := _named("BloodDroplet")
		game.events.emit("enemyHit", {"enemy": undead, "damage": 5, "kind": "strike", "swing": false})
		check(_named("BloodDroplet") == reds and _named("HitChip") > 0, "the undead throw bone chips, not blood")
	for i in 400:
		game.fx.update(dt)
	check(_named("BloodSplat") == 0 and _named("BloodDroplet") == 0 and _named("JumpDust") == 0, "it all fades away")

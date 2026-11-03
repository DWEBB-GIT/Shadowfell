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
	# a crit jolts the body back without moving the creature
	if bandit:
		for i in 60:
			bandit.rig.update(dt, 0.0)
		var at: Vector3 = bandit.position
		var model_at: Vector3 = bandit.rig.model.position
		game.events.emit("enemyHit", {"enemy": bandit, "damage": 5, "crit": true, "kind": "strike", "swing": true})
		check(bandit.rig.model.position.distance_to(model_at) > 0.1, "a crit jolts the body back")
		check(bandit.position == at, "but the enemy itself does not move")
		for i in 60:
			bandit.rig.update(dt, 0.0)
		check(bandit.rig.model.position.distance_to(model_at) < 0.01, "and it settles back")
	# area blows and kills weigh more; each foe sounds of what it is made of
	if bandit and undead:
		check(AudioSystem.material_of(undead) == "bone" and AudioSystem.material_of(bandit) == "flesh", "blows sound of bone on the undead, flesh on the living")
		game.shake = 0.0
		game.events.emit("burst", {"id": "", "position": bandit.position, "radius": 4.0, "hits": [bandit, undead], "school": "holy"})
		check(game.shake > DB.CONFIG.impact.shake and bandit.rig.held > 0 and undead.rig.held > 0, "an area blow on two kicks the camera and holds both")
		game.events.emit("enemyHit", {"enemy": bandit, "damage": 5, "kind": "spell", "school": "fire"})
		game.shake = 0.0
		bandit.position = game.player.position + Vector3(2, 0, 0)
		game.events.emit("enemyDefeated", {"enemy": bandit})
		check(game.shake > 0, "a kill kicks the camera")

	# the spell queue covers the end of a cast, not only the global cooldown
	var sp = game.spells
	pl.casting = {"id": "testCast", "t": 0.8, "total": 1.0, "channel": false}
	sp.queued = null
	sp.try_cast("cleave")
	check(sp.queued != null and sp.queued.id == "cleave", "a key pressed near the end of a cast is queued")
	pl.casting = {"id": "testCast", "t": 0.1, "total": 1.0, "channel": false}
	sp.queued = null
	sp.try_cast("cleave")
	check(sp.queued == null, "but not one pressed early in the cast")
	# the same spell again, pressed at 0.4 s left of its own cast, queues and
	# goes the moment the cast ends (Dan, 2026-11-02)
	pl.casting = {"id": "cleave", "t": 0.6, "total": 1.0, "channel": false}
	sp.queued = null
	sp.try_cast("cleave")
	check(sp.queued != null and sp.queued.id == "cleave", "the same spell pressed 0.4 s before its cast ends is queued")
	# pressed with 0.4 s of the global cooldown left, it survives to go off
	pl.casting = null
	sp.queued = null
	pl.cooldowns.gcd = 0.4
	var known := ""
	for sid in DB.spells:
		if game.skills.knows_ability(sid) and not DB.spells[sid].tuning.get("offGlobalCooldown", false):
			known = sid
			break
	pl.cooldowns.erase(known)
	sp.try_cast(known)
	var q_left: float = sp.queued.left if sp.queued != null else 0.0
	check(sp.queued != null and q_left > 0.4, "a key 0.4 s before the global cooldown ends is queued past it (%.2f s)" % q_left)
	sp.queued = null
	pl.cooldowns.gcd = 0.0
	check(DB.CONFIG.player.speed == 6.4, "the player runs at 7 yards (6.4 m) a second")

	# a spell with no stagger in its data never stops the enemy (Blight Bolt)
	var foe2 = null
	for e in game.enemies.list:
		if not e.dead and not e.cfg.get("dummy"):
			foe2 = e
			break
	if foe2:
		foe2.stagger = 0.0
		var at2: Vector3 = foe2.position
		var bolt: Dictionary = {"id": "testBolt", "kind": "cast", "school": "shadow", "name": "Test Bolt", "tuning": {"damageMin": 1, "damageMax": 1}}
		sp._damage(bolt, foe2, 1.0, "", 1.0, {"stagger": 0.12, "knockFrom": pl.position, "knockback": 0.3, "periodic": true})
		check(foe2.stagger == 0.0, "a spell without stagger in its data does not stagger (%.2f)" % foe2.stagger)
		for i in 10:
			foe2.update(dt, pl)
		check(foe2.knock.length() < 0.001, "nor shoves it")

	# a weapon swing never staggers; it pushes back a spell being cast
	if foe2:
		foe2.stagger = 0.0
		game.combat._player_hit(foe2, 1.0, {"stagger": 0.0, "knockFrom": pl.position, "knockback": 0.0}, {"swing": true, "hand": "main"})
		check(foe2.stagger == 0.0, "a weapon swing does not stagger")
		var tg := {"t": 1.0, "duration": 2.0}
		foe2.casting = {"kind": "circle", "telegraph": tg, "label": "Test", "interruptible": true}
		foe2.dead = false
		foe2.health = foe2.max_health
		foe2.hurt(5, {"stagger": 0.0})
		check(absf(tg.t - (1.0 - DB.cast_pushback)) < 0.001, "a blow pushes back a spell being cast (%.2f)" % tg.t)
		foe2.hurt(5, {"stagger": 0.0})
		foe2.hurt(5, {"stagger": 0.0})
		check(tg.t >= 0.0 and foe2.casting.pushbacks == DB.max_pushbacks, "up to %d times a cast" % DB.max_pushbacks)
		foe2.casting = null

	# taken a blow, the player's head snaps back; the body stays put
	var prig: Rig = pl.rig
	if prig.anim and not prig.anim.has_animation("Hit"):
		var head: int = prig._skel.find_bone("mixamorig_Head") if prig._skel else -1
		for i in 20:
			prig.update(dt, 0.0)
		if head < 0 and prig._skel:
			head = prig._skel.find_bone("mixamorig_Head")
		var before: Quaternion = prig._skel.get_bone_pose_rotation(head) if head >= 0 else Quaternion()
		var pos_before: Vector3 = pl.position
		prig.hit()
		for i in 4:
			prig.update(dt, 0.0)
		var during: Quaternion = prig._skel.get_bone_pose_rotation(head) if head >= 0 else Quaternion()
		check(head >= 0 and before.angle_to(during) > 0.1, "a blow snaps the head back (%.2f rad)" % before.angle_to(during))
		check(pl.position == pos_before, "and the player is not moved")
		for i in 40:
			prig.update(dt, 0.0)
		check(prig.snap < 0, "then it settles")

	for i in 400:
		game.fx.update(dt)
	check(_named("BloodSplat") == 0 and _named("BloodDroplet") == 0 and _named("JumpDust") == 0, "it all fades away")

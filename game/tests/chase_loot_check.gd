extends SceneTree
## Dan's 2026-11-02 combat feel follow-up: attacking on the move keeps the
## legs running (the swing plays on the upper body only), enemies keep up
## with a fleeing player and hit on the run, and coins fall to the ground
## as a purse to pick up:
##   godot --headless --path . --script res://game/tests/chase_loot_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_chase_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Chase Tester", "warden")
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
		print("chase and loot checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _run() -> void:
	var dt := 1.0 / 60.0
	var rig: Rig = game.player.rig
	check(rig.anim != null, "the player is an imported, skinned model")
	if rig.anim:
		# standing, the swing is the whole body's
		for i in 30:
			rig.update(dt, 0.0)
		rig.play("strike", 0.5, 0.4)
		rig.update(dt, 0.0)
		check(rig.clip == "Attack" and rig._upper == null, "standing, the whole body swings (%s)" % rig.clip)
		for i in 40:
			rig.update(dt, 0.0)
		# running, the legs keep the run and the arms swing
		for i in 30:
			rig.update(dt, 1.0)
		rig.play("strike", 0.5, 0.4)
		for i in 10:
			rig.update(dt, 1.0)
		check(rig.clip == "Run", "running, the legs keep the Run clip while attacking (%s)" % rig.clip)
		check(rig._upper != null and rig._upper.name == "Attack" and rig._upper_w > 0.5, "and the upper body plays the swing")
		check(rig._upper_bones.size() > 10 and rig._upper_bones.size() < rig._skel.get_bone_count() - 6, "the upper body is the waist up (%d of %d bones)" % [rig._upper_bones.size(), rig._skel.get_bone_count()])
		var leg := rig._skel.find_bone("mixamorig_LeftUpLeg")
		check(leg >= 0 and not rig._upper_bones.has(leg), "the legs are not part of it")
		for i in 60:
			rig.update(dt, 1.0)
		check(rig.action == null and rig._upper == null and rig.clip == "Run", "after the swing the body just runs on")
		# a flinch on the move is the upper body's too (models with a Hit clip)
		if rig.anim.has_animation("Hit"):
			rig.hit()
			rig.update(dt, 1.0)
			check(rig.clip == "Run" and rig._upper != null and rig._upper.name == "Hit", "a flinch on the run keeps the legs running")

	# enemies keep up and hit on the run
	var pl = game.player
	var foe = null
	for e in game.enemies.list:
		if not e.cfg.get("dummy") and e.cfg.speed > 0 and e.cfg.speed < DB.CONFIG.player.speed and not e.cfg.get("ranged") and not e.cfg.get("telegraph"):
			foe = e
			break
	check(foe != null, "found a slow melee foe")
	if foe:
		check(foe.chase_speed >= DB.CONFIG.player.speed, "chasing, it runs as fast as the player (%.1f vs %.1f)" % [foe.chase_speed, DB.CONFIG.player.speed])
		check(foe.move_speed < DB.CONFIG.player.speed, "but wanders at its own pace (%.1f)" % foe.move_speed)
		# the player 0.2 m beyond its standing reach, running away
		var reach: float = foe.cfg.meleeRange + pl.radius + foe.radius * 0.5
		pl.position = foe.position + Vector3(reach + 0.2, 0, 0)
		foe.state = "chase"
		foe.attack_timer = 0.0
		foe.since_struck = 0.0
		foe.update(dt, pl)
		check(foe.attack_timer > 0.0, "a foe in chase still swings at a player just out of reach")

	# coins fall as a purse on the ground
	var victim = null
	for e in game.enemies.list:
		if e.cfg.get("coins", 0) > 0 and not e.cfg.get("skin"):
			victim = e
			break
	check(victim != null, "found a foe that carries coins")
	if victim:
		var ws = game.world_state
		game.combat.on_enemy_defeated(victim)
		var pile = null
		for g in ws.ground:
			if g.id == Loot.COINS:
				pile = g
		check(pile != null and pile.count == int(victim.cfg.coins), "its coins drop to the ground (%s)" % str(pile))
		check(not ws.corpses.has(victim.id), "and the body keeps none")
		var save: Dictionary = game.save.serialize()
		var errs: Array = SaveManager.validate_save(save)
		check(errs.is_empty(), "a save with coins on the ground is valid %s" % str(errs))
		var entry = null
		for l in game.loot.active:
			if l.def.get("ground") == pile:
				entry = l
		check(entry != null and entry.group.get_child_count() > 0, "the purse lies in the world")
		var coins: int = game.inventory.coins
		if entry:
			check(game.loot.collect(entry), "picking it up works")
		check(game.inventory.coins == coins + int(victim.cfg.coins) and not ws.ground.has(pile), "and the coins go to the purse (%d)" % game.inventory.coins)

	check(AudioSystem.TRIM.get("step_dirt", 1.0) < 1.0 and AudioSystem.TRIM.get("panel", 1.0) < 1.0 and AudioSystem.TRIM.get("sheathe", 1.0) < 1.0, "footsteps, panels and sheathing are turned down")

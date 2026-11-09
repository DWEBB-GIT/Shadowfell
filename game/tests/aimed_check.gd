extends SceneTree
## Aimed combat (Settings: aimedCombat, a trial): swings and bolts go where
## you aim and can be dodged; the target only bends the aim near the cursor.
##   godot --headless --path . --script res://game/tests/aimed_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0
var foe = null
var hp0 := 0.0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		ProjectSettings.set_setting(Terrain.MAP_SETTING, "act1")
		Store.dir = "user://test_store_aimed"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Testaim", "warden")
		game.enter_world(made.character.id)
		check(not game.aimed_combat, "aimed combat is off by default")
		game.settings.set_value("aimedCombat", true)
		check(game.aimed_combat, "the setting turns aimed combat on")
	if frame <= 2:
		return false
	if t0 == 0:
		if game.hud.modal == "loading" or game.hud.blocks_gameplay:
			if frame > 3000:
				check(false, "the world loads")
				quit(1)
			return false
		t0 = frame
	var f := frame - t0
	if f == 1:
		game.random = func() -> float: return 0.5
		foe = game.enemies.list[0]
		# move every other enemy well away so only `foe` can be hit
		for e in game.enemies.list:
			if e != foe:
				e.position = foe.position + Vector3(200, 0, 200)
		var p: Vector3 = foe.position + Vector3(1.2, 0, 0)
		game.player.position = p
		game.player.facing = -PI / 2
		var c = game.combat
		check(c.aimed_strike_target(foe.position) == foe, "a swing aimed at a foe in reach hits it")
		check(c.aimed_strike_target(p + Vector3(3, 0, 0)) == null, "a swing aimed away from the foe whiffs")
		check(c.aimed_strike_target(p + Vector3(-3, 0, 1.0)) == foe, "a foe inside the arc is hit though the aim is a little off")
		# soft aim: the cursor near the target bends onto it; far off, it does not
		game.targeting.select(foe)
		game.player.position = foe.position + Vector3(8, 0, 0)
		game.raw_aim = foe.position + Vector3(0, 0, 1.5)
		check(game.aim_at(18).distance_to(foe.position) < 0.01, "with the cursor near your target the aim bends onto it")
		game.raw_aim = game.player.position + Vector3(0, 0, 6)
		check(game.aim_at(18).distance_to(foe.position) > 3, "with the cursor far from your target the aim goes to the cursor")
		game.targeting.clear()
		# a skill shot along the line hits; one aimed beside the foe misses
		hp0 = foe.health
		game.raw_aim = foe.position
		game.spells._skillshot(game.spells.tuned("arcaneBolt"))
		check(game.spells.shots.size() == 1, "a bolt in aimed combat is a skill shot")
		for i in 30:
			game.spells._update_shots(0.05)
		check(game.spells.shots.is_empty(), "the skill shot is done")
		check(foe.health < hp0 or not foe.alive, "a skill shot down the line hits the foe (%s -> %s)" % [hp0, foe.health])
		hp0 = foe.health
		game.raw_aim = game.player.position + Vector3(0, 0, 8)
		game.spells._skillshot(game.spells.tuned("arcaneBolt"))
		for i in 30:
			game.spells._update_shots(0.05)
		check(foe.health == hp0, "a skill shot aimed away misses (dodged)")
		# auto attack in aimed combat swings (hit or whiff) without errors
		game.player.position = foe.position + Vector3(1.2, 0, 0)
		game.targeting.engage(foe)
	elif f == 90:
		check(game.player.last_swing_at != null and game.player.last_swing_at > 0, "auto attack swings in aimed combat")
		game.settings.set_value("aimedCombat", false)
		print("aimed combat checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + what)

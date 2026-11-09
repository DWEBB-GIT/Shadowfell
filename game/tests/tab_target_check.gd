extends SceneTree
## Tab picks the closest enemy you face, or one right beside you first:
##   godot --headless --path . --script res://game/tests/tab_target_check.gd

var failures := 0
var game
var frame := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		ProjectSettings.set_setting(Terrain.MAP_SETTING, "act1")
		Store.dir = "user://test_store_tab"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
		return false
	if frame == 2:
		var made: Dictionary = game.roster.create("Testtab", "warden")
		game.enter_world(made.character.id)
		return false
	if game.hud.modal == "loading" or game.hud.blocks_gameplay:
		if frame > 3000:
			check(false, "the world loads")
			quit(1)
		return false
	var tg = game.targeting
	var p: Vector3 = game.player.position
	game.player.facing = 0.0 # facing +z
	var foes: Array = game.enemies.list.filter(func(e): return tg.targetable(e))
	check(foes.size() >= 3, "three enemies to test with")
	# everyone else far away, so only our three are in range
	for e in foes:
		e.position = p + Vector3(500, 0, 500)
	var ahead = foes[0]
	var beside = foes[1]
	var behind = foes[2]
	ahead.position = p + Vector3(0.5, 0, 8)
	beside.position = p + Vector3(0, 0, -2)
	behind.position = p + Vector3(0, 0, -6)
	var ahead_far = p + Vector3(0, 0, 9)
	tg.select(null)
	tg.cycle()
	check(tg.current == beside, "an enemy right beside you comes first, even behind")
	tg.cycle()
	check(tg.current == ahead, "then the one in front, before a nearer one behind")
	tg.cycle()
	check(tg.current == behind, "then the one behind")
	tg.cycle()
	check(tg.current == beside, "and round again")
	beside.position = p + Vector3(500, 0, 500)
	tg.select(null)
	tg.cycle()
	check(tg.current == ahead, "with nobody beside you, the one you face wins over a nearer one behind")
	ahead.position = ahead_far
	behind.position = p + Vector3(0, 0, -2.5)
	tg.select(null)
	tg.cycle()
	check(tg.current == behind, "someone at your back within reach wins")
	print("tab target check: %s" % ("PASS" if failures == 0 else "%d FAILED" % failures))
	quit(1 if failures > 0 else 0)
	return true


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: " + what)
	else:
		print("ok: " + what)

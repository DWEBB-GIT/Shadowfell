extends SceneTree
## Level, skills and position save together while playing, so a crash
## keeps them (Dan 2026-11-11: a crash lost a level and learned skills).
##   godot --headless --path . --script res://game/tests/autosave_check.gd

var game
var frame := 0
var failed := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_autosave"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Hale", "warrior")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.save.autosave_enabled = true
		game.save.autosave()
		var before: Dictionary = game.save.read().data
		# a level up and a learned skill, with nothing else saving
		game.progression.add_xp(game.progression.xp_to_next + 1)
		var level: int = game.progression.level
		var spells: Array = game.skills.spells.duplicate()
		game.player.place_at(before.player.position.x + 3.0, before.player.position.z, 0.0)
		for i in 5:
			game.step(0.1) # under the gap: not yet
		_ok(int(game.save.read().data.progression.level) == int(before.progression.level), "no save straight away")
		for i in 40:
			game.step(0.1)
		var after: Dictionary = game.save.read().data
		_ok(int(after.progression.level) == level and level > int(before.progression.level), "the level up is saved within seconds (%d)" % int(after.progression.level))
		_ok(after.spells == spells, "spells learned with it are saved too")
		_ok(absf(float(after.player.position.x) - (float(before.player.position.x) + 3.0)) < 0.5, "position saves in the same write")
		# periodic: something unsaved and no milestone is written within 15 s
		game.inventory.add_item("healing_draught", 1, true)
		for i in 160:
			game.step(0.1)
		_ok(JSON.stringify(game.save.read().data.inventory).contains("healing_draught"), "bags save on the timer")
		print("autosave_check: %s" % ("PASS" if failed == 0 else "%d FAILED" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		failed += 1
	print(("  ok   " if cond else "  FAIL ") + msg)

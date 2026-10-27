extends SceneTree
## A class spell taught by a trainer (archetypes.json `trained`): unknown
## until learned, locked below its level, learned for coins, kept in a save.
##   godot --headless --path . --script res://game/tests/trainer_spell_check.gd

var game
var frame := 0
var failed := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		# Mara teaches Warriors Rend from level 3 for 15 silver (test data only)
		DB.archetypes.warden.trained = [{"ability": "rend", "trainer": "mara", "level": 3, "cost": 15}]
		var made: Dictionary = game.roster.create("Trainer Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var sk = game.skills
		_ok(not sk.knows_ability("rend") and not ActionBar.bar_ability(game, "rend"), "a trained spell is unknown and not in the spellbook until learned")
		_ok(sk.knows_ability("cleave"), "the rest of the kit is known from the start")
		var row = game.dialogue.train_rows("mara").filter(func(r): return r.id == "spell:rend")
		_ok(row.size() == 1 and row[0].state == "locked", "below its level the trainer shows it locked: %s" % [row])
		_ok(not sk.learn_spell("rend"), "it cannot be learned below its level")
		game.progression.level = 3
		game.inventory.coins = 100
		row = game.dialogue.train_rows("mara").filter(func(r): return r.id == "spell:rend")
		_ok(row[0].state == "learn", "at its level it can be learned")
		DB.archetypes.warden.trained[0].quest = "missing_delivery"
		row = game.dialogue.train_rows("mara").filter(func(r): return r.id == "spell:rend")
		_ok(row[0].state == "locked" and row[0].need.begins_with("Requires") and not sk.learn_spell("rend"), "a quest gate locks it until the quest is handed in: %s" % [row])
		game.quests.done["missing_delivery"] = true
		_ok(game.dialogue.train_rows("mara").filter(func(r): return r.id == "spell:rend")[0].state == "learn", "handing the quest in unlocks it")
		_ok(sk.learn_spell("rend") and sk.knows_ability("rend") and game.inventory.coins == 85, "learning it costs its coins and teaches it")
		var data: Dictionary = game.save.serialize()
		_ok(data.spells == ["rend"], "the save keeps it")
		sk.reset()
		sk.apply_spells(data.spells)
		_ok(sk.knows_ability("rend"), "and a load gives it back")
		DB.archetypes.warden.erase("trained")
		print("trainer spell check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failed += 1
		print("  FAIL ", what)

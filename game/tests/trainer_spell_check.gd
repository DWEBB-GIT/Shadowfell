extends SceneTree
## A class spell taught by a trainer (archetypes.json `trained`): unknown
## until learned, locked below its level, learned for coins, kept in a save.
##   godot --headless --path . --script res://game/tests/trainer_spell_check.gd

var game
var frame := 0
var failed := 0
var real_trained: Array


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		ProjectSettings.set_setting(Terrain.MAP_SETTING, "act1")
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		real_trained = DB.archetypes.warden.trained.duplicate(true)
		# Mara teaches Warriors Rend from level 3 for 15 silver (test data only)
		DB.archetypes.warden.trained = [{"ability": "rend", "trainer": "mara", "level": 3, "cost": 15}]
		var made: Dictionary = game.roster.create("Trainer", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var sk = game.skills
		_ok(not sk.knows_ability("rend") and not ActionBar.bar_ability(game, "rend"), "a trained spell is unknown and not in the spellbook until learned")
		_ok(sk.knows_ability("heavyStrike"), "the first core ability is known from the start")
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
		# several trainers may teach the same spell (Dan, 2026-11-02)
		_ok(game.dialogue.train_rows("brask").filter(func(r): return r.id == "spell:rend").is_empty(), "a trainer not named does not teach it")
		DB.archetypes.warden.trained[0].trainers = ["brask"]
		_ok(game.dialogue.train_rows("brask").filter(func(r): return r.id == "spell:rend").size() == 1, "a second trainer in trainers teaches it too")
		_ok(game.dialogue.train_rows("mara").filter(func(r): return r.id == "spell:rend").size() == 1, "and the first still does")
		var fishing: Dictionary = DB.skills.fishing
		var had = fishing.get("trainers")
		fishing.trainers = ["brask"]
		_ok(game.dialogue.train_rows("brask").any(func(r): return r.id == "train:fishing"), "a skill can have more than one trainer")
		if had == null:
			fishing.erase("trainers")
		_ok(sk.learn_spell("rend") and sk.knows_ability("rend") and game.inventory.coins == 85, "learning it costs its coins and teaches it")
		var data: Dictionary = game.save.serialize()
		_ok(data.spells == ["rend"], "the save keeps it")
		sk.reset()
		sk.apply_spells(data.spells)
		_ok(sk.knows_ability("rend"), "and a load gives it back")
		# The production class has six core spells. Trainers offer six swaps.
		DB.archetypes.warden.trained = real_trained
		sk.reset()
		game.progression.level = 1
		_ok(DB.archetypes.warden.bar.filter(func(id): return sk.knows_ability(id)) == ["heavyStrike"], "a new Warrior begins with one core ability")
		_ok(game.dialogue.train_rows("brask").filter(func(r): return r.id.begins_with("spell:")).size() == 6, "Brask offers six Warrior swaps")
		_ok(not sk.knows_ability("brace") and not sk.learn_spell("brace"), "a later swap remains level locked")
		print("trainer spell check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failed += 1
		print("  FAIL ", what)

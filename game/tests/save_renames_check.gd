extends SceneTree
## Saves survive content edits (SaveManager.tidy_ids, data/meta/renames.json):
## an item, spell, quest or recipe that was renamed follows its rename, and
## one that was removed is dropped from the save instead of the whole
## character being refused.
##   godot --headless --path . --script res://game/tests/save_renames_check.gd

var game
var frame := 0
var failed := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_renames"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Rename", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.save.autosave_enabled = false
		var inv = game.inventory
		inv.add_item("healing_draught", 2, true)
		var spells: Array = game.action_bar.slots.filter(func(a): return typeof(a) == TYPE_STRING and DB.abilities.has(a))
		var spell: String = spells[0] if not spells.is_empty() else ""
		var quest: String = DB.quests.keys()[0]
		var data: Dictionary = game.save.serialize()
		_ok(SaveManager.validate_save(data).is_empty(), "a fresh save validates")

		# pretend these ids were renamed: the save still holds the old names
		SaveManager._renames = {"items": {"old_draught": "healing_draught"}, "abilities": {"old_spell": spell}, "quests": {"old_quest": quest}}
		var text := JSON.stringify(data)
		text = text.replace("\"healing_draught\"", "\"old_draught\"")
		var edited = JSON.parse_string(text)
		if spell != "":
			var i: int = edited.bar.find(spell)
			if i >= 0:
				edited.bar[i] = "old_spell"
		if typeof(edited.get("quests")) == TYPE_DICTIONARY:
			edited.quests.accepted = ["old_quest"]
		# and these were deleted outright
		edited.inventory.sockets[0].slots[edited.inventory.sockets[0].slots.size() - 1] = {"id": "gone_sword", "count": 1}
		edited.bar[edited.bar.size() - 1] = "gone_spell"
		edited.quests.done = ["gone_quest"]
		_ok(not SaveManager.validate_save(edited).is_empty(), "before tidying, the old save would be refused")

		Store.set_item(game.save.key, JSON.stringify(edited))
		var back: Dictionary = game.save.read()
		_ok(back.status == "ok", "the edited save loads: %s" % [back.get("errors", [])])
		if back.status == "ok":
			var d: Dictionary = back.data
			var flat := JSON.stringify(d)
			_ok(flat.contains("\"healing_draught\"") and not flat.contains("old_draught"), "a renamed item follows its rename")
			_ok(not flat.contains("gone_sword"), "a removed item is dropped")
			_ok(spell == "" or (d.bar.has(spell) and not d.bar.has("old_spell")), "a renamed spell stays on the bar")
			_ok(not d.bar.has("gone_spell"), "a removed spell leaves an empty button")
			_ok(d.quests.accepted == [quest], "a renamed quest stays in the log")
			_ok(d.quests.done.is_empty(), "a removed quest is dropped")
		SaveManager._renames = null
		_ok(SaveManager.rename_problems().is_empty(), "the real renames.json is sound")
		SaveManager._renames = {"items": {"healing_draught": "nope"}}
		_ok(SaveManager.rename_problems().size() == 2, "a rename of a live id to an unknown id is caught twice")
		SaveManager._renames = null
		return _end()
	return false


func _ok(cond: bool, msg: String) -> void:
	print(("ok   " if cond else "FAIL ") + msg)
	if not cond:
		failed += 1


func _end() -> bool:
	print("save renames check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)
	return true

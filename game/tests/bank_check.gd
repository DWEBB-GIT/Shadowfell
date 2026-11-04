extends SceneTree
## The bank (Bank): a banker by the start opens your vault; stacks move
## between bags and vault by right-click or drag, merge with what is there,
## quest items stay with you, and the vault saves with the character.
##   godot --headless --path . --script res://game/tests/bank_check.gd

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
		var made: Dictionary = game.roster.create("Bank", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.save.autosave_enabled = false
		var n = game.npcs.by_id("banker")
		_ok(n != null, "the banker is in the world")
		if n == null:
			return _end()
		var p: Vector3 = game.player.position
		_ok(Vector2(p.x - n.position.x, p.z - n.position.z).length() < 30, "and stands in the starting town")
		game.player.position = Vector3(n.position.x + 2, p.y, n.position.z)
		game.dialogue.open(n)
		var opts: Array = game.dialogue.page.options.map(func(o): return o.id)
		_ok(opts.has("bank"), "talking to them offers Open your bank")
		game.dialogue.choose("bank")
		_ok(game.bank.is_open and game.dialogue.npc == null, "which opens the vault")
		_ok(game.hud.items.bank_win.panel.visible, "and its window")
		var inv = game.inventory
		_ok(inv.bank.size() == int(DB.CONFIG.bank.slots), "the vault has %d slots" % inv.bank.size())
		# food stacks: deposit it, then a second lot merges into the same slot
		var food: String = inv.get_at("b:0:1").id
		var had: int = inv.count(food)
		_ok(inv.deposit("b:0:1"), "a bag stack goes into the vault")
		_ok(inv.count(food) == 0 and inv.bank[0] != null and inv.bank[0].id == food, "and leaves the bags")
		inv.add_item(food, 2, true)
		inv.deposit(inv._find(food))
		_ok(inv.bank[0].count == had + 2 and inv.bank[1] == null, "a second lot merges with it")
		_ok(inv.withdraw("v:0") and inv.count(food) == had + 2 and inv.bank[0] == null, "right-click brings it back")
		# drag: move() between bag and vault
		inv.add_item("healing_draught", 1, true)
		var from = inv._find("healing_draught")
		_ok(inv.move(from, "v:5").ok and inv.get_at("v:5").id == "healing_draught", "dragging into a vault slot works")
		# quest items stay with you
		var quest_id := ""
		for id in DB.items:
			if DB.items[id].get("quest"):
				quest_id = id
				break
		if quest_id != "":
			inv.add_item(quest_id, 1, true)
			_ok(not inv.deposit(inv._find(quest_id)), "a quest item cannot be banked")
		# saved and loaded with the character
		var saved: Dictionary = game.save.serialize()
		inv.bank[5] = null
		game.save.apply(saved)
		_ok(inv.get_at("v:5") != null and inv.get_at("v:5").id == "healing_draught", "the vault saves with the character")
		_ok(SaveManager.validate_save(saved).is_empty(), "and the save validates")
		# walking away shuts it
		game.player.position.x += 20
		game.bank.update()
		_ok(not game.bank.is_open, "walking away shuts the vault")
		return _end()
	return false


func _end() -> bool:
	print("bank check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)
	return true


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
	print(("  ok    " if cond else "  FAIL  ") + what)

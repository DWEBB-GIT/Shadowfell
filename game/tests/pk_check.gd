extends SceneTree
## PK points (Law, data/npcs/infamy.json `pk`), after Conquer Online:
## killing an innocent player adds points, red at 30, black at 100, striking
## an innocent makes you flash, points fade with time alive, and a red or
## black name drops worn gear onto the ground when they fall.
##   godot --headless --path . --script res://game/tests/pk_check.gd

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
		var made: Dictionary = game.roster.create("Pk", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.save.autosave_enabled = false
		var law = game.law
		var cfg: Dictionary = Law.pk_cfg()
		_ok(law.pk == 0 and law.pk_name == "white", "a new character has no PK points and a white name")
		var innocent := {"pk": 0, "flash": 0}
		law.pk_struck({"pk": 40, "flash": 0})
		_ok(law.flash == 0, "striking a red name does not make you flash")
		law.pk_struck(innocent)
		_ok(law.flash == float(cfg.flashSeconds), "striking an innocent makes you flash for %ss" % cfg.flashSeconds)
		_ok(law.nameplate_colour() == Color(cfg.nameplates.flashing), "and your name shows blue")
		_ok(law.aura != null and law.aura.id == "flashing", "with a Flashing entry on the buff row")
		law.update(float(cfg.flashSeconds) + 1)
		_ok(law.flash == 0, "flashing wears off")
		var inf0: float = law.infamy
		_ok(law.pk_killed({"pk": 0, "flash": 5}) == 0, "killing a flashing player costs nothing")
		_ok(law.pk_killed({"pk": 120, "flash": 0}) == 0, "killing a black name costs nothing")
		for i in 3:
			law.pk_killed(innocent)
		_ok(law.pk == 3 * int(cfg.perKill), "three innocents killed: %d PK points" % law.pk)
		_ok(law.pk_name == "red", "which makes a red name")
		_ok(law.nameplate_colour() == Color(cfg.nameplates.red), "and a red nameplate")
		var labels = game.hud.labels
		labels.update()
		_ok(labels.skull != null and labels.skull.visible, "and a skull over your head")
		var head: Vector2 = game.camera.unproject_position(game.player.position + Vector3(0, 2.15 * DB.CONFIG.player.visualScale, 0))
		_ok(labels.skull != null and labels.skull.position.y + labels.skull.size.y <= head.y, "above your head")
		_ok(absf(law.infamy - inf0 - 3 * float(cfg.infamy)) < 0.01, "each killing adds Infamy too")
		law.update(float(cfg.decay.seconds) + 0.5)
		_ok(law.pk == 29 and law.pk_name == "white", "points fade with time alive (29: white again)")
		labels.update()
		_ok(not labels.skull.visible, "and the skull goes")
		_ok(Law.pk_name_of(100) == "black" and Law.pk_fair_game(30, false) and not Law.pk_fair_game(29, false), "any client can tell a player's name from their points")
		# gear drops
		var inv = game.inventory
		var worn := func(): return inv.equipment.values().filter(func(s): return s != null).size()
		var before: int = worn.call()
		var ground: int = game.world_state.ground.size()
		_ok(law.pk_drop_gear().is_empty() and worn.call() == before, "a white name drops nothing")
		law.pk = 100
		_ok(law.pk_name == "black", "100 points: a black name")
		var guard = null
		for e in game.enemies.list:
			if Law.is_guard(e):
				guard = e
				break
		if guard != null:
			_ok(law.hostile(guard), "the watch attacks a black name on sight")
		var keep: float = cfg.drops.black
		cfg.drops.black = 1.0
		_ok(before >= 2, "the warden starts with %d worn pieces" % before)
		var dropped: Array = law.pk_drop_gear()
		cfg.drops.black = keep
		_ok(dropped.size() == int(cfg.drops.max), "a black name drops up to %d pieces (%d)" % [cfg.drops.max, dropped.size()])
		_ok(worn.call() == before - dropped.size(), "taken off the body")
		_ok(game.world_state.ground.size() == ground + dropped.size(), "and left on the world's ground for anyone")
		law.flash = 12
		var saved: Dictionary = law.serialize()
		law.apply(JSON.parse_string(JSON.stringify(saved)))
		_ok(law.pk == 100 and law.flash == 12, "PK points and flashing are saved with the character")
		return _end()
	return false


func _end() -> bool:
	print("pk check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)
	return true


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
	print(("  ok    " if cond else "  FAIL  ") + what)

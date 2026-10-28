extends SceneTree
## Miss chance (Dan, 2026-10-28): your level is your combat skill. 5% to
## miss a foe of your level, less below you, +5% a level above; accuracy
## takes it down; no range penalty; ticks never miss; a grey "Miss".
##   godot --headless --path . --script res://game/tests/miss_check.gd

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
		var made: Dictionary = game.roster.create("Miss Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		_run()
		print("miss check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		print("FAILED: ", what)


func _run() -> void:
	_ok(is_equal_approx(Stats.miss_chance(5, 5), 5.0), "5% against your own level")
	_ok(is_equal_approx(Stats.miss_chance(5, 4), 2.5), "2.5% one level below")
	_ok(Stats.miss_chance(5, 2) == 0.0, "never below 0")
	_ok(is_equal_approx(Stats.miss_chance(5, 7), 15.0), "+5% a level above")
	_ok(is_equal_approx(Stats.miss_chance(5, 7, 3), 12.0), "accuracy takes points off")
	_ok(Stats.miss_chance(1, 30) == DB.CONFIG.stats.missCap, "capped")

	var e = null
	for x in game.enemies.list:
		if x.alive and x.cfg.get("level", 1) == game.progression.level:
			e = x
			break
	_ok(e != null, "an even-level enemy to swing at")
	if e == null:
		return
	var numbers := []
	game.events.on("damageNumber", func(n): numbers.append(n))
	var hp: float = e.health
	game.random = func() -> float: return 0.0 # every roll misses
	var hit: Dictionary = game.combat._player_hit(e, 1.0, {"stagger": 0.0}, {"swing": true})
	_ok(hit.get("miss", false) and hit.amount == 0 and e.health == hp, "a low roll misses and does no harm")
	_ok(numbers.size() == 1 and numbers[0].kind == "miss", "a Miss number")
	game.random = func() -> float: return 0.99
	hit = game.combat._player_hit(e, 1.0, {"stagger": 0.0}, {"swing": true})
	_ok(not hit.get("miss", false) and hit.amount > 0, "a high roll lands")

	# accuracy from an elixir comes off the chance
	game.inventory.add_item("hawkeye_tincture", 1)
	game.boons.drink_elixir("hawkeye_tincture")
	_ok(is_equal_approx(game.stats.accuracy, 3.0), "the tincture gives 3% accuracy")
	_ok(is_equal_approx(Stats.miss_chance(1, 1, game.stats.accuracy), 2.0), "and takes it off the miss")
	game.random = func() -> float: return 0.025 # 2.5: would miss at 5%, lands at 2%
	hit = game.combat._player_hit(e, 1.0, {"stagger": 0.0}, {"swing": true})
	_ok(not hit.get("miss", false), "accurate enough to land")
	game.random = randf

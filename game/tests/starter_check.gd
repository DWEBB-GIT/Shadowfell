extends SceneTree
## A new character's kit (food, a drink for mana, no coins, utility bar),
## Return Home and Return to Camp with their 30 minute cooldowns, slow
## rested experience capped at 100%, and the level cap.
##   godot --headless --path . --script res://game/tests/starter_check.gd

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
		var made: Dictionary = game.roster.create("Kit Tester", "occultist")
		game.enter_world(made.character.id)
	elif frame == 3:
		var inv = game.inventory
		var bar: Array = game.action_bar.slots
		_ok(inv.coins == 0, "a new character has no coins")
		_ok(inv.count(ActionBar.STARTER_FOOD) == 5 and inv.count(ActionBar.STARTER_DRINK) == 5, "a mana class starts with 5 food and 5 drinks")
		_ok(bar.slice(6) == ["item:healing_draught", "item:trail_bread", "item:spring_water", "returnHome"], "the utility bar holds them and Return Home: %s" % [bar.slice(6)])
		# drinking restores mana while sitting
		game.resources.mana = 0
		var loc = null
		for l in inv.bag_locations():
			if inv.get_at(l) != null and inv.get_at(l).id == ActionBar.STARTER_DRINK:
				loc = l
		_ok(game.cooking.eat(loc) and game.player.eating != null, "a drink can be drunk")
		for i in 60:
			game.cooking.update(0.25)
		_ok(game.resources.mana >= 100, "drinking restores mana (%d)" % game.resources.mana)
		# Return Home needs a home
		_ok(not game.camp.portal_ok("home"), "no home: Return Home is refused")
		game.world_state.home = "inn:" + _innkeeper()
		_ok(game.camp.portal_ok("home"), "with a home it may be cast")
		game.camp.portal("returnHome", "home", 1800)
		var inn: Dictionary = game.afterlife.inn_point()
		_ok(game.player.position.distance_to(Vector3(inn.x, game.player.position.y, inn.z)) < 0.1, "Return Home takes you to the inn")
		game.player.cooldowns = Player.fresh_cooldowns()
		game.camp.update(0.0, 0.0)
		_ok(game.player.cooldowns.returnHome > 1790, "its cooldown outlasts a revive (%.0f)" % game.player.cooldowns.returnHome)
		var data: Dictionary = game.world_state.serialize()
		game.world_state.reset()
		game.world_state.apply(data)
		_ok(game.world_state.home != "" and game.world_state.portal_ready.has("returnHome"), "home and cooldown are saved")
		# Return to Camp
		game.world_state.camp = {"x": 10.0, "z": 10.0}
		game.camp.portal("returnToCamp", "camp", 1800)
		_ok(absf(game.player.position.x - 11.4) < 0.1, "Return to Camp takes you to the fire")
		# rested experience: slow, capped at 100%
		var prog = game.progression
		prog.rested = 0
		var cap: float = prog.xp_to_next
		var full: float = DB.CONFIG.camp.restedFullSeconds.camp
		prog.rested = cap * 0.5
		_ok(prog.rested_percent == 50, "rested shows as a percentage")
		prog.rested = cap * 2
		_ok(prog.rested_percent == 100, "and never more than 100%")
		_ok(full >= 600, "a full rest at camp takes %d s" % full)
		# the level cap
		prog.level = 99
		prog.xp = 0
		prog.add_xp(prog.xp_to_next + 500)
		_ok(prog.level == 100 and prog.xp == 0, "levels stop at 100")
		_ok(prog.add_xp(1000) == 0 and prog.level == 100, "no experience past the cap")
		print("starter check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _innkeeper() -> String:
	for id in DB.npcs:
		if DB.npcs[id].get("innkeeper"):
			return id
	return ""


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
	print(("  ok    " if cond else "  FAIL  ") + what)

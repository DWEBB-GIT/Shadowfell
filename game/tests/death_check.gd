extends SceneTree
## Death (Dan, 2026-10-27): your bags and coins wait in a grave, scavengers
## take them when its time runs out, killing them gives them back, and you
## come back wounded until an inn or a healer mends you.
##   godot --headless --path . --script res://game/tests/death_check.gd

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
		var made: Dictionary = game.roster.create("Grave Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		_run()
		print("death check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _die() -> void:
	game.player.take_damage(99999)
	game.on_player_death(null)
	game.release_spirit()


func _run() -> void:
	var inv = game.inventory
	var ws = game.world_state
	inv.add_coins(40)
	var carried := _bag_stacks()
	_ok(carried > 0, "the new character carries something (%d stacks)" % carried)
	var full: int = game.player.max_health
	_die()
	_ok(ws.grave != null and ws.grave.items.size() == carried and ws.grave.coins == 40, "the bags and coins go to the grave")
	_ok(inv.coins == 0 and _bag_stacks() == 0, "and leave the bags empty")
	_ok(game.afterlife.revive_here(), "return to life at the rest point")
	_ok(game.afterlife.wounds == 1 and game.player.max_health < full, "you come back wounded (%d -> %d)" % [full, game.player.max_health])
	# the grave waits, then scavengers take it
	_ok(game.grave.interactions().size() == 1, "the grave can be taken back")
	ws.time = ws.grave.until + 1
	game.grave.update(0.1)
	_ok(ws.grave.phase == "stolen" and game.grave.interactions().is_empty(), "after its time scavengers take it")
	var scav: Array = game.enemies.list.filter(func(e): return ws.grave.scavengers.has(e.id))
	_ok(scav.size() == DB.CONFIG.death.scavengers, "scavengers linger by the grave (%d)" % scav.size())
	# a save keeps the stolen grave and brings its scavengers back
	var data: Dictionary = ws.serialize()
	ws.reset()
	ws.apply(data)
	_ok(ws.grave != null and ws.grave.phase == "stolen", "a stolen grave is saved")
	var xp_before: int = game.progression.xp
	for e in scav:
		e.hurt(99999)
		game.combat.on_enemy_defeated(e)
	_ok(game.progression.xp == xp_before, "scavengers pay no XP")
	_ok(ws.grave.phase == "dropped" and game.grave.interactions().size() == 1, "the last scavenger drops the bundle")
	game.grave.recover()
	_ok(ws.grave == null and inv.coins == 40 and _bag_stacks() == carried, "everything comes back (%d stacks, %d coins)" % [_bag_stacks(), inv.coins])
	# a healer mends wounds for a fee
	game.afterlife.heal_wounds("test")
	_ok(game.afterlife.wounds == 0 and game.player.max_health == full, "healing restores full maximum health")
	# resting at an inn mends them too
	game.afterlife.wounds = 2
	game.afterlife.rest_tick(DB.CONFIG.death.woundRestSeconds + 1, "camp")
	_ok(game.afterlife.wounds == 2, "a campfire does not mend wounds")
	game.afterlife.rest_tick(DB.CONFIG.death.woundRestSeconds + 1, "inn")
	_ok(game.afterlife.wounds == 0, "a rest at an inn does")
	# a bed at the inn: pay, sleep, wake whole and rested, the inn your rest point
	game.afterlife.wounds = 2
	game.recompute_max_health()
	game.player.health = 1
	game.resources.mana = 0
	game.progression.rested = 0
	var coins_before: int = inv.coins
	var price := Inn.bed_price("hester")
	_ok(game.inn.sleep("hester") and inv.coins == coins_before - price, "a bed costs %d" % price)
	game.inn.wake("hester")
	_ok(game.afterlife.wounds == 0 and game.player.health == full, "you wake mended at full health")
	_ok(game.resources.mana == game.resources.max_mana, "and full mana")
	_ok(game.progression.rested > 0 and ws.rest_point == "inn:hester", "rested, with the inn as your rest point")
	var broke: int = inv.coins
	inv.lose_coins(broke)
	_ok(not game.inn.sleep("hester"), "no coin, no bed")
	inv.add_coins(broke)
	# falling again before taking it back loses the old grave
	inv.add_coins(5)
	_die()
	game.afterlife.revive_here()
	inv.add_coins(7)
	_die()
	_ok(ws.grave.coins == 7, "a second fall loses the first grave")


func _bag_stacks() -> int:
	var inv = game.inventory
	return inv.bag_locations().filter(func(l): return inv.get_at(l) != null and l.split(":")[1].to_int() < Items.BAG_SOCKETS).size()


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		print("FAIL: " + what)
	else:
		print("ok: " + what)

extends SceneTree
## Build layers: path points, forks, key passives, statuses, powers, the forge.
##   godot --headless --path . --script res://game/tests/builds_check.gd

var game
var frame := 0
var failures := 0
var a
var b


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Build Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		_points_and_forks()
		_passive()
		_statuses_and_powers()
		_forge()
		_save_round_trip()
		# Contagion: kill a Rotting enemy beside another
		a = game.enemies.list[0]
		b = game.enemies.list[1]
		b.position = a.position + Vector3(2, 0, 0)
		game.inventory.add_item("plague_saints_wraps")
		game.inventory.equip("plague_saints_wraps")
		check(game.spells.tuned("rot").get("spreadsOnDeath", false), "Plague-Saint's Wraps give Rot spreadsOnDeath")
		game.spells._apply_dot(game.spells.tuned("rot"), a, null, true)
		a.hurt(a.health + a.max_health * 0.5, {"knockFrom": game.player.position})
		check(a.dead, "the rotting enemy dies")
		check(a.knock.length() > 0.1, "an overkill throws the body back")
		game.spells.update(1.0 / 30)
	elif frame == 4:
		check(game.spells.has_status(b, "blighted"), "Rot spread to the enemy beside it (Blighted)")
		print("builds check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _points_and_forks() -> void:
	var bd = game.builds
	check(bd.points_total == 0, "no path points before level 10")
	check(not bd.enhance("cleave"), "cannot enhance without points")
	game.progression.level = 12
	check(bd.points_total == 3, "three path points at level 12")
	var before: Dictionary = game.spells.tuned("cleave")
	check(bd.enhance("cleave"), "Cleave is Enhanced")
	check(game.spells.tuned("cleave").tuning.maxTargets == before.tuning.maxTargets + 1, "Enhanced Cleave hits one more (on top of Weapon Master)")
	check(not bd.choose_fork("cleave", "nope"), "an unknown fork is refused")
	check(bd.choose_fork("cleave", "bleedingEdge"), "Bleeding Edge chosen")
	check(game.spells.tuned("cleave").get("follow") == "rend", "Bleeding Edge makes Cleave apply Rend")
	check(not bd.choose_fork("cleave", "wideArc"), "one fork per spell")
	check(bd.enhance("crushingBlow") and bd.points_free == 0, "the last point spent")
	check(not bd.enhance("lunge"), "no points left")


func _passive() -> void:
	var bd = game.builds
	check(not bd.choose_passive("assassin"), "another class's key passive is refused")
	check(bd.choose_passive("bloodlust"), "Bloodlust chosen")
	var s0: float = game.spells.damage_scale
	game.spells.after_hit({"amount": 10, "crit": false})
	game.spells.after_hit({"amount": 10, "crit": false})
	check(game.spells.buffs.hitStacks.stacks == 2, "two hits, two Bloodlust stacks")
	check(game.spells.damage_scale > s0, "Bloodlust raises your damage")
	game.spells.buffs.erase("hitStacks")


func _statuses_and_powers() -> void:
	var sp = game.spells
	var e = game.enemies.list[2]
	sp._apply_dot(sp.tuned("rend"), e, null, true)
	check(sp.has_status(e, "bleeding"), "Rend makes an enemy Bleeding")
	check(not sp.has_status(e, "slowed"), "not Slowed yet")
	sp.apply_aura("hexOfWithering", e, DB.spells.hexOfWithering.applies)
	sp.update(0.0)
	check(sp.has_status(e, "slowed") and sp.has_status(e, "weakened"), "Hex of Withering: Slowed and Weakened")
	var m0: float = sp.hit_mods(e).mult
	game.inventory.add_item("hunters_patience")
	game.inventory.equip("hunters_patience")
	check(game.builds.powers().size() == 1, "Hunter's Patience worn: one power")
	check(sp.hit_mods(e).mult > m0 * 1.09, "Hunter's Patience: +10% against a Slowed enemy")
	e.health = e.max_health * 0.2
	check(is_equal_approx(sp._execute_scale({"execute": {"below": 35, "percent": 50}}, e), 1.5), "Executioner: +50% below 35% health")
	e.health = e.max_health
	check(is_equal_approx(sp._execute_scale({"execute": {"below": 35, "percent": 50}}, e), 1.0), "no execute at full health")


func _forge() -> void:
	var inv = game.inventory
	var dlg = game.dialogue
	inv.add_item("bloodletter")
	inv.add_coins(500)
	var src := ""
	for loc in inv.bag_locations():
		var st = inv.get_at(loc)
		if st != null and st.id == "bloodletter":
			src = loc
	check(src != "", "Bloodletter is in the bags")
	var targets: Array = dlg._forge_targets(src)
	check(targets.has("e:mainHand"), "the worn weapon can take Bloodletter's power")
	dlg.npc = game.npcs.all.filter(func(n): return n.id == "mara")[0]
	dlg.view = {"kind": "menu"}
	check(dlg.page.options.any(func(o): return o.id == "forge"), "Mara offers to move a legendary power")
	check(dlg._imprint(src, "e:mainHand"), "Mara moves the power")
	check(inv.count("bloodletter") == 0, "Bloodletter is melted down")
	check(Items.power_of(inv.equipment.mainHand) == "bloodletter", "the worn weapon now carries Bloodletter")
	check(Items.view(inv.equipment.mainHand).rarity == "legendary", "and shows as legendary")
	check(game.spells.tuned("cleave").get("follow") == "rend", "its power names Cleave")
	dlg.npc = null


func _save_round_trip() -> void:
	var data: Dictionary = game.builds.serialize()
	game.builds.reset()
	game.builds.apply(data)
	check(game.builds.fork_of("cleave") == "bleedingEdge" and game.builds.key_passive == "bloodlust", "builds survive a save")
	var saved: Dictionary = game.save.serialize()
	check(saved.has("builds"), "the save has builds")
	check(Items.valid_rolls(game.inventory.equipment.mainHand.id, game.inventory.equipment.mainHand.get("rolls")), "a forged power is valid rolls")


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)

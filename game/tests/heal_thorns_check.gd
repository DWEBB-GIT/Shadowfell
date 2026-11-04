extends SceneTree
## Healing and thorns spell kinds (Dan, 2026-11-02): cast and instant heals,
## a heal over time, a heal that consumes it, a healing zone, a healing burst
## that also burns enemies, and thorns. Uses the Paladin's example spells.
##   godot --headless --path . --script res://game/tests/heal_thorns_check.gd

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
		var made: Dictionary = game.roster.create("Heal", "paladin")
		game.enter_world(made.character.id)
	elif frame == 3:
		_run()
		print("heal and thorns check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		print("FAILED: ", what)


func _ready_to_cast() -> void:
	var pl = game.player
	pl.cooldowns.gcd = 0.0
	pl.casting = null
	game.resources.mana = 9999.0


func _tick(seconds: float) -> void:
	var dt := 0.05
	for i in int(round(seconds / dt)):
		game.spells.update(dt)


func _run() -> void:
	var sp = game.spells
	var pl = game.player
	game.random = func() -> float: return 0.99 # never crit, top of every roll
	# Quick Mend comes from Sister Lyra's class quest (Dan, 2026-11-04)
	_ok(not game.skills.knows_ability("quickMend"), "Quick Mend waits for the class quest")
	game.skills.grant_spell("quickMend")
	for id in ["mendingPrayer", "quickMend", "renewingLight", "swiftRenewal", "circleOfMending", "radiantNova", "thornedVow"]:
		_ok(DB.spells.has(id) and game.skills.knows_ability(id), "the paladin knows %s" % id)

	# an instant heal heals at once
	pl.health = 10.0
	_ready_to_cast()
	_ok(sp.try_cast("quickMend") and pl.health > 10.0 and pl.casting == null, "Quick Mend heals at once (%.1f)" % pl.health)

	# a cast heal fills a cast bar, then heals
	pl.health = 10.0
	_ready_to_cast()
	_ok(sp.try_cast("mendingPrayer") and pl.casting != null, "Mending Prayer starts a cast")
	_ok(pl.health == 10.0, "and heals nothing yet")
	_tick(2.2)
	_ok(pl.casting == null and pl.health >= 10.0 + 18, "and heals when the cast ends (%.1f)" % pl.health)

	# a heal over time ticks every 3 s for 12 s
	pl.health = 10.0
	_ready_to_cast()
	sp.try_cast("renewingLight")
	_ok(sp.buffs.has("renewingLight") and pl.health == 10.0, "Renewing Light sits on you")
	_tick(3.05)
	var one: float = pl.health - 10.0
	_ok(one >= 5, "it heals after 3 s (%.1f)" % one)
	_tick(9.2)
	_ok(not sp.buffs.has("renewingLight") and is_equal_approx(pl.health - 10.0, one * 4), "four ticks in all (%.1f)" % (pl.health - 10.0))

	# Swift Renewal needs Renewing Light, and eats what it had left
	_ready_to_cast()
	pl.cooldowns.erase("swiftRenewal")
	_ok(not sp.try_cast("swiftRenewal"), "Swift Renewal refuses without Renewing Light")
	_ready_to_cast()
	sp.try_cast("renewingLight")
	var left: float = sp.hot_left("renewingLight", sp.buffs.renewingLight)
	var avg: float = 5.5 + 0.3 * game.stats.spell_power
	_ok(is_equal_approx(left, avg * 4), "a fresh Renewing Light has four average ticks to give (%.1f)" % left)
	pl.health = 10.0
	_ready_to_cast()
	_ok(sp.try_cast("swiftRenewal"), "Swift Renewal goes with Renewing Light on you")
	_ok(not sp.buffs.has("renewingLight"), "and consumes it")
	_ok(pl.health - 10.0 >= left, "healing at least what it had left (%.1f)" % (pl.health - 10.0))

	# a healing zone heals you while you stand in it
	pl.health = 10.0
	_ready_to_cast()
	game.raw_aim = pl.position
	sp.try_cast("circleOfMending")
	_ok(sp.zones.any(func(z): return z.id == "circleOfMending" and z.get("heal")), "Circle of Mending lies on the ground")
	_tick(1.0)
	_ok(pl.health > 10.0, "and heals you in it (%.1f)" % pl.health)
	sp.zones.clear()

	# a healing burst heals you and burns enemies close by
	var foe = null
	for e in game.enemies.list:
		if e.alive and not e.cfg.get("dummy") and not e.protected:
			foe = e
			break
	_ok(foe != null, "found an enemy to test on")
	if foe == null:
		return
	foe.position = pl.position + Vector3(2, 0, 0)
	var hp_before: float = foe.health
	pl.health = 10.0
	_ready_to_cast()
	sp.try_cast("radiantNova")
	_ok(pl.health > 10.0, "Radiant Nova heals you (%.1f)" % pl.health)
	_ok(foe.health < hp_before or not foe.alive, "and burns the enemy next to you (%.1f -> %.1f)" % [hp_before, foe.health])

	# thorns: an enemy that lands a blow takes damage back
	if foe.alive:
		foe.health = foe.max_health
		_ready_to_cast()
		game.targeting.stop_attack()
		sp.try_cast("thornedVow")
		_ok(sp.buffs.has("thornedVow"), "Thorned Vow sits on you")
		var before: float = foe.health
		game.events.emit("playerHurt", {"enemy": foe, "damage": 5, "crit": false, "blocked": false})
		_ok(foe.health < before, "an enemy that hits you is hurt back (%.1f -> %.1f)" % [before, foe.health])
		before = foe.health
		game.events.emit("playerHurt", {"enemy": foe, "damage": 0, "crit": false, "blocked": false})
		_ok(foe.health == before, "a blow that missed hurts nothing")
		_tick(31.0)
		_ok(not sp.buffs.has("thornedVow"), "Thorned Vow fades after 30 s")

	# the tooltip names the heal coefficient, the editor knows every kind
	var line: String = game.hud.items._scaling_line(DB.abilities.mendingPrayer)
	_ok(line.contains("150% spell power healing"), "tooltip: " + line)
	var DataStoreT = load("res://addons/shadowfell_data/store.gd")
	for k in ["heal", "hot", "healZone", "healBurst", "thorns"]:
		_ok(DataStoreT.SPELL_KINDS.has(k), "the builder offers %s" % k)

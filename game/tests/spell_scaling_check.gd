extends SceneTree
## Spell coefficients (Dan, 2026-11-02): every damaging spell grows with
## gear, as WoW coefficients: a share of spell power and of a weapon roll.
##   godot --headless --path . --script res://game/tests/spell_scaling_check.gd

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
		var made: Dictionary = game.roster.create("Scale", "paladin")
		game.enter_world(made.character.id)
	elif frame == 3:
		_run()
		print("spell scaling check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		print("FAILED: ", what)


func _run() -> void:
	# every spell with a base roll states its spell power share
	for id in DB.abilities:
		var t: Dictionary = DB.abilities[id].get("tuning", {})
		if t.has("damageMin"):
			_ok(t.has("spellPower"), "%s states its spellPower coefficient" % id)
	var sp = game.spells
	var t: Dictionary = DB.abilities.lightsHammer.tuning
	game.random = func() -> float: return 0.0
	var w0: float = Stats.weapon_roll(game.random, game.stats)
	var expect: float = t.damageMin + t.spellPower * game.stats.spell_power + t.weaponDamage * w0
	var got: float = sp._spell_base(t)
	_ok(is_equal_approx(got, expect), "Light's Hammer = base + 80%% spell power + 35%% weapon (%s vs %s)" % [got, expect])
	print("level 1 paladin: weapon roll %.1f, spell power %.1f, Light's Hammer %.1f, Light Strike %.1f" % [w0, game.stats.spell_power, got, w0 * DB.abilities.holyStrike.tuning.damageMultiplier])
	# more spell power or a better weapon both make the hammer hit harder
	game.random = func() -> float: return 0.5
	var mid: float = sp._spell_base(t)
	var w5: float = Stats.weapon_roll(game.random, game.stats)
	_ok(is_equal_approx(mid - got, (t.damageMax - t.damageMin) * 0.5 + t.weaponDamage * (w5 - w0)), "the weapon roll feeds the hammer")
	print("average: Light's Hammer %.1f (was %.1f), Light Strike %.1f" % [mid, 3.5 + game.stats.spell_power, w5 * DB.abilities.holyStrike.tuning.damageMultiplier])
	var line: String = game.hud.items._scaling_line(DB.abilities.lightsHammer)
	_ok(line.contains("35% weapon damage") and line.contains("80% spell power"), "tooltip names the coefficients: " + line)
	line = game.hud.items._scaling_line(DB.abilities.holyStrike)
	_ok(line.contains("160% weapon damage"), "Light Strike tooltip: " + line)
	# a weapon ability can take a share of spell power too (editor Scaling)
	var hs: Dictionary = DB.abilities.holyStrike.tuning.duplicate()
	game.random = func() -> float: return 0.5
	var plain: float = sp._weapon_base(hs) * hs.damageMultiplier
	hs.spellPower = 0.5
	var with_sp: float = sp._weapon_base(hs) * hs.damageMultiplier
	_ok(is_equal_approx(with_sp - plain, 0.5 * game.stats.spell_power), "Light Strike + 50%% spell power adds half your spell power (%s)" % (with_sp - plain))
	_ok(game.hud.items._scaling_line({"tuning": hs}).contains("50% spell power"), "tooltip shows a weapon ability's spell power")

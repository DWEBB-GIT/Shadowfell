extends SceneTree
## Weapon runes (data/professions/runes.json, Runes): a rune scroll from the
## test vendor goes on the main-hand weapon, the weapon glows in the rune's
## colour (brighter with enchant ranks, sparks from +3), the rune survives a
## save, and each rune's proc does what it says.
##   godot --headless --path . --script res://game/tests/runes_check.gd

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
		var made: Dictionary = game.roster.create("Rune Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		_scrolls()
		_drag()
		_glow()
		_procs()
		if OS.get_environment("SHOT") == "":
			return _end()
		# SHOT=<folder>: one picture a rune, at +4 so the sparks show
		var n = game.npcs.by_id("test_vendor")
		game.player.position.x = n.position.x + 2.0
		game.player.position.z = n.position.z + 2.0
		game.player.facing = PI * 0.25
		for e in game.enemies.list:
			e.position.y = -500.0
	elif frame >= 40 and (frame - 40) % 60 == 0:
		var i := (frame - 40) / 60
		var ids := ["embers", "rime", "venom", "storm", "dawn", "dread"]
		if i > 0:
			root.get_texture().get_image().save_png(OS.get_environment("SHOT") + "/rune_%s.png" % ids[i - 1])
		if i >= ids.size():
			return _end()
		var st = game.inventory.equipment.mainHand
		st.rolls.rune = ids[i]
		st.rolls.temper = 4
		game.player.show_equipment(game.inventory.equipment)
	return false


func _clear_bags() -> void:
	var inv = game.inventory
	for l in inv.bag_locations():
		if inv.get_at(l) != null:
			inv.remove_all(inv.get_at(l).id)


func _scrolls() -> void:
	var inv = game.inventory
	_clear_bags()
	var n = game.npcs.by_id("test_vendor")
	_ok(n != null, "the test vendor is in the world")
	game.merchant.open("test_curios", n)
	var all := true
	for r in DB.runes.runes:
		all = all and game.merchant.price_of("rune_" + r.id) == 0
	_ok(all and DB.runes.runes.size() == 6, "six free rune scrolls on sale")
	_ok(game.merchant.buy("rune_embers") and game.merchant.buy("rune_rime"), "rune scrolls can be bought")
	game.merchant.close()
	var w = inv.equipment.mainHand
	_ok(w != null, "the warden has a main-hand weapon")
	inv.use(inv._find("rune_embers"))
	_ok(Runes.of(inv.equipment.mainHand) == "embers", "using the scroll puts Embers on the weapon")
	_ok(inv.count("rune_embers") == 0, "and the scroll is used up")
	_ok(Items.valid_rolls(inv.equipment.mainHand.id, inv.equipment.mainHand.rolls), "the rune is a valid roll (saves keep it)")
	_ok(not Items.valid_rolls(inv.equipment.mainHand.id, {"rune": "nonsense"}), "an unknown rune is refused")
	# a second rune asks before replacing; apply directly as the confirm would
	inv.use(inv._find("rune_rime"))
	_ok(Runes.of(inv.equipment.mainHand) == "embers", "a different rune waits for a yes")
	game.hud.modal = null
	_ok(game.runes.apply(inv._find("rune_rime"), "rime") and Runes.of(inv.equipment.mainHand) == "rime", "saying yes replaces it with Rime")


## Drag a scroll onto any weapon: one in the bags, the off hand.
func _drag() -> void:
	var inv = game.inventory
	game.hud.modal = null
	var n = game.npcs.by_id("test_vendor")
	game.merchant.open("test_curios", n)
	game.merchant.buy("rune_venom")
	game.merchant.buy("rune_storm")
	game.merchant.buy("test_frostbite")
	game.merchant.close()
	var wl = inv._find("test_frostbite")
	_ok(wl != null, "a spare weapon in the bags")
	inv.move(inv._find("rune_venom"), wl)
	_ok(Runes.of(inv.get_at(wl)) == "venom" and inv.count("rune_venom") == 0, "dropping a rune on a bagged weapon enchants it")
	var off = inv.equipment.get("offHand")
	if off != null and Items.get_def(off.id).get("kind") == "weapon":
		inv.move(inv._find("rune_storm"), "e:offHand")
		_ok(Runes.of(inv.equipment.offHand) == "storm", "dropping one on the off-hand weapon enchants it")
	var before: int = inv.count("rune_storm")
	var food = inv._find(ActionBar.STARTER_FOOD)
	if food != null and inv.count("rune_storm") > 0:
		inv.move(inv._find("rune_storm"), food)
		_ok(inv.count("rune_storm") == before, "a rune dropped on something else is not used up")


func _glow() -> void:
	var inv = game.inventory
	var pl = game.player
	pl.show_equipment(inv.equipment)
	var g = pl.weapon_part.find_child("Glow", false, false) if pl.weapon_part else null
	_ok(g is FancyGear, "the runed weapon glows")
	if g is FancyGear:
		_ok(g.colour.is_equal_approx(Color("#7fd8ff")), "in Rime's colour")
	var st = inv.equipment.mainHand
	var g0 := Runes.glow_for(st)
	st.rolls.temper = 3
	var g3 := Runes.glow_for(st)
	_ok(g3.strength > g0.strength and g3.motes and not g0.motes, "brighter with enchant ranks, sparks from +3")
	st.rolls.erase("temper")


func _procs() -> void:
	var inv = game.inventory
	var p: Vector3 = game.player.position
	var foe = null
	for e in game.enemies.list:
		if e.alive and (foe == null or e.cfg.level < foe.cfg.level):
			foe = e
	_ok(foe != null, "there is an enemy to test on")
	if foe == null:
		return
	foe.position = p + Vector3(1.5, 0, 0)
	_ok(is_equal_approx(Runes.proc_chance(4, 3.0), 0.2), "procs per minute: 4 ppm on a 3 s weapon is 20%")
	var st = inv.equipment.mainHand
	st.rolls.rune = "dread"
	_ok(game.runes.on_spell_hit(foe, 40, false, true) and game.spells.has_status(foe, "vulnerable"), "a spell hit draws on the main-hand rune (casters)")
	for rid in ["embers", "rime", "venom", "storm", "dawn", "dread"]:
		st.rolls.rune = rid
		foe.health = foe.max_health
		var before: float = foe.health
		game.player.health = game.player.max_health * 0.5
		var hp_before: float = game.player.health
		_ok(game.runes.on_weapon_hit(foe, "main", 40, true), "%s procs" % rid)
		match rid:
			"embers", "venom":
				var status: String = Runes.def(rid).status
				_ok(game.spells.has_status(foe, status), "%s leaves the foe %s" % [rid, status])
				for i in 60:
					game.runes.update(0.25)
				_ok(foe.health < before, "%s burns it down over time (%d)" % [rid, before - foe.health])
				_ok(not game.spells.has_status(foe, status), "and wears off")
			"rime":
				_ok(foe.health < before and game.spells.has_status(foe, "slowed"), "Rime hurts and slows")
			"storm":
				_ok(foe.health < before, "Storm strikes")
			"dawn":
				_ok(foe.health < before and game.player.health > hp_before, "Dawn hurts and heals")
			"dread":
				_ok(game.spells.has_status(foe, "vulnerable"), "Dread leaves it Vulnerable")


func _ok(cond: bool, what: String) -> void:
	print(("ok    " if cond else "FAIL  ") + what)
	if not cond:
		failed += 1


func _end() -> bool:
	print("runes check: %d failed" % failed)
	quit(1 if failed else 0)
	return true

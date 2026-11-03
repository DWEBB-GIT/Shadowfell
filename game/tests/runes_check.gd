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
		_refine()
		_refining_window()
		_fellstones()
		_runecraft()
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
	# runes are fused at a rune forge now (Dan, 2026-11-03), not from the bags
	inv.use(inv._find("rune_embers"))
	inv.move(inv._find("rune_embers"), "e:mainHand")
	_ok(Runes.of(inv.equipment.mainHand) == "" and inv.count("rune_embers") == 1, "using or dragging a rune onto a weapon no longer fuses it")
	var rf = game.rune_forge
	_at_forge()
	_ok(game.hud.items.open.runeforge, "using the rune forge opens its window")
	_ok(rf.blocked() != "" and not rf.fuse(), "Fuse waits for a weapon and a rune")
	_ok(not rf.put(inv._find("rune_embers"), "f:weapon"), "a rune won't go in the weapon slot")
	_ok(rf.put("e:mainHand") and rf.put(inv._find("rune_embers")), "the weapon and the rune go into their slots")
	_ok(rf.fuse() and rf.channel != null, "Fuse starts the forge working")
	rf.update(1.0)
	_ok(Runes.of(inv.equipment.mainHand) == "" and rf.bar() != null, "fusing takes a few seconds (cast bar shown)")
	rf.update(RuneForge.CHANNEL)
	_ok(rf.channel == null and Runes.of(inv.equipment.mainHand) == "embers", "then the rune is in the weapon")
	_ok(inv.count("rune_embers") == 0 and rf.in_slot("f:rune") == null, "and the rune is used up")
	_ok(rf.in_slot("f:weapon") != null, "the weapon stays on the forge")
	_ok(Items.valid_rolls(inv.equipment.mainHand.id, inv.equipment.mainHand.rolls), "the rune is a valid roll (saves keep it)")
	_ok(not Items.valid_rolls(inv.equipment.mainHand.id, {"rune": "nonsense"}), "an unknown rune is refused")
	# a second rune asks before replacing; begin as the Yes would
	game.hud.modal = null
	rf.put(inv._find("rune_rime"))
	rf.fuse()
	_ok(rf.channel == null and Runes.of(inv.equipment.mainHand) == "embers", "a different rune waits for a yes")
	game.hud.modal = null
	rf._begin("rime")
	game.player.moving = true
	rf.update(0.1)
	game.player.moving = false
	_ok(rf.channel == null and Runes.of(inv.equipment.mainHand) == "embers", "moving stops the fusing")
	rf._begin("rime")
	rf.update(RuneForge.CHANNEL + 0.1)
	_ok(Runes.of(inv.equipment.mainHand) == "rime", "saying yes replaces it with Rime")


## Stand at the first rune forge and use it.
func _at_forge() -> void:
	var sts: Array = Layout.stations.filter(func(st): return st.kind == RuneForge.KIND)
	_ok(not sts.is_empty(), "there is a rune forge in the world")
	var st: Dictionary = sts[0]
	game.player.position = Vector3(st.position[0], Terrain.height_at(st.position[0], st.position[1]), st.position[1])
	game.player.moving = false
	game.hud.modal = null
	for c in game.interaction._candidates():
		if c.key == "station:" + st.id:
			c.run.call()


## Refining (Dan, 2026-11-02): stones, a chance that can slip, and a
## failed try only costs the stones while making the next one likelier.
func _refine() -> void:
	var inv = game.inventory
	var fg = game.forge
	_clear_bags()
	inv.add_item("test_frostbite", 1, true)
	var loc = inv._find("test_frostbite")
	inv.add_item("fellstone", 20, true)
	inv.add_item("soulshard", 2, true)
	inv.coins += 5000
	_ok(Items.get_def("fellstone").name == "Fellstone" and fg.temper_cost(inv.get_at(loc)).items[0].item == "fellstone", "refining is paid in Fellstones")
	var rnd = game.random
	game.random = func(): return 0.0
	_ok(fg.temper(loc) and fg.temper(loc), "+1 and +2 always take")
	var c3: Dictionary = fg.temper_cost(inv.get_at(loc))
	_ok(c3.chance < 100, "+3 can slip (%d%%)" % c3.chance)
	var stones: int = inv.count("fellstone")
	game.random = func(): return 0.999
	_ok(not fg.temper(loc), "a slip fails the try")
	_ok(Items.temper_of(inv.get_at(loc)) == 2 and inv.count("test_frostbite") == 1, "but the item keeps its rank and is not lost")
	_ok(inv.count("fellstone") < stones, "the stones are spent")
	_ok(fg.temper_cost(inv.get_at(loc)).chance == mini(100, c3.chance + 10), "and the next try is 10% likelier")
	_ok(Items.valid_rolls("test_frostbite", inv.get_at(loc).rolls), "the item's resolve is a valid roll")
	game.random = func(): return 0.0
	_ok(fg.temper(loc) and Forge.resolve_of(inv.get_at(loc)) == 0, "a success clears the resolve")
	game.random = rnd
	_clear_bags()


## The refining window (Dan, 2026-11-03): an altar, an item slot, a preview
## of the next rank, a channel, then the rank (or a slip).
func _refining_window() -> void:
	var inv = game.inventory
	var ui = game.hud.items
	var rf = game.refinery
	_clear_bags()
	inv.add_item("test_frostbite", 1, true)
	inv.add_item("fellstone", 20, true)
	inv.coins += 5000
	var sts: Array = Layout.stations.filter(func(s): return s.kind == Refinery.KIND)
	_ok(not sts.is_empty(), "there is a refining altar in the world")
	if sts.is_empty():
		return
	var st: Dictionary = sts[0]
	game.player.position = Vector3(st.position[0], Terrain.height_at(st.position[0], st.position[1]), st.position[1])
	game.player.moving = false
	game.hud.modal = null
	for c in game.interaction._candidates():
		if c.key == "station:" + st.id:
			c.run.call()
	_ok(ui.open.refining, "using the altar opens the refining window")
	_ok(rf.blocked() != "", "Refine waits for gear")
	_ok(not rf.put(inv._find("fellstone")), "stones don't go in the slot")
	var loc = inv._find("test_frostbite")
	ui.dropOn(loc, "r:item")
	_ok(rf.loc() == loc, "dragging gear into the slot places it")
	var before: float = Items.view(inv.get_at(loc)).itemLevel
	_ok(rf.preview().get("itemLevel", 0) == before + 1 and rf.cost().rank == 1, "the window shows the next rank's item level")
	var rnd = game.random
	game.random = func(): return 0.0
	_ok(rf.refine() and rf.channel != null and rf.bar() != null, "Refine starts the weave (cast bar shown)")
	rf.update(1.0)
	_ok(Items.temper_of(inv.get_at(loc)) == 0, "it takes a moment")
	rf.update(Refinery.CHANNEL)
	_ok(Items.temper_of(inv.get_at(loc)) == 1 and rf.last == "ok", "then the item is +1")
	_ok(rf.loc() == loc and rf.cost().rank == 2, "the item stays in the slot for the next rank")
	rf.refine()
	game.player.moving = true
	rf.update(0.1)
	game.player.moving = false
	_ok(rf.channel == null and Items.temper_of(inv.get_at(loc)) == 1, "moving stops it")
	game.random = rnd
	ui.close("refining")
	rf.update(0.1)
	_ok(rf.at == null and rf.item == null, "closing the window clears it")
	_clear_bags()


## Fellstones: only from foes that still give XP; bosses always; old
## refining stones in a save turn into Fellstones.
func _fellstones() -> void:
	var inv = game.inventory
	var loot = game.loot
	var foe = game.enemies.list[0]
	var rnd = game.random
	game.random = func(): return 0.0
	_ok(loot.drop_fellstones(foe, 0) == 0, "a grey foe (no XP) never drops one")
	_ok(loot.drop_fellstones(foe, 10) >= 1, "a foe worth XP can")
	game.random = func(): return 0.999
	var cfg: Dictionary = foe.cfg
	_ok(Loot.fellstone_kind({"type": "normal"}) == "normal" and Loot.fellstone_kind({"elite": true}) == "elite" and Loot.fellstone_kind({"mana": 10}) == "caster" and Loot.fellstone_kind({"uniqueDrop": "x"}) == "boss", "foes sort into normal, caster, elite and boss")
	_ok(loot.drop_fellstones(foe, 10) == 0 or Loot.fellstone_kind(cfg) == "boss", "an unlucky roll drops none")
	game.random = rnd
	_clear_bags()
	inv.add_item("glimmering_dust", 5, true)
	inv.apply(inv.serialize())
	_ok(inv.count("fellstone") == 5 and inv.count("glimmering_dust") == 0, "old refining stones in a save turn into Fellstones")
	_ok(not DB.loot_tables.values().any(func(t): return JSON.stringify(t).contains("soulshard")), "no low-level loot table drops Soulshards")
	_clear_bags()


## Runecraft: fragments drop from fitting foes; a Refiner binds 10 into a rune.
func _runecraft() -> void:
	var inv = game.inventory
	_ok(Runes.fragment_element("seer") == "dread" and Runes.fragment_element("ghoul") == "dawn", "foes carry fitting fragments")
	var seer = null
	for e in game.enemies.list:
		if e.cfg.get("id") == "seer":
			seer = e
	var rnd = game.random
	game.random = func(): return 0.0
	if seer != null:
		_ok(game.runes.drop_from_enemy(seer, 10).has("rune_dread_fragment"), "a seer can drop a Dread fragment")
		_ok(game.runes.drop_from_enemy(seer, 0).is_empty(), "but not once it is grey")
	game.random = rnd
	_clear_bags()
	inv.coins += 1000
	inv.add_item("rune_rime_fragment", 9, true)
	_ok(not game.runes.can_bind("rime"), "nine fragments are not enough")
	inv.add_item("rune_rime_fragment", 1, true)
	_ok(game.runes.bind("rime") and inv.count("rune_rime") == 1 and inv.count("rune_rime_fragment") == 0, "ten fragments bind into a Rune of Rime")
	_clear_bags()


## Drag a scroll onto any weapon: one in the bags, the off hand.
func _drag() -> void:
	var inv = game.inventory
	var ui = game.hud.items
	var rf = game.rune_forge
	game.hud.modal = null
	var n = game.npcs.by_id("test_vendor")
	game.merchant.open("test_curios", n)
	game.merchant.buy("rune_venom")
	game.merchant.buy("test_frostbite")
	game.merchant.close()
	_at_forge()
	var wl = inv._find("test_frostbite")
	_ok(wl != null, "a spare weapon in the bags")
	ui.dropOn(wl, "f:weapon")
	ui.dropOn(inv._find("rune_venom"), "f:rune")
	_ok(rf.slot_loc("f:weapon") == wl and rf.in_slot("f:rune") != null, "dragging into the forge's slots places them")
	ui.dropOn("f:weapon", null)
	_ok(rf.in_slot("f:weapon") == null and inv.get_at(wl) != null, "dragging out of the forge only takes it off the forge")
	ui.dropOn(wl, "f:weapon")
	rf.fuse()
	rf.update(RuneForge.CHANNEL + 0.1)
	_ok(Runes.of(inv.get_at(wl)) == "venom" and inv.count("rune_venom") == 0, "a bagged weapon takes a rune at the forge")
	ui.close("runeforge")
	rf.update(0.1)
	_ok(rf.station == null and rf.weapon == null, "closing the window clears the forge")


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

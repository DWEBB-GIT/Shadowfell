extends SceneTree
## Dan's 2026-11-11 skills update (basics): Woodcutting fells trees with a
## hatchet, Woodcraft shapes logs at a workbench, Smithing smelts and makes
## at a forge (smelting moved off Mining), Hunting (the old Skinning)
## fillets fish anywhere with a knife, and weapon masteries rise with
## landed blows and unlock titles:
##   godot --headless --path . --script res://game/tests/new_skills_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_newskills_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Skills", "warden")
		game.enter_world(made.character.id)
	if frame <= 2:
		return false
	if t0 == 0:
		if game.hud.modal == "loading" or game.hud.blocks_gameplay:
			if frame > 3000:
				check(false, "the world loads")
				quit(1)
			return false
		t0 = frame
		game.set_process(false)
		_run()
		print("new skills checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func place(x: float, z: float) -> void:
	var p = game.player
	p.position = Vector3(x, p.position.y, z)


func _craft(id: String, label: String) -> void:
	var r: Dictionary = DB.recipes[id]
	var before: int = game.inventory.count(r.output.item)
	check(game.cooking.start(id), "%s: starts (%s)" % [label, game.cooking.blocked(r)])
	game.cooking.update(10)
	check(game.inventory.count(r.output.item) == before + int(r.output.count), "%s: makes %s" % [label, r.output.item])


## Dan 2026-11-11: every success has a chance at one skill point by its
## colour, the same in every skill; regular meat comes from Hunting.
func _skill_points() -> void:
	var sk = game.skills
	var c: Dictionary = DB.skill_ladder.pointChance
	check(is_equal_approx(c.orange, 0.8) and is_equal_approx(c.yellow, 0.5) and c.green > 0 and c.green < c.yellow and c.grey == 0, "orange 80%, yellow 50%, green low, grey nothing")
	var roll: Callable = game.random
	for id in ["mining", "woodcutting", "skinning"]:
		sk.grant(id)
		sk.ranks[id] = 5
		var orange: String = sk.colour_for(id, 5)
		var green: String = sk.colour_for(id, 5 - int(DB.skills[id].get("bands", DB.skill_ladder.bands)[1]))
		check(orange == "orange" and green == "green", "%s: a task at your level is orange, well under it green (%s, %s)" % [id, orange, green])
		game.random = func() -> float: return 0.7
		check(sk.gain(id, "orange") == 1 and sk.rank(id) == 6, "%s: a 70 roll lands on orange (80%%)" % id)
		check(sk.gain(id, "yellow") == 0 and sk.rank(id) == 6, "%s: but misses on yellow (50%%)" % id)
		game.random = func() -> float: return 0.0
		check(sk.gain(id, "grey") == 0, "%s: grey never teaches" % id)
		check(sk.gain(id, "red") == 0, "%s: nor does a task beyond you" % id)
	game.random = roll
	# meat: butchered with Hunting, not dropped by the beast
	for t in ["wild_boar", "bristleback", "ridge_wolf"]:
		var s := JSON.stringify(DB.loot_tables[t].get("always", [])) + JSON.stringify(DB.loot_tables[t].get("drops", {}))
		check(not s.contains("_meat"), "%s no longer drops meat" % t)
	for t in ["skin_boar", "skin_bristleback", "skin_wolf"]:
		check(JSON.stringify(DB.loot_tables[t].always).contains("_meat"), "%s gives meat" % t)


func _run() -> void:
	_skill_points()
	var sk = game.skills
	var inv = game.inventory
	check(DB.skills.skinning.name == "Hunting", "Skinning is now called Hunting")
	check(not DB.skills.mining.has("craft"), "smelting has moved off Mining")
	for id in ["smithing", "woodcutting", "woodcraft"]:
		check(DB.skills.has(id) and sk.laddered(id), "%s is a laddered skill" % id)
	# Woodcutting: an ash tree needs the skill and a hatchet on the belt
	var trees: Array = game.gathering.live().filter(func(v): return v.skill == "woodcutting" and v.level == 1)
	check(not trees.is_empty(), "ash trees grow on the map")
	if not trees.is_empty():
		var v: Dictionary = trees[0]
		check(game.gathering.block(v).begins_with("needs"), "a tree can't be felled without Woodcutting")
		sk.grant("woodcutting")
		check(game.gathering.block(v) == "needs a hatchet", "without a hatchet the tree says so (%s)" % game.gathering.block(v))
		inv.add_item("hatchet", 1, true)
		check(game.gathering.block(v) == "", "with the skill and a hatchet the tree can be felled")
		place(v.x + 1.0, v.z)
		var before: int = inv.count("ash_log")
		var roll: Callable = game.random
		game.random = func() -> float: return 0.0 # every skill-up chance lands
		check(game.gathering.start(v.n), "chopping starts")
		check(game.gathering.bar.name.begins_with("Chopping"), "the bar says Chopping")
		for i in 12:
			game.gathering.update(3.0, game.time + i * 3.0)
		check(inv.count("ash_log") > before, "chopping yields ash logs")
		game.random = roll
		check(sk.rank("woodcutting") > 1, "chopping trains Woodcutting")
	# Woodcraft at the workbench
	sk.grant("woodcraft")
	inv.add_item("ash_log", 4, true)
	var benches: Array = Layout.stations.filter(func(s): return s.kind == "workbench")
	check(not benches.is_empty(), "a workbench stands in Thornford")
	if not benches.is_empty():
		place(benches[0].position[0] + 1.0, benches[0].position[1])
		_craft("carve_arrow_shafts", "woodcraft at the workbench")
	# Smithing at the forge: smelting and charcoal
	sk.grant("smithing")
	var forge: Dictionary = Layout.stations.filter(func(s): return s.kind == "forge")[0]
	place(forge.position[0] + 1.5, forge.position[1])
	inv.add_item("copper_ore", 1, true)
	_craft("smelt_copper", "smithing smelts copper")
	sk.ranks.smithing = 10
	sk.tiers.smithing = 1
	_craft("burn_charcoal", "smithing burns charcoal")
	# Hunting: fillet a perch anywhere, with a knife
	sk.grant("skinning")
	inv.add_item("gloomwater_perch", 1, true)
	place(forge.position[0] + 60.0, forge.position[1] + 60.0)
	check(game.cooking.near_station("knife") == "", "no knife: no filleting")
	inv.add_item("skinning_knife", 1, true)
	_craft("fillet_perch", "hunting fillets a perch")
	check(not DB.loot_tables.get("skin_hound", {}).get("always", []).any(func(e): return e.item.ends_with("meat")), "hounds give no meat to hunters (never dogs)")
	# weapon masteries
	inv.add_item("arming_sword", 1, true)
	inv.equip("arming_sword")
	var t: String = sk.mastery_type("main")
	check(t != "", "the main hand weapon trains a mastery (%s)" % t)
	if t != "":
		for i in 400:
			sk.mastery_hit("main")
		check(sk.mastery_level(t) > 1, "landed blows raise the %s mastery" % t)
		var saved: Dictionary = sk.serialize_ladder()
		sk.mastery = {}
		sk.apply_ladder(saved)
		check(sk.mastery_level(t) > 1, "mastery survives a save")
	check(game.titles.locked_because("swordhand") != "" or sk.mastery_level("sword") >= 10, "mastery titles are gated by mastery level")

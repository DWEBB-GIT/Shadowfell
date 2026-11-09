extends SceneTree
## The Thornford starter chains (Dan, 2026-11-04): no belt at the start, the
## first quest gives it, the cook teaches Cooking, Tobin lends a rod.
## godot --headless --path . --script res://game/tests/starter_chain_check.gd

var game
var frame := 0
var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)


func run(id: String) -> void:
	var q = game.quests
	if q.status(id) not in ["active", "ready"]:
		check(q.status(id) == "available", "%s is offered (%s)" % [id, q.status(id)])
		check(q.accept(id, true), "%s accepted" % id)
	for o in DB.quests[id].objectives:
		if o.type == "collect":
			game.inventory.add_item(o.target, int(o.get("count", 1)) - game.inventory.count(o.target))
		elif o.type == "kill":
			for n in int(o.get("count", 1)):
				q.count_kill(o.target)
		elif o.type == "talk":
			q.count_talk(o.target)
		elif o.type == "examine":
			game.world_state.examined[o.target] = true
		elif o.type == "use":
			for n in int(o.get("count", 1)):
				q.count_use(o.target, o.get("on", ""))
	check(q.complete(id), "%s handed in" % id)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_starter"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Starter", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var inv = game.inventory
		check(inv.tool_pack == null, "no belt at the start")
		game.hud.belt.toggle()
		check(not game.hud.belt.visible, "the belt stays shut without a belt")
		check(game.quests.status("vr_perch") == "locked", "Elsie's perch waits for Tobin's lesson")
		# the road in (Dan 2026-11-09): start on the west road, outside the town
		var start: Array = DB.world.playerStart.position
		check(Vector2(start[0], start[1]).distance_to(Vector2(-450, -207)) > 60, "a new player starts outside Thornford")
		check(game.quests.active == ["ni_stretch_your_legs"], "the first quest is Abel's milestone (%s)" % [game.quests.active])
		check(game.quests.status("sf_odd_jobs") == "locked", "Elsie's odd jobs wait for the road in")
		run("ni_stretch_your_legs")
		run("ni_rats_in_the_grain")
		run("ni_loose_boar")
		run("ni_the_road_in")
		check(inv.count("ni_abel_note") == 0, "Abel's note is handed to Elsie")
		run("sf_odd_jobs")
		check(inv.tool_pack != null and inv.tool_pack.id == "belt_pouch", "Iren's utility belt worn")
		check(inv.count("sf_broken_hinge") == 0, "the hinge is handed over")
		game.hud.modal = "" # the loading screen is still up in a headless run
		game.hud.belt.toggle()
		check(game.hud.belt.visible, "the belt opens once worn")
		game.hud.belt.close()
		run("sf_hungry_work")
		run("sf_a_meal_earned")
		check(game.skills.has("cooking"), "Hobb teaches Cooking")
		check(game.cooking.knows("roast_boar"), "Hobb teaches spit-roast boar")
		check(inv.count("firewood") == 0, "the firewood is used")
		game.quests.accept("sf_borrowed_rod", true)
		check(inv.count("old_rod") == 1, "Tobin lends the old rod")
		check(inv.on_belt("old_rod"), "the old rod is on the belt")
		check(game.skills.has("fishing"), "Tobin's lesson teaches Fishing")
		inv.add_item("gloomwater_perch", 1)
		check(game.quests.complete("sf_borrowed_rod"), "sf_borrowed_rod handed in")
		check(inv.count("old_rod") == 0, "the old rod goes home with Tobin")
		check(game.cooking.knows("pan_fried_perch"), "Tobin's pan perch learned")
		check(game.quests.status("vr_perch") == "available", "Elsie's perch is offered after")
		_extra()
		print("starter chain check: %s" % ("ok" if fails == 0 else "%d failed" % fails))
		quit(1 if fails else 0)
	return false


## later stages add their chains here
func _extra() -> void:
	game.progression.level = 3
	game.quests.done.in_watchmans_word = true
	game.quests.done.tf_lanterns = true
	# each trainer opens one step on (Dan 2026-11-09): Iren after her gauge,
	# Agna after the boars, Morrow once you have met him and done his soup round
	for id in ["in_farm_introduction", "vr_first_hunt", "nr_gauge", "in_hollow_introduction", "in_soup_round"]:
		game.quests.done[id] = true
	var inv = game.inventory
	for pair in [["sf_ore_for_the_forge", "mining", "mining_pick"], ["sf_hides_for_agna", "skinning", "skinning_knife"], ["sf_bitter_roots", "herbalism", "herb_knife"]]:
		var had: int = inv.count(pair[2])
		run(pair[0])
		check(game.skills.has(pair[1]), "%s teaches %s" % pair.slice(0, 2))
		check(inv.count(pair[2]) == had, "%s takes back the %s" % [pair[0], pair[2]])
	# level 5: the mayor sends a warrior to Rowan, who teaches Cleave
	check(game.quests.status("sf_calling_warden") == "locked", "the calling waits for level 5")
	check(game.quests.status("sf_calling_paladin") == "locked", "another class's calling is never offered")
	game.progression.level = 5
	run("sf_calling_warden")
	check(game.skills.knows_ability("cleave"), "Cleave arrives naturally at level 5")
	check(game.quests.accept("sf_class_warden", true), "Rowan's class quest taken")
	check(game.skills.knows_ability("cleave"), "Rowan teaches the practical use of Cleave")
	game.quests.count_use("cleave", "ridge_wolf")
	check(game.quests.objectives("sf_class_warden")[0].have == 0, "Cleave on the wrong beast does not count")
	for n in 3:
		game.quests.count_use("cleave", "vr_young_boar")
	check(game.quests.complete("sf_class_warden"), "Cleave the boars handed in")

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
	check(q.status(id) == "available", "%s is offered (%s)" % [id, q.status(id)])
	check(q.accept(id, true), "%s accepted" % id)
	for o in DB.quests[id].objectives:
		if o.type == "collect":
			game.inventory.add_item(o.target, int(o.get("count", 1)) - game.inventory.count(o.target))
		elif o.type == "kill":
			for n in int(o.get("count", 1)):
				q.count_kill(o.target)
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
	pass

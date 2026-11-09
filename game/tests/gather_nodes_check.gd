extends SceneTree
## Dan's 2026-11-09 ask: wild garlic (and every placed gathering node) is
## gathered over the gather bar, not grabbed at once, and a picked node is
## gone from the world until its respawn timer grows it back:
##   godot --headless --path . --script res://game/tests/gather_nodes_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_gather_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Gather", "warden")
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
		print("gather node checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _run() -> void:
	var loot = game.loot
	var nodes: Array = loot.active.filter(func(e): return e.def.id.begins_with("sf_garlic_"))
	check(nodes.size() > 0, "wild garlic nodes are placed")
	if nodes.is_empty():
		return
	var e: Dictionary = nodes[0]
	check(Loot.is_node(e.def), "wild garlic counts as a gathering node")
	var p = game.player
	p.position = Vector3(e.x + 1.0, p.position.y, e.z)
	var l: Dictionary = loot.lootables().filter(func(x): return x.id == e.def.id)[0]
	check(not l.area, "wild garlic is never area-looted")
	var before: int = game.inventory.count("wild_garlic")
	loot.loot_area(l)
	check(loot.gathering != null and loot.gather_bar != null, "using it starts the gather bar")
	check(game.inventory.count("wild_garlic") == before, "nothing is taken before the bar fills")
	for i in 60:
		loot.update(0.1, game.time)
	check(loot.gathering == null, "the bar finishes")
	check(game.inventory.count("wild_garlic") == before + 1, "the garlic goes in the bags")
	check(not e.group.visible and not loot.available(e), "the picked garlic is gone from the world")
	check(loot.lootables().filter(func(x): return x.id == e.def.id).is_empty(), "a picked node can't be looted")
	game.time += float(e.def.respawn) + 1.0
	loot.update(0.1, game.time)
	check(e.group.visible and loot.available(e), "it grows back on its timer")

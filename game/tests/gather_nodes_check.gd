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
	# tied to Hobb's quest: always in sight as a prop, only takeable during it
	check(e.def.get("quest") == "sf_a_meal_earned", "wild garlic is tied to Hobb's quest")
	check(e.group.visible and not loot.available(e), "before the quest the garlic stands in the world but can't be taken")
	for r in DB.quests.sf_a_meal_earned.get("requires", []):
		game.quests.done[r] = true
	game.quests.accept("sf_a_meal_earned", true)
	check(loot.available(e), "with the quest active the garlic can be gathered")
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
	_herbs()


## Dan's 2026-11-09 ask: real herbs on the new map, picked like ores, with
## wild garlic among them so the Pan-fried Perch has a source past Hobb.
func _herbs() -> void:
	var g = game.gathering
	var groups: Array = DB.nodes.get("nodeGroups", [])
	check(groups.size() >= 5, "the new map has its own herb grounds (%d)" % groups.size())
	var dry := 0
	for gr in groups:
		for k in gr.kinds:
			check(not Gathering.kind_def(k.kind).is_empty(), "%s grows a known herb (%s)" % [gr.id, k.kind])
		for p in gr.spots:
			if not Terrain.walkable(p[0], p[1]):
				dry += 1
	check(dry == 0, "every herb spot stands on walkable ground (%d not)" % dry)
	check(groups.any(func(gr): return gr.kinds.any(func(k): return k.kind == "wild_garlic")), "wild garlic grows wild somewhere")
	check(g.live().size() == groups.reduce(func(a, x): return a + int(x.live), 0), "every herb ground grows its live herbs")
	# force a garlic patch and pick it
	var n: Dictionary = g.nodes.filter(func(x): return x.kind != "")[0]
	n.kind = "wild_garlic"
	g._paint(n)
	check(n.model.ends_with("Flower_3_Group.gltf") and n.node.get_child_count() == 1, "each herb kind shows its own plant")
	game.inventory.coins += 100
	check(game.skills.learn("herbalism"), "Herbalism can be learned on the new map")
	var had: int = game.inventory.count("wild_garlic")
	game.player.place_at(n.x + 1.0, n.z)
	check(g.start(n), "picking wild garlic starts")
	var time: float = game.time + 10.0
	for i in 4:
		time += 1.0
		g.update(1.0, time)
	check(game.inventory.count("wild_garlic") > had, "wild garlic from the herb goes in the bags")

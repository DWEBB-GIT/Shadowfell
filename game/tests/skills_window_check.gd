extends SceneTree
## Dan's 2026-11-10 Skills window (RuneScape style) and semi-AFK loops:
## the unlock list, total level, skill experience drops and the tracker,
## Keep fishing's recast and idle stop, and herb patches that hold picks:
##   godot --headless --path . --script res://game/tests/skills_window_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_skillswin_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Skiller", "warden")
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
		print("skills window checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _run() -> void:
	var sk = game.skills
	for id in ["fishing", "herbalism", "alchemy", "cooking", "mining"]:
		sk.grant(id)
	# the unlock list: from the data, lowest first, no place names
	for id in ["fishing", "herbalism", "alchemy", "cooking", "mining"]:
		var list: Array = sk.unlocks(id)
		var sorted := true
		for i in range(1, list.size()):
			sorted = sorted and list[i - 1].level <= list[i].level
		check(list.size() >= 2 and sorted, "%s lists %d unlocks, lowest first" % [id, list.size()])
	var fish: Array = sk.unlocks("fishing")
	check(fish.any(func(u): return u.kind == "perk") and fish.any(func(u): return u.kind == "rank") and fish.any(func(u): return u.kind == "tool"), "fishing unlocks show perks, rank limits and rods")
	var names := {}
	for w in Layout.water:
		names[str(w.get("name", ""))] = true
	check(not fish.any(func(u): return names.has(u.text)), "no water is named: where to fish is for the player to find")
	check(sk.total_level() >= 5, "total level adds up the skills (%d)" % sk.total_level())
	# experience drops and the AFK share
	var seen := []
	game.events.on("skillXp", func(e): seen.append(e))
	sk.xp["fishing"] = 0
	var roll: Callable = game.random
	game.random = func() -> float: return 0.45
	sk.gain("fishing", "orange", 0.6) # 80% x 0.6 = 48%: lands
	check(seen.size() == 1 and int(seen[0].amount) == 1 and int(sk.xp.fishing) == 1, "a semi-AFK catch can still give a skill point and shows a drop")
	game.random = func() -> float: return 0.5
	sk.gain("fishing", "orange", 0.6) # 48%: misses
	check(seen.size() == 1 and int(sk.xp.fishing) == 1, "the AFK share lowers the chance")
	game.random = roll
	sk.tracked = "fishing"
	game.hud.skill_tracker.update(1.0)
	check(game.hud.skill_tracker.visible and game.hud.skill_tracker.title.text.begins_with("Fishing"), "the tracked skill shows on the HUD")
	# the window: a tile per learned skill and a ? per one still to find
	var items = game.hud.items
	items.show_window("skills")
	items._render_skills()
	check(items.skills_win.title.text == "Skills", "the window is called Skills")
	check(items.skills_win.panel.visible and items.skill_pick == "fishing", "Skills opens on the tracked skill")
	var grids: Array = items.skills_win.inner.find_children("*", "GridContainer", true, false)
	var tiles: int = grids[0].get_child_count() if not grids.is_empty() else 0
	check(tiles == DB.skills.size(), "one tile for every skill, learned or not (%d)" % tiles)
	var scrolls: Array = items.skills_win.inner.find_children("*", "ScrollContainer", true, false)
	check(not scrolls.is_empty(), "the unlock list scrolls on its own")
	items.skill_pick = "combat"
	items._render_skills()
	check(items.skills_win.panel.visible, "Combat shows the character level")
	# Keep fishing: a finished cast schedules the next; idle ends it
	var f = game.fishing
	sk.keep_fishing = true
	f.state = {"bob": Node3D.new(), "line": Node3D.new(), "x": game.player.position.x + 4, "z": game.player.position.z, "from": game.player.position}
	f.stop(false, true)
	check(f.again != null, "Keep fishing casts again after a catch")
	game.input.last_active_ms = Time.get_ticks_msec() - int(DB.CONFIG.afk.idleStop * 1000) - 1000
	f.update(0.1)
	check(f.again == null, "a long idle ends Keep fishing")
	game.input.last_active_ms = Time.get_ticks_msec()
	sk.keep_fishing = false
	f.state = {"bob": Node3D.new(), "line": Node3D.new(), "x": 0.0, "z": 0.0, "from": game.player.position}
	f.stop(false, true)
	check(f.again == null, "without Keep fishing nothing recasts")
	# a herb patch holds picks: one click keeps picking until it is bare
	var g = game.gathering
	var live: Array = g.nodes.filter(func(x): return x.kind != "")
	check(not live.is_empty(), "herb patches grow")
	if live.is_empty():
		return
	var n: Dictionary = live[0]
	n.kind = "wild_garlic"
	n.picks = 3
	g._paint(n)
	game.player.place_at(n.x + 1.0, n.z)
	var had: int = game.inventory.count("wild_garlic")
	check(g.start(n), "picking starts")
	var time: float = game.time + 10.0
	for i in 12:
		time += 1.0
		g.update(1.0, time)
	check(game.inventory.count("wild_garlic") - had == 3, "three picks from one click (%d)" % (game.inventory.count("wild_garlic") - had))
	check(n.kind == "", "the patch is bare after its last pick")

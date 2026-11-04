extends SceneTree
## Real-world content, alternate-route gates, gathering, puzzle and save checks.
const EditorStore := preload("res://addons/shadowfell_data/store.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")
var game
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)

func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://campaign_world_check_%d" % Time.get_ticks_usec()
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Campaign", "warden")
	check(made.ok, "isolated character created")
	game.enter_world(made.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		await process_frame
		frames += 1
		if frames > 4000:
			check(false, "world loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	var store := EditorStore.new()
	store.load_all()
	var problems := Checks.run(store)
	check(problems.is_empty(), "Godot authoring data validates: " + str(problems))
	check(DB.world.questHubs.size() == 34, "34 onward hubs plus the existing opening")
	check(DB.world.campaignScope.approved_dungeon_layouts == 7, "seven approved dungeon layouts")
	var dungeon_ids := {}
	for entrance in DB.world.dungeonEntrances:
		dungeon_ids[entrance.dungeon] = true
		check(Terrain.walkable(entrance.position[0], entrance.position[1]), "dungeon approach is reachable: " + entrance.name)
	check(dungeon_ids.size() == 7 and DB.world.dungeonEntrances.size() == 8, "two finale approaches share one of seven layouts")
	var cap_patrols: Array = DB.quests.values().filter(func(q): return str(q.id).begins_with("wm_return_") and int(q.get("minLevel", 1)) == 50)
	check(cap_patrols.size() == 3 and cap_patrols.all(func(q): return int(q.reward.xp) == 0), "three public level-50 patrols grant no character XP")
	var placement_errors := []
	for sp in DB.world.npcSpawns + DB.world.enemySpawns + DB.world.placedLoot:
		var id: String = str(sp.get("id", sp.get("npc", "")))
		if id.begins_with("wm_") and not Terrain.walkable(sp.position[0], sp.position[1]):
			placement_errors.append(id)
	check(placement_errors.is_empty(), "all new residents, enemies and pickups stand on walkable land: " + str(placement_errors))
	var road_errors := []
	for road in DB.world.roads:
		if not str(road.id).begins_with("wm_"):
			continue
		for i in road.points.size() - 1:
			var a := Vector2(road.points[i][0], road.points[i][1])
			var b := Vector2(road.points[i + 1][0], road.points[i + 1][1])
			for n in range(ceili(a.distance_to(b) / 2.0) + 1):
				var p := a.lerp(b, minf(1, n * 2.0 / maxf(0.01, a.distance_to(b))))
				var resolved: Vector3 = game.collision.resolve(Vector3(p.x, Terrain.height_at(p.x, p.y), p.y), 0.4)
				if not Terrain.walkable(p.x, p.y) or Vector2(resolved.x, resolved.z).distance_to(p) > 1.0:
					if road_errors.size() < 15:
						road_errors.append("%s @ %.1f,%.1f" % [road.id, p.x, p.y])
	check(road_errors.is_empty(), "new road centres are walkable and clear: " + str(road_errors))
	for hub in DB.world.questHubs:
		var lead = game.npcs.by_id("wm_" + hub.id + "_lead")
		check(lead != null and DB.region_at(hub.position[0], hub.position[1]).name == hub.name, "resident and level district: " + hub.name)
	check(game.quests.status("vr_first_hunt") == "active", "original opening still starts")
	check(game.quests.status("agna_first_hides") == "locked" and game.quests.status("agna_wolf_pelts") == "locked", "retained NPC cannot offer legacy-map objectives here")
	var q: String = "wm_lantern_crossing_work"
	game.progression.level = 1
	game.quests.done.vr_crypt = true
	check(game.quests.status(q) == "locked", "onward quest honours its minimum level")
	game.progression.level = 8
	check(game.quests.status(q) == "available", "opening completion unlocks an onward route")
	game.quests.done.wm_mossreed_landing_record = true
	check(game.quests.status("wm_rillbank_quays_work") == "available", "marsh outcome can unlock the river's next chapter")
	check(game.quests.status("wm_millward_work") == "locked", "a later chapter cannot skip its prerequisite milestone")
	check(game.quests.accept(q), "accept first onward quest")
	game.world_state.examined["poi:wm_lantern_crossing_worksite"] = true
	for i in 3:
		game.quests.count_kill("wm_lantern_crossing_threat")
	check(game.quests.complete(q), "first onward work quest completes with recorded evidence and kills")
	var record: String = "wm_lantern_crossing_record"
	check(game.quests.accept(record), "accept record recovery")
	var entries: Array = game.loot.active.filter(func(e): return e.def.id == "wm_lantern_crossing_record_packet")
	check(entries.size() == 1, "record exists as a real world pickup")
	if not entries.is_empty():
		game.player.place_at(entries[0].x + 0.8, entries[0].z)
		check(game.loot.start_gather(entries[0]), "record can be gathered")
		game.loot.update(3.0, game.time)
		check(game.quests.complete(record), "physical record can be handed in")
		check(not game.inventory.has("wm_lantern_crossing_record_packet"), "hand-in consumes the record")
	game.progression.level = 20
	var puzzle_id: String = "wm_millward_allocation"
	check(game.quests.accept("wm_millward_local"), "independent local dispute is available")
	var puzzle: Dictionary = DB.world.puzzles.filter(func(p): return p.id == puzzle_id)[0]
	for i in puzzle.nodes.size():
		var node: Dictionary = puzzle.nodes[i]
		game.player.place_at(puzzle.position[0] + node.offset[0], puzzle.position[1] + node.offset[1])
		for press in int(puzzle.answer[i]):
			game.puzzles.operate(puzzle_id, i)
			check(int(game.puzzles.state(puzzle_id).values[i]) == press + 1, "allocation handle responds")
	game.player.place_at(puzzle.position[0], puzzle.position[1] + 2)
	check(game.puzzles.operate(puzzle_id, "check") and game.puzzles.solved(puzzle_id), "local dispute has a real solvable mechanism")
	check(game.quests.complete("wm_millward_local"), "local puzzle quest hands in")
	check(game.save.save().ok and game.save.read().status == "ok", "campaign quest and puzzle state saves correctly")
	if OS.get_cmdline_user_args().size() > 0:
		await _pictures(OS.get_cmdline_user_args()[0])
	print("campaign_world_check: %d failed" % failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)

func _pictures(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for id in ["lantern_crossing", "mossreed_landing", "scribes_rest", "hearthwatch", "wellward"]:
		var hub: Dictionary = DB.world.questHubs.filter(func(h): return h.id == id)[0]
		game.player.place_at(hub.position[0], hub.position[1])
		game._snap_camera()
		game.world.land.update(game.player.position, true)
		game._bwk = -1
		game._update_region(2)
		game._place_camera()
		game.enemies.update(0.0)
		game.npcs.update(0.0)
		game.hud.update(8)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("campaign-%s.png" % id))
	for spot in [["watch-path", -450.0, -340.0], ["red-rock", -86.0, 458.0]]:
		game.player.place_at(spot[1], spot[2])
		game._snap_camera()
		game.world.land.update(game.player.position, true)
		game._bwk = -1
		game._update_region(2)
		game._place_camera()
		game.enemies.update(0.0)
		game.npcs.update(0.0)
		game.hud.update(8)
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("terrain-%s.png" % spot[0]))
	game.hud.world_map.open()
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("campaign-world-map.png"))

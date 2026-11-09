extends SceneTree
## Cap boundaries, legacy-cap saves and the level 1-2 XP price.
var game
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("ok: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://level_50_check_%d" % Time.get_ticks_usec()
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Cap", "warden")
	game.enter_world(made.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		await process_frame
		frames += 1
		if frames > 3000:
			check(false, "test world loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	check(DB.CONFIG.progression.maxLevel == 50, "configured character cap is 50")
	check(DB.xp_for_next_level(1) == 280, "level 1 to 2 still takes 280 XP")
	var total := 0
	for level in range(1, 50):
		total += DB.xp_for_next_level(level)
	check(total > 1000000, "the pacing-plan curve totals about 1.45 million XP across 49 gains")
	var p = game.progression
	p.level = 49
	p.xp = p.xp_to_next - 1
	p.rested = 250
	p.add_xp(1)
	check(p.level == 50 and p.xp == 0 and p.rested == 0, "one XP crosses 49 to 50 and clears overflow/rested")
	check(p.add_xp(1000000) == 0 and p.level == 50 and p.xp == 0, "large awards cannot create level 51")
	# its prerequisite first (Elsie's odd jobs), handed in for real so the
	# save holds what that quest gives
	for need in DB.quests.vr_reed_message.get("requires", []):
		if game.quests.status(need) == "available":
			game.quests.accept(need) # (Odd Jobs is taken on entering the world)
		game.quests.count_talk(DB.quests[need].turnIn) # walk the hinge to Iren
		check(game.quests.complete(need), "prerequisite %s completes at the cap" % need)
	var coins_before: int = game.inventory.coins
	check(game.quests.accept("vr_reed_message") and game.quests.complete("vr_reed_message"), "quests can still complete at the cap")
	check(game.inventory.coins == coins_before + 8 and p.level == 50 and p.xp == 0, "capped quest pays currency without character XP")
	check(game.save.save().ok and game.save.read().status == "ok", "a level-50 character saves and reads normally")
	var saved: Dictionary = game.save.read().data
	var inventory: Dictionary = saved.inventory.duplicate(true)
	var quests: Dictionary = saved.quests.duplicate(true)
	var quest_states := {}
	for id in quests.accepted + quests.done:
		quest_states[id] = game.quests.status(id)
	for previous_level in [51, 99, 100]:
		var legacy := saved.duplicate(true)
		legacy.progression = {"level": previous_level, "xp": 1234, "rested": 500}
		check(SaveManager.validate_save(legacy).is_empty(), "previous-cap save validates at %d" % previous_level)
		game.save.apply(legacy)
		check(p.level == 50 and p.xp == 0 and p.rested == 0, "previous level %d normalizes to 50" % previous_level)
		# Save/load normalizes JSON numbers and removes completed IDs from the
		# accepted list. Compare actual possessions and meaningful quest state.
		var quests_preserved: bool = quest_states.keys().all(func(id): return game.quests.status(id) == quest_states[id])
		var inventory_preserved: bool = JSON.parse_string(JSON.stringify(game.inventory.serialize())) == JSON.parse_string(JSON.stringify(inventory))
		check(inventory_preserved, "possessions survive legacy-cap normalization")
		check(quests_preserved and game.quests.focus == quests.focus, "quest progress survives legacy-cap normalization")
	var invalid := saved.duplicate(true)
	invalid.progression.level = 101
	check(not SaveManager.validate_save(invalid).is_empty(), "unrecognized level 101 is still rejected")
	p.apply({"level": 5, "xp": 123, "rested": 45})
	check(p.level == 5 and p.xp == 123 and p.rested == 45, "ordinary lower-level progress is preserved")
	print("level_50_check: %d failed" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

extends SceneTree
## Real quest pickup/hand-in/combat and physical mechanism regression checks.
const EditorStore := preload("res://addons/shadowfell_data/store.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")
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
	Store.dir = "user://quiet_levy_check_%d" % Time.get_ticks_usec()
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Levy Tester", "warden")
	check(made.ok, "isolated character created")
	game.enter_world(made.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		await process_frame
		frames += 1
		if frames > 3000:
			check(false, "world loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	var capture_args := OS.get_cmdline_user_args()
	if capture_args.has("--shots-only") and DisplayServer.get_name() != "headless":
		await _pictures(capture_args[0])
		print("quiet_levy_capture: complete")
		game.queue_free()
		await process_frame
		quit(0)
		return
	var store := EditorStore.new()
	store.load_all()
	var problems := Checks.run(store)
	check(problems.is_empty(), "authored quests/mechanisms validate: %s" % str(problems))
	check(DB.region_at(-350, -275).id == "nr_orchard" and DB.region_at(-560, -300).id == "nr_briar", "fields and woodland have separate quest zones")
	check(DB.quests.tf_bell.requires == ["tf_lanterns"] and DB.quests.vr_crypt.requires == ["vr_names"], "side quests never gate the main story")
	var additions: Array = DB.quests.values().filter(func(q): return q.id.begins_with("nr_"))
	check(additions.size() == 12, "twelve original additions are installed")
	check(additions.reduce(func(n, q): return n + q.reward.xp, 0) == 220, "new quest XP stays within the 220 XP district budget")
	check(game.quests.status("nr_water_rights") == "locked" and not game.puzzles.operate("nr_water_regulator", 0), "water lesson waits for Heda's trade message")
	for id in ["nr_gauge", "nr_timber", "nr_water_notes", "nr_reverse_route", "nr_bedding", "nr_shelter_tracks", "nr_bottle_labels", "nr_pollinator_notes"]:
		_finish(id)
	check(game.quests.done.has("nr_timber") and not game.inventory.has("nr_handle_billet"), "billets are delivered to Iren and consumed")
	_finish("vr_reed_message")
	check(game.quests.accept("nr_water_rights"), "Tobin offers the local water dispute after the trade")
	game.interaction.examine("nr_water_board")
	check(game.quests.status("nr_water_rights") == "active", "reading an allocation clue does not solve the puzzle")
	check(not game.puzzles.operate("nr_water_regulator", 0) and game.puzzles.state("nr_water_regulator").values == [0, 0, 0], "remote calls cannot turn controls")
	_press("nr_water_regulator", "check")
	check(not game.puzzles.solved("nr_water_regulator") and game.quests.status("nr_water_rights") == "active", "incorrect flow remains retryable and grants no credit")
	_press("nr_water_regulator", 0)
	_press("nr_water_regulator", 1)
	var partial: Dictionary = game.save.serialize()
	game.world_state.puzzles.clear()
	game.world_state.apply(partial.world)
	check(game.puzzles.state("nr_water_regulator").values == [1, 1, 0], "partial dial positions survive save serialization")
	_press("nr_water_regulator", "reset")
	check(game.puzzles.state("nr_water_regulator").values == [0, 0, 0], "reset closes the handles safely")
	for n in [0, 1, 1, 2]:
		_press("nr_water_regulator", n)
	_press("nr_water_regulator", "check")
	check(game.puzzles.solved("nr_water_regulator") and game.quests.status("nr_water_rights") == "ready", "real dial solution advances the quest")
	_hand_in("nr_water_rights")
	var coins: int = game.inventory.coins
	_press("nr_water_regulator", "check")
	check(not game.quests.complete("nr_water_rights") and game.inventory.coins == coins, "solved controls and repeated hand-ins cannot duplicate rewards")
	for id in ["vr_first_hunt", "tf_lanterns", "nr_overtime", "tf_bell", "nr_quiet_hours", "vr_names", "vr_crypt"]:
		_finish(id)
	check(game.quests.accept("nr_last_word"), "memorial epilogue unlocks after the burial seals")
	game.interaction.examine("nr_memorial_verse")
	check(game.quests.status("nr_last_word") == "active", "reading the memorial verse does not count as playing it")
	_press("nr_memorial_bells", 1)
	check(game.puzzles.state("nr_memorial_bells").progress == 0, "wrong first bell gives a safe retry")
	_press("nr_memorial_bells", 0)
	_press("nr_memorial_bells", 2)
	partial = game.save.serialize()
	game.world_state.puzzles.clear()
	game.world_state.apply(partial.world)
	check(game.puzzles.state("nr_memorial_bells").progress == 2, "a half-played verse resumes after save/load")
	_press("nr_memorial_bells", 0)
	check(game.puzzles.state("nr_memorial_bells").progress == 0, "an incorrect later note restarts only the verse")
	for n in [0, 2, 1, 3]:
		_press("nr_memorial_bells", n)
	check(game.puzzles.solved("nr_memorial_bells") and game.quests.status("nr_last_word") == "ready", "four physical bells solve the memorial")
	_hand_in("nr_last_word")
	_press("nr_memorial_bells", "reset")
	check(game.puzzles.solved("nr_memorial_bells"), "completed memorial cannot be accidentally reset")
	var lyra = game.npcs.by_id("vr_lyra")
	game.dialogue.open(lyra)
	check(game.dialogue.page.text.contains("municipal expense"), "Lyra acknowledges the memorial with its own aftermath")
	game.dialogue.close()
	check(game.save.save().ok and game.save.read().status == "ok", "complete narrative progress saves and validates")
	var saved: Dictionary = game.save.read().data
	game.save.apply(saved)
	game.puzzles.refresh()
	check(game.puzzles.solved("nr_memorial_bells") and game.puzzles.solved("nr_water_regulator") and game.quests.status("nr_last_word") == "done", "full save apply reconstructs both solved mechanisms and quest outcomes")
	var old: Dictionary = saved.duplicate(true)
	old.world.erase("puzzles")
	check(SaveManager.validate_save(old).is_empty(), "older saves without puzzle state remain valid")
	var invalid: Dictionary = saved.duplicate(true)
	invalid.world.puzzles.nr_memorial_bells.progress = "three"
	check(not SaveManager.validate_save(invalid).is_empty(), "invalid puzzle state is rejected before applying a save")
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not args.is_empty():
		await _pictures(args[0])
	print("quiet_levy_check: %d failed" % failures)
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)


func _finish(id: String) -> void:
	if game.quests.status(id) == "available":
		check(game.quests.accept(id), "accept " + id)
	check(game.quests.status(id) in ["active", "ready"], "quest can be worked: " + id)
	for o in DB.quests[id].objectives:
		match o.type:
			"examine":
				var points: Array = game.world.examine_points.filter(func(p): return p.id == o.target)
				check(not points.is_empty(), "clue is physically placed: " + o.target)
				if not points.is_empty():
					var point: Dictionary = points[0]
					_near(point.x, point.z)
					game.interaction.examine(o.target)
			"collect":
				var nodes: Array = game.loot.active.filter(func(e): return e.def.get("quest") == id and e.def.get("reward", {}).get("item") == o.target)
				check(nodes.size() >= int(o.count), "enough quest pickups placed: " + o.target)
				for node in nodes.slice(0, int(o.count)):
					_near(node.x, node.z)
					check(game.loot.start_gather(node), "actual gather starts: " + node.def.id)
					game.loot.update(3.0, game.time)
			"kill":
				_defeat(o.target, int(o.get("count", 1)))
	_hand_in(id)


func _hand_in(id: String) -> void:
	check(game.quests.status(id) == "ready", "objectives ready: " + id)
	var n = game.npcs.by_id(DB.quests[id].turnIn)
	check(n != null, "actual recipient present: " + id)
	if n == null:
		return
	game.player.place_at(n.position.x + 1, n.position.z)
	game.dialogue.open(n)
	game.dialogue.choose("quest:" + id)
	check(game.dialogue.page.options.any(func(o): return o.id == "complete"), "recipient offers hand-in: " + id)
	game.dialogue.choose("complete")
	check(game.quests.status(id) == "done", "story completed: " + id)
	game.dialogue.close()


func _near(x: float, z: float) -> void:
	var found := false
	for i in 16:
		var angle := TAU * i / 16.0
		var at := Vector3(x + cos(angle), 0, z + sin(angle))
		at.y = Terrain.height_at(at.x, at.z)
		var resolved: Vector3 = game.collision.resolve(at, game.player.radius)
		if Terrain.walkable(resolved.x, resolved.z) and Vector2(resolved.x - x, resolved.z - z).length() < 2.1 and not game.collision.wall_between(resolved.x, resolved.z, x, z):
			game.player.place_at(resolved.x, resolved.z)
			found = true
			break
	check(found, "interaction approach is reachable at %.1f, %.1f" % [x, z])


func _press(id: String, action) -> void:
	var p := WorldPuzzles.definition(id)
	var off: Array = p.nodes[action].offset if action is int else p.get(action + "Offset", [0, 2])
	_near(p.position[0] + off[0], p.position[1] + off[1])
	var key := "puzzle:%s:%s" % [id, str(action)]
	var choices: Array = game.interaction.click_points().filter(func(c): return c.key == key)
	check(choices.size() == 1, "control is clickable: " + key)
	if not choices.is_empty():
		choices[0].run.call()


func _defeat(type: String, count: int) -> void:
	var enemies: Array = game.enemies.list.filter(func(e): return e.type == type and not e.dead)
	check(enemies.size() >= count, "enough living combat targets: " + type)
	game.random = func(): return 0.5
	for enemy in enemies.slice(0, count):
		game.player.place_at(enemy.position.x + 0.9, enemy.position.z)
		game.targeting.engage(enemy)
		for swing in 400:
			if enemy.dead:
				break
			game.combat.resolve_player_strike({"x": enemy.position.x, "z": enemy.position.z})
		check(enemy.dead, "real combat defeats " + enemy.id)
	for slot in game.inventory.equipment:
		var item = game.inventory.equipment[slot]
		if item is Dictionary:
			item.erase("dur")
	game.inventory._equipment_changed()


func _pictures(out: String) -> void:
	DirAccess.make_dir_recursive_absolute(out)
	game.hud.banner_queue.clear()
	game.hud.banner_time = 0
	game.hud.banner.visible = false
	game.hud.banner_band.visible = false
	game.targeting.clear()
	for spot in [["water-regulator", -411, -178], ["memorial", -366, -439], ["woodland-shelter", -580, -295]]:
		game.player.place_at(spot[1], spot[2])
		game._snap_camera()
		game.world.land.update(game.player.position, true)
		game._bwk = -1
		game._update_region(2)
		game._place_camera()
		game.puzzles.refresh()
		game.hud.update(8)
		for frame in 12:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(out.path_join("quiet-%s.png" % spot[0])) == OK, "rendered " + spot[0])

extends SceneTree
## Isolated play-slice checks, with optional real rendered captures:
## godot --headless --path . --script res://game/tests/thornford_check.gd
## Omit --headless and pass -- output_directory for screenshots.
var game
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", what)
	else:
		print("ok: ", what)


func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://thornford_check_%d" % Time.get_ticks_usec()
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Reach", "warden")
	check(made.ok, "separate test character created")
	game.enter_world(made.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		await process_frame
		frames += 1
		if frames > 2400:
			check(false, "world finishes loading")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	check(game.player.position.distance_to(Vector3(-450, Terrain.height_at(-450, -203), -203)) < 0.1, "new character starts in Thornford")
	check(game.quests.status("vr_first_hunt") == "active" and not game.quests.accepted.has("missing_delivery"), "opening follows the level-one orchard story")
	check(DB.region_at(-450, -203).name == "Thornford" and DB.region_at(267, -155).name == "The Uncharted Marches", "regional names use authored bounds")
	var route_failures := []
	for road in DB.world.roads:
		if not str(road.id).begins_with("tf_") and not str(road.id).begins_with("vr_"):
			continue
		for i in road.points.size() - 1:
			var a := Vector2(road.points[i][0], road.points[i][1])
			var b := Vector2(road.points[i + 1][0], road.points[i + 1][1])
			for n in ceili(a.distance_to(b)) + 1:
				var p := a.lerp(b, minf(1, n / a.distance_to(b)))
				var pos := Vector3(p.x, Terrain.height_at(p.x, p.y), p.y)
				var resolved: Vector3 = game.collision.resolve(pos, DB.CONFIG.player.radius)
				if not Terrain.walkable(p.x, p.y) or Vector2(resolved.x, resolved.z).distance_to(p) > 0.9:
					route_failures.append("%s at %s" % [road.id, p])
	check(route_failures.is_empty(), "all authored road centres are walkable and clear: %s" % str(route_failures.slice(0, 5)))
	for sp in DB.world.npcSpawns + DB.world.enemySpawns + DB.world.placedLoot:
		var id := str(sp.get("id", sp.get("npc", "")))
		if id.begins_with("tf_") or id.begins_with("vr_"):
			check(Terrain.walkable(sp.position[0], sp.position[1]), "authored spawn is on open ground: " + id)
	for npc in ["tf_rowan", "tf_elsie", "tf_iren", "tf_scout"]:
		var n = game.npcs.by_id(npc)
		check(n != null and Assets.has(n.def.model), "resident has a real model: " + npc)
		game.dialogue.open(n)
		check(not str(game.dialogue.page.text).is_empty(), "resident has a greeting: " + npc)
	game.dialogue.close()
	var rotation := Vector3.ZERO
	for z in [DB.CONFIG.camera.zoomMin, DB.CONFIG.camera.zoomDefault, DB.CONFIG.camera.zoomMax]:
		game.zoom = z
		game._snap_camera()
		if rotation == Vector3.ZERO:
			rotation = game.camera.rotation
		check(game.camera.rotation.distance_to(rotation) < 0.001, "fixed camera pitch at zoom %.2f" % z)
		check(game.env.fog_depth_begin > game.camera.position.distance_to(game.camera_target), "player remains in clear air at zoom %.2f" % z)
	check(game.get_viewport().scaling_3d_scale == 1.0 and game.get_viewport().msaa_3d == Viewport.MSAA_4X, "native resolution with edge smoothing")
	check(DB.CONFIG.player.speed == 6.4, "movement keeps the 7 yards (6.4 m) a second base speed")
	game.zoom = DB.CONFIG.camera.zoomDefault
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not args.is_empty():
		await _captures(args[0])
	_defeat("vr_young_boar", 3)
	game.interaction.examine("poi:vr_meadow")
	check(game.quests.complete("vr_first_hunt"), "level-one orchard story completes")
	check(game.quests.accept("tf_lanterns"), "watch story unlocks after the first hunt")
	game.interaction.examine("poi:tf_cairn")
	_defeat("tf_revenant", 3)
	check(game.quests.status("tf_lanterns") == "ready" and game.quests.complete("tf_lanterns"), "real enemy defeat events complete the first quest")
	check(game.quests.accept("tf_briar"), "scout's next quest unlocks")
	game.interaction.examine("poi:tf_hollow")
	_defeat("tf_wolf", 3)
	check(game.quests.complete("tf_briar"), "woodland loop quest completes and rewards a tool pack")
	check(game.progression.level >= 3, "opening rewards reach the first class training level")
	var train: Array = game.dialogue.train_rows("tf_rowan")
	check(train.any(func(r): return r.id == "spell:cleave" and r.state == "learn"), "resident captain offers the Warden's unlocked ability")
	check(game.skills.learn_spell("cleave"), "earned coins can buy the first new combat ability")
	check(game.action_bar.slots.slice(0, 6).has("cleave"), "learned combat spell goes on a combat slot")
	check(game.quests.accept("tf_bell"), "final watch quest unlocks")
	game.interaction.examine("poi:tf_watch")
	game.interaction.examine("poi:tf_shrine")
	_defeat("tf_keeper", 1)
	check(game.quests.complete("tf_bell") and game.world_state.flags.has("tf_reach_safe"), "Bellkeeper defeat completes the district's story")
	check(game.quests.accept("tf_herbs"), "optional gathering quest can be accepted")
	for id in ["tf_herb_0", "tf_herb_1", "tf_herb_2"]:
		var patches: Array = game.loot.active.filter(func(e): return e.def.id == id)
		check(not patches.is_empty(), "flower patch exists: " + id)
		if not patches.is_empty():
			game.loot.collect(patches[0])
	check(game.quests.status("tf_herbs") == "ready" and game.quests.complete("tf_herbs"), "three real flower patches complete the optional gathering quest")
	var saved: Dictionary = game.save.save()
	check(saved.ok and game.save.read().status == "ok", "district progress saves and validates")
	game.hud.world_map.open()
	check(game.hud.world_map._survey != null, "large regional map surveys the actual terrain")
	game.hud.world_map.visible = false
	print("thornford_check: %d failed" % failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _defeat(type: String, count: int) -> void:
	var foes: Array = game.enemies.list.filter(func(e): return e.type == type)
	check(foes.size() >= count, "encounter exists: " + type)
	game.random = func(): return 0.5
	for foe in foes.slice(0, count):
		game.player.place_at(foe.position.x + 0.9, foe.position.z)
		game.targeting.engage(foe)
		for swing in 300:
			if foe.dead:
				break
			game.combat.resolve_player_strike({"x": foe.position.x, "z": foe.position.z})
		check(foe.dead, "combat damage defeats " + foe.id)


func _captures(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for spot in [["village", -450, -203], ["lantern-road", -465, -291], ["briarwood", -575, -275], ["old-watch", -450, -414], ["dawnstone", -415, -477]]:
		game.player.place_at(spot[1], spot[2])
		game._snap_camera()
		game.world.land.update(game.player.position, true)
		game._update_region(1)
		game._place_camera()
		# Advance HUD fades in the paused test simulation before capturing.
		game.hud.update(8.0)
		game.hud.minimap._refresh_overhead(true)
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("thornford-%s.png" % spot[0]))
	game.player.place_at(-450, -300)
	game.hud.world_map.open()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("thornford-region-map.png"))

extends SceneTree
## Isolated integration checks and optional rendered captures for the expansion.
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
	Store.dir = "user://reach_village_check_%d" % Time.get_ticks_usec()
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var character: Dictionary = game.roster.create("Village", "warden")
	check(character.ok, "isolated test character created")
	game.enter_world(character.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		await process_frame
		frames += 1
		if frames > 3000:
			check(false, "game loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	var store := EditorStore.new()
	store.load_all()
	var problems := Checks.run(store)
	check(problems.is_empty(), "active-map authoring content validates: %s" % str(problems))
	check(game.quests.status("vr_first_hunt") == "active" and game.quests.status("tf_lanterns") == "locked", "new character starts with a level-one hunt before the undead story")
	check(not DB.quests.tf_bell.requires.has("tf_briar"), "wolf side quest is independent of the main story")
	check(not DB.quests.vr_names.requires.has("vr_perch") and not DB.quests.vr_crypt.requires.has("vr_hollow_story"), "fishing and local tales do not gate the main story")
	var local_quests := ["vr_fence_dispute", "vr_pig_wolf", "vr_reed_message", "vr_lost_brooch"]
	for id in local_quests:
		check(DB.quests[id].requires.is_empty(), "local story can stand independently: " + id)
	var smith = game.npcs.by_id("tf_iren")
	var woodcutter = game.npcs.by_id("vr_osric")
	check(smith != null and smith.def.has("anvil"), "smith works at his actual forge anvil")
	check(woodcutter != null and woodcutter.model.find_child("WorkTool", true, false) != null, "woodcutter has a real held axe")
	if woodcutter != null:
		woodcutter.work_timer = 0
		woodcutter.update(0.1, game.player)
		check(woodcutter.rig.action != null, "woodcutter performs his work between conversations")
	var pigs: Array = game.enemies.list.filter(func(e): return e.type == "vr_farm_pig")
	check(pigs.size() == 3 and pigs.all(func(e): return e.protected), "farm has three surviving protected pigs")
	var model: Node3D = game.player.model
	check(is_equal_approx(model.scale.x, DB.CONFIG.player.visualScale), "player body and attached equipment use the readability scale")
	check(is_equal_approx(game.player.radius, 0.4) and DB.CONFIG.player.speed == 6.4, "readability does not alter collision radius or movement speed")
	game.zoom = DB.CONFIG.camera.zoomDefault
	game._snap_camera()
	var body_height: float = game.camera.unproject_position(game.player.position).distance_to(game.camera.unproject_position(game.player.position + Vector3(0, 2.15 * DB.CONFIG.player.visualScale, 0)))
	check(body_height > 32, "character-height projection remains readable at 720p (%.1f pixels)" % body_height)
	var mesh := Land._grass_blade()
	check(mesh.get_aabb().size.y < 0.24 and mesh.get_faces().size() > 30, "grass is a short multi-leaf clump, not oversized spear triangles")
	check(Assets.has("thorn_boar") and Assets.model_path("thorn_boar").ends_with(".tscn"), "boars use a real authored native model")
	var boar := Assets.instance("thorn_boar")
	check(boar.find_child("Tusk-1", true, false) != null and boar.find_child("Snout", true, false) != null, "boar has a distinct snout and tusks")
	boar.free()
	var teachers := {"warden": "tf_rowan", "rogue": "vr_rogue", "ranger": "tf_scout", "occultist": "vr_morrow", "paladin": "vr_lyra"}
	for type in teachers:
		check(DB.archetypes[type].trained.all(func(t): return t.trainer == teachers[type]) and game.npcs.by_id(teachers[type]) != null, "resident class trainer: " + type)
	check(DB.skills.fishing.trainer == "vr_tobin" and game.npcs.by_id("vr_tobin") != null, "fishing is taught beside Willow Pond")
	var guards: Array = game.enemies.list.filter(func(e): return e.type == "vr_watchman")
	check(guards.size() == 2 and guards.all(func(e): return e.protected), "village guards are present and protected from accidental attacks")
	check(Law.jurisdiction_at(-450, -203).get("reeve") == "vr_mayor", "the mayor serves the local watch jurisdiction")
	check(DB.region_at(-343, -456).name == "Mourning Hollow", "graveyard has its own region and level band")
	check(Terrain.gloom(-343, -456) > 0.8 and Terrain.gloom(-450, -203) < 0.2, "haunted lighting transitions independently of the village")
	for place in [[-395, -171], [-523, -217], [-300, -404]]:
		check(Terrain.walkable(place[0], place[1]), "fishing approach is walkable: %s" % str(place))
	for pond in ["vr_willow_pond", "vr_mill_pool", "vr_widow_pool"]:
		var rows: Array = Layout.water.filter(func(v): return v.id == pond)
		check(rows.size() == 1 and DB.loot_tables.has(rows[0].fishTable), "fishable pond has a real catch table: " + pond)
		if not rows.is_empty():
			var at: Array = rows[0].position
			check(not Terrain.walkable(at[0], at[1]), "pond water blocks walking: " + pond)
	# Test the actual door, roof cutaway and resting behaviour.
	game.player.place_at(-478, -204)
	for x in range(-478, -462):
		var desired := Vector3(x, Terrain.height_at(x, -204), -204)
		var resolved: Vector3 = game.collision.resolve(desired, game.player.radius)
		check(Vector2(resolved.x - x, resolved.z + 204).length() < 0.8, "inn doorway is clear at x=%d" % x)
	game.player.place_at(-465, -204)
	game._snap_camera()
	check(game.world.indoors != null and game.world.indoors.def.id == "vr_lantern_inn", "Lantern Inn can be entered")
	check(game.camp.resting == "inn", "standing inside the inn grants a real rest area")
	game.player.health = 10
	game.afterlife.wounds = 1
	game.inn.wake("tf_elsie")
	check(game.player.health == game.player.max_health and game.afterlife.wounds == 0 and game.world_state.rest_point == "inn:tf_elsie", "inn rest heals and sets a valid home rest point")
	game.player.place_at(-450, -164)
	game._snap_camera()
	check(game.world.indoors != null and game.world.indoors.def.id == "vr_town_hall", "town hall has an accessible interior")
	check(not game.world.roof_over(-448, -165), "mayor is visible inside the roof cutaway")
	var args := OS.get_cmdline_user_args()
	if DisplayServer.get_name() != "headless" and not args.is_empty():
		await _pictures(args[0])
	# Earn the first reward through real strikes, then buy fishing training
	# and a rod from the resident trainer using those earned coins.
	_defeat("vr_young_boar", 3)
	game.interaction.examine("poi:vr_meadow")
	check(game.quests.complete("vr_first_hunt"), "first local hunt completes with real kills")
	check(game.progression.level >= 2, "starting hunt reaches level two")
	check(game.skills.learn("fishing"), "first quest reward can pay for fishing training")
	var angler = game.npcs.by_id("vr_tobin")
	game.merchant.open("vr_tackle", angler)
	check(game.merchant.buy("fishing_rod"), "earned coins can buy a rod at the pond")
	game.merchant.close()
	check(game.quests.accept("vr_perch"), "independent inn fishing quest can be taken")
	game.player.place_at(-395, -171)
	game.player.pending = null
	game.player.casting = null
	# A deterministic 20% roll bites, lands, and selects common perch.
	game.random = func(): return 0.2
	for attempt in 3:
		check(game.fishing.cast({"x": -389.0, "z": -171.0}), "cast into Willow Pond")
		for tick in 150:
			if game.fishing.biting or not game.fishing.active:
				break
			game.fishing.update(0.1)
		check(game.fishing.biting and game.fishing.strike(), "actual bite can be reeled in")
		game.fishing.stop(true)
	check(game.inventory.count("gloomwater_perch") >= 3 and game.quests.complete("vr_perch"), "three caught perch complete the inn's local supper quest")
	check(game.quests.accept("tf_lanterns"), "main story opens independently of the side quests")
	game.interaction.examine("poi:tf_cairn")
	_defeat("tf_revenant", 3)
	check(game.quests.complete("tf_lanterns"), "level-two undead road chapter completes")
	check(game.progression.level >= 3, "main quest rewards reach level three without the wolf side quest")
	check(game.quests.accept("tf_bell"), "watch finale unlocks without the wolf side quest")
	game.interaction.examine("poi:tf_watch")
	game.interaction.examine("poi:tf_shrine")
	_defeat("tf_keeper", 1)
	check(game.quests.complete("tf_bell"), "level-three Bellkeeper chapter completes")
	check(game.quests.accept("vr_names"), "graveyard story unlocks after the watch")
	game.interaction.examine("poi:vr_graves")
	_defeat("vr_gravewalker", 3)
	check(game.quests.complete("vr_names"), "graveyard chapter completes")
	check(game.progression.level >= 4, "story progression reaches level four before the final crypt")
	check(game.quests.accept("vr_crypt"), "crypt finale unlocks")
	game.interaction.examine("poi:vr_crypt")
	_defeat("vr_crypt_keeper", 1)
	check(game.quests.complete("vr_crypt") and game.world_state.flags.has("vr_names_restored"), "local main story restores the lost names")
	check(game.quests.accept("vr_fence_dispute"), "boundary dispute is offered separately")
	game.interaction.examine("poi:vr_boundary")
	check(game.quests.complete("vr_fence_dispute") and game.world_state.flags.has("vr_boundary_settled"), "reading the boundary settles the village dispute")
	game.dialogue.open(woodcutter)
	check(str(game.dialogue.page.text).contains("Three paces"), "woodcutter acknowledges the settled dispute")
	game.dialogue.close()
	check(game.quests.accept("vr_pig_wolf"), "farmer's wolf problem is an independent quest")
	_defeat("vr_briarjaw", 1)
	check(game.quests.complete("vr_pig_wolf") and game.world_state.flags.has("vr_pigs_safe"), "Briarjaw's defeat resolves the pig problem")
	check(game.quests.accept("vr_reed_message") and game.quests.status("vr_reed_message") == "ready", "oral message becomes deliverable to the named recipient")
	game.player.place_at(-397, -170)
	game.dialogue.open(angler)
	check(game.dialogue.choose("quest:vr_reed_message") and game.dialogue.choose("complete"), "recipient accepts the delivered message through the actual dialogue")
	game.dialogue.close()
	check(game.quests.accept("vr_lost_brooch"), "lost keepsake quest is available")
	var pouches: Array = game.loot.active.filter(func(e): return e.def.id == "vr_lost_pouch")
	check(not pouches.is_empty(), "lost keepsake is physically placed at the mill pool")
	if not pouches.is_empty():
		game.player.place_at(-524, -220)
		game.player.pending = null
		game.player.casting = null
		check(game.loot.start_gather(pouches[0]), "keepsake can be gathered in the world")
		game.loot.update(3.0, game.time)
	check(game.inventory.has("vr_brooch_pouch") and game.quests.complete("vr_lost_brooch"), "recovering the keepsake completes Elsie's local story")
	check(not game.inventory.has("vr_brooch_pouch"), "returned keepsake leaves the player's bags")
	var chest_rows: Array = game.chests.list.filter(func(c): return c.def.id == "tf_watch_chest")
	check(not chest_rows.is_empty() and game.chests.open(chest_rows[0]), "watch strongbox rewards are usable")
	check(game.save.save().ok and game.save.read().status == "ok", "expanded world and quest progress saves and validates")
	var preview_ref: WeakRef = weakref(game.hud.items.preview)
	game.queue_free()
	await process_frame
	await process_frame
	check(preview_ref.get_ref() == null, "unopened character preview is released with the game")
	print("reach_village_check: %d failed" % failures)
	quit(1 if failures else 0)


func _defeat(type: String, count: int) -> void:
	var list: Array = game.enemies.list.filter(func(e): return e.type == type)
	check(list.size() >= count, "enemy group exists: " + type)
	game.random = func(): return 0.5
	for foe in list.slice(0, count):
		game.player.place_at(foe.position.x + 0.9, foe.position.z)
		game.targeting.engage(foe)
		for swing in 350:
			if foe.dead:
				break
			game.combat.resolve_player_strike({"x": foe.position.x, "z": foe.position.z})
		check(foe.dead, "combat can defeat " + foe.id)
	# The live loop expects a smith visit between chapters; reset test wear
	# rather than letting a fast synthetic barrage test broken-weapon fists.
	for slot in game.inventory.equipment:
		var item = game.inventory.equipment[slot]
		if item is Dictionary:
			item.erase("dur")
	game.inventory._equipment_changed()


func _pictures(output: String) -> void:
	DirAccess.make_dir_recursive_absolute(output)
	for spot in [["village", -450, -203], ["inn", -465, -204], ["town-hall", -452, -164],
		["willow-pond", -395, -171], ["mill-pool", -523, -217], ["boars", -336, -309],
		["farmyard", -338, -255], ["woodlot", -380, -273],
		["mourning-hollow", -310, -382], ["graveyard", -343, -469], ["crypt", -313, -482]]:
		game.player.place_at(spot[1], spot[2])
		game._snap_camera()
		game.world.land.update(game.player.position, true)
		game._bwk = -1
		game._update_region(2)
		game._place_camera()
		game.hud.update(8)
		game.hud.minimap._refresh_overhead(true)
		for frame in 12:
			game.npcs.update(0.04)
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join("reach-%s.png" % spot[0])) == OK, "rendered view saved: " + spot[0])

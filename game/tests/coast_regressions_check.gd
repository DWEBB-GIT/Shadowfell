extends SceneTree
## Run with --headless --path <project> --script res://game/tests/coast_regressions_check.gd.
## An optional output directory after -- captures the native renderer.

const BUILDINGS := preload("res://game/world/lantern_coast/settlement_building.gd")
var game: Game
var checks := 0
var failures := 0
var heavy_hits := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> bool:
	checks += 1
	failures += int(not ok)
	print("PASS " if ok else "FAIL ", text)
	return ok


func _run() -> void:
	Store.dir = "user://coast_regression_%d" % Time.get_ticks_usec()
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for frame in 1200:
		await process_frame
		game = current_scene as Game
		if game != null and game.is_node_ready():
			break
	if not check(game != null and game.is_node_ready(), "The normal character lobby loads"):
		quit(1)
		return
	game.set_process(false)
	_test_materials()
	_test_original_buildings()
	var made := game.roster.create("MineCheck", "warden")
	game.enter_world(made.character.id, "lantern_coast")
	for frame in 2000:
		await process_frame
		game = current_scene as Game
		if is_instance_valid(game) and game.started and not game.hud.loading.visible:
			break
	if not check(game.started and game.world_key == "lantern_coast", "A fresh character enters Lantern Coast"):
		quit(1)
		return
	game.set_process(false)
	game.save.autosave_enabled = false
	_test_coast_buildings()
	await _capture_buildings()
	_test_skinning()
	await _test_dungeon()
	print("COAST_REGRESSIONS checks=", checks, " failures=", failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _test_materials() -> void:
	var material := StandardMaterial3D.new()
	var model := MeshInstance3D.new()
	model.mesh = BoxMesh.new()
	model.material_override = material
	var other := MeshInstance3D.new()
	other.mesh = model.mesh
	other.material_override = material
	var isolated := Rig.isolate_materials(model)
	Rig.set_alpha(isolated, 0.15)
	check(isolated.size() == 1 and model.get_active_material(0) == isolated[0]
		and is_equal_approx(model.material_override.albedo_color.a, 0.15)
		and is_equal_approx(other.material_override.albedo_color.a, 1.0),
		"An overridden root mesh fades without changing shared materials")
	var mesh := BoxMesh.new()
	mesh.material = material
	other.material_override = null
	other.mesh = mesh
	var surfaces := Rig.isolate_materials(other)
	Rig.set_alpha(surfaces, 0.3)
	check(other.get_surface_override_material(0) == surfaces[0] and is_equal_approx(material.albedo_color.a, 1.0),
		"Surface materials retain independent fades")
	model.free()
	other.free()


func _test_original_buildings() -> void:
	if not check(not game.world.buildings.is_empty(), "The campaign's original walk-in buildings are available"):
		return
	var building: Dictionary = game.world.buildings[0]
	var inside := Vector3((building.minX + building.maxX) * 0.5, 0.0, (building.minZ + building.maxZ) * 0.5)
	var outside := inside + Vector3(0, 0, building.maxZ - building.minZ + 12.0)
	game.world.update_indoors(0.0, outside)
	game.world.update_indoors(0.1, inside)
	check(building.fade[1].obj.visible and building.fade[1].opacity > 0.05 and building.fade[1].opacity < 0.95,
		"The original roof eases away while entering")
	game.world.update_indoors(0.0, inside)
	check(not building.fade[1].obj.visible and is_equal_approx(building.fade[0].opacity, 0.15),
		"The original interior hides its roof and retains a faint front wall")
	game.world.update_indoors(0.0, outside)
	check(building.fade[1].obj.visible and is_equal_approx(building.fade[0].opacity, 1.0),
		"The original walls and roof restore outside")


func _visit(at: Vector2) -> void:
	game.player.place_at(at.x, at.y)
	game.world.coast_scene.stream_for_player(game.player.position, true)
	game._snap_camera()
	game._place_camera()


func _test_coast_buildings() -> void:
	var bad := []
	var surface = Terrain.coast
	var scene = game.world.coast_scene
	for site in surface.buildings:
		_visit(site.center)
		var player := Vector3(site.center.x, site.floor, site.center.y)
		if not surface.direct_walk(BUILDINGS.exterior(site), site.center, game.player.radius):
			bad.append(site.def.name + " doorway")
		for side in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var at := BUILDINGS.to_world(site, side * 20.0)
			var camera := Vector3(at.x, site.floor + 22.0, at.y)
			scene.update_buildings(player + Vector3(0, 0, 100), camera, 0.0)
			scene.update_buildings(player, camera, 0.1)
			if not site.visual.get_node("Roof").visible or site.fade.Roof.opacity <= 0.05:
				bad.append(site.def.name + " abrupt roof fade")
			scene.update_buildings(player, camera, 0.0)
			var nearest := ["Street" if side.y > 0 else "Rear", "East" if side.x > 0 else "West"]
			for wall in ["Street", "Rear", "West", "East"]:
				var alpha := 0.15 if wall in nearest else 1.0
				if not is_equal_approx(float(site.fade[wall].opacity), alpha):
					bad.append(site.def.name + " " + wall)
				for mat in site.fade[wall].mats:
					if mat is BaseMaterial3D and not is_equal_approx(mat.albedo_color.a, alpha):
						bad.append(site.def.name + " unchanged material")
			if site.visual.get_node("Roof").visible:
				bad.append(site.def.name + " roof")
			scene.update_buildings(player + Vector3(0, 0, 100), camera, 0.0)
			if not site.visual.get_node("Roof").visible or site.inside > 0.0:
				bad.append(site.def.name + " restore")
	check(bad.is_empty(), "%d modular interiors fade the correct walls from all four views %s" % [surface.buildings.size(), bad])
	var inn: Dictionary = surface.buildings.filter(func(site): return site.def.name == "The Brass Bell Inn")[0]
	_visit(inn.center)
	game.world.update_indoors(0.0, game.player.position)
	check(game.world.indoors == inn and game.camp.resting == "inn", "The fading interior still supports inn rest")
	var palette_opaque := true
	for mat in BUILDINGS.materials.values():
		if mat is BaseMaterial3D:
			palette_opaque = palette_opaque and is_equal_approx(mat.albedo_color.a, 1.0)
	check(palette_opaque, "The reusable building palette stays opaque")


func _test_skinning() -> void:
	var valid := true
	for level in range(1, 51):
		var expected := 1 + ((level - 1) / 5) * 10
		valid = valid and Loot.skin_rank(level) == expected and Loot.skin_rank(level) <= game.skills.top("skinning")
	check(valid, "All creature levels 1–50 fit the Hunting 1–100 progression")
	check(Loot.skin_rank(1) == 1 and Loot.skin_rank(2) == 1 and Loot.skin_rank(3) == 1
		and Loot.skin_rank(5) == 1 and Loot.skin_rank(6) == 11 and Loot.skin_rank(50) == 91,
		"Starter beasts share rank 1 and the endgame band needs rank 91")
	game.skills.ranks.skinning = 1
	game.inventory.add_item("skinning_knife")
	check(game.inventory.on_belt("skinning_knife"), "The starter knife occupies its real tool-belt slot")
	game.random = func(): return 0.0
	var complete := 0
	for level in [1, 2, 3, 6]:
		var at := Vector2(-798, 212)
		_visit(at + Vector2(1, 0))
		var enemy := Enemy.new(game, {"id":"regression_boar_" + str(level), "type":"vr_young_boar", "level":level,
			"position":[at.x, at.y]})
		game.enemies.list.append(enemy)
		game.enemies._show(enemy, 1.0)
		enemy.hurt(enemy.max_health + 1.0)
		game.combat.on_enemy_defeated(enemy)
		game.loot.loot_corpse(enemy.id)
		var action: Dictionary = game.loot.corpse_action(enemy)
		if level <= 3:
			if check(action.get("rank") == 1 and game.loot.skin_block(action) == "" and game.loot.start_skin(action),
				"The level %d boar can be skinned by a new hunter" % level):
				game.loot.update(2.3, game.time)
				complete += int(not game.world_state.corpses.has(enemy.id))
		else:
			check(not game.loot.skin_block(action).is_empty(), "The next band shows its actual Hunting requirement")
			game.skills.ranks.skinning = 11
			check(game.loot.skin_block(action).is_empty(), "Training Hunting to 11 unlocks the next band")
	check(complete == 3 and game.skills.recent.get("skinning", []).size() >= 3,
		"All three starter carcasses yield loot and Hunting experience")
	var unlocks := game.skills.unlocks("skinning").filter(func(row): return row.kind == "gather")
	check(unlocks.size() == 10 and unlocks[0].level == 1 and unlocks[-1].level == 91,
		"The Skills window lists all ten beast-level bands")
	game.random = func(): return 0.72


func _advance(seconds: float) -> void:
	for frame in ceili(seconds * 30.0):
		game.step(1.0 / 30.0)


func _test_dungeon() -> void:
	game.progression.apply({"level":8,"xp":0})
	game.inventory.add_item("wm_lantern_crossing_arming_sword")
	check(game.inventory.equip("wm_lantern_crossing_arming_sword"), "The level 8 test character equips a level-appropriate sword")
	game.player.health = game.player.max_health
	game.resources.reset()
	var mine = game.blackpick
	_visit(mine.outside())
	if not check(mine.enter(), "The level 8 character enters Blackpick"):
		return
	await process_frame
	await process_frame
	game.events.on("playerHurt", func(e):
		if e.get("heavy", false) and e.get("enemy") == mine.actor:
			heavy_hits += 1)
	for encounter in 2:
		var enemy: Enemy = mine.actor
		game.player.place_at(enemy.position.x, enemy.position.z + 1.5)
		game.enemies._show(enemy, 1.0)
		game.targeting.select(enemy)
		game.player.health = game.player.max_health
		check(enemy.cfg.special.get("damage", 0.0) > 0.0, enemy.cfg.name + " has level-scaled heavy-attack damage")
		for frame in 210:
			game.step(1.0 / 30.0)
			if enemy.casting != null and enemy.casting.kind == "special":
				break
		# Isolate the heavy hit from the ordinary attacks taken while waiting for it.
		game.player.health = game.player.max_health
		var health: float = game.player.health
		var before := heavy_hits
		var special = enemy.casting.telegraph if enemy.casting != null else null
		if encounter == 0 and special != null:
			game._snap_camera()
			game._place_camera()
			await _capture("blackpick_first_swing.png")
		for frame in 100:
			game.step(1.0 / 30.0)
			if special == null or special.done:
				break
		check(special != null and special.done and heavy_hits > before and game.player.health < health and not game.player.dead,
			enemy.cfg.name + " telegraphs and resolves its first heavy attack")
		game.player.health = game.player.max_health
		enemy.special_timer = 0.0
		for frame in 30:
			game.step(1.0 / 30.0)
			if enemy.casting != null and enemy.casting.kind == "special":
				break
		var interrupted = enemy.interrupt(1.0)
		check(interrupted is String and enemy.casting == null,
			enemy.cfg.name + " can be interrupted during its heavy swing")
		enemy.special_timer = 0.0
		_advance(0.1)
		var warned: bool = enemy.casting != null and enemy.casting.kind == "special"
		var origin: Vector3 = enemy.position
		game.player.place_at(origin.x - 5.2, origin.z)
		before = heavy_hits
		_advance(2.7)
		check(warned and heavy_hits == before, enemy.cfg.name + " misses when the player leaves its telegraph")
		game.player.place_at(enemy.position.x, enemy.position.z + 1.5)
		game.player.health = game.player.max_health
		game.targeting.engage(enemy)
		for swing in 120:
			if enemy.dead:
				break
			game.player.health = game.player.max_health
			game.combat.resolve_player_strike(enemy.position)
			game.step(0.08)
		check(enemy.dead and mine.stage == encounter + 1, enemy.cfg.name + " dies cleanly and advances the dungeon")
		game.targeting.clear()
		if encounter == 0:
			check(mine.release_brake(), "The brake opens the foreman's wing")
			game.player.dead = true
			game.player.health = 0.0
			game.on_player_death()
			await process_frame
			await process_frame
			check(not game.player.dead and mine.stage == 1 and mine.actor.cfg.special.get("damage", 0) > 0,
				"Retrying at the checkpoint rebuilds a working encounter")
	game.resources.reset()
	check(mine.claim() and not mine.claim(), "The payroll and first-clear reward pay once")
	var reward: Dictionary = Items.get_def("wm_rillbank_quays_arming_sword")
	check(game.inventory.count(reward.id) == 1 and Inventory.required_level(reward) == 10,
		"The first-clear weapon fits the dungeon's level 8–10 bracket")
	check(mine.leave(), "The service ladder returns to Bellharbor")
	await process_frame
	await process_frame
	check(not mine.active() and game.telegraphs.active.is_empty(), "Leaving clears the dungeon's telegraphs")
	check(mine.enter(), "The mine can be entered again after a complete clear")
	await process_frame
	await process_frame
	game.resources.reset()
	check(mine.leave(), "The new run can be left safely")
	await process_frame
	await process_frame
	_advance(5.0)


func _capture_buildings() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	for title in ["The Brass Bell Inn", "Whitehorn Shelter", "Redwash Caravan House"]:
		var site: Dictionary = Terrain.coast.buildings.filter(func(s): return s.def.name == title)[0]
		for pose in ["inside", "outside"]:
			_visit(site.center if pose == "inside" else BUILDINGS.exterior(site) + Vector2(0, 4))
			_advance(0.5)
			game.world.update_indoors(0.0, game.player.position)
			game.hud.zone_left = 0.0
			game.hud.zone_banner.hide()
			await _capture(title.to_snake_case() + "_" + pose + ".png")


func _capture(filename: String) -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		return
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var target: String = args[0].path_join(filename)
	check(root.get_texture().get_image().save_png(target) == OK, "Captured " + filename)

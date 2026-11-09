extends SceneTree
## Headless checks for the Godot build:
##   godot --headless --path . --script res://game/tests/run_tests.gd
## (npm run godot:test does the same). Exits 1 if anything fails.

var failures := 0


func _initialize() -> void:
	var data = load("res://game/autoload/game_data.gd").new()
	check(data.problems.is_empty(), "data loads cleanly: %s" % ", ".join(data.problems))
	for t in ["items", "enemies", "npcs", "quests", "abilities", "archetypes", "enemySpawns", "placedLoot", "chests"]:
		check(not data.table(t).is_empty(), "table %s has records" % t)
	for s in data.section("world", "npcSpawns"):
		check(not data.get_record("npcs", s.npc).is_empty(), "npc spawn %s names a known npc" % s.npc)
	for s in data.section("world", "enemySpawns"):
		check(not data.get_record("enemies", s.enemy).is_empty(), "enemy spawn %s names a known enemy" % s.id)
	# each map's placements stand on open ground of its own baked ground
	# (tools/world/bake_world.py), and its start is where a game can begin
	var chosen := Terrain.chosen_map()
	for map in Terrain.MAPS:
		ProjectSettings.set_setting(Terrain.MAP_SETTING, map)
		DB.ready = false
		DB.ensure()
		check_ground(map)
	ProjectSettings.set_setting(Terrain.MAP_SETTING, chosen)
	DB.ready = false
	DB.ensure()
	# spell looks (data/abilities/spell_fx.json) name real spells, poses and shapes
	for id in DB.spell_fx:
		var look: Dictionary = DB.spell_fx[id]
		check(DB.abilities.has(id), "spell look %s names a known spell" % id)
		for key in ["anim", "windupAnim"]:
			if look.get(key) is Dictionary:
				check(DB.spell_poses.has(look[key].type) or look[key].type in ["guard", "strike", "slam", "brace", "shoot", "cast", "cleave"], "spell look %s uses a known pose" % id)
		for phase in Fx.PHASES:
			for part in look.get(phase, []):
				check(phase == "projectile" or part.fx in ["mesh", "ring", "sparks", "dust", "flash", "shake"], "spell look %s part %s is a known effect" % [id, part.get("fx", "mesh")])
				if part.get("fx", "mesh") == "mesh":
					check(Fx.fx_mesh(part.mesh) != null, "spell look %s shape %s exists" % [id, part.mesh])
	# moment looks (`moments`, such as levelUp) use known effects and shapes
	for id in DB.fx_moments:
		if id.begins_with("_"):
			continue
		for part in DB.fx_moments[id].get("cast", []):
			check(part.fx in ["mesh", "ring", "sparks", "dust", "flash", "shake", "light"], "moment look %s part %s is a known effect" % [id, part.fx])
			if part.fx == "mesh":
				check(Fx.fx_mesh(part.mesh) != null, "moment look %s shape %s exists" % [id, part.mesh])
	data.free()


## Everything placed on the map now loaded stands on open ground.
func check_ground(map: String) -> void:
	for list in ["npcSpawns", "enemySpawns", "placedLoot", "chests", "shrines", "stations", "signposts"]:
		for s in DB.world.get(list, []):
			check(Terrain.walk_at(s.position[0], s.position[1]) >= 0.5, "%s map: %s %s stands on open ground" % [map, list, s.get("id", s.get("npc", ""))])
	for g in DB.mining.get("veinGroups", []):
		for o in g.outcrops:
			check(Terrain.walk_at(o[0], o[1]) >= 0.5, "%s map: vein outcrop of %s stands on open ground" % [map, g.id])
	var start: Array = DB.world.playerStart.position
	if map == "act1":
		check(WorldMap.act1_box.has_point(Vector2(start[0], start[1])), "the player starts in Act 1")
	else:
		check(Terrain.walkable(start[0], start[1]), "%s map: the start is open ground" % map)


## The game itself: start it, play a little, save. Runs over frames, so the
## scene is ready and systems update as in play.
var game
var frame := 0
var foe = null


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store" # a clean store, apart from real saves
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		check(game.hud.modal == "title", "the title screen opens first")
		var made: Dictionary = game.roster.create("Testwarden", "warden")
		check(made.ok, "a character is created")
		game.enter_world(made.character.id)
		check(game.started, "a character enters the world")
		check(game.npcs.all.size() == Layout.npcs.size(), "every townsperson is placed")
		check(game.enemies.list.size() == Layout.enemies.size(), "every enemy is placed")
		if Terrain.is_new_map():
			# no trees are scattered on the new map: Dan places its scenery
			check(Layout.props.size() > 0, "the placed scenery is loaded")
		else:
			check(game.world.group.find_children("Woodland_*", "", true, false).size() > 0, "the woodland is planted")
		check(game.action_bar.slots.any(func(a): return a != null), "the spell bar has abilities")
		game.random = func() -> float: return 0.5
		# the nearest enemy a new character may fight (not the peaceful watch
		# or livestock, nothing far above its level)
		var fair: Array = game.enemies.list.filter(func(e): return not game.law.protected(e) and int(e.cfg.level) <= 3)
		check(not fair.is_empty(), "there is a low level enemy to fight")
		foe = fair[0]
		for e in fair:
			if e.position.distance_to(game.player.position) < foe.position.distance_to(game.player.position):
				foe = e
	elif frame < 600:
		# walk up to the nearest enemy and fight it with auto attack
		game.targeting.engage(foe)
		if foe.alive and foe.position.distance_to(game.player.position) > 1.5:
			game.move_to = {"x": foe.position.x, "z": foe.position.z, "reach": 1.3}
		game.step(1.0 / 30)
	elif frame == 600:
		check(foe.health < foe.max_health or not foe.alive, "auto attack hurts the enemy")
		check(game.player.health < game.player.max_health or game.player.dead or not foe.alive, "the enemy fights back (or fell first)")
		if game.player.dead:
			game.release_spirit()
			game.afterlife.revive_here()
		var r: Dictionary = game.manual_save()
		check(r.ok, "the game saves: %s" % r.get("reason", ""))
		var back: Dictionary = game.save.read()
		check(back.status == "ok", "the save reads back as valid: %s" % back.get("errors", ""))
		print("godot tests: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)

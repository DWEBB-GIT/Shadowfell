extends SceneTree
## Headless checks for the Godot build:
##   godot --headless --path . --script res://game/tests/run_tests.gd
## (npm run godot:test does the same). Exits 1 if anything fails.

# heightAt() from src/world/terrain.js at a few points, so both builds agree
const JS_HEIGHTS := [[-6, 33, 0.15082], [0, 0, 0.29], [22.5, -19.5, 0.15119], [-24, -14, -1.63163], [8, 72, 0.74378], [4.6, -63, 0.49001], [-6.4, -115, -0.68835], [30, 90, -0.02694], [-40, -130, 6.49159]]

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
	Terrain.setup(data.files.world)
	for p in JS_HEIGHTS:
		var h := Terrain.height_at(p[0], p[1])
		check(absf(h - p[2]) < 0.001, "terrain height at %s,%s is %.5f (browser build %.5f)" % [p[0], p[1], h, p[2]])
	data.free()


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
		var made: Dictionary = game.roster.create("Test Warden", "warden")
		check(made.ok, "a character is created")
		game.enter_world(made.character.id)
		check(game.started, "a character enters the world")
		check(game.npcs.all.size() == Layout.npcs.size(), "every townsperson is placed")
		check(game.enemies.list.size() == Layout.enemies.size(), "every enemy is placed")
		check(game.world.group.find_children("Woodland_*", "", true, false).size() > 0, "the woodland is planted")
		check(game.action_bar.slots.any(func(a): return a != null), "the spell bar has abilities")
		game.random = func() -> float: return 0.5
		foe = game.enemies.list[0]
		for e in game.enemies.list:
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
		check(game.player.health < game.player.max_health or game.player.dead, "the enemy fights back")
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

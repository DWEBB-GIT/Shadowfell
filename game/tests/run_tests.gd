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
	var world = load("res://game/world/world_builder.gd").new()
	world.rebuild()
	var generated: Node = world.get_node("Generated")
	check(generated.get_node("townsfolk").get_child_count() == data.section("world", "npcSpawns").size(), "every townsperson is placed")
	check(generated.get_node("enemies").get_child_count() == data.section("world", "enemySpawns").size(), "every enemy is placed")
	check(generated.get_node("woodland").get_child_count() > 0, "the woodland is planted")
	world.free()
	data.free()
	print("godot tests: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)

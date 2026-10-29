extends SceneTree
## Dying on Dan's new map (no shrines, inns or graveyards) must not crash:
## the spirit rises at the map's start, and stepping the game as a ghost works.
##   godot --headless --path . --script res://game/tests/death_new_map_check.gd

var game
var frame := 0
var failed := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Ghost Tester", "occultist")
		game.enter_world(made.character.id)
	elif frame == 3:
		_ok(Layout.shrines.is_empty(), "the new map has no shrines")
		game.player.take_damage(99999)
		game.on_player_death(null)
		game.world_state.respawn = {"x": 0.0, "z": 0.0}  # a stale shrine respawn from an old save
		var r: Dictionary = game.respawn_point()
		_ok(r.kind == "start", "the spirit rises at the start (%s)" % r.kind)
		game.release_spirit()
		_ok(game.afterlife.ghost, "the player is a ghost")
		var _near: bool = game.afterlife.near_rest_point
		game.afterlife.interactions()
	elif frame < 30:
		pass  # the game steps as a ghost
	else:
		print("death new map check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


func _ok(ok: bool, what: String) -> void:
	if not ok:
		failed += 1
		print("FAIL: ", what)

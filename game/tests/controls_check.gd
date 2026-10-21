extends SceneTree
## Mouse aim and classic controls, and the camera's tilt:
##   godot --headless --path . --script res://game/tests/controls_check.gd

var failures := 0
var game
var frame := 0
var foe = null
var t0 := 0 ## the frame the world is ready (after the loading screen)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_controls"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Test Warden", "warden")
		game.enter_world(made.character.id)
		check(game.mouse_aim, "mouse aim is the default")
		check(game.keys.keys("bar4") == ["KeyR"] and game.keys.keys("bar5") == ["KeyF"], "mouse aim puts slots 5 and 6 on R and F")
		check(game.keys.keys("bar0").has("MouseRight"), "the right button fires slot 1")
		game.settings.set_value("classicControls", true)
		check(game.keys.keys("bar4") == ["KeyQ"], "classic controls keep Q and E")
		game.keys.bind("bar3", "KeyG")
		game.settings.set_value("classicControls", false)
		check(game.keys.keys("bar4") == ["KeyR"] and game.keys.keys("bar3") == ["Digit4"], "each scheme keeps its own bindings")
		game.settings.set_value("classicControls", true)
		check(game.keys.keys("bar3") == ["KeyG"], "a classic binding survives a switch")
		game.keys.reset_all()
		game.settings.set_value("classicControls", false)
		game.keys.bind("bar0", "KeyT")
		check(game.keys.keys("bar0") == ["KeyT", "MouseRight"], "rebinding slot 1 keeps the right button")
		game.keys.reset_all()
		# the camera: low near, steep far; classic keeps one angle
		var pitch := func(z: float) -> float:
			game.zoom = z
			var o: Vector3 = game._camera_offset(1.0)
			return rad_to_deg(atan2(o.y, o.z))
		check(absf(pitch.call(0.6) - 40) < 0.1 and absf(pitch.call(1.0) - 52) < 0.1 and absf(pitch.call(1.6) - 60) < 0.1, "the camera tilts with the zoom")
		game.settings.set_value("classicCamera", true)
		check(absf(pitch.call(0.6) - pitch.call(1.3)) < 0.01, "the classic camera keeps one angle")
		game.settings.set_value("classicCamera", false)
		game.zoom = 1.0
		foe = game.enemies.list[0]
	if frame <= 2:
		return false
	if t0 == 0:
		if game.hud.modal == "loading" or game.hud.blocks_gameplay:
			if frame > 3000:
				check(false, "the world loads")
				quit(1)
			return false
		t0 = frame
	var f := frame - t0
	if f == 1 or f == 40:
		# engaged, in reach, stepping away east from a foe to the west
		game.player.position = foe.position + Vector3(1.0, 0, 0)
		game.player.facing = -PI / 2
		game.targeting.engage(foe)
		game.input.held["KeyD"] = true
	elif f == 35:
		check(absf(angle_difference(game.player.facing, PI / 2)) < 0.3, "mouse aim: walking away faces the way you walk (%.2f)" % game.player.facing)
		game.input.held.erase("KeyD")
		game.settings.set_value("classicControls", true)
	elif f == 44:
		var to_foe := atan2(foe.position.x - game.player.position.x, foe.position.z - game.player.position.z)
		check(absf(angle_difference(game.player.facing, to_foe)) < 0.5, "classic: in reach, you keep facing your target as you walk")
		game.settings.set_value("classicControls", false)
		print("controls checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + what)

extends SceneTree
## Dying, then a real mouse click on "Release spirit" (Dan, 2026-11-04: the
## death screen seemed to freeze). The click must reach the button, the
## death screen must close, the loading screen must cover the rising and
## lift again, and a ghost must rise. The click goes in local (canvas)
## coordinates: headless windows are not the 1280x720 canvas.
##   godot --headless --path . --script res://game/tests/release_click_check.gd

var game
var frame := 0
var failed := 0
var died_at := -1
var click_at := Vector2.ZERO
var watch_until := 0
var t_last := 0
var worst := 0.0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_release"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Release", "warrior")
		game.enter_world(made.character.id)
	elif frame == 50:
		# a yes/no box (and with it the backdrop) raised earlier in the session
		game.hud.confirm("Test?", func(): pass)
	elif frame == 52:
		game.hud.close_modal()
	elif frame == 55:
		# die far from the rest point, so the spirit rises somewhere unbuilt
		var r: Dictionary = game.respawn_point()
		game.player.place_at(r.x + 250, r.z + 250)
		game._snap_camera()
	elif frame == 60:
		game.player.take_damage(99999)
		game.on_player_death(null)
		died_at = frame
	elif died_at > 0 and game.hud.modal == "death" and not game.afterlife.ghost and frame < 2000:
		if frame % 30 != 0:
			return false
		var btn := _release_button()
		_ok(btn != null, "the death screen has a Release button")
		if btn == null:
			return _end()
		var at: Vector2 = btn.get_global_rect().get_center()
		var mv := InputEventMouseMotion.new()
		mv.position = at
		mv.global_position = at
		root.push_input(mv, true)
		click_at = at
		died_at = -5
	elif died_at <= -4 and died_at > -100:
		died_at += 1
	elif died_at == -3:
		_ok(root.gui_get_hovered_control() == _release_button(), "the mouse is over the Release button")
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = click_at
			e.global_position = click_at
			root.push_input(e, true)
		died_at = -2
	elif died_at == -2:
		died_at = -1
	elif died_at == -1 and frame > 70:
		_ok(not game.hud.death.visible, "the click closes the death screen")
		_ok(game.afterlife.ghost, "the spirit rises")
		died_at = -100
		watch_until = frame + 900
		t_last = Time.get_ticks_usec()
	elif died_at == -100:
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - t_last) / 1000.0)
		t_last = now
		if frame >= watch_until:
			_ok(game.hud.modal == null and not game.hud.death.visible, "the death screen stays closed and the loading screen lifts")
			_ok(worst < 1000.0, "no frame stalls a second (worst %.0f ms)" % worst)
			return _end()
	elif frame > 2000:
		_ok(false, "the death screen never came up")
		return _end()
	return false


func _release_button() -> Button:
	for b: Button in game.hud.death.find_children("*", "Button", true, false):
		if b.text.contains("Release"):
			return b
	return null


func _ok(ok: bool, what: String) -> void:
	print(("ok: " if ok else "FAIL: ") + what)
	if not ok:
		failed += 1


func _end() -> bool:
	print("release_click_check: %s" % ("PASS" if failed == 0 else "%d FAILED" % failed))
	quit(1 if failed else 0)
	return true

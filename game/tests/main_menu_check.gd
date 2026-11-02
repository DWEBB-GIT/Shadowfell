extends SceneTree
## Escape opens the main menu (after closing windows and dropping the
## target), Logout counts down and can be cancelled, and the Settings window
## has its pages, Target lock and Character specific key bindings.
## godot --headless --path . --script res://game/tests/main_menu_check.gd
## (with a display, a path after -- also saves pictures of the menu and pages)

var game
var frame := 0
var bad := 0
var shots := ""


func _check(ok: bool, what: String) -> void:
	if not ok:
		bad += 1
	print(("  ok   " if ok else "  FAIL ") + what)


func _shot(name: String) -> void:
	if shots != "":
		root.get_texture().get_image().save_png("%s/%s.png" % [shots, name])


func _process(dt: float) -> bool:
	frame += 1
	var hud = game.hud if game else null
	match frame:
		1:
			var args := OS.get_cmdline_user_args()
			shots = args[0] if args.size() > 0 else ""
			Store.dir = "user://test_store"
			for f in DirAccess.get_files_at(Store.dir):
				DirAccess.remove_absolute(Store.dir + "/" + f)
			game = load("res://game/main.tscn").instantiate()
			root.add_child(game)
		2:
			var made: Dictionary = game.roster.create("Menu Tester", "warden")
			game.enter_world(made.character.id)
		20:
			hud.hide_loading()
			hud.show_window("bags")
			game.input.pressed["Escape"] = true
		22:
			_check(not hud.items.any_open and not hud.main_menu.is_open, "Escape closes the bags first")
			game.input.pressed["Escape"] = true
		24:
			_check(hud.main_menu.is_open and hud.modal == "menu", "Escape with nothing open opens the main menu")
		26:
			_shot("main_menu")
			game.input.pressed["Escape"] = true
		28:
			_check(not hud.main_menu.is_open and hud.modal == null, "Escape closes the main menu")
			hud.main_menu.open()
			hud.main_menu._start("logout")
			_check(not hud.main_menu.is_open and hud.main_menu.leaving == "logout", "Logout starts a countdown")
		32:
			_shot("logout_countdown")
			var left: float = hud.main_menu.left
			_check(left < MainMenu.COUNTDOWN and left > MainMenu.COUNTDOWN - 1, "the countdown runs (%.2f s left)" % left)
			_check(hud.main_menu.wait_label.text.begins_with("Logging out in"), "it says so: " + hud.main_menu.wait_label.text)
			game.input.pressed["Escape"] = true
		34:
			_check(hud.main_menu.leaving == "" and not hud.main_menu.wait_panel.visible, "Escape cancels the countdown")
			hud.main_menu.open()
			hud.main_menu._settings()
		38:
			_check(hud.items.open.settings and not hud.main_menu.is_open, "Settings opens the Settings window")
			var w = hud.items.settings_win
			_check(w.tabs.size() == Settings.TABS.size(), "Settings has its pages")
			_shot("settings_controls")
			for id in ["leftInteract", "autoLoot", "clickToMove", "targetLock"]:
				_check(w.pages.controls.is_ancestor_of(w.inputs[id][0]), "%s is on Controls" % id)
			for id in ["soundOn", "outputDevice", "volMaster", "volMusic", "volEffects", "volAmbience"]:
				_check(w.pages.audio.is_ancestor_of(w.inputs[id][0]), "%s is on Audio" % id)
			_check(w.inputs.outputDevice[0].item_count >= 1, "output devices are listed")
			hud.items.settings_tab = "keys"
			hud.items._show_settings_tab()
		42:
			_shot("settings_keys")
			hud.items.settings_tab = "audio"
			hud.items._show_settings_tab()
		46:
			_shot("settings_audio")
			hud.items.close_all()
			# stand a few steps from an enemy, facing it, so it is on screen
			var e = game.enemies.list[0]
			game.player.position = e.position - Vector3(0, 0, 3)
			game.player.facing = 0.0
		52:
			# Target lock off: nothing locks on by itself
			var far := 10.0
			game.settings.set_value("targetLock", false)
			_check(game.targeting.soft_target(null, far) == null, "Target lock off: no soft lock")
			_check(game.targeting.soft_target(null, far, true) != null, "Tab still finds the enemy ahead")
			game.settings.set_value("targetLock", true)
			# Character specific key bindings
			game.keys.bind("jump", "KeyJ")
			game.settings.set_value("keysPerCharacter", true)
			_check(game.keys.keys("jump") == ["KeyJ"], "Character specific starts from the shared bindings")
			game.keys.bind("jump", "KeyH")
			game.settings.set_value("keysPerCharacter", false)
			_check(game.keys.keys("jump") == ["KeyJ"], "the shared bindings are untouched")
			game.settings.set_value("keysPerCharacter", true)
			_check(game.keys.keys("jump") == ["KeyH"], "the character keeps its own")
			game.settings.set_value("keysPerCharacter", false)
			game.settings.set_value("soundOn", false)
			_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Enable sound off mutes")
			game.settings.set_value("soundOn", true)
			print("main menu: %d failed" % bad)
			quit(1 if bad else 0)
	return false

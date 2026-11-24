extends SceneTree
## Exercises the real input, movement, combat and persisted-world paths.
## Saves are isolated from player accounts. Optional user arg: capture folder.
class TestPad extends Pad:
	func poll() -> void: pass

var game: Game
var origin := Vector3.ZERO
var enemy
var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, label: String) -> void:
	checks += 1
	failures += int(not ok)
	print("PASS " if ok else "FAIL ", label)


func _load_world() -> bool:
	for i in 2400:
		await process_frame
		game = current_scene as Game
		if is_instance_valid(game) and game.started and not game.hud.loading.visible:
			game.set_process(false)
			game.input.set_process(false)
			game.save.autosave_enabled = false
			game.atmosphere.set_process(false)
			game.pad = TestPad.new()
			for j in 16: game.pad.now.append(false)
			game.pad.prev = game.pad.now.duplicate()
			return true
	return false


func _run() -> void:
	Store.dir = "user://strafing_%d" % Time.get_ticks_usec()
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for i in 1200:
		await process_frame
		game = current_scene as Game
		if game != null and game.is_node_ready(): break
	var made := game.roster.create("Strafing", "warden")
	game.enter_world(made.character.id, "lantern_coast")
	if not await _load_world():
		check(false, "Lantern Coast loads")
		quit(1)
		return
	check(not game.settings.get_value("combatStrafing"), "New accounts retain movement-facing by default")
	check(game.keys.keys("toggleStrafing").is_empty(), "The toggle starts unbound")
	origin = game.player.position
	for e in game.enemies.list:
		if e.alive and not e.protected:
			enemy = e
			break
	check(enemy != null, "A living enemy is available for the trial")
	if enemy == null:
		quit(1)
		return
	for classic in [false, true]:
		game.settings.set_value("classicControls", classic)
		game.settings.set_value("tankControls", false)
		game.settings.set_value("clickToMove", true)
		for yaw in [0.0, 45.0]:
			var at := origin + Vector3.UP
			game.camera.position = at + (DB.CONFIG.camera.offset as Vector3).rotated(Vector3.UP, deg_to_rad(yaw))
			game.camera.look_at(at)
			game.settings.set_value("combatStrafing", false)
			_reset()
			_key(KEY_S, true)
			var controls: Dictionary = game._handle_input(0.05)
			game.player.facing = atan2(controls.move.x, controls.move.z)
			_walk(8)
			var baseline := game.player.position
			check(game.player.facing_point(origin.x + controls.move.x * 100, origin.z + controls.move.z * 100, 2), "Disabled: follows travel (classic=%s yaw=%s)" % [classic, yaw])
			game.settings.set_value("combatStrafing", true)
			game.settings.set_value("strafeFacing", "Selected enemy")
			_reset()
			_key(KEY_S, true)
			game.player.facing = atan2(enemy.position.x - origin.x, enemy.position.z - origin.z)
			_walk(8)
			check(game.player.position.distance_to(baseline) < 0.001, "Strafing preserves travel and speed (classic=%s yaw=%s)" % [classic, yaw])
			check(game.player.facing_point(enemy.position.x, enemy.position.z, 4), "Strafing follows the enemy while retreating (classic=%s yaw=%s)" % [classic, yaw])
			check(game.player.rig.clip == "Jog_Fwd", "The moving model continues its gait")
	_test_fallbacks()
	_test_cursor_and_pad()
	_test_jump_and_combat()
	_test_toggle()
	_test_settings_ui()
	await _capture_settings()
	game.settings.set_value("combatStrafing", true)
	game.settings.set_value("strafeFacing", "Mouse cursor")
	game.settings.set_value("keysPerCharacter", true)
	game.keys.bind("toggleStrafing", "KeyV", 0)
	Game.enter_id = made.character.id
	Game.enter_world_key = ""
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	var loaded: bool = await _load_world()
	check(loaded and game.world_key == "" and game.settings.get_value("combatStrafing") and game.settings.get_value("strafeFacing") == "Mouse cursor" and game.keys.keys("toggleStrafing").has("KeyV"), "The same character keeps strafing preferences and bindings in Campaign")
	game.settings.set_value("combatStrafing", false)
	check(not Settings.new(game).get_value("combatStrafing"), "Turning it off is saved for the next login")
	print("STRAFING checks=", checks, " failures=", failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)


func _reset() -> void:
	game.input.held.clear()
	game.input.release_mouse()
	game.input.end_frame()
	game.input.mouse.onCanvas = false
	game.move_to = null
	game.dialogue.close()
	game.pad.left = Vector3.ZERO
	game.pad.right = Vector3.ZERO
	game.hud.set_pad_mode(false)
	game.player.place_at(origin.x, origin.z)
	game.player.pending = null
	game.player.pending_off = null
	game.player.pending_shot = null
	game.player.rig.action = null
	enemy.dead = false
	enemy.position = origin + Vector3(5, 0, -2)
	game.targeting.select(enemy)
	game.targeting.stop_attack()


func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	game.input._input(event)


func _walk(frames: int) -> void:
	for i in frames:
		game.player.update(0.05, game._handle_input(0.05))
		game.input.end_frame()


func _test_fallbacks() -> void:
	_reset()
	_key(KEY_D, true)
	game.targeting.clear()
	check(game._handle_input(0.05).strafeAim == null, "No target returns to travel-facing")
	game.targeting.select(enemy)
	enemy.dead = true
	check(game._handle_input(0.05).strafeAim == null, "A defeated target immediately releases strafe-facing")
	enemy.dead = false
	game.targeting.select_friendly(game.npcs.by_id("lc_mill_angler"))
	check(game._handle_input(0.05).strafeAim == null, "A friendly NPC does not lock movement facing")
	_reset()
	game.settings.set_value("tankControls", true)
	_key(KEY_D, true)
	var before := game.player.position
	game.player.facing = 0
	_walk(2)
	check(game.player.position.distance_to(before) < 0.001 and game.player.facing < 0, "Keyboard turning keeps its own turning behavior")
	game.settings.set_value("tankControls", false)
	_reset()
	game.move_to = {"x": origin.x + 4, "z": origin.z, "reach": 0.2}
	var route: Dictionary = game._handle_input(0.05)
	check(route.strafeAim == null and Vector2(route.move.x, route.move.z).length() > 0, "Click routes face their route even with strafing enabled")
	_key(KEY_W, true)
	var takeover: Dictionary = game._handle_input(0.05)
	check(game.move_to == null and takeover.strafeAim != null, "WASD takes over from a click route and resumes target-facing")
	_reset()
	_key(KEY_W, true)
	_key(KEY_D, true)
	var diagonal: Dictionary = game._handle_input(0.05)
	check(absf(Vector2(diagonal.move.x, diagonal.move.z).length() - 1) < 0.001, "Diagonal strafing has no speed advantage")


func _test_cursor_and_pad() -> void:
	_reset()
	game.settings.set_value("strafeFacing", "Mouse cursor")
	var aim := origin + Vector3(-3, 0, 1)
	var pixel := game.camera.unproject_position(aim)
	game.input.mouse.x = pixel.x
	game.input.mouse.y = pixel.y
	game.input.mouse.onCanvas = true
	_key(KEY_S, true)
	var controls: Dictionary = game._handle_input(0.05)
	check(controls.strafeAim != null, "Cursor mode acquires the world under the pointer")
	if controls.strafeAim != null:
		game.player.facing = atan2(controls.strafeAim.x - origin.x, controls.strafeAim.z - origin.z)
		_walk(8)
		check(game.player.facing_point(controls.strafeAim.x, controls.strafeAim.z, 4), "WASD movement retains cursor-facing")
	game.input.mouse.onCanvas = false
	check(game._handle_input(0.05).strafeAim == null, "Hovering UI releases cursor-facing")
	_reset()
	game.pad.left = Vector3(0.25, 0, 0.25)
	game.pad.right = Vector3(0, -1, 1)
	var pad_controls: Dictionary = game._handle_input(0.05)
	check(pad_controls.strafeAim != null and absf(Vector2(pad_controls.move.x, pad_controls.move.z).length() - 0.25) < 0.001, "Dual-stick facing retains analog movement speed")
	game.pad.right = Vector3.ZERO
	game.hud.set_pad_mode(true)
	check(game._handle_input(0.05).strafeAim == null, "Releasing the aiming stick returns to travel-facing")
	game.settings.set_value("strafeFacing", "obsolete value")
	check(game.settings.get_value("strafeFacing") == "Selected enemy", "An invalid stored facing mode safely uses the default")


func _test_jump_and_combat() -> void:
	_reset()
	_key(KEY_S, true)
	_key(KEY_SPACE, true)
	_walk(1)
	check(game.player.rig.airborne and game.player.jump_h > 0, "A retreating strafe can jump")
	_key(KEY_SPACE, false)
	_walk(22)
	check(not game.player.rig.airborne and game.player.jump_h < 0.01, "The jump lands while retaining movement control")
	_reset()
	# A real melee swing, while moving sideways past a living enemy.
	enemy.position = origin + Vector3(1.5, 0, 0)
	game.player.facing = PI / 2
	game.player.cooldowns.attack = 0
	game.player.opener = true
	game.targeting.engage(enemy)
	_key(KEY_S, true)
	_walk(1)
	check(game.player.rig.action != null and game.player.rig.action.type == "strike" and game.player.last_main_impact_at != null, "A target-facing strafe delivers an actual melee opening blow")
	game.player.rig.held = 0
	game.player.rig.update(0.05, DB.CONFIG.player.runGait)
	var rig: ForgeRig = game.player.rig
	var thigh: int = rig._skel.find_bone("thigh_l")
	check(rig.action != null and rig._moving() and not rig.last_action_clip.is_empty() and thigh >= 0 and not rig._upper_bones.has(thigh), "The moving swing keeps the legs in the gait and samples the upper-body attack")
	game.player.pending_shot = {"t": 0.5, "total": 0.5}
	_walk(1)
	check(game.player.pending_shot == null, "Moving still cancels an auto-shot draw")
	game.targeting.stop_attack()
	game.player.casting = {"id": "test", "target": null, "spell": {"kind": "cast"}, "channel": false}
	game.spells.update(0.05)
	check(game.player.casting == null, "Strafing still interrupts stationary spell casts")


func _test_toggle() -> void:
	_reset()
	game.keys.bind("toggleStrafing", "KeyV", 0)
	game.settings.set_value("strafeFacing", "Mouse cursor")
	game.settings.set_value("combatStrafing", false)
	_key(KEY_V, true)
	game._handle_input(0.05)
	check(game.settings.get_value("combatStrafing"), "The assigned shortcut turns strafing on")
	game._handle_input(0.05)
	check(game.settings.get_value("combatStrafing"), "Holding the shortcut does not toggle every frame")
	_key(KEY_V, false)
	_key(KEY_V, true)
	game._handle_input(0.05)
	check(not game.settings.get_value("combatStrafing") and game.settings.get_value("strafeFacing") == "Mouse cursor", "The shortcut turns it off and remembers the chosen facing mode")
	_key(KEY_V, false)
	var field := LineEdit.new()
	game.hud.root.add_child(field)
	field.grab_focus()
	_key(KEY_V, true)
	game._handle_input(0.05)
	check(not game.settings.get_value("combatStrafing"), "Typing the shortcut in a text field does not toggle strafing")
	field.release_focus()
	field.queue_free()
	game.input.end_frame()
	game.keys.bind("toggleStrafing", "Mouse4", 1)
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_XBUTTON1
	mouse.pressed = true
	game.input._input(mouse)
	game.input._unhandled_input(mouse)
	game.input.mouse.onCanvas = true
	game._handle_input(0.05)
	check(game.settings.get_value("combatStrafing") and game.move_to == null, "A mouse-button toggle activates strafing without starting a walk")
	mouse.pressed = false
	game.input._input(mouse)
	game.input.end_frame()


func _test_settings_ui() -> void:
	game.hud.toggle_panel("settings")
	game.hud.items._render_settings()
	var inputs: Dictionary = game.hud.items.settings_win.inputs
	var enabled: CheckBox = inputs.combatStrafing[0]
	enabled.button_pressed = false
	check(not game.settings.get_value("combatStrafing"), "The Settings checkbox switches strafing off")
	enabled.button_pressed = true
	check(game.settings.get_value("combatStrafing"), "The Settings checkbox switches strafing on")
	var facing: OptionButton = inputs.strafeFacing[0]
	check(facing.item_count == 2 and facing.get_item_text(0) == "Selected enemy" and facing.get_item_text(1) == "Mouse cursor", "The facing menu shows the intended choices")
	facing.item_selected.emit(0)
	check(game.settings.get_value("strafeFacing") == "Selected enemy", "Choosing target-facing updates the live preference")
	game.hud.items.close("settings")


func _capture_settings() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless": return
	game.hud.toggle_panel("settings")
	game.hud.items.settings_tab = "controls"
	game.hud.items._show_settings_tab()
	game.hud.update(0.1)
	game.hud.items._render_settings()
	for i in 12:
		await process_frame
		game.hud.items.layout()
		await create_timer(0.025).timeout
	game.hud.items.settings_win.scroll.ensure_control_visible(game.hud.items.settings_win.inputs.strafeFacing[0])
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(args[0].path_join("settings.png")) == OK, "Captured the optional strafing controls")
	game.hud.items.close("settings")

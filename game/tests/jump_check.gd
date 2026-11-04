extends SceneTree
## Real gameplay input, jumping, mixed movement and camera checks. Saves isolated.
class TestPad extends Pad:
	func poll() -> void: pass
var game
var failures := 0
var origin := Vector3.ZERO
var output := ""
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func _run() -> void:
	Store.dir = "user://jump_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Jump Tester", "warden")
	game.enter_world(made.character.id)
	var began := Time.get_ticks_msec()
	while game.hud.loading.visible:
		await process_frame
		if Time.get_ticks_msec() - began > 240000:
			check(false, "world loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.pad = TestPad.new()
	for i in 16: game.pad.now.append(false)
	game.pad.prev = game.pad.now.duplicate()
	game.settings.set_value("tankControls", false)
	game.settings.set_value("clickToMove", true)
	game.targeting.stop_attack()
	origin = game.player.position
	game._snap_camera()
	_reset()
	var camera_before: Vector3 = game.camera.position
	var feet_before: Vector2 = game.camera.unproject_position(game.player.position)
	var aim_before = game._aim_point()
	_key(KEY_SPACE, true)
	_tick()
	check(game.player.rig.airborne and game.player.position.y > origin.y, "Space lifts the actual player above the terrain")
	for i in 19: _tick()
	check(game.player.jump_h > 1.0, "jump has a readable height of over one metre")
	check(game.camera.position.distance_to(camera_before) < 0.001, "standing jump does not lift the camera")
	check(game.camera.unproject_position(game.player.position).y < feet_before.y - 10, "jump moves visibly upward on screen")
	check(absf(game.player.ground_shadow.global_position.y - origin.y - 0.03) < 0.001, "contact shadow stays on the ground")
	check(game._aim_point().distance_to(aim_before) < 0.001, "jumping does not change the mouse ground-target plane")
	check(game.player.rig.anim == null or game.player.rig.clip == "Jump", "imported player uses its jump animation")
	var peak: float = game.player.jump_h
	for i in 70: _tick()
	check(game.player.jump_h == 0.0 and game.player.jump_v == 0.0 and not game.player.rig.airborne, "player lands cleanly on the terrain")
	check(absf(game.player.position.y - Terrain.height_at(game.player.position.x, game.player.position.z)) < 0.001, "landing leaves feet at ground height")
	check(game.player.jump_h == 0.0, "holding Space does not repeatedly bounce after landing")
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	_tick()
	var velocity: float = game.player.jump_v
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	_tick()
	check(game.player.jump_v < velocity, "a second early press cannot double-jump")
	for i in 90: _tick()
	check(game.player.jump_h == 0.0, "an early airborne press expires rather than causing a delayed hop")
	_reset()
	_key(KEY_SPACE, true)
	for i in 37: _tick()
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	for i in 7: _tick()
	check(game.player.jump_v > 0.0 and game.player.jump_h > 0.0, "a press just before landing buffers the next jump")
	for classic in [true, false]:
		game.settings.set_value("classicControls", classic)
		_reset()
		_key(KEY_W, true)
		_key(KEY_SPACE, true)
		var start: Vector3 = game.player.position
		for i in 20: _tick()
		var moved := Vector2(game.player.position.x-start.x, game.player.position.z-start.z).length()
		check(game.player.rig.airborne and moved > 1.5, "WASD continues through the jump in " + str(classic))
		check(absf(moved - DB.CONFIG.player.speed / 3.0) < 0.05, "jump preserves normal running speed in " + str(classic))
		_reset()
		_click_ground(classic)
		check(game.move_to != null, "real mouse click queues a route in " + str(classic))
		_key(KEY_SPACE, true)
		for i in 20: _tick()
		check(game.player.rig.airborne and game.move_to != null, "jump keeps the clicked destination in " + str(classic))
		for i in 180: _tick()
		check(game.move_to == null and game.player.jump_h == 0.0, "click route finishes and player lands in " + str(classic))
		# Rebinding works in each independent mouse scheme.
		game.keys.bind("jump", "KeyJ")
		_reset()
		_key(KEY_J, true)
		_tick()
		check(game.player.rig.airborne, "rebound jump key works in " + str(classic))
		game.keys.reset_all()
	_reset()
	game.player.set_sitting(true)
	_key(KEY_SPACE, true)
	_tick()
	check(not game.player.sitting and game.player.rig.airborne, "jump stands a seated player up")
	game.player.set_sitting(true)
	check(not game.player.sitting, "sitting cannot freeze the pose in mid-air")
	game.player.place_at(origin.x, origin.z)
	check(game.player.jump_h == 0.0 and game.player.jump_v == 0.0 and not game.player.rig.airborne, "teleport resets airborne state")
	_reset()
	_key(KEY_SPACE, true)
	_tick()
	game.player.take_damage(100000)
	check(game.player.dead and game.player.jump_h == 0.0 and not game.player.rig.airborne, "death clears the jump and grounds the body")
	_key(KEY_SPACE, false)
	_key(KEY_SPACE, true)
	_tick()
	check(game.player.jump_h == 0.0, "dead players cannot jump")
	game.player.revive(origin.x, origin.z)
	_reset()
	var field := LineEdit.new()
	game.hud.root.add_child(field)
	field.grab_focus()
	_key(KEY_SPACE, true)
	_tick()
	check(game.player.jump_h == 0.0, "Space in a text field does not jump")
	field.release_focus()
	field.queue_free()
	for hz in [10, 30, 60, 120]:
		_reset()
		_key(KEY_SPACE, true)
		var high := 0.0
		for i in hz:
			_tick(1.0 / hz)
			high = maxf(high, game.player.jump_h)
		check(absf(high - peak) < 0.03 and game.player.jump_h == 0.0, "jump height and landing stay consistent at %d fps" % hz)
	# Optional native screenshots use the same actual gameplay camera.
	if DisplayServer.get_name() != "headless" and OS.get_cmdline_user_args().size():
		output = OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
		_reset()
		game._snap_camera()
		game.hud.banner.visible = false
		game.hud.zone_banner.visible = false
		await _picture("jump-ground")
		_key(KEY_SPACE, true)
		for i in 20: _tick()
		await _picture("jump-apex")
		for i in 30: _tick()
		await _picture("jump-landed")
	game.queue_free()
	game = null
	await process_frame
	await process_frame
	print("jump_check: %d failed" % failures)
	quit(1 if failures else 0)
func _tick(dt := 1.0 / 60.0) -> void:
	var controls = game._handle_input(dt)
	game.input.end_frame()
	game.player.update(dt, controls)
	game._update_camera(dt)
func _key(code: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = down
	game.input._input(event)
func _reset() -> void:
	game.input.held.clear()
	game.input.end_frame()
	game.input.mouse.leftHeld = false
	game.input.mouse.rightHeld = false
	game.input.mouse.onCanvas = false
	game.move_to = null
	game.player.rig.action = null
	game.player.rig.pose = null
	game.player.place_at(origin.x, origin.z)
func _click_ground(classic: bool) -> void:
	var goal := origin + Vector3(6, 0.5, 0)
	for offset in [Vector3(6, 0.5, 0), Vector3(-5, 0.5, -3), Vector3(3, 0.5, -5)]:
		goal = origin + offset
		var at: Vector2 = game.camera.unproject_position(goal)
		game.input.mouse.x = at.x
		game.input.mouse.y = at.y
		game.input.mouse.onCanvas = true
		if game._pick_under_cursor() == null: break
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT if classic else MOUSE_BUTTON_LEFT
	event.position = Vector2(game.input.mouse.x, game.input.mouse.y)
	event.pressed = true
	game.input._unhandled_input(event)
	game.input.mouse.onCanvas = true
	game._handle_input(0.0)
	event.pressed = false
	game.input._input(event)
	game.input.end_frame()
func _picture(label: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label + ".png"))

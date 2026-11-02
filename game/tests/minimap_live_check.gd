extends SceneTree
## Real-world minimap checks. All character/settings data uses an isolated store.
##   godot --headless --path . --script res://game/tests/minimap_live_check.gd -- new
## For rendered QA, omit --headless and add an output directory after the map id.
var game
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, message: String) -> void:
	if ok:
		print("ok: ", message)
	else:
		failures += 1
		printerr("FAIL: ", message)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var map_id := args[0] if not args.is_empty() else "new"
	ProjectSettings.set_setting(Terrain.MAP_SETTING, map_id)
	Store.dir = "user://minimap_live_check_%s_%d" % [map_id, Time.get_ticks_usec()]
	DB.ready = false
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Map Tester", "warden")
	check(made.ok, "test character created in a separate store")
	if not made.ok:
		quit(1)
		return
	game.enter_world(made.character.id)
	var frames := 0
	while not game.started or game.hud.blocks_gameplay:
		await process_frame
		frames += 1
		if frames > 1800:
			check(false, "game finishes loading")
			quit(1)
			return
	game.save.autosave_enabled = false
	var minimap: Minimap = game.hud.minimap
	minimap._refresh_overhead(true)
	await process_frame
	check(minimap.terrain_view != null and minimap.overhead_camera != null, "actual-world overhead camera is created")
	check(minimap.terrain_view.world_3d == game.get_world_3d(), "minimap shares the active gameplay world")
	check(minimap.picture == minimap.terrain_view.get_texture(), "minimap background is a rendered viewport texture")
	check(minimap.overhead_camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "overhead view uses orthographic projection")
	check(not minimap.overhead_camera.environment.fog_enabled and game.env.fog_enabled, "map fog is disabled independently of gameplay fog")
	check(game.get_viewport().get_camera_3d() == game.camera, "minimap does not replace the gameplay camera")
	var player: Vector3 = game.player.position
	var centre := Vector2.ONE * Minimap.SIZE * 0.5
	for index in Minimap.ZOOMS.size():
		minimap.set_zoom(index)
		minimap._refresh_overhead(true)
		var scale: float = Minimap.ZOOMS[index]
		check(is_equal_approx(minimap.overhead_camera.size, Minimap.CAPTURE_PIXELS / scale), "capture and marker scales agree at zoom %d" % index)
		check(minimap.world_to_map(Vector2(player.x, player.z)).is_equal_approx(centre), "player remains centred at zoom %d" % index)
		var east := minimap.world_to_map(Vector2(player.x + 10, player.z))
		var north := minimap.world_to_map(Vector2(player.x, player.z - 10))
		check(is_equal_approx(east.x, centre.x + 10 * scale) and north.y < centre.y, "markers point east/right and north/up at zoom %d" % index)
	var pc := minimap.overhead_camera.unproject_position(player)
	var pe := minimap.overhead_camera.unproject_position(player + Vector3(10, 0, 0))
	var pn := minimap.overhead_camera.unproject_position(player + Vector3(0, 0, -10))
	check(pe.x > pc.x and pn.y < pc.y, "rendered camera orientation matches marker orientation")
	check(minimap.overhead_camera.unproject_position(player + Vector3(0, 20, 0)).distance_to(pc) < 0.01, "raised terrain and objects retain the same map coordinates")
	check(Minimap.SIZE * 0.5 / Minimap.ZOOMS[0] < Land.RADIUS - 10, "widest circle stays inside the streamed terrain radius")
	minimap.set_zoom(999)
	check(minimap.zoom == Minimap.ZOOMS.size() - 1, "zoom-in is bounded")
	minimap.set_zoom(-1)
	check(minimap.zoom == 0, "zoom-out is bounded")
	minimap.set_zoom(1)
	var old_at := minimap._captured_at
	game.player.place_at(player.x + 20, player.z)
	minimap._refresh_overhead()
	check(minimap._captured_at.distance_to(old_at) > 10, "teleport refreshes the capture immediately")
	game.player.place_at(player.x, player.z)
	minimap._refresh_overhead(true)
	if DisplayServer.get_name() != "headless":
		await _render_check(minimap, args)
	var map_ref: WeakRef = weakref(minimap)
	var camera_ref: WeakRef = weakref(minimap.overhead_camera)
	var capture_ref: WeakRef = weakref(minimap.terrain_view)
	game.queue_free()
	await process_frame
	await process_frame
	check(map_ref.get_ref() == null and camera_ref.get_ref() == null and capture_ref.get_ref() == null, "minimap and its rendering resources are released with the game scene")
	Terrain._ground_img = null
	Terrain._map_tex = null
	Assets._cache.clear()
	Assets._converted.clear()
	Assets._shared.clear()
	print("minimap_live_check (%s): %d failed" % [map_id, failures])
	quit(1 if failures else 0)


func _render_check(minimap: Minimap, args: PackedStringArray) -> void:
	# Let the loading screen finish its visual fade before taking HUD images.
	while game.hud.loading.visible:
		await process_frame
	for frame in 5:
		await process_frame
	minimap._refresh_overhead(true)
	await RenderingServer.frame_post_draw
	var before := minimap.terrain_view.get_texture().get_image()
	check(not before.is_empty(), "overhead viewport produces a rendered image")
	var p: Vector3 = game.player.position
	var tree := World.prop_instance({"model": "res://assets/environment/nature/trees/CommonTree_1.gltf", "position": [p.x + 12, p.z], "scale": 2})
	game.world.group.add_child(tree)
	minimap._refresh_overhead(true)
	await RenderingServer.frame_post_draw
	await process_frame
	var after := minimap.terrain_view.get_texture().get_image()
	if not before.is_empty() and not after.is_empty():
		var point := minimap.overhead_camera.unproject_position(tree.global_position)
		var differences := 0
		for y in range(maxi(0, int(point.y) - 22), mini(after.get_height(), int(point.y) + 22)):
			for x in range(maxi(0, int(point.x) - 22), mini(after.get_width(), int(point.x) + 22)):
				if before.get_pixel(x, y) != after.get_pixel(x, y):
					differences += 1
		check(differences > 10, "an actual newly placed nature asset appears in the minimap")
	tree.queue_free()
	await process_frame
	minimap._refresh_overhead(true)
	await RenderingServer.frame_post_draw
	after = minimap.terrain_view.get_texture().get_image()
	if args.size() > 1:
		var output := args[1]
		DirAccess.make_dir_recursive_absolute(output)
		check(after.save_png(output.path_join(map_name() + "-overhead.png")) == OK, "overhead QA image saved")
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join(map_name() + "-game.png")) == OK, "game/HUD QA image saved")


func map_name() -> String:
	return Terrain.chosen_map()

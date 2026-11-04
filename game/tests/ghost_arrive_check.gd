extends SceneTree
## The spirit rising far from the body must not stall the game: the ground
## at the rest point is built behind the loading screen a slice per frame,
## and a chunk's grass tests only the town shapes near it. Also: a spirit
## can hop, casts no shadow, and the wind plays while dead.
##   godot --headless --path . --script res://game/tests/ghost_arrive_check.gd

var game
var frame := 0
var failed := 0
var t0 := 0
var worst := 0.0
var start_frame := -1
var loading_seen := false


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_arrive"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Arrive", "warrior")
		game.enter_world(made.character.id)
	elif frame == 60:
		var r: Dictionary = game.respawn_point()
		game.player.place_at(r.x + 250, r.z + 250)
		game._snap_camera()
		_town_test()
	elif frame == 120:
		game.player.take_damage(99999)
		game.on_player_death(null)
		_ok(game.audio.death_loop != null and game.audio.death_loop.playing, "the wind plays while dead")
		_ok(game.audio.dead and (game.audio.music.stream_paused or not game.audio.music.playing), "the music waits while dead")
	elif frame == 150:
		var u := Time.get_ticks_usec()
		game.release_spirit()
		worst = (Time.get_ticks_usec() - u) / 1000.0
		start_frame = frame
		t0 = Time.get_ticks_usec()
	elif start_frame > 0 and frame <= start_frame + 200:
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - t0) / 1000.0)
		t0 = now
		loading_seen = loading_seen or game.hud.modal == "loading"
		if frame == start_frame + 120:
			_ok(game.hud.modal != "loading", "the loading screen lifts once the ground is built")
			_ok(game.world.land.missing(game.camera_target) == 0, "the ground round the rest point is built")
			var casting := 0
			for gi: GeometryInstance3D in game.player.model.find_children("*", "GeometryInstance3D", true, false):
				if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					casting += 1
			_ok(casting == 0, "a spirit casts no shadow (%d parts still do)" % casting)
			var solid := 0
			for mi: MeshInstance3D in game.player.model.find_children("*", "MeshInstance3D", true, false):
				if mi.visible and mi.mesh != null:
					for i in mi.mesh.get_surface_count():
						var m := mi.get_active_material(i)
						if m is BaseMaterial3D and m.albedo_color.a >= 1.0:
							solid += 1
			_ok(solid == 0, "a spirit fades whole, gear too (%d parts solid)" % solid)
			game.player.update(0.016, {"move": {"x": 0.0, "z": 0.0}, "jump": true})
			game.player.update(0.05, {"move": {"x": 0.0, "z": 0.0}})
			_ok(game.player.jump_h > 0.0, "a spirit can hop")
		if frame == start_frame + 160:
			game.afterlife.revive_here()
			_ok(not game.audio.death_loop.playing, "the wind stops on return to life")
			_ok(not game.audio.dead and not game.audio.music.stream_paused, "the music carries on")
	elif start_frame > 0:
		_ok(loading_seen, "the arrival is behind the loading screen")
		print("worst frame after the spirit rose: %.0f ms" % worst)
		_ok(worst < 600.0, "no long stall when the spirit rises (%.0f ms)" % worst)
		print("ghost arrive check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
		quit(1 if failed else 0)
	return false


## the chunk-local town test agrees with the whole-world one
func _town_test() -> void:
	var bad := 0
	var rng := RandomNumberGenerator.new()
	var spots := [Vector2(game.player.position.x, game.player.position.z), Vector2(Layout.player_start.position[0], Layout.player_start.position[1])]
	for b in Layout.houses.slice(0, 3):
		spots.append(Vector2(b.position[0], b.position[1]))
	for c in spots:
		var k := Vector2i(floori(c.x / Land.CHUNK), floori(c.y / Land.CHUNK))
		var near := World._town_near(k.x * Land.CHUNK, k.y * Land.CHUNK, (k.x + 1) * Land.CHUNK, (k.y + 1) * Land.CHUNK)
		for i in 400:
			var x := k.x * Land.CHUNK + rng.randf() * Land.CHUNK
			var z := k.y * Land.CHUNK + rng.randf() * Land.CHUNK
			if World._clear_of(near, x, z) != World._clear_of_town(x, z):
				bad += 1
	_ok(bad == 0, "grass keeps clear of the town as before (%d differ)" % bad)


func _ok(ok: bool, what: String) -> void:
	if not ok:
		failed += 1
		print("FAIL: ", what)

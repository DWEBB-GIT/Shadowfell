extends SceneTree
## Forest ambience by day or night, music that waits and fades (Dan,
## 2026-11-02), and a trainer's quest turning the page.
##   godot --headless --path . --script res://game/tests/ambience_music_check.gd

var game
var frame := 0
var failed := 0


func _ok(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	if not c:
		failed += 1


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_ambience"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Amb Tester", "warrior")
		game.enter_world(made.character.id)
	elif frame == 30:
		var a = game.audio
		_ok(not a.music.playing, "no music on arrival")
		_ok(a.music_wait >= a.MUSIC_FIRST[0] - 1, "music waits a few minutes first")
		var want: String = a.FOREST_NIGHT if a.is_night() else a.FOREST_DAY
		_ok(a._amb_for("blackwood") == want, "open country plays the forest for the hour")
		_ok(a._amb_for("brackenford") == "amb_town.mp3", "town keeps its loop")
		_ok(a._stream(a.FOREST_DAY) != null and a._stream(a.FOREST_NIGHT) != null, "both forest loops load")
		# day to night: the old loop fades, the new one comes in
		a.amb_file = a.FOREST_DAY
		a.amb_want = a.FOREST_NIGHT
		a.amb_check = 999
		for i in 150:
			a._update_ambience(1.0 / 30)
		_ok(a.amb_file == a.FOREST_NIGHT and a.amb_loop.playing, "crossed to the night loop")
		# the music comes in, fades up, then fades out and goes quiet
		a.music_wait = 0.01
		a._update_music(0.1)
		_ok(a.music.playing, "music starts when its wait runs out")
		for i in 100:
			a._update_music(0.1)
		_ok(a.music_level > 0.9, "music faded in")
		a.music_fading = true
		for i in 200:
			a._update_music(0.1)
		_ok(not a.music.playing and a.music_wait >= a.MUSIC_QUIET[0] - 1, "faded out, long silence next")
		# opening a quest turns the page (a trainer's as any other npc's)
		var n = game.npcs.by_id("vr_morrow")
		if n == null:
			n = game.npcs.list[0]
		game.dialogue.open(n)
		a.last_sfx_frame = -1
		game.dialogue.choose("quest:" + DB.quests.keys()[0])
		_ok(a.last_sfx_frame == Engine.get_process_frames(), "opening a quest plays the page turn, not the click")
		game.dialogue.close()
	elif frame == 32:
		print("FAILED %d" % failed if failed else "ALL OK")
		quit(1 if failed else 0)
	return false

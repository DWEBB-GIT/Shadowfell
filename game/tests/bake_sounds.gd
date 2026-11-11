extends SceneTree
## Bakes every made (synthesised) sound to assets/sounds/made/ with an
## index.json (recipe key -> file). Re-run after changing a sound recipe,
## spell_fx.json sound cues or the warm list in audio.gd:
##   godot --headless --path . --script res://game/tests/bake_sounds.gd
## With `-- --check` it only reports recipes missing from the bake (CI).

const DIR := "res://assets/sounds/made/"


func _initialize() -> void:
	Store.dir = "user://bake_sounds_store"
	var g = load("res://game/main.tscn").instantiate()
	root.add_child(g)
	await process_frame
	var a: AudioSystem = g.audio
	# the game's own audio already read the index: make everything afresh
	a.bake = true
	a.made = {}
	a.cache = {}
	# every variant of every recipe (a few pick theirs at random)
	a.warming = true
	for v in AudioSystem.VARIANTS:
		a.warm = []
		a._ready()
		while not a.warm.is_empty():
			a._force_variant = v
			a.warm.pop_front().call()
	a._force_variant = -1
	a.warming = false
	var check := "--check" in OS.get_cmdline_user_args()
	if check:
		var have := {}
		if FileAccess.file_exists(DIR + "index.json"):
			have = JSON.parse_string(FileAccess.get_file_as_string(DIR + "index.json"))
		var missing: Array = a.cache.keys().filter(func(k): return not have.has(k))
		print("bake_sounds: %d recipes, %d missing from the bake%s" % [a.cache.size(), missing.size(), (": " + ", ".join(missing)) if missing else ""])
		if missing:
			print("  FAIL run game/tests/bake_sounds.gd")
		quit(1 if missing else 0)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".wav") or f.ends_with(".wav.import"):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR + f))
	var index := {}
	var bytes := 0
	for key in a.cache:
		var w: AudioStreamWAV = a.cache[key]
		var file := (key as String).replace(":", "_").replace("[", "").replace("]", "").replace(", ", "-").replace(" ", "").validate_filename() + ".wav"
		w.save_to_wav(ProjectSettings.globalize_path(DIR + file))
		index[key] = file
		bytes += w.data.size()
	var f := FileAccess.open(DIR + "index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(index, "\t", true))
	f.close()
	print("bake_sounds: %d sounds, %.1f MB of 16-bit samples" % [index.size(), bytes / 1e6])
	quit()

extends SceneTree
## Renders every synthesised sound once and prints how long each took and
## its loudest sample (a quick check that nothing clips or takes too long):
##   godot --headless --path . --script res://game/tests/audio_check.gd

var frames := 0
var game


func _initialize() -> void:
	Store.dir = "user://audio_check_store"
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_d: float) -> bool:
	frames += 1
	if frames < 3:
		return false
	var a: AudioSystem = game.audio
	var t0 := Time.get_ticks_msec()
	a.start()
	print("start (rumble loop): %d ms" % (Time.get_ticks_msec() - t0))
	var calls := {
		"whoosh": func(): a.whoosh(0.18, 900), "impact": func(): a.impact(), "thud": func(): a.thud(110, 0.25),
		"shieldBreak": func(): a.shield_break(), "growl": func(): a.growl(70, 0.5), "death": func(): a.death(true),
		"chime": func(): a.chime([392, 494, 587, 784], 0.22), "coins": func(): a.coins(), "bell": func(): a.bell(0.25, 440),
		"crow": func(): a.crow(), "creak": func(): a.creak(),
	}
	for k in calls:
		var t := Time.get_ticks_msec()
		calls[k].call()
		print("%s: %d ms" % [k, Time.get_ticks_msec() - t])
	for key in a.cache:
		var w: AudioStreamWAV = a.cache[key]
		var peak := 0
		for i in range(0, w.data.size(), 2):
			peak = maxi(peak, absi(w.data.decode_s16(i)))
		print("  %s peak %.2f" % [key, peak / 32767.0])
	quit()
	return false

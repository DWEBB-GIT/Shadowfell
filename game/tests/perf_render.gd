extends SceneTree
## Real frame times with rendering (run with a display, e.g. xvfb-run),
## with parts switched off in turn (each between two full runs) to see what
## costs what. Software GL (xvfb) is slow overall; compare the rows:
##   godot --path . --rendering-driver opengl3 --script res://game/tests/perf_render.gd -- x z

var frames := 0
var game
var phase := 0
var last := 0
var acc := 0.0
var n := 0
const PHASES := ["all", "no_sparkles", "all", "no_hud", "all", "no_omni", "all", "no_sun_shadow", "all"]


func _initialize() -> void:
	Store.dir = "user://perf_store"
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _lights(n: Node, out: Array) -> void:
	if n is OmniLight3D:
		out.append(n)
	for c in n.get_children():
		_lights(c, out)


func _process(_d: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		var r = game.roster.create("Perf", "warden")
		game.enter_world(r.character.id if r.ok else game.roster.list[0].id)
		if args.size() >= 2:
			game.player.place_at(float(args[0]), float(args[1]))
		game._snap_camera()
	if frames < 120:
		last = Time.get_ticks_usec()
		return false
	var now := Time.get_ticks_usec()
	acc += (now - last) / 1000.0
	last = now
	n += 1
	if n == 120:
		var ls := []
		_lights(root, ls)
		var vis := ls.filter(func(l): return l.visible)
		print("%-14s frame %.1f ms  omni on %d  draws %d  objects %d  prims %d  process %.1f" % [PHASES[phase], acc / n, vis.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.TIME_PROCESS) * 1000])
		n = 0
		acc = 0
		phase += 1
		if phase >= PHASES.size():
			quit()
			return false
		game.sun.shadow_enabled = true
		game.sparkles.node.visible = true
		game.hud.visible = true
		for l in ls:
			l.visible = true
		match PHASES[phase]:
			"no_sun_shadow":
				game.sun.shadow_enabled = false
			"no_omni":
				for l in ls:
					l.visible = false
			"no_sparkles":
				game.sparkles.node.visible = false
			"no_hud":
				game.hud.visible = false
			"no_fog":
				game.env.fog_enabled = false
	return false

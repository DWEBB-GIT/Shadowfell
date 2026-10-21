extends SceneTree
## Renders the game and saves a picture, for checking a change without
## opening the editor (needs a display; on a server use xvfb-run):
##   godot --path . --script res://game/tests/screenshot.gd -- out.png [x z [windows]]
## With a position it makes a character (in a separate store) and stands
## them there; without one it shows the title screen.

var frames := 0
var out := "screenshot.png"
var game


func _initialize() -> void:
	Store.dir = "user://shot_store"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3 and args.size() >= 3:
		var r = game.roster.create("Shot", "warden")
		game.enter_world(r.character.id if r.ok else game.roster.list[0].id)
		game.player.place_at(float(args[1]), float(args[2]))
		game._snap_camera()
	# a fourth argument opens windows: bags,character,quests...
	if frames == 30 and args.size() >= 4:
		for w in args[3].split(","):
			game.hud.show_window(w)
	if frames == 60:
		root.get_texture().get_image().save_png(out)
		print("saved ", out, " at ", game.player.position)
		quit()
	return false

extends SceneTree
## The same spot at a few hours of the world clock, for judging the day and
## night light (needs a display; on a server use xvfb-run):
##   godot --path . --script res://game/tests/day_night_shots.gd -- out_dir [x z]
## Saves hour-<hh>.png for each hour in HOURS (Thornford by default).

const HOURS := [9.0, 16.0, 19.5, 23.0]

var frames := 0
var game
var shot := 0


func _initialize() -> void:
	Store.dir = "user://day_night_shots"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		var r = game.roster.create("Shot", "warrior")
		game.enter_world(r.character.id)
	var k := frames - 10
	if k >= 0 and k % 90 == 0 and shot < HOURS.size():
		var x: float = float(args[1]) if args.size() > 2 else -452.0
		var z: float = float(args[2]) if args.size() > 2 else -190.0
		game.player.place_at(x, z)
		game.world_state.hour = HOURS[shot]
		game._snap_camera()
	if k >= 0 and k % 90 == 89 and shot < HOURS.size():
		root.get_texture().get_image().save_png(args[0].path_join("hour-%02d.png" % int(HOURS[shot])))
		print("saved hour ", HOURS[shot])
		shot += 1
		if shot == HOURS.size():
			quit()
	return false

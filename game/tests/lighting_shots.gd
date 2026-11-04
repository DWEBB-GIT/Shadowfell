extends SceneTree
## Pictures of the world lighting at a few places, for judging a light or
## grade change side by side (needs a display; on a server use xvfb-run):
##   godot --path . --script res://game/tests/lighting_shots.gd -- out_dir [tag]
## Saves light-<spot>[-tag].png for each spot.

## [name, x, z] on the Act 1 map: lane start, Brackenford, the farms, the Blackwood
const SPOTS := [["lane", -402.0, 435.0], ["town", -615.0, 440.0], ["farms", -436.0, 292.0], ["blackwood", -582.0, -60.0]]

var frames := 0
var game
var shot := 0


func _initialize() -> void:
	Store.dir = "user://lighting_shots"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var r = game.roster.create("Shot", "warrior")
		game.enter_world(r.character.id)
	var k := frames - 10
	if k >= 0 and k % 90 == 0 and shot < SPOTS.size():
		var s: Array = SPOTS[shot]
		game.player.place_at(s[1], s[2])
		game._snap_camera()
	if k >= 0 and k % 90 == 89 and shot < SPOTS.size():
		var args := OS.get_cmdline_user_args()
		var tag: String = ("-" + args[1]) if args.size() > 1 else ""
		root.get_texture().get_image().save_png(args[0].path_join("light-%s%s.png" % [SPOTS[shot][0], tag]))
		print("saved ", SPOTS[shot][0])
		shot += 1
		if shot == SPOTS.size():
			quit()
	return false

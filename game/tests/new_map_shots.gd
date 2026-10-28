extends SceneTree
## Pictures of Dan's new map in the game (data/terrain/new_map):
##   godot --path . --script res://game/tests/new_map_shots.gd -- out_dir
## Stands at a few places on it and saves what the camera sees, then the
## world map (M).

## [name, x, z]: map pixel p sits at x = p.x * 2 - 1024, z = p.y * 2 - 1536
const SPOTS := [["town", 267.0, -155.0], ["coast", -610.0, -780.0], ["town-shore", 288.0, 58.0], ["hills", -264.0, -772.0], ["red-rock", -86.0, 458.0], ["desert", -312.0, 976.0]]

var frames := 0
var game
var shot := 0


func _initialize() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://new_map_shots"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _save(name: String) -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png(out.path_join("new-map-%s.png" % name))
	print("saved ", name)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var r = game.roster.create("Shot", "warrior")
		game.enter_world(r.character.id)
	# each spot: go there, let the ground stream in, take the picture
	var k := frames - 10
	if k >= 0 and k % 60 == 0 and shot < SPOTS.size():
		var s: Array = SPOTS[shot]
		game.player.place_at(s[1], s[2])
		game.zoom = game._zoom_max() # pulled right out, to see the land
		game._snap_camera()
	if k >= 0 and k % 60 == 50 and shot < SPOTS.size():
		_save(SPOTS[shot][0])
		shot += 1
	if shot == SPOTS.size() and frames == 10 + SPOTS.size() * 60 + 5:
		game.player.place_at(SPOTS[0][1], SPOTS[0][2])
		game.hud.world_map.open()
	if frames == 10 + SPOTS.size() * 60 + 20:
		_save("world-map")
		return true
	return false

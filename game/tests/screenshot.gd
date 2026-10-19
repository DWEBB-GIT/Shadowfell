extends SceneTree
## Renders the game scene and saves a picture, for checking a change without
## opening the editor (needs a display; on a server use xvfb-run):
##   godot --path . --script res://game/tests/screenshot.gd -- out.png [x z]

var frames := 0
var out := "screenshot.png"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	root.add_child(load("res://game/main.tscn").instantiate())


func _process(_delta: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 2 and args.size() >= 3:
		var p: Node3D = root.get_child(-1).get_node("Player")
		p.position = Vector3(float(args[1]), Terrain.height_at(float(args[1]), float(args[2])), float(args[2]))
	if frames == 40:
		root.get_texture().get_image().save_png(out)
		print("saved ", out, " at ", root.get_child(-1).get_node("Player").position)
		quit()
	return false

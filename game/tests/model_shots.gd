extends SceneTree
## Pictures of the imported models (assets/blender/import_models.py) playing
## each clip, for checking a rig without opening the editor (needs a display;
## on a server use xvfb-run):
##   godot --path . --script res://game/tests/model_shots.gd -- out_dir
## One row per model, one column per clip; a picture at each of SHOT_TIMES
## (fractions of each clip). Also shows the imported weapons beside the
## code-built ones they stand in for.

const MODELS := [["rat", 3.0], ["chicken", 2.5], ["base_male", 0.75]]
const CLIPS := ["Idle", "Walk", "Run", "Attack", "Cast", "Sit", "Death"]
const SHOT_TIMES := [0.0, 0.25, 0.5, 0.75]

var out_dir := "."
var frames := 0
var shot := 0
var players := []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	root.size = Vector2i(1280, 960)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("6f7f6a")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.0
	root.add_child(cam)
	cam.look_at_from_position(Vector3(1.6, 6, 7), Vector3(1.6, 0.2, 0.4))
	for r in MODELS.size():
		for c in CLIPS.size():
			var m := Assets.instance(MODELS[r][0])
			m.scale *= MODELS[r][1]
			m.position = Vector3(c * 1.15 - 1.8, 0, r * 1.7 - 1.7)
			m.rotation.y = 0.7
			root.add_child(m)
			var ap := m.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if ap and not ap.has_animation(CLIPS[c]):
				m.visible = false
			if ap and ap.has_animation(CLIPS[c]):
				ap.play(CLIPS[c])
				ap.speed_scale = 0
				players.append(ap)
	# weapons: code-built on the left of each pair, imported on the right
	var pairs := [["dirk", "stylized_dagger"], ["worn_sword", "stylized_sword"]]
	for i in pairs.size():
		for j in 2:
			var w := Assets.instance(pairs[i][j])
			w.position = Vector3(6.0 + i * 1.0 + j * 0.45, 0.1, 0.6)
			w.scale *= 1.6
			root.add_child(w)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 5:
		return false
	if shot >= SHOT_TIMES.size():
		quit()
		return false
	for ap: AnimationPlayer in players:
		ap.seek(SHOT_TIMES[shot] * ap.get_animation(ap.current_animation).length, true)
	if frames % 3 == 0:
		var img := root.get_texture().get_image()
		img.save_png("%s/models_%d.png" % [out_dir, shot])
		shot += 1
	return false

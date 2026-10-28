extends SceneTree
## In-game pictures of the imported models: a Warrior (imported starting
## sword) and a Rogue (imported daggers) at the Corrick farm among the hens,
## with granary rats brought alongside, one of them dying. Needs a display
## (xvfb-run on a server):
##   godot --path . --script res://game/tests/model_game_shots.gd -- out_dir warden|rogue

const STEP := 1.0 / 60
const SPOT := Vector3(-442, 0, 280)

var frames := 0
var out_dir := "."
var game
var stage := 0
var t := 0.0
var rats := []
var archetype := "warden"


func _initialize() -> void:
	Store.dir = "user://shot_store"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		archetype = args[1]
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _enter() -> void:
	var r = game.roster.create("Shot" + archetype, archetype)
	game.enter_world(r.character.id)
	game.zoom = 0.45
	game.set_process(false)
	game.player.place_at(SPOT.x, SPOT.z, PI * 0.75)
	game._snap_camera()
	rats = []
	for e in game.enemies.list:
		if e.cfg.id == "granary_rat" and rats.size() < 3:
			rats.append(e)
	for i in rats.size():
		rats[i].home = SPOT + Vector3(1.5 + i * 0.9, 0, 1.6 - i * 0.6)
		rats[i].position = rats[i].home
	t = 0.0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_enter()
	if frames < 3:
		return false
	game.step(STEP)
	t += STEP
	if stage == 0 and t > 1.5:
		_shot(archetype)
		rats[0].hurt(9999)
		stage = 1
	elif stage == 1 and t > 2.2:
		_shot(archetype + "_rat_dying")
		quit()
	return false


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png("%s/game_%s.png" % [out_dir, name])

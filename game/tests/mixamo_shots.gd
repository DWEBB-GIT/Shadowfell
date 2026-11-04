extends SceneTree
## Pictures of the player's Mixamo clips (Idle, Walk, Run, Jump) in game,
## holding a sword and a shield, then a torch, to check the hand sockets.
## Needs a display (xvfb-run on a server):
##   godot --path . --script res://game/tests/mixamo_shots.gd -- out_dir

const STEP := 1.0 / 60
const SPOT := Vector3(-442, 0, 280)
## clip, speed01 (before runGait), airborne, seconds in, off hand
const SHOTS := [
	["idle", 0.0, false, 1.0, "kite_shield"],
	["walk", 0.5, false, 0.6, "kite_shield"],
	["run", 1.0, false, 0.5, "kite_shield"],
	["jump", 0.0, true, 0.25, "torch"],
	["run_torch", 1.0, false, 0.35, "torch"],
	["idle_torch", 0.0, false, 2.0, "torch"],
]

var frames := 0
var out_dir := "."
var game
var shot := -1
var t := 0.0


func _initialize() -> void:
	Store.dir = "user://shot_store"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _enter() -> void:
	var r = game.roster.create("ShotMixamo", "warden")
	var id = r.character.id if r.ok else null
	for c in game.roster.list:
		if id == null and c.name == "ShotMixamo":
			id = c.id
	game.enter_world(id)
	game.zoom = 0.3
	game.set_process(false)
	game.player.place_at(SPOT.x, SPOT.z, PI * 0.75)
	game._snap_camera()


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_enter()
	if frames < 6:
		return false
	if shot < 0 or t >= SHOTS[shot][3]:
		if shot >= 0:
			root.get_texture().get_image().save_png("%s/mixamo_%s.png" % [out_dir, SHOTS[shot][0]])
		shot += 1
		t = 0.0
		if shot >= SHOTS.size():
			quit()
			return false
		game.inventory.equipment.offHand = {"id": SHOTS[shot][4]}
		game.player.show_equipment(game.inventory.equipment)
	var rig = game.player.rig
	rig.airborne = SHOTS[shot][2]
	rig.update(STEP, SHOTS[shot][1] * DB.CONFIG.player.runGait)
	t += STEP
	return false

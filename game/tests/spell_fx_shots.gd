extends SceneTree
## Pictures of spell looks (data/spell_fx.json) mid-cast, for checking a new
## effect or pose without opening the editor (needs a display; on a server
## use xvfb-run):
##   godot --path . --script res://game/tests/spell_fx_shots.gd -- out_dir heavyStrike,cleave,...
## For each spell a Warrior stands at the start with an enemy in front,
## casts it, and a picture is saved at each of SHOT_TIMES seconds in.
## Time is stepped by hand, so the pictures land on the same moments
## however slowly the machine draws.

const SHOT_TIMES := [0.08, 0.18, 0.3, 0.5]
const STEP := 1.0 / 60

var frames := 0
var out_dir := "."
var spells := []
var game
var foe = null
var current := -1
var t := 0.0
var shot := 0


func _initialize() -> void:
	Store.dir = "user://shot_store"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		spells = Array(args[1].split(","))
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var r = game.roster.create("Shot", "warden")
		game.enter_world(r.character.id if r.ok else game.roster.list[0].id)
		game.zoom = float(OS.get_environment("SHOT_ZOOM")) if OS.has_environment("SHOT_ZOOM") else 0.7
		game._snap_camera()
		game.set_process(false)
		game.random = func() -> float: return 0.5
		for id in spells:
			game.skills.learn_spell(id)
		foe = game.enemies.list[0]
		for e in game.enemies.list:
			if e.position.distance_to(game.player.position) < foe.position.distance_to(game.player.position):
				foe = e
	if frames < 40:
		if frames > 3:
			game.step(STEP)
		return false
	if current < 0 or (shot >= SHOT_TIMES.size() and t > 1.6):
		current += 1
		if current >= spells.size():
			quit()
			return false
		_start(spells[current])
	# the enemy holds still in front (it walks off home otherwise)
	if t < 0.6 and spells[current] != "lunge":
		foe.position = game.player.position + Vector3(1.9, 0, 0)
	game.step(STEP)
	t += STEP
	if shot < SHOT_TIMES.size() and t >= SHOT_TIMES[shot]:
		var path := "%s/%s_%d.png" % [out_dir, spells[current], shot]
		root.get_texture().get_image().save_png(path)
		shot += 1
	return false


func _start(id: String) -> void:
	var p = game.player
	p.health = p.max_health
	for k in p.cooldowns:
		p.cooldowns[k] = 0.0
	# side on to the camera, so the pose reads
	p.facing = PI / 2
	game.resources.add("resolve", 100)
	# the enemy stands in front, a step away, full of health
	foe.position = p.position + Vector3(1.9, 0, 0)
	foe.health = foe.max_health
	game.targeting.select(foe)
	t = 0.0
	shot = 0
	print(id, " (", game.stats.archetype.get("id"), "): ", "cast" if game.spells.try_cast(id) else "refused")

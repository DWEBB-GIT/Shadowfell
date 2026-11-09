extends SceneTree
## A rendered review of class feedback, using an isolated character profile.

var game
var foe
var output := "user://class_feedback"
const STEP := 1.0 / 60.0
const CASES := [
	["warden", "flurry", 0.20],
	["paladin", "lightShield", 0.14],
	["paladin", "lightsHammer", 0.18],
	["rogue", "poisonedBlade", 0.16],
	["ranger", "flamingArrow", 0.34],
	["occultist", "siphonLife", 1.05],
	["wizard", "firebolt", 0.6],
	["wizard", "meteor", 2.78],
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	Store.dir = "user://class_feedback_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hud.title.class_id = "wizard"
	game.hud.title.show_view("create")
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("class_selection.png"))
	var made: Dictionary = game.roster.create("Spellreview", "wizard")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:
		await process_frame
	game.save.autosave_enabled = false
	game.set_process(false)
	game.random = func() -> float: return 0.5
	game.zoom = 0.8
	game._snap_camera()
	for enemy in game.enemies.list:
		if not enemy.protected and not enemy.cfg.get("dummy", false):
			foe = enemy
			break
	for scenario in CASES:
		_prepare(scenario[0], scenario[1])
		var cast: bool = game.spells.try_cast(scenario[1])
		print("render ", scenario[0], " ", scenario[1], " cast=", cast)
		if not cast:
			quit(1)
			return
		for frame in ceili(float(scenario[2]) / STEP):
			game.time += STEP
			game.spells.update(STEP)
			game.player.rig.update(STEP, 0.0)
			game.player._sync()
			foe.rig.update(STEP, 0.0)
			foe._sync()
			game.fx.update(STEP)
			game.hud.update(STEP)
			game.world.update(STEP, game.time)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(scenario[0]+"_"+scenario[1]+".png"))
	game.spells.reset()
	game.fx.update(1000)
	game.enemies.clear()
	foe = null
	game.queue_free()
	await process_frame
	await process_frame
	quit()


func _prepare(class_id: String, ability: String) -> void:
	game.spells.reset()
	game.fx.update(1000)
	game.archetype_id = class_id
	game.inventory.reset()
	game.resources.reset()
	game.skills.all_spells = true
	game.targeting.stop_attack()
	game.targeting.select(foe)
	game.player.casting = null
	game.player.lunge = null
	game.player.pending = null
	game.player.pending_off = null
	game.player.pending_shot = null
	game.player.health = game.player.max_health
	game.player.facing = PI / 2
	game.player.rig.action = null
	game.player.rig.off_action = null
	if class_id == "warden":
		game.inventory.equipment.mainHand = {"id":"oak_club","count":1}
		game.inventory.equipment.offHand = {"id":"ironwood_club","count":1}
	game.inventory._equipment_changed()
	for cooldown in game.player.cooldowns:
		game.player.cooldowns[cooldown] = 0.0
	for bar in game.resources.bars:
		game.resources.add(bar.id, bar.max)
	game.resources.mana = game.resources.max_mana
	game.resources.since_combat = INF
	game.resources.engaged = false
	game.action_bar.reset()
	if not game.action_bar.slots.has(ability):
		game.action_bar.place(ability, 0)
	if ability == "lightsHammer":
		game.spells.reprisal = game.spells.reprisal_cap
	foe.position = game.player.position + Vector3(2.0,0,0)
	foe.max_health = 10000
	foe.health = 10000
	foe.dead = false
	foe.state = "idle"
	foe.rig.revive()
	foe.group.visible = true
	if foe.group.get_parent() == null:
		game.world.group.add_child(foe.group)
	foe._sync()
	game.raw_aim = foe.position

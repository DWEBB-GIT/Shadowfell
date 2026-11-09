extends SceneTree
## Normal renderer, camera and scene. Isolated capture character.
const SPOTS := [
	["thornford",-450.0,-203.0,9.0],
	["orchard",-354.0,-266.0,10.0],
	["mourning-hollow",-327.0,-422.0,19.0],
	["lantern-crossing",-244.0,-133.0,17.0],
	["mossreed",-551.0,-94.0,19.5],
	["lamplighters-rest",-343.0,-101.0,20.0],
	["blackpick",-274.0,-255.0,15.0],
]
var game
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING,"new")
	Store.dir="user://intro_shots_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made: Dictionary=game.roster.create("Journey","warden")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:
		await process_frame
	game.save.autosave_enabled=false
	for enemy in game.enemies.list:
		enemy.cfg.detection=0
		enemy.calm=1000
	var out: String=OS.get_cmdline_user_args()[0]
	for spot in SPOTS:
		if OS.get_cmdline_user_args().size()>1 and spot[0] not in OS.get_cmdline_user_args().slice(1):
			continue
		game.player.place_at(spot[1],spot[2])
		game.world_state.hour=spot[3]
		game._snap_camera()
		for i in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("intro-%s.png" % spot[0]))
		print("CAPTURE ",spot[0])
	game.queue_free()
	await process_frame
	quit()

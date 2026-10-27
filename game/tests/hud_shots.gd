extends SceneTree
## Pictures of the unit frames, objectives, log and a house fading:
##   BEHIND=3.5 godot --path . --script res://game/tests/hud_shots.gd -- out_dir x z [class]
## (x z: a house's middle; BEHIND: metres past it, away from the camera)

var frames := 0
var game


func _initialize() -> void:
	Store.dir = "user://shot_store2"
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _process(_delta: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		var r = game.roster.create("Shot", args[3] if args.size() > 3 else "rogue")
		game.enter_world(r.character.id)
		game.player.place_at(float(args[1]), float(args[2]))
		game._snap_camera()
	if frames == 5:
		# stand just behind the house nearest the spot, as the camera sees it
		var off: Vector3 = game.camera.global_position - game.player.position
		off.y = 0
		off = off.normalized()
		game.player.place_at(float(args[1]) - off.x * float(OS.get_environment("BEHIND")), float(args[2]) - off.z * float(OS.get_environment("BEHIND")))
		game._snap_camera()
	if frames == 20:
		game.resources.add("combo", 3)
		for t in ["You hear the smithy's hammer ring.", "The Fallen Road. Somewhere ahead lies the old watch post.", "You loot 3 copper."]:
			game.hud.log_line(t)
		var best = null
		for e in game.enemies.list:
			if e.alive and (best == null or e.position.distance_to(game.player.position) < best.position.distance_to(game.player.position)):
				best = e
		if best and best.position.distance_to(game.player.position) < 60:
			game.targeting.select(best)
		else:
			var npc = null
			for n in game.npcs.all:
				if npc == null or n.position.distance_to(game.player.position) < npc.position.distance_to(game.player.position):
					npc = n
			game.targeting.select_friendly(npc)
		print("combo ", game.resources.amount("combo"))
	if frames == 85:
		game.resources.since_hit = 0.0 # points fade a while after your last hit
		game.resources.add("combo", 3)
	if frames == 90:
		root.get_texture().get_image().save_png(args[0] + "/shot.png")
		quit()
	return false

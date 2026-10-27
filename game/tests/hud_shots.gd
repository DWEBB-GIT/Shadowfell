extends SceneTree
## Pictures of the unit frames, objectives, log and a house fading:
##   BEHIND=3.5 godot --path . --script res://game/tests/hud_shots.gd -- out_dir x z [class]
## (x z: a house's middle; BEHIND: metres past it, away from the camera)
## DEMO=1 also fills the party frames, the log tabs, a cast on you and your
## target, and the level-up banner.

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
		if best and OS.get_environment("DEMO") != "": # stand near it to see its cast
			game.player.place_at(best.position.x + 6, best.position.z + 6)
			game._snap_camera()
		if best and (best.position.distance_to(game.player.position) < 60 or OS.get_environment("DEMO") != ""):
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
	if frames == 60 and OS.get_environment("DEMO") != "":
		var models := []
		for n in DB.npcs.values():
			if n.get("model") and models.size() < 2:
				models.append(n.model)
		game.hud.party.members = [
			{"name": "Brother Aldric", "level": 4, "health": 62, "max_health": 80, "mana": 40, "max_mana": 90, "model": models[0]},
			{"name": "Wren", "level": 5, "health": 18, "max_health": 96, "mana": 0, "max_mana": 0, "model": models[1]},
			{"name": "Hollis Vane", "level": 3, "health": 0, "max_health": 70, "mana": 10, "max_mana": 60},
		]
		for t in [["Bandit Cutthroat hits you for 6.", "hurt"], ["Your Lunge hits Bandit Cutthroat for 14.", "hit"], ["You loot Wolf Pelt.", "loot"]]:
			game.hud.log_line(t[0], t[1])
		game.hud.show_level_up({"level": 5, "gains": [{"label": "Strength", "from": 12, "to": 14, "diff": 2}, {"label": "Stamina", "from": 11, "to": 12, "diff": 1}, {"label": "Health", "from": 120, "to": 138, "diff": 18}]})
	if frames == 88 and OS.get_environment("DEMO") != "":
		var id = DB.spells.keys()[0]
		for k in DB.spells:
			if DB.spells[k].get("kind") == "cast":
				id = k
				break
		game.player.casting = {"id": id, "spell": DB.spells[id], "t": 0.9, "total": 1.8, "target": null, "pushbacks": 0, "channel": false, "next": 0.0}
		if game.hud.shown_target != null:
			game.hud.shown_target.casting = {"kind": "demo", "label": "Crushing Blow", "telegraph": {"t": 1.1, "duration": 2.0}, "interruptible": true}
	if frames == 90:
		root.get_texture().get_image().save_png(args[0] + "/shot.png")
		quit()
	return false

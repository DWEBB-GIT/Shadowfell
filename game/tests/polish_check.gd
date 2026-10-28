extends SceneTree
## Chat window, tracker, loot beams, full bags and Blocked words:
##   godot --path . --script res://game/tests/polish_check.gd -- [shot.png]
## (headless runs the checks; with a display it also saves a picture)

var frames := 0
var game
var bad := 0


func _initialize() -> void:
	Store.dir = "user://polish_store"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func check(ok: bool, what: String) -> void:
	print("ok   " if ok else "FAIL ", what)
	if not ok:
		bad += 1


func _process(_delta: float) -> bool:
	frames += 1
	var hud = game.hud if game else null
	if frames == 3:
		var r = game.roster.create("Polish", "warrior")
		game.enter_world(r.character.id)
		game.player.place_at(-612, 440)
		game._snap_camera()
	if frames == 20:
		check(Quests.MAX_TRACKED == 10, "up to 10 quests tracked")
		for i in 30:
			hud.log_line("Line %d of the chat, to scroll back through." % i, "hit" if i % 2 else "")
		check(hud.log_box.get_child_count() >= 30, "the chat keeps more than a screenful")
		check(hud.log_box.get_parent() == hud.log_scroll, "the chat scrolls")
		# a green sword on the ground has a beam, a white one does not
		var green = game.loot.drop_at({"id": "watchmans_edge", "count": 1}, game.player.position + Vector3(2, 0, 1))
		var white = game.loot.drop_at({"id": "worn_longsword", "count": 1}, game.player.position + Vector3(-2, 0, 1))
		check(green.get("beam") != null, "a green drop rises in light")
		check(white.get("beam") == null, "a white drop does not")
		# full bags: no vein swung at, no herb picked
		while game.inventory.free_slots() > 0:
			game.inventory.add_item("worn_longsword", 1, true)
		var vein = null
		for o in game.mining.outcrops:
			if o.rock != "":
				vein = o
				break
		if vein:
			check(game.mining.bags_full(vein), "a full bag is seen as full")
			check(not game.mining.start(vein), "no mining with full bags")
		# Blocked over you, and over an enemy
		var before: int = hud.numbers.items.size()
		game.events.emit("damageNumber", {"target": game.player, "kind": "taken", "text": "Blocked"})
		game.events.emit("damageNumber", {"target": game.player, "kind": "dealt", "amount": 7, "blocked": 3})
		check(hud.numbers.items.size() == before + 3, "Blocked shows as words beside the number")
		check(hud.numbers.items[-2].label.text == "Blocked", "the word reads Blocked")
	if frames == 60:
		var args := OS.get_cmdline_user_args()
		if args.size() > 0 and DisplayServer.get_name() != "headless":
			root.warp_mouse(Vector2(120, 700))
			root.get_texture().get_image().save_png(args[0])
		print("polish check: %d failed" % bad)
		quit(1 if bad else 0)
	return false

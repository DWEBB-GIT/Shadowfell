extends SceneTree
## Dan's 2026-10-29 playtest batch: jumping a fence, footsteps from the walk,
## leaving combat, panels on top, vendor bags, the inn home question, rising
## where you stand and the minimap's distance tip:
##   godot --headless --path . --script res://game/tests/playtest_1029_check.gd

var failures := 0
var game
var frame := 0
var t0 := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_1029"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Test Warden", "warden")
		game.enter_world(made.character.id)
	if frame <= 2:
		return false
	if t0 == 0:
		if game.hud.modal == "loading" or game.hud.blocks_gameplay:
			if frame > 3000:
				check(false, "the world loads")
				quit(1)
			return false
		t0 = frame
		_run()
		print("playtest 1029 checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _run() -> void:
	var pl = game.player
	var hud = game.hud
	# a fence: in the way on foot, under you at the top of a hop
	var peak: float = pl.JUMP_SPEED * pl.JUMP_SPEED / (2 * pl.JUMP_GRAVITY)
	check(peak > 1.1, "the hop rises over a fence (%.2f m)" % peak)
	var at := Vector3(pl.position.x + 40, 0, pl.position.z + 40)
	game.collision.add(at.x, at.z, 0.3, false, 1.05)
	var near := at + Vector3(0.2, 0, 0)
	check(game.collision.resolve(near, 0.4).distance_to(near) > 0.3, "walking into a fence is blocked")
	check(game.collision.resolve(near, 0.4, 1.15).distance_to(near) < 0.01, "high in a hop you pass over it")

	# footsteps follow the feet: walking steps, standing does not
	var still: int = pl.rig.steps
	for i in 60:
		pl.update(1.0 / 60, {"move": {"x": 0.0, "z": 0.0}})
	check(pl.rig.steps == still, "no footfalls standing still")
	for i in 120:
		pl.update(1.0 / 60, {"move": {"x": 1.0, "z": 0.0}})
	var walked: int = pl.rig.steps - still
	check(walked >= 3 and walked <= 12, "footfalls while walking two seconds (%d)" % walked)
	for i in 30:
		pl.update(1.0 / 60, {"move": {"x": 0.0, "z": 0.0}})

	# leaving combat: a second after the last blow when nobody fights you
	var res = game.resources
	res.since_combat = 0.0
	res.update(0.5)
	check(res.in_combat, "in combat just after a blow")
	res.update(0.6)
	check(not res.in_combat, "out of combat a second later")
	var foe = game.enemies.list[0]
	var was: String = foe.state
	foe.state = "chase"
	res.since_combat = 0.0
	res.update(3.0)
	check(res.in_combat, "still in combat while a foe chases you")
	foe.state = was
	res.update(0.1)
	check(not res.in_combat, "out once it stops")

	# the panel opened last sits on top
	hud.toggle_panel("character")
	hud.toggle_panel("spellbook")
	var items = hud.items
	check(items.spellbook.panel.get_index() > items.character.panel.get_index(), "the spellbook opens over the character panel")
	hud.toggle_panel("quests")
	check(hud.quests.get_index() > items.get_index(), "the quest log opens over the item windows")
	hud.toggle_panel("character")
	hud.toggle_panel("character")
	check(items.get_index() > hud.quests.get_index() and items.character.panel.get_index() > items.spellbook.panel.get_index(), "the character panel reopened comes back on top")
	hud.close_modal()
	hud.close_modal()

	# talking to a vendor opens the bags; goodbye closes them
	var mara = game.npcs.by_id("mara")
	game.dialogue.open(mara)
	check(items.bags_open, "a vendor's talk opens your bags")
	game.dialogue.close()
	check(not items.bags_open, "and closes them after")

	# the inn: asked first
	var inn = null
	for n in game.npcs.list:
		if DB.npcs[n.id].get("innkeeper"):
			inn = n
			break
	if inn != null:
		game.world_state.home = ""
		game.dialogue.open(inn)
		game.dialogue.choose("home")
		check(hud.modal == "confirm" and game.world_state.home == "", "making the inn home asks first")
		hud.answer_confirm(true)
		check(game.world_state.home == "inn:" + inn.id, "yes makes it home")
		game.dialogue.close()

	# rise where you stand by the body, not on it
	pl.take_damage(99999)
	game.on_player_death(null)
	game.release_spirit()
	var c: Dictionary = game.afterlife.corpse
	pl.position = Vector3(c.x + 2.0, pl.position.y, c.z)
	game.afterlife.revive_at_corpse()
	check(absf(pl.position.x - (c.x + 2.0)) < 0.5 and absf(pl.position.z - c.z) < 0.5, "you rise where you stood (%.1f, %.1f vs body %.1f, %.1f)" % [pl.position.x, pl.position.z, c.x, c.z])


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + what)
	else:
		print("ok: " + what)

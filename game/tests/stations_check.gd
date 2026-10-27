extends SceneTree
## Every profession station, signpost and examine point, used for real:
## stand there, take its interaction, open the window, make each recipe.
##   godot --headless --path . --script res://game/tests/stations_check.gd

var game
var frame := 0
var failures := 0
var queue: Array = []
var wait := 0
var made := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var who: Dictionary = game.roster.create("Station Tester", "warden")
		game.enter_world(who.character.id)
	elif frame == 3:
		game.inventory.add_coins(100000)
		for s in DB.skills.values():
			game.skills.learn(s.id)
		for r in DB.recipes.values():
			game.cooking.learned[r.id] = true
		# a swing with nothing selected falls on whoever is in front (no crash)
		game.targeting.current = null
		game.combat.resolve_player_strike(null)
		_plan()
	elif wait > 0:
		wait -= 1
	elif not queue.is_empty():
		var step: Callable = queue.pop_front()
		step.call()
	else:
		check(made > 0, "some recipe was made")
		print("stations check: %d recipes made, %s" % [made, "all passed" if failures == 0 else "%d failed" % failures])
		quit(1 if failures else 0)
	return false


func _plan() -> void:
	for st in Layout.stations:
		queue.append(func(): _station(st))
	for sp in Layout.signposts:
		queue.append(func(): _go(sp.position[0], sp.position[1]); _run("sign:" + sp.id); check(game.hud.sign_card.visible, "signpost %s opens its card" % sp.id))
	for p in game.world.examine_points:
		queue.append(func(): _go(p.x, p.z); _run("examine:" + p.id); _run("examine:" + p.id); _run("examine:" + p.id))


func _go(x: float, z: float) -> void:
	game.player.position = Vector3(x, Terrain.height_at(x, z), z)
	game.player.moving = false
	wait = 2


func _run(key: String) -> bool:
	for c in game.interaction._candidates():
		if c.key == key:
			c.run.call()
			return true
	check(false, "interaction %s is offered" % key)
	return false


func _station(st: Dictionary) -> void:
	_go(st.position[0], st.position[1])
	if not _run("station:" + st.id):
		return
	var sk: String = game.hud.items.craft_skill
	queue.push_front(func():
		check(game.hud.items.open.cooking, "%s opens the %s window" % [st.id, sk])
		for r in game.cooking.known(sk):
			if r.get("station", "fire") != st.kind or game.cooking.rank(sk) < r.rank:
				continue
			for x in r.inputs:
				game.inventory.add_item(x.item, x.count, true)
			var ok: bool = game.cooking.start(r.id, 1)
			check(ok, "%s: %s starts (%s)" % [st.id, r.id, game.cooking.blocked(r)])
			if ok:
				game.cooking.update(999.0)
				check(game.cooking.crafting == null, "%s: %s finishes" % [st.id, r.id])
				made += 1
		game.hud.items.open.cooking = false
		wait = 2)


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

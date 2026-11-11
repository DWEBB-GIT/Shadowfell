extends SceneTree
## Town life (Dan 2026-11-11): the background folk from the town_life
## overlay are in the world with their own ids and names, keep their hours
## (regulars at the inn, shoppers round the shop fronts), travellers walk
## their road and rest at the ends, a pedlar sells from a pack, bodies are
## only built near the player, and none of them crowd the minimap.
##   godot --headless --path . --script res://game/tests/town_life_check.gd

var game
var frame := 0
var failures := 0


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
		var who: Dictionary = game.roster.create("Lively", "warden")
		game.enter_world(who.character.id)
	elif frame == 4:
		_people()
		_bodies()
		_drinker()
		_shopper()
		_walker()
		_pedlar()
		_door()
		print("town_life_check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _life() -> Array:
	return game.npcs.all.filter(func(n): return n.def.get("ambient"))


func _people() -> void:
	var life := _life()
	var ids := {}
	var names := {}
	for n in life:
		ids[n.id] = true
		names[n.name] = true
	check(life.size() >= 40, "the towns have background folk (%d)" % life.size())
	check(ids.size() == life.size() and names.size() == life.size(), "each has their own id and name")
	check(life.all(func(n): return DB.npcs.has(n.id) and DB.npcs[n.id].name == n.name), "each is found by id (DB.npcs)")
	for kind in ["life_drinker", "life_shopper", "life_traveller", "life_pedlar"]:
		check(life.any(func(n): return n.id.begins_with(kind + "_")), "some %s" % kind)
	var marks: Array = game.hud.minimap.markers()
	if not marks.is_empty():
		check(not marks.any(func(m): return m.get("kind") == "npc" and life.any(func(n): return n.name == m.get("label"))), "background folk are left off the minimap")


func _bodies() -> void:
	game.npcs.update(0.016)
	var life := _life()
	var far: Array = life.filter(func(n): return n.position.distance_to(game.player.position) > WorldStream.VIEW_OUT + 20)
	check(far.size() > 0 and far.all(func(n): return n.model == null), "no body is built for folk far away (%d)" % far.size())
	var n = far[0]
	game.player.position = Vector3(n.position.x + 2, game.player.position.y, n.position.z)
	game.npcs.update(0.016)
	check(n.model != null and n.group.get_parent() != null, "a body is built when you come near")


func _find(prefix: String, test: Callable):
	for n in _life():
		if n.id.begins_with(prefix) and test.call(n):
			return n
	return null


func _drinker() -> void:
	var n = _find("life_drinker_", func(c): return c.places.has("inn"))
	check(n != null, "an inn regular has an inn to sit in")
	if n == null:
		return
	check(n.place_at(13.0 + n.shift) == "inn", "a regular is at the inn of an afternoon")


func _shopper() -> void:
	var n = _find("life_shopper_", func(c): return c.places.has("stall_1"))
	check(n != null, "a shopper has shop fronts to visit")
	if n == null:
		return
	var stalls := {}
	for h in range(7, 21):
		var p: String = n.place_at(float(h) + 0.25 + n.shift)
		if p.begins_with("stall_"):
			stalls[p] = true
	check(stalls.size() >= 2, "a shopper goes round more than one shop in a day (%s)" % ", ".join(stalls.keys()))
	check(n.place_at(23.0 + n.shift) in ["home", "work"], "and goes home at night")


func _walker() -> void:
	var ws = game.world_state
	ws.hour = 10.0
	var n = _find("life_traveller_", func(c): return c.path.size() >= 2)
	check(n != null, "a traveller has a road")
	if n == null:
		return
	n.linger = 0.0
	var start: Vector3 = n.position
	for i in 60:
		game.npcs.update(0.1)
	var moved: float = Vector2(n.position.x - start.x, n.position.z - start.z).length()
	check(moved > 5.0, "a traveller walks their road, drawn or not (%.1f m in 6 s)" % moved)
	# to the end of the road: they rest there before turning back
	var end_i: int = n.path.size() - 1 if n.path_dir > 0 else 0
	var end: Vector2 = n.path[end_i]
	var reached := false
	for i in 20000:
		game.npcs.update(0.1)
		if n.linger > 0.0:
			reached = true
			break
	check(reached and Vector2(n.position.x, n.position.z).distance_to(end) < 0.5, "they reach the end of the road and rest")
	var rest_at: Vector3 = n.position
	game.npcs.update(1.0)
	check(n.position.distance_to(rest_at) < 0.01, "standing still while they rest")
	# a rest ending after dark waits for morning
	ws.hour = 22.0
	n.linger = 0.05
	game.npcs.update(0.1)
	check(n.linger > 0.0, "no setting out after dark")
	ws.hour = 7.0
	n.linger = 0.05
	game.npcs.update(0.1)
	game.npcs.update(0.5)
	check(n.position.distance_to(rest_at) > 0.2, "and back along the road in the morning")


func _pedlar() -> void:
	var n = _find("life_pedlar_", func(c): return c.path.size() >= 2)
	check(n != null, "a pedlar walks a road")
	if n == null:
		return
	check(DB.npcs[n.id].get("shop") == "pedlar_pack", "a pedlar sells from a pack")
	game.player.position = n.position
	game.npcs.talk(n)
	var page = game.dialogue.page
	check(page != null and page.options.any(func(o): return o.id == "shop"), "talking to a pedlar offers their goods")
	var before: Vector3 = n.position
	n.linger = 0.0
	game.npcs.update(0.5)
	check(n.position.distance_to(before) < 0.01, "a pedlar stops while you talk")
	game.dialogue.close()


func _door() -> void:
	for b in Layout.buildings:
		if b.get("rest") and b.get("walls") is Array:
			var d: Array = Npcs.inn_door(b)
			check(d[0].x < -float(b.size[0]) * 0.5 and absf(d[0].y) < 1.0, "an inn is walked into by its west door (%s)" % b.id)
			return


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL: " + what)

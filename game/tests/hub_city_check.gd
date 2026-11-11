extends SceneTree
## The test hub city (tools/world/new_map/hub_city.py, map.json overlays):
##   godot --headless --path . --script res://game/tests/hub_city_check.gd
##   xvfb-run godot --path . --script res://game/tests/hub_city_check.gd -- out_dir   (also saves pictures)
## Its placements load on top of the new map's own, the streets are open,
## the fountain and river are water, the waystones carry you there and back,
## and a training dummy's meter counts blows. Exits 1 on failure.

const CENTRE := Vector2(-180, -656)
var failures := 0
var frames := 0
var game
var out := ""
var shots := []
var shot := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	Store.dir = "user://hub_city_check"
	DirAccess.make_dir_recursive_absolute(Store.dir)
	for f in DirAccess.get_files_at(Store.dir):
		DirAccess.remove_absolute(Store.dir + "/" + f)
	out = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)


func _w(u: float, v: float) -> Vector2:
	var k := sqrt(0.5)
	return CENTRE + Vector2(k * (u - v), k * (u + v))


func _data_checks() -> void:
	check(Layout.houses.filter(func(h): return h.id.begins_with("hub_")).size() >= 25, "the hub's houses are placed")
	check(Layout.houses.any(func(h): return h.id == "tf_smithy"), "the hand-placed houses are still there")
	check(Layout.town_walls.any(func(t): return t.get("style") == "stone"), "the city has stone walls")
	check(Layout.gates.any(func(g): return g.get("kind") == "city_gate"), "the Grand Gate is a city gate")
	check(Layout.stations.filter(func(s): return s.kind == "waystone").size() == 2, "two waystones")
	check(Terrain.walkable(_w(0, 12).x, _w(0, 12).y), "Crown Square is open ground")
	check(Terrain.water_at(_w(0, 0).x, _w(0, 0).y) != null, "the fountain is water")
	check(Terrain.water_at(_w(97.5, 0).x, _w(97.5, 0).y) != null, "the river runs outside the south-east wall")
	check(Terrain.walkable(_w(27.5, 9).x, _w(27.5, 9).y), "the street crosses the canal on a bridge")
	check(absf(Terrain.height_at(_w(60, 60).x, _w(60, 60).y) - Terrain.height_at(_w(-60, -60).x, _w(-60, -60).y)) < 0.3, "the city stands on flat ground")
	check(DB.npcs.has("hub_smith") and DB.npcs.hub_smith.get("forge"), "the city smith reforges and punches sockets")
	check(DB.enemies.has("training_dummy_40") and DB.enemies.training_dummy_armoured.dummy, "the dummy rows")


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		var r = game.roster.create("Hub", "warrior")
		game.enter_world(r.character.id)
	if frames == 8:
		_data_checks()
		var stone = Layout.station("hub_waystone_start")
		check(game.travel_to(stone.to[0], stone.to[1], stone.get("toFacing"), "Travelling…"), "the start's waystone carries you")
		check(Vector2(game.player.position.x, game.player.position.z).distance_to(CENTRE) < 120, "you arrive inside the city")
	if frames == 120:
		var dummy = null
		for e in game.enemies.list:
			if e.cfg.get("dummy", false) and Vector2(e.position.x, e.position.z).distance_to(CENTRE) < 130:
				dummy = e
		check(dummy != null, "the yard's dummies stand in the city")
		if dummy:
			game.events.emit("damageNumber", {"target": dummy, "amount": 40, "crit": true, "kind": "dealt"})
			game.events.emit("damageNumber", {"target": dummy, "amount": 0, "kind": "miss"})
			var m = game.dummy_meter.meters.get(dummy)
			check(m != null and m.hits == 1 and m.crits == 1 and m.misses == 1 and m.total == 40.0, "the dummy's meter counts hits, crits and misses")
		if out == "":
			return _finish()
		shots = [["square", _w(0, 10)], ["wall", _w(-60, 76)], ["gate", _w(0, 66)], ["yard", _w(50, 50)], ["artisans", _w(-55, 0)], ["cathedral", _w(-55, -40)], ["guilds", _w(0, -55)], ["market", _w(50, 3)], ["docks", _w(62, -55)], ["lane", _w(-55, 55)]]
	if out != "" and frames > 120:
		var k := frames - 121
		if shot < shots.size():
			if k % 90 == 0:
				var p: Vector2 = shots[shot][1]
				game.player.place_at(p.x, p.y)
				game.zoom = game._zoom_max()
				game._snap_camera()
			elif k % 90 == 80:
				root.get_texture().get_image().save_png(out.path_join("hub-%s.png" % shots[shot][0]))
				print("saved ", shots[shot][0])
				shot += 1
		else:
			return _finish()
	return false


func _finish() -> bool:
	print("hub_city_check: %s" % ("ok" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)
	return true

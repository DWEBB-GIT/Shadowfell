extends SceneTree
## The explorable world (Terrain, Land, WorldMap, Discovery):
##   godot --headless --path . --script res://game/tests/world_check.gd
## Tiles unpack only where asked, high ground blocks and slides, regions and
## subzones name the right places, chunks build within a frame's budget, a
## boat sails and discoveries are saved. Exits 1 if anything fails.

var failures := 0
var game
var frame := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	DB.ensure()
	var off := WorldMap.offset
	check(Terrain.tiles_loaded() < 400, "only some tiles are unpacked at start (%d)" % Terrain.tiles_loaded())
	var wreck := Vector2(205, 314) + off
	check(Terrain.walk_at(wreck.x, wreck.y) >= 0.5, "the Last Cart is open ground")
	check(DB.region_at(wreck.x, wreck.y).id == "bracken_vale", "the Last Cart is in Bracken Vale (%s)" % DB.region_at(wreck.x, wreck.y).id)
	check(WorldMap.subzone_at(wreck.x, wreck.y) == "The Last Cart", "the wreck's valley is named")
	var town: Array = DB.world.regions[0].town
	check(DB.region_at(town[0], town[1]).id == "brackenford", "Brackenford is its own region")
	check(DB.region_at(700, 900).id == "kingsfold", "the Kingsfold is a zone (%s)" % DB.region_at(700, 900).id)
	check(Terrain.height_at(-2500, 3800) < 0, "the far corner is sea")
	check(Terrain.walk_at(-2500, 3800) < 0.5, "the sea cannot be walked")
	# walking into high ground slides back onto open ground
	var col := Collision.new()
	var blocked := Vector3.ZERO
	for r in range(10, 120, 2):
		var p := Vector2(wreck.x + r, wreck.y - r)
		if Terrain.walk_at(p.x, p.y) < 0.2:
			blocked = Vector3(p.x, 0, p.y)
			break
	check(blocked != Vector3.ZERO, "high ground near the wreck")
	var out := col.resolve(blocked, 0.4)
	check(Terrain.walk_at(out.x, out.z) >= 0.45, "a mover is pushed off high ground (%.2f)" % Terrain.walk_at(out.x, out.z))
	check(WorldMap.pois.size() > 90, "POIs from Act 1 and the world (%d)" % WorldMap.pois.size())
	check(not DB.examine_text("poi:wreck").is_empty(), "a POI has its story note")
	# chunk cost
	var t0 := Time.get_ticks_usec()
	for i in 4:
		Land.chunk_ground(Vector2i(floori(wreck.x / 64.0) + i, floori(wreck.y / 64.0)), null)
		Land.chunk_trees(Vector2i(floori(wreck.x / 64.0) + i, floori(wreck.y / 64.0)))
	var ms := (Time.get_ticks_usec() - t0) / 4000.0
	print("chunk ground + trees: %.1f ms" % ms)
	check(ms < 30, "a chunk builds in under 30 ms (%.1f)" % ms)


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://world_check_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 3:
		var r = game.roster.create("Walker", "warden")
		game.enter_world(r.character.id)
	elif frame == 10:
		var start: Array = DB.world.playerStart.position
		check(game.player.position.distance_to(Vector3(start[0], game.player.position.y, start[1])) < 1.0, "a new character starts at the Last Cart")
		check(game.world.land.chunks.size() > 4, "chunks are built round the player (%d)" % game.world.land.chunks.size())
		check(game.discovery.docks.size() >= 2, "boat jetties (%d)" % game.discovery.docks.size())
		# a boat crossing
		var d: Dictionary = game.discovery.docks[0]
		game.player.place_at(d.at.x, d.at.y)
		game.discovery.sail(d)
		check(Vector2(game.player.position.x, game.player.position.z).distance_to(d.to) < 1.0, "the boat lands at the far jetty")
		var p := WorldMap.poi("brackenford")
		game.player.place_at(p.at[0], p.at[1])
	elif frame == 90:
		check(game.discovery.is_discovered("brackenford"), "walking into Brackenford discovers it")
		check(game.region.get("id", "") == "brackenford", "the region is Brackenford (%s)" % game.region.get("id", ""))
		var saved: Dictionary = game.save.serialize()
		check(saved.world.discovered.has("brackenford"), "discoveries are saved")
		check(saved.get("map") == SaveManager.MAP_VERSION, "saves record the map")
		# an old save (the 72 m strip) starts again at the Last Cart
		saved.erase("map")
		saved.player.position = {"x": -6, "z": 33}
		game.save.apply(saved)
		var start: Array = DB.world.playerStart.position
		check(Vector2(game.player.position.x, game.player.position.z).distance_to(Vector2(start[0], start[1])) < 1.0, "an old save is moved to the Last Cart")
		print("world_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
		quit(1 if failures else 0)
	return false

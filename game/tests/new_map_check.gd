extends SceneTree
## Dan's new map (data/terrain/new_map, 2026-10-28):
##   godot --headless --path . --script res://game/tests/new_map_check.gd
## With shadowfell/world/map = "new" the ground comes from the new map, with
## nothing from the old world on it; the start stands on open ground; the
## brushes work on it and their layer is the new map's own. Writes nothing to
## the project. Exits 1 on failure.

const Sculpt := preload("res://addons/shadowfell_world/sculpt.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	DB.ensure()
	check(Terrain.is_new_map(), "the setting picks the new map")
	check(Terrain.dir == "res://data/terrain/new_map/", "its folder")
	check(Sculpt.path() == "res://data/terrain/new_map/sculpt.json", "the brushes' layer is the new map's")
	check(Layout.npcs.is_empty() and Layout.enemies.is_empty() and Layout.props.is_empty() and Layout.houses.is_empty(), "nothing from the old world is placed")
	check(WorldMap.pois.is_empty() and Terrain.roads().is_empty(), "no old roads or places")
	var st: Array = Layout.player_start.position
	var p := Vector2(st[0], st[1])
	check(Terrain.walkable(p.x, p.y), "the start (%s) is open ground" % p)
	check(Terrain.height_at(p.x, p.y) > 0.5, "the start is above the sea")
	check(Terrain.ground_colour(p.x, p.y) != null, "the ground has Dan's colours")
	check(Land.chunk_trees(Vector2i(4, -3)).is_empty(), "no trees are scattered (Dan places them)")
	# the brushes
	var h0 := Terrain.base_height(p.x, p.y)
	var far := Terrain.base_height(p.x + 30, p.y)
	var s = Sculpt.new()
	s.begin_stroke()
	s.apply(Sculpt.RAISE, p.x, p.y, 12, 1.0, 0.5)
	check(Terrain.base_height(p.x, p.y) > h0 + 2.0, "raise lifts the ground (%.2f -> %.2f)" % [h0, Terrain.base_height(p.x, p.y)])
	check(absf(Terrain.base_height(p.x + 30, p.y) - far) < 0.001, "outside the brush is untouched")
	var states: Array = s.end_stroke()
	check(s.dirty, "edits are waiting to be saved")
	# saving packs the edit into a copy of world.bin that reads back the same
	var raised := Terrain.base_height(p.x, p.y)
	check(Terrain.save_tiles(s._dirty, "user://world.bin") == OK, "the edited tiles save")
	s.restore(states[0])
	check(absf(Terrain.base_height(p.x, p.y) - h0) < 0.01, "undo puts it back")
	Terrain.dir = "user://"
	Terrain.reload_tiles()
	check(absf(Terrain.base_height(p.x, p.y) - raised) < 0.06, "the saved file has the raised ground")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://world.bin"))
	Terrain.dir = Terrain.MAPS.new
	Terrain.reload_tiles()
	check(absf(Terrain.base_height(p.x, p.y) - h0) < 0.01, "the map on disk is unchanged")
	# the whole map's ground, as the World editor draws it
	var b: Dictionary = DB.world.bounds
	var t0 := Time.get_ticks_msec()
	var mat := Land.ground_material()
	var n := 0
	for i in range(floori(b.minX / Land.CHUNK), ceili(b.maxX / Land.CHUNK), 4):
		for j in range(floori(b.minZ / Land.CHUNK), ceili(b.maxZ / Land.CHUNK), 4):
			Land.chunk_ground(Vector2i(i, j), mat).free()
			n += 1
	print("new_map_check: %d chunks in %d ms (%.1f ms each)" % [n, Time.get_ticks_msec() - t0, (Time.get_ticks_msec() - t0) / float(n)])
	# the World editor opens just the ground, and saving untouched writes nothing
	var ed = load("res://addons/shadowfell_data/world_editor.tscn").instantiate()
	root.add_child(ed)
	ed.rebuild()
	check(ed._chunks.size() == 32 * 48, "the World editor draws the whole map (%d chunks)" % ed._chunks.size())
	check(ed.get_node_or_null("NPCs") == null, "and nothing placed on it")
	check(ed.save_world().is_empty(), "saving with no edits writes nothing")
	ed.free()
	print("new_map_check: %s" % ("ok" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)

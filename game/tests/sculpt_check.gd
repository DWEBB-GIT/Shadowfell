extends SceneTree
## The World editor's sculpt brushes (addons/shadowfell_world/sculpt.gd):
##   godot --headless --path . --script res://game/tests/sculpt_check.gd
## Brushes change the ground at once, undo puts it back, and a tile packs
## back into world.bin's format unchanged. Writes nothing. Exits 1 on failure.

const Sculpt := preload("res://addons/shadowfell_world/sculpt.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	DB.ensure()
	var p := Vector2(205, 314) + WorldMap.offset
	var h0 := Terrain.base_height(p.x, p.y)
	var w0 := Terrain.walk_at(p.x, p.y)
	var far := Terrain.base_height(p.x + 30, p.y)
	var s = Sculpt.new()
	s.begin_stroke()
	s.apply(Sculpt.RAISE, p.x, p.y, 12, 1.0, 0.5)
	check(Terrain.base_height(p.x, p.y) > h0 + 2.0, "raise lifts the ground (%.2f -> %.2f)" % [h0, Terrain.base_height(p.x, p.y)])
	check(absf(Terrain.base_height(p.x + 30, p.y) - far) < 0.001, "outside the brush is untouched")
	var chunks: Dictionary = s.apply(Sculpt.BLOCK, p.x, p.y, 8, 1.0, 0.1)
	check(Terrain.walk_at(p.x, p.y) < 0.5, "the blocked brush closes the ground")
	check(chunks.has(Vector2i(floori(p.x / Land.CHUNK), floori(p.y / Land.CHUNK))), "the chunk under the brush is redrawn")
	var top := Terrain.base_height(p.x, p.y)
	s.begin_stroke()
	s.apply(Sculpt.FLATTEN, p.x, p.y, 12, 1.0, 1.0, h0)
	check(absf(Terrain.base_height(p.x, p.y) - h0) < absf(top - h0) * 0.5, "flatten pulls towards its height")
	s.end_stroke()
	s.begin_stroke()
	s.apply(Sculpt.PAINT, p.x, p.y, 8, 1.0, 0.1, 0.0, Terrain.SAND)
	check(Terrain.surface_at(p.x, p.y) == Terrain.SAND, "paint sets the surface")
	var states: Array = s.end_stroke()
	s.restore(states[0])
	check(Terrain.surface_at(p.x, p.y) != Terrain.SAND, "undo puts the surface back")
	check(s.dirty, "edits are waiting to be saved")
	# a tile packs back to exactly what the bake wrote
	Terrain.reload_tiles()
	var i := floori((p.x - Terrain.grid_origin().x) / 128.0)
	var j := floori((p.y - Terrain.grid_origin().y) / 128.0)
	var t = Terrain._tile_at(i, j)
	var raw := Terrain.stored_tile(i, j)
	check(raw.size() > 0, "the tile is land")
	check(Terrain._pack(t).decompress(33 * 33 * 4, FileAccess.COMPRESSION_DEFLATE) == raw, "a tile packs as bake_world.py packs it")
	check(absf(Terrain.base_height(p.x, p.y) - h0) < 0.01 and absf(Terrain.walk_at(p.x, p.y) - w0) < 0.01, "reload drops unsaved edits")
	print("sculpt_check: %s" % ("ok" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)

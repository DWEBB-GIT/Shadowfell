extends SceneTree
## World streaming (game/world/stream.gd): placed props are built by the
## 32 m cell near the camera as MultiMesh batches, freed far away; still
## views (herbs, veins, chests) leave the scene with their cell; enemy
## bodies join the scene by distance while their AI runs regardless.
##   godot --headless --path . --script res://game/tests/stream_check.gd
##   godot --headless --path . --script res://game/tests/stream_check.gd -- new   (Dan's new map)

var game
var frame := 0
var failures := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		if "new" in OS.get_cmdline_user_args():
			ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
		Store.dir = "user://test_store"
		DirAccess.make_dir_recursive_absolute(Store.dir)
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		var t0 := Time.get_ticks_msec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
		print("stream_check: game built in %d ms (%d props as data)" % [Time.get_ticks_msec() - t0, Layout.props.size()])
	elif frame == 2:
		var who: Dictionary = game.roster.create("Stream", "warden")
		game.enter_world(who.character.id)
	elif frame == 4:
		_props_near()
		_same_as_nodes()
		_far_away()
		_enemy_bodies()
		print("stream_check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


## every prop in a loaded cell is drawn once per mesh part, nothing far is
func _props_near() -> void:
	var st: WorldStream = game.world.stream
	var at: Vector3 = game.camera_target
	st.update(at)
	var s := st.stats()
	var want_batched := 0
	var want_nodes := 0
	var batchable := 0
	for p in Layout.props:
		var kt := WorldStream.kit(p)
		if kt.batch:
			batchable += 1
		if not st.is_loaded(p.position[0], p.position[1]):
			continue
		if kt.batch:
			want_batched += kt.parts.size()
		else:
			want_nodes += 1
	print("stream_check: %d of %d props can batch; near the start %d cells, %d prop parts in %d batches + %d nodes" % [
		batchable, Layout.props.size(), s.cells, s.batched, s.batches, s.nodes])
	check(s.cells > 0, "cells are loaded round the camera")
	check(s.batched == want_batched and s.nodes == want_nodes, "each nearby prop is drawn once (%d/%d batched parts, %d/%d nodes)" % [s.batched, want_batched, s.nodes, want_nodes])
	if Layout.props.size() > 0:
		check(batchable * 2 > Layout.props.size(), "most props batch (%d of %d)" % [batchable, Layout.props.size()])
	for k in st.loaded:
		check(WorldStream.cell_distance(k, at) <= WorldStream.KEEP, "no loaded cell past KEEP")


## a batched prop sits exactly where its node would, and measures the same
## height for the jump-over check
func _same_as_nodes() -> void:
	var tried := 0
	for p in Layout.props:
		var kt := WorldStream.kit(p)
		if not kt.batch or tried >= 40:
			continue
		tried += 1
		var obj := World.prop_instance(p)
		World.budget_prop(obj, str(p.model))
		var meshes: Array = []
		_collect(obj, obj.transform, meshes)
		var xf := WorldStream.placed(p, kt.base)
		var ok: bool = meshes.size() == kt.parts.size()
		for i in mini(meshes.size(), kt.parts.size()):
			var want: Transform3D = meshes[i][1]
			var got: Transform3D = xf * kt.parts[i].xf
			ok = ok and want.origin.distance_to(got.origin) < 0.001 and (want.basis.x - got.basis.x).length() < 0.001 \
				and (want.basis.y - got.basis.y).length() < 0.001 and (want.basis.z - got.basis.z).length() < 0.001
			ok = ok and meshes[i][0].cast_shadow == kt.parts[i].shadow
		check(ok, "%s batches where its node stands" % str(p.model).get_file())
		var h0 := World.prop_height(obj, Terrain.height_at(p.position[0], p.position[1]))
		var h1 := WorldStream.prop_height(p)
		check(absf(h0 - h1) < 0.01 or (h0 == INF and h1 == INF), "%s measures the same height (%.2f / %.2f)" % [str(p.model).get_file(), h0, h1])
		obj.free()
	if Layout.props.size() > 0:
		check(tried > 0, "some props were compared")


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	if n is MeshInstance3D and n.visible and n.mesh != null:
		out.append([n, xf])
	# same walk order as WorldStream.kit (a stack: last child first)
	var kids := n.get_children()
	kids.reverse()
	for ch in kids:
		if ch is Node3D:
			_collect(ch, xf * ch.transform, out)


## a long way off: the old cells go, their herbs/veins/chests leave the scene
func _far_away() -> void:
	var st: WorldStream = game.world.stream
	var here: Vector3 = game.camera_target
	var views_here := 0
	for o in game.mining.outcrops + game.gathering.nodes:
		if o.node.get_parent() != null:
			views_here += 1
	var far := here + Vector3(900, 0, 900)
	st.update(far)
	check(not st.is_loaded(here.x, here.z), "the old cells unload")
	check(st.is_loaded(far.x, far.z), "the new place loads at once")
	var stale := 0
	for o in game.mining.outcrops + game.gathering.nodes:
		if o.node.get_parent() != null and not st.is_loaded(o.x, o.z):
			stale += 1
	check(stale == 0, "no herb patch or vein stays in the scene in an unloaded cell")
	for c in game.chests.list:
		check(c.group.is_inside_tree() == st.is_loaded(c.x, c.z), "a chest is in the scene only with its cell")
	st.update(here)
	var back := 0
	for o in game.mining.outcrops + game.gathering.nodes:
		if o.node.get_parent() != null:
			back += 1
	check(back == views_here, "coming back puts them back (%d / %d)" % [back, views_here])
	var s := st.stats()
	check(s.cells > 0 and st.cells.size() >= s.cells, "cells reload on return")


## bodies by distance; the AI runs for a fighting enemy wherever it is
func _enemy_bodies() -> void:
	var en = game.enemies
	if en.list.is_empty():
		return
	var player = game.player
	var far = null
	var near = null
	for e in en.list:
		var d: float = e.position.distance_to(player.position)
		if d > WorldStream.VIEW_OUT + 5 and e.alive and far == null:
			far = e
		if d < WorldStream.VIEW_IN - 5 and e.alive and near == null:
			near = e
	en.update(0.016)
	if near:
		check(near.group.is_inside_tree(), "a nearby enemy is drawn")
	if far == null:
		print("stream_check: (no enemy far from the start to test)")
		return
	check(not far.group.is_inside_tree(), "a far idle enemy is not in the scene")
	far.state = "chase"
	var before: Vector3 = far.position
	en.update(0.016)
	check(far.group.is_inside_tree(), "a fighting enemy is drawn wherever it is")
	check(far.position != before or far.state != "chase", "and its AI ran")
	far.reset()
	en.update(0.016)
	print("stream_check: enemies drawn %d of %d" % [en.shown_count(), en.list.size()])


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL: " + what)

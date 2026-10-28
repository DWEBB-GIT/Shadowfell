extends SceneTree
## The frame speed-ups behave as the old code did: enemies still push
## apart, Space and clicks still find what is near, area loot still
## counts the same, NPCs and far drops are still clickable.
##   godot --headless --path . --script res://game/tests/perf_behaviour_check.gd

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
		var who: Dictionary = game.roster.create("Behaviour Tester", "warden")
		game.enter_world(who.character.id)
	elif frame == 4:
		_separation()
		_interaction_near()
		_area_loot()
		_clicks()
		print("perf behaviour check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


## no two living enemies (nor the player and one) overlap once separation
## has settled, and a lone pair is pushed exactly as push_apart says
func _separation() -> void:
	var en = game.enemies
	var living: Array = en.list.filter(func(e): return e.alive and not e.cfg.get("dummy", false))
	check(living.size() >= 6, "enough enemies to test (%d)" % living.size())
	# pile six on one spot, the player among them
	var at: Vector3 = living[0].position
	for i in 6:
		living[i].position = at + Vector3(0.05 * i, 0, 0.03 * i)
	game.player.position = at + Vector3(0.02, 0, 0.02)
	for i in 60:
		en._separate()
	var worst := 0.0
	for i in 6:
		for j in range(i + 1, 6):
			var a = living[i]
			var b = living[j]
			worst = maxf(worst, a.radius + b.radius - U.hyp(a.position.x - b.position.x, a.position.z - b.position.z))
	check(worst < 0.05, "a pile of six enemies spreads out (worst overlap %.3f m)" % worst)
	var near_player := 0.0
	for i in 6:
		var e = living[i]
		near_player = maxf(near_player, game.player.radius + e.radius - U.hyp(e.position.x - game.player.position.x, e.position.z - game.player.position.z))
	check(near_player < 0.05, "and off the player (worst overlap %.3f m)" % near_player)
	# a lone pair far from the rest: one step matches push_apart
	var a = living[0]
	var b = living[1]
	a.position = Vector3(5000, 0, 5000)
	b.position = Vector3(5000.3, 0, 5000.1)
	var want: Array = Enemies.push_apart(a.position, a.radius, b.position, b.radius, 0.5)
	en._separate()
	check(a.position.is_equal_approx(want[0]) and b.position.is_equal_approx(want[1]), "a lone pair moves as push_apart says")
	# a pair close in x but far in z is left alone
	b.position = Vector3(5000.1, 0, 5010)
	var pa: Vector3 = a.position
	en._separate()
	check(a.position == pa, "enemies far apart in z are not pushed")


## Space picks the same thing as the old full list, wherever you stand
func _interaction_near() -> void:
	var ia = game.interaction
	var spots := []
	for st in Layout.stations:
		spots.append(Vector2(st.position[0], st.position[1]))
	for sp in Layout.signposts:
		spots.append(Vector2(sp.position[0], sp.position[1]))
	for sh in Layout.shrines:
		spots.append(Vector2(sh.position[0], sh.position[1]))
	for p in game.world.examine_points:
		spots.append(Vector2(p.x, p.z))
	for n in game.npcs.list:
		spots.append(Vector2(n.position.x, n.position.z))
	var same := 0
	for s in spots:
		for off in [Vector2.ZERO, Vector2(1.5, 0), Vector2(0, -2.5)]:
			game.player.position = Vector3(s.x + off.x, Terrain.height_at(s.x + off.x, s.y + off.y), s.y + off.y)
			ia.update()
			var got = ia.current.key if ia.current else ""
			var want = _old_pick(ia)
			if got == want:
				same += 1
			else:
				check(false, "at %s Space picks %s, the full list %s" % [str(s + off), got, want])
	check(same == spots.size() * 3, "Space picks as before at %d spots" % same)


## the old update(): the nearest of every candidate in the world
func _old_pick(ia) -> String:
	var p: Vector3 = game.player.position
	var best := ""
	var best_score := INF
	for c in ia._candidates():
		var d := U.hyp(c.x - p.x, c.z - p.z)
		if d > c.get("reach", DB.CONFIG.interaction.radius):
			continue
		if game.collision.wall_between(p.x, p.z, c.x, c.z):
			continue
		if d + c.bias < best_score:
			best_score = d + c.bias
			best = c.key
	return best


## a heap of drops: the shared list counts each one's area as before, and
## Space offers "and N more nearby"
func _area_loot() -> void:
	var loot = game.loot
	var p: Vector3 = game.player.position
	var base := Vector3(p.x + 3, p.y, p.z)
	for i in 4:
		loot.drop_at({"id": "rough_stone", "count": 1}, base + Vector3(0.4 * i, 0, 0))
	var all: Array = loot.lootables()
	var ok := true
	for l in all:
		ok = ok and loot.area_count(l) == loot.area_count(l, all)
	check(ok and all.size() >= 4, "area counts match with the shared list (%d lootables)" % all.size())
	game.player.position = base
	game.interaction.update()
	var cur = game.interaction.current
	check(cur != null and cur.key.begins_with("loot:") and cur.prompt.contains("more nearby"), "Space offers the heap (%s)" % (cur.prompt if cur else "nothing"))


## a click on an NPC, and on a drop at the edge of the screen, still lands
func _clicks() -> void:
	var cam: Camera3D = game.camera
	var npc = null
	for n in game.npcs.list:
		npc = n
		break
	if npc == null:
		check(false, "an NPC to click")
		return
	game.player.place_at(npc.position.x + 4, npc.position.z + 4)
	game._snap_camera()
	var sp := cam.unproject_position(npc.position + Vector3(0, 1, 0))
	game.input.mouse.x = sp.x
	game.input.mouse.y = sp.y
	var pick = game._pick_under_cursor()
	check(pick != null and pick.kind == "npc" and is_same(pick.obj, npc), "clicking %s picks them (%s)" % [npc.cfg.get("name", "npc") if "cfg" in npc else "npc", str(pick.kind) if pick else "nothing"])
	# a drop off to the side of the screen
	var pp: Vector3 = game.player.position
	var right: Vector3 = cam.global_transform.basis.x
	var far := Vector3(pp.x + right.x * 5, 0, pp.z + right.z * 5)
	far.y = Terrain.height_at(far.x, far.z)
	game.loot.drop_at({"id": "rough_stone", "count": 1}, far)
	sp = cam.unproject_position(far + Vector3(0, 0.3, 0))
	if cam.is_position_behind(far) or not cam.get_viewport().get_visible_rect().has_point(sp):
		check(false, "the far drop is on screen to click (%s)" % str(sp))
		return
	game.input.mouse.x = sp.x
	game.input.mouse.y = sp.y
	pick = game._pick_under_cursor()
	check(pick != null and pick.kind == "loot", "a drop at the side of the screen is still clickable (%s)" % (str(pick.kind) if pick else "nothing"))


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)

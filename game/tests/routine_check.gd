extends SceneTree
## NPC routines and the world clock (foundations step 3): the clock runs and
## is saved with the world, the light follows it, townsfolk walk to the inn
## of an evening and go in at home overnight (answering a knock), the walk
## runs whether or not they are drawn, and only bodies near the player are in
## the scene.
##   godot --headless --path . --script res://game/tests/routine_check.gd

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
		var who: Dictionary = game.roster.create("Routine Tester", "warden")
		game.enter_world(who.character.id)
	elif frame == 4:
		_clock()
		_light()
		_routine()
		_streaming()
		print("routine_check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _clock() -> void:
	var ws = game.world_state
	check(absf(ws.hour - float(DB.CONFIG.clock.startHour)) < 0.1, "a new world starts at the start hour (%.2f)" % ws.hour)
	var h0: float = ws.hour
	ws.advance_clock(float(DB.CONFIG.clock.dayMinutes) * 60.0 / 24.0)
	check(absf(ws.hour - h0 - 1.0) < 0.001, "an hour passes in dayMinutes / 24 real minutes")
	ws.hour = 23.9
	var d0: int = ws.day
	ws.advance_clock(float(DB.CONFIG.clock.dayMinutes) * 60.0 / 24.0 * 0.2)
	check(ws.day == d0 + 1 and ws.hour < 1.0, "midnight starts a new day")
	ws.hour = 15.25
	var saved: Dictionary = ws.serialize()
	ws.reset()
	ws.apply(saved)
	check(absf(ws.hour - 15.25) < 0.01 and ws.day == d0 + 1, "the clock is saved with the world")
	var old: Dictionary = saved.duplicate()
	old.erase("clock")
	ws.apply(old)
	check(absf(ws.hour - float(DB.CONFIG.clock.startHour)) < 0.01, "a save from before the clock starts at the start hour")
	ws.hour = 22.0
	game.inn.wake("hester")
	check(absf(ws.hour - float(DB.CONFIG.inn.wakeHour)) < 0.01, "a night at the inn wakes at first light")


func _light() -> void:
	var noon := DayNight.light(12.0)
	var night := DayNight.light(0.0)
	var afternoon := DayNight.light(16.0)
	check(noon.light > afternoon.light and afternoon.light > night.light, "the sun is strongest at noon, the moon dim")
	check(noon.offset.y > 0 and night.offset.y > 0, "sun and moon are above the ground")
	check(DayNight.light(7.0).offset.x > 0 and DayNight.light(17.0).offset.x < 0, "the sun rises in the east and sets in the west")
	var o: Vector3 = afternoon.offset.normalized()
	check(o.distance_to(Vector3(-22, 17, 9).normalized()) < 0.06, "four in the afternoon keeps the approved low sun (%s)" % o)
	game.world_state.hour = 12.0
	game.step(0.016)
	var day_sun: float = game.sun.light_energy
	var day_amb: float = game.env.ambient_light_energy
	game.world_state.hour = 0.5
	game.step(0.016)
	check(game.sun.light_energy < day_sun * 0.5 and game.env.ambient_light_energy < day_amb, "night is darker (sun %.2f -> %.2f)" % [day_sun, game.sun.light_energy])


func _routine() -> void:
	var n = null
	for c in game.npcs.all:
		if c.routine.size() and c.places.has("inn") and c.places.has("home") and c.present:
			n = c
			break
	check(n != null, "someone in the world has an inn and a home to go to")
	if n == null:
		return
	var inn_at: float = 0.0
	var home_at: float = 0.0
	for b in n.routine:
		if b.at == "inn":
			inn_at = float(b.from) + n.shift
		elif b.at == "home":
			home_at = float(b.from) + n.shift
	var ws = game.world_state
	print("routine_check: following %s (%s, shift %+.2f h; inn %.2f, home %.2f)" % [n.id, n.def.routine, n.shift, inn_at, home_at])
	# just before the inn: snapped to work
	ws.hour = inn_at - 0.1
	game.npcs.update(0.016)
	check(n.place == "work" and n.position.distance_to(n.post) < 0.01, "at work during the day")
	check(not n.collider.off, "standing at their post blocks the way")
	# the hour turns: they set off, and walk there however far the player is
	game.player.position = Vector3(n.post.x + 400, game.player.position.y, n.post.z + 400)
	ws.hour = inn_at + 0.05
	var walked := false
	var seen_walking := false
	for i in 1200:
		game.npcs.update(0.1)
		seen_walking = seen_walking or n.walking
		if n.place == "inn" and not n.walking and not n.waiting:
			walked = true
			break
	check(seen_walking, "they walk to the inn")
	check(walked and Vector2(n.position.x, n.position.z).distance_to(n.places.inn.at) < 0.05, "and arrive at a seat inside (%s)" % n.position)
	check(n.group.get_parent() == null, "no body drawn while the player is far away")
	check(n.collider.off, "no collider left at the post while away")
	# night: home, out of sight, answering a knock
	ws.hour = home_at + 0.5
	game.npcs.update(0.016)
	check(n.inside and not game.npcs.list.has(n) and game.npcs.here.has(n), "at home overnight: gone in, still findable")
	game.player.position = n.position + Vector3(1, 0, 0)
	game.npcs.update(0.016)
	check(n.group.get_parent() == null, "nobody drawn inside a house")
	var knock: Array = game.npcs.interactions().filter(func(i): return i.key == "npc:" + n.id)
	check(knock.size() == 1 and str(knock[0].prompt).begins_with("Knock"), "you can knock for them")
	# morning: back at work, drawn near the player
	ws.hour = 13.0 + n.shift
	game.npcs.update(0.016)
	game.player.position = n.post + Vector3(2, 0, 0)
	game.npcs.update(0.016)
	check(n.place == "work" and not n.inside and n.group.get_parent() != null, "back at work in the morning, drawn near the player")


func _streaming() -> void:
	var p: Vector3 = game.player.position
	var far := 0
	for n in game.npcs.all:
		if n.group.get_parent() != null and n.position.distance_to(p) > WorldStream.VIEW_OUT + 1:
			far += 1
	print("routine_check: %d of %d townsfolk drawn" % [game.npcs.shown_count(), game.npcs.all.size()])
	check(far == 0, "no townsperson drawn past VIEW_OUT")
	var t0 := Time.get_ticks_usec()
	for i in 60:
		game.npcs.update(0.016)
	print("routine_check: npcs.update %.3f ms a frame for %d townsfolk" % [(Time.get_ticks_usec() - t0) / 60000.0, game.npcs.all.size()])


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("  FAIL: " + what)

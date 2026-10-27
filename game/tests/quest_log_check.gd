extends SceneTree
## The quest log and tracker: zones, levels, the way to each quest.
## godot --headless --path . --script res://game/tests/quest_log_check.gd

var game
var frame := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Log Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var q = game.quests
		for id in DB.quests:
			var lv := Quests.levels(id)
			var z := Quests.zone(id)
			print("%-28s %-8s %-16s hand in: %s" % [id, QuestUI.level_text(lv), z.name, Quests.hand_in(id)])
		# take every quest that can be taken, a few rounds deep
		for i in 3:
			for id in DB.quests:
				if q.status(id) == "available":
					q.accept(id, true)
				if q.status(id) == "active":
					q.done[id] = true
		q.done = {}
		for id in DB.quests:
			if q.status(id) == "available":
				q.accept(id, true)
		print("active: ", q.active.size(), " tracked: ", q.tracked.size())
		for id in q.active:
			var g: Dictionary = q.goal(id)
			print("  goal %s -> %s" % [id, g.get("label", "(none)")])
		q.set_focus(q.active[0])
		assert(q.focus == q.active[0])
		var ui = game.hud.quests
		for gr in ui.groups():
			print("group ", gr.name, " dungeon=", gr.dungeon, " ", gr.ids)
		ui.toggle_log(true)
		ui.tracker_collapsed = true
		ui.render_tracker()
		ui.tracker_collapsed = false
		ui.render_tracker()
		var marks: Array = game.hud.minimap.markers().filter(func(m): return m.kind == "goal")
		print("minimap goals: ", marks.size(), " focused: ", marks.filter(func(m): return m.focus).size())
		game.hud.minimap._draw_map()
		game.hud.toggle_world_map()
		var d: Dictionary = q.serialize()
		q.apply(d, {})
		assert(q.focus == d.focus)
		game.step(1.0 / 30)
	elif frame == 6:
		print("way: ", game.hud.quests._way_text)
		print("quest log check done")
		quit(0)
	return false

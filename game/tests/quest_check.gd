extends SceneTree
## Hands in every quest: godot --headless --path . --script res://game/tests/quest_check.gd

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
		var made: Dictionary = game.roster.create("Quest Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var q = game.quests
		# profession quests wait for their skill (`skillReq`)
		for s in DB.skills:
			game.skills.ranks[s] = 30
		for pass_i in 6:
			for id in DB.quests:
				if q.status(id) == "available":
					q.accept(id, true)
				if q.status(id) == "active" or q.status(id) == "ready":
					for o in DB.quests[id].objectives:
						if o.type == "collect":
							game.inventory.add_item(o.target, int(o.get("count", 1)))
						elif o.type == "kill":
							for n in int(o.get("count", 1)):
								q.count_kill(o.target)
						elif o.type == "examine":
							game.world_state.examined[o.target] = true
					q.refresh()
					if q.status(id) == "ready" and not q.complete(id):
						print("could not hand in ", id)
		game.step(1.0 / 30)
	elif frame == 5:
		print("quest check: %d of %d quests handed in" % [q_done(), DB.quests.size()])
		quit(0)
	else:
		game.step(1.0 / 30)
	return false


func q_done() -> int:
	return game.quests.done.size()

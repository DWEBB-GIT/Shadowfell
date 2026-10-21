extends SceneTree
## Checks the Quests, Quest chains and NPCs tabs of the Game Data editor
## without the Godot editor: a new npc with a shop and a quest, a quest
## reward and objective, saved and read back, passing the checks. Works on a
## copy of data/, so the real files are not touched.
##   godot --headless --path . --script res://game/tests/quest_npc_editor_check.gd

const Main := preload("res://addons/shadowfell_data/main.gd")
const IO := preload("res://addons/shadowfell_data/json_io.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")
const Chains := preload("res://addons/shadowfell_data/chains_page.gd")

const COPY := "user://quest_npc_editor_check"
var failed := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(COPY)
	for f in DirAccess.get_files_at("res://data"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://data/" + f), ProjectSettings.globalize_path(COPY + "/" + f))
	var main = Main.new(COPY)
	root.add_child(main)
	var s = main.s
	_ok(Checks.run(s).is_empty(), "the data as it is passes the checks: %s" % "\n".join(Checks.run(s)))
	var quests = main.page_named("Quests")
	var npcs = main.page_named("NPCs")
	_ok(quests != null and npcs != null and main.page_named("Quest chains") != null and main.page_named("Chests") != null, "the Quests, Quest chains, NPCs and Chests tabs are there")

	# every quest and npc form builds
	for q in s.quests:
		quests.select(q.id)
	for n in s.npcs:
		npcs.select(n.id)
	_ok(quests.form.get_child_count() > 10 and npcs.form.get_child_count() > 5, "every quest and npc form builds")

	# a new npc: named, given a greeting, a shop with a sword, placed in town
	npcs._new_npc()
	var n: Dictionary = npcs.current
	n.name = "Osric Dunn"
	npcs._rename_new("osric_dunn")
	_ok(n.id == "osric_dunn" and s.npc("osric_dunn") == n, "a new npc takes its id from its name")
	npcs.give_dialogue(n)
	_ok(s.dialogue(n.dialogue).greetings[0].text != "", "they get a greeting of their own")
	npcs._new_shop(n)
	var shop: Dictionary = s.shop(n.shop)
	_ok(shop.id == "osric_dunn_shop", "they get a shop of their own: %s" % shop)
	shop.vendorType = "smith"
	shop.stock.append("arming_sword")
	npcs._place(n)
	var sp: Dictionary = s.spawn_of("osric_dunn")
	_ok(not sp.is_empty(), "they are placed in the world")
	_ok(Checks.run(s).is_empty(), "the new npc passes the checks: %s" % "\n".join(Checks.run(s)))
	shop.stock.append("manifest")
	_ok(Array(Checks.run(s)).any(func(p): return p.contains("quest item manifest cannot be sold")), "a quest item in a shop is caught")
	shop.stock.erase("manifest")
	_ok(not npcs._sellable(s.item("manifest"), ["material"]) and npcs._sellable(s.item("arming_sword"), ["weapon"]), "the stock picker offers only what the vendor type sells")

	# a quest from the new npc: kill a ghoul, bring a pelt, a sword as reward
	main.open_record("new_quest", "osric_dunn")
	var q: Dictionary = quests.current
	_ok(q.giver == "osric_dunn" and q.turnIn == "osric_dunn", "New quest from an npc makes them its giver")
	q.name = "Iron for Osric"
	quests._rename_new("iron_for_osric")
	_ok(q.id == "iron_for_osric", "the quest takes its id from its name")
	_ok(Array(Checks.run(s)).any(func(p): return p.begins_with("Quest iron_for_osric: needs summary")), "an unwritten quest is caught")
	for k in ["summary", "offer", "progress", "complete"]:
		q[k] = "Words."
	q.objectives[0].target = "ghoul"
	q.objectives[0].label = "Ghouls slain"
	q.objectives.append({"id": "pelts", "type": "collect", "target": "hound_pelt", "count": 2, "label": "Hound pelts"})
	q.reward.items = [{"item": "arming_sword", "count": 1}]
	q.reward.reputation = {"road_wardens": 100}
	q.requires = ["missing_delivery"]
	quests._changed()
	_ok(q.keys().find("requires") < q.keys().find("summary") and q.keys().find("reward") > q.keys().find("objectives"), "its keys are kept in the file's order: %s" % [q.keys()])
	_ok(Checks.run(s).is_empty(), "the finished quest passes the checks: %s" % "\n".join(Checks.run(s)))
	quests.select(q.id)
	npcs.select("osric_dunn")

	# the checks catch broken quests
	q.objectives[0].count = 999
	_ok(Array(Checks.run(s)).any(func(p): return p.contains("the world only has")), "more kills than the world holds is caught")
	q.objectives[0].count = 1
	q.objectives.append({"id": "talk", "type": "talk", "target": "mara", "label": "Speak to Mara"})
	_ok(Array(Checks.run(s)).any(func(p): return p.contains("a talk objective names the hand-in npc")), "a talk objective to someone else is caught")
	q.objectives.pop_back()
	_find(s.quests, "missing_delivery").requires = ["iron_for_osric"]
	_ok(Array(Checks.run(s)).any(func(p): return p.contains("loop back")), "a requirement loop is caught")
	_find(s.quests, "missing_delivery").erase("requires")

	# the chain map lays out every quest, the new one after its requirement
	var pos: Dictionary = Chains.layout(s.quests)
	_ok(pos.size() == s.quests.size() and pos.iron_for_osric.x > pos.missing_delivery.x, "the chain map places every quest, follow-ups to the right")
	var chains = main.page_named("Quest chains")
	chains.refresh_tree()
	chains._disconnect(&"missing_delivery", 0, &"iron_for_osric", 0)
	_ok(not q.has("requires"), "removing an arrow removes the requirement")
	chains._connect(&"missing_delivery", 0, &"iron_for_osric", 0)
	_ok(q.requires == ["missing_delivery"], "drawing an arrow adds it back")

	var saved = s.save_all()
	_ok(Array(saved).has("npcs.json") and Array(saved).has("shops.json") and Array(saved).has("quests.json") and Array(saved).has("world.json") and Array(saved).has("dialogue.json"), "npcs, shops, quests, world and dialogue are saved: %s" % [saved])
	var back = IO.load_file(COPY + "/quests.json")
	_ok(back.quests.any(func(x): return x.id == "iron_for_osric" and x.reward.items[0].item == "arming_sword"), "the quest and its reward are in quests.json")
	back = IO.load_file(COPY + "/shops.json")
	_ok(back.shops.any(func(x): return x.id == "osric_dunn_shop" and x.stock == ["arming_sword"]), "the shop and its stock are in shops.json")
	# the files the editor writes read back byte for byte when unchanged
	for f in ["shops", "npcs", "dialogue"]:
		var text := FileAccess.get_file_as_string("res://data/%s.json" % f)
		_ok(IO.to_text(IO.load_file("res://data/%s.json" % f), false, f == "shops") == text, "%s.json reads back byte for byte" % f)
	# the game reads the new data
	main.s.load_all()
	_ok(Checks.run(main.s).is_empty(), "the saved data passes the checks: %s" % "\n".join(Checks.run(main.s)))
	main.queue_free()
	print("quest and npc editor: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)


static func _find(list: Array, id) -> Dictionary:
	for r in list:
		if r.get("id") == id:
			return r
	return {}


func _ok(cond: bool, what: String) -> void:
	if cond:
		print("  ok   ", what)
	else:
		failed += 1
		print("  FAIL ", what)

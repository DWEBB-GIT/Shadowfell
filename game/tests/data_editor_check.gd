extends SceneTree
## Checks the Game Data editor (addons/shadowfell_data) without the Godot
## editor: every data file it writes reads back the same, and a new sword,
## added to a loot table and a quest reward, saves and passes the checks.
## Works on a copy of data/, so the real files are not touched.
##   godot --headless --path . --script res://game/tests/data_editor_check.gd

const Main := preload("res://addons/shadowfell_data/main.gd")
const IO := preload("res://addons/shadowfell_data/json_io.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")

const COPY := "user://data_editor_check"
var failed := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(COPY)
	for f in DirAccess.get_files_at("res://data"):
		DirAccess.copy_absolute(ProjectSettings.globalize_path("res://data/" + f), ProjectSettings.globalize_path(COPY + "/" + f))
	var main = Main.new(COPY)
	root.add_child(main)
	var s = main.s
	_ok(Checks.run(s).is_empty(), "the data as it is passes the checks: %s" % "\n".join(Checks.run(s)))

	# a new one-hand sword, enhanced, strength and stamina
	var items = main.pages[0]
	items._create(items.NEW_TYPES[0][1], "sword", "Hunter's Sword", "enhanced")
	var d: Dictionary = s.item("hunters_sword")
	_ok(not d.is_empty(), "the new sword is made with an id from its name")
	_ok(d.kind == "weapon" and d.slot == "oneHand" and d.weaponType == "sword", "it is a one-hand sword")
	d.statSplit = {"strength": 1, "stamina": 1}
	var sc := Scaling.scaled_item(d)
	_ok(sc.damage is Array and sc.stats.get("strength", 0) > 0, "its damage and stats are worked out: %s" % [sc])
	items._add_to_table("ghoul")
	var ghoul = _find(s.loot_tables, "ghoul")
	_ok(ghoul.drops.items.enhanced.any(func(e): return e.item == "hunters_sword"), "it is added to the ghoul table under enhanced")
	var q = _find(s.quests, "missing_delivery")
	q.reward.items.append({"item": "hunters_sword", "count": 1})
	s.touch("quests")
	d.description = "A plain blade."
	# a level 10 to 12 ghoul for another zone: its own entry based on the ghoul
	var loot = main.pages[1]
	loot._new_variant(_find(s.enemies, "ghoul"))
	var v: Dictionary = loot.current_enemy
	v.level = 6
	_ok(v.base == "ghoul" and s.resolved(v).model == "ghoul" and s.resolved(v).lootTable == "ghoul", "a level variant takes the rest from its base")
	_ok(s.band_for(v).get("id") == "world_6_10" and s.band_for(_find(s.enemies, "ghoul")).get("id") == "world_1_5", "world drops are picked by level")
	_ok(s.band_for(_find(s.enemies, "hound")).is_empty(), "beasts roll no world drops")
	loot._enemy_set(v, "lootTable", null)
	_ok(v.lootTable == "" and s.resolved(v).lootTable == "", "a variant can drop nothing of its own while its base does")
	# a quest drop: the bandits' black rag, only while Pell's quest wants it
	var bh := _find(s.loot_tables, "blackhedge")
	bh.questDrops = [{"item": "blackhedge_rag", "quest": "bandit_rag", "chance": 0.5}]
	_ok(Checks.run(s).is_empty(), "a quest drop for an item the quest collects passes the checks")
	bh.questDrops[0].quest = "missing_delivery"
	_ok(Array(Checks.run(s)).any(func(p): return p.contains("no objective to collect")), "a quest drop the quest does not ask for is caught")
	bh.erase("questDrops")
	_ok(Checks.run(s).is_empty(), "the checks pass: %s" % "\n".join(Checks.run(s)))
	var saved = s.save_all()
	_ok(saved.size() == 4, "items, loot tables, enemies and quests are saved: %s" % [saved])

	# what was written reads back, and the item is in it
	var back = IO.load_file(COPY + "/items.json")
	_ok(back.items.any(func(x): return x.id == "hunters_sword"), "the sword is in items.json")
	# a file the editor writes changes only where it changed
	for f in ["enemies", "loot_tables", "rarities", "npcs"]:
		var text := FileAccess.get_file_as_string("res://data/%s.json" % f)
		_ok(IO.to_text(IO.load_file("res://data/%s.json" % f)) == text, "%s.json reads back byte for byte" % f)
	main.queue_free()
	print("data editor: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)


static func _find(list: Array, id) -> Dictionary:
	for r in list:
		if r.get("id") == id:
			return r
	return {}


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		printerr("FAIL: " + what)

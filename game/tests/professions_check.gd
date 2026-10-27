extends SceneTree
## The profession ladder (Fishing, Herbalism, Alchemy): ranks, skill
## experience, perks, tools, gated water and fish, herb patches, brewing,
## elixirs and the save.
##   godot --headless --path . --script res://game/tests/professions_check.gd

var game
var frame := 0
var failures := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Prof Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.inventory.add_coins(5000)
		_data()
		_ladder()
		_fishing()
		_herbalism()
		_alchemy()
		_save_round_trip()
		print("professions check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _data() -> void:
	var rank_ids: Array = DB.skill_ladder.ranks.map(func(r): return r.id)
	for s in DB.skills.values():
		for e in s.get("train", []):
			check(rank_ids.has(e.rank) and DB.npcs.has(e.trainer), "%s %s names a rank and a trainer" % [s.id, e.rank])
			if e.has("quest"):
				check(DB.quests.has(e.quest) and DB.quests[e.quest].get("skillReq", {}).get("skill") == s.id, "%s %s quest %s is that skill's" % [s.id, e.rank, e.quest])
	for k in DB.nodes.nodeKinds:
		check(DB.skills.has(k.skill) and DB.items.has(k.yields.item), "node kind %s names its skill and yield" % k.id)
	for g in DB.nodes.nodeGroups:
		for p in g.spots:
			check(Terrain.walk_at(p[0], p[1]) >= 0.5 and Terrain.water_at(p[0], p[1]) == null, "%s spot %s is on open ground" % [g.id, str(p)])
	for r in DB.recipes.values():
		check(DB.items.has(r.output.item) and r.inputs.all(func(x): return DB.items.has(x.item)), "recipe %s makes and uses real items" % r.id)


func _ladder() -> void:
	var sk = game.skills
	check(sk.learn("fishing"), "Tam teaches Fishing")
	check(sk.rank_name("fishing") == "Novice" and sk.cap("fishing") == 10, "a new angler is a Novice, capped at 10")
	var xp_was: int = game.progression.xp + game.progression.level * 100000
	var levels := 0
	for i in 200:
		levels += sk.gain("fishing", "orange")
	check(sk.rank("fishing") == 10 and levels == 9, "orange tasks raise Fishing to the cap (%d)" % sk.rank("fishing"))
	check(game.progression.xp + game.progression.level * 100000 > xp_was, "skill levels pay character experience")
	check(sk.gain("fishing", "orange") == 0, "no more past the cap")
	check(sk.gain("fishing", "grey") == 0, "grey tasks teach nothing")
	check(sk.rank_blocked("fishing").begins_with("Requires The Blackpool Tench"), "Apprentice waits on Tam's quest: %s" % sk.rank_blocked("fishing"))
	check(game.quests.status("tam_blackpool") == "available", "Tam's quest is offered at Fishing 6+")
	check(game.quests.status("briony_bloodroot") == "locked", "Briony's waits for Herbalism")
	game.quests.done["tam_blackpool"] = true
	var renown: float = game.reputation.renown
	check(sk.train_rank("fishing"), "Tam trains Apprentice Fishing")
	check(sk.cap("fishing") == 20 and sk.rank_name("fishing") == "Apprentice", "now capped at 20")
	check(game.reputation.renown > renown, "a rank earns renown")
	check(sk.perk_choices("fishing").size() == 1, "a perk is waiting at level 10")
	check(not sk.choose_perk("fishing", 20, "double_haul"), "no level 20 perk yet")
	check(sk.choose_perk("fishing", 10, "steady_hands"), "Steady Hands chosen")
	check(sk.perk("fishing", "landChance") == 10.0 and sk.perk_choices("fishing").is_empty(), "its effect counts")


func _fishing() -> void:
	var sk = game.skills
	var f = game.fishing
	game.inventory.add_item("yew_fishing_rod")
	game.inventory.add_item("ash_fishing_rod")
	check(sk.tool_bonus("fishing") == 10, "the ash rod needs Fishing 12; the yew rod counts (%d)" % sk.tool_bonus("fishing"))
	sk.ranks.fishing = 12
	check(sk.tool_bonus("fishing") == 15, "at 12 the ash rod counts")
	var pool: Dictionary = Layout.water.filter(func(w): return w.id == "blackpool")[0]
	var t: Dictionary = f._table(pool)
	check(not t.drops.items.rare.any(func(e): return e.item == "mirror_pike"), "mirror pike won't bite below Fishing 15")
	sk.ranks.fishing = 15
	check(f._table(pool).drops.items.rare.any(func(e): return e.item == "mirror_pike"), "at 15 it will")
	check(sk.colour_for("fishing", 8) == "green", "the Blackpool is green at 15")
	check(sk.colour_for("fishing", 16) == "red", "a level 16 water is beyond you")


func _herbalism() -> void:
	var sk = game.skills
	var g = game.gathering
	var live: Array = g.live()
	check(live.size() == DB.nodes.nodeGroups.reduce(func(a, x): return a + int(x.live), 0), "every herb group grows its live patches (%d)" % live.size())
	var v = live.filter(func(x): return x.level == 1)
	if v.is_empty():
		v = live
	v = v[0]
	check(g.block(v) == "needs Herbalism", "herbs need the skill")
	check(sk.learn("herbalism"), "Briony teaches Herbalism")
	var blood = live.filter(func(x): return x.level == 10)
	if not blood.is_empty():
		check(g.block(blood[0]) == "needs Herbalism 10", "bloodroot needs Herbalism 10")
	if v.level > 1:
		sk.ranks.herbalism = v.level
	var n: Dictionary = v.n
	var item: String = Gathering.kind_def(n.kind).yields.item
	var had: int = game.inventory.count(item)
	var xp_was: int = int(sk.xp.get("herbalism", 0)) + sk.rank("herbalism") * 1000
	game.player.place_at(n.x + 1.0, n.z)
	check(g.start(n), "picking starts")
	var time := 500.0
	for i in 4:
		time += 1.0
		g.update(1.0, time)
	check(game.inventory.count(item) > had, "the herb is in the bags")
	check(int(sk.xp.get("herbalism", 0)) + sk.rank("herbalism") * 1000 > xp_was, "Herbalism learned from it")
	check(n.kind == "" and g.regrow.size() == 1, "the patch is bare and will grow back elsewhere")
	g.update(0.0, time + 1000.0)
	check(g.live().size() == live.size(), "the group grew another patch")


func _alchemy() -> void:
	var sk = game.skills
	var ck = game.cooking
	check(sk.learn("alchemy"), "Briony teaches Alchemy")
	var st: Dictionary = Layout.stations.filter(func(s): return s.kind == "alchemy")[0]
	game.player.place_at(st.position[0] + 1.5, st.position[1])
	check(ck.near_station("alchemy") != "", "standing at %s" % st.name)
	game.inventory.add_item("ditchbell", 4, true)
	var r: Dictionary = DB.recipes.brew_healing_draught
	check(ck.blocked(r) == "", "a healing draught can be brewed here: %s" % ck.blocked(r))
	var had: int = game.inventory.count("healing_draught")
	check(ck.start(r.id), "brewing starts")
	ck.update(10.0)
	check(game.inventory.count("healing_draught") > had, "a healing draught is brewed")
	check(int(sk.xp.get("alchemy", 0)) > 0, "Alchemy learned from it")
	check(ck.blocked(DB.recipes.brew_strong_draught) != "", "the strong draught waits for Briony and rank 10")
	# an elixir raises its stat; a second replaces the first
	var sta: float = game.stats.snapshot().stamina.v
	game.player.cooldowns.draught = 0.0
	game.inventory.add_item("fortifying_tonic", 1, true)
	check(game.inventory.use(_bag_loc("fortifying_tonic")), "the tonic is drunk")
	check(game.boons.elixir != null and game.stats.snapshot().stamina.v == sta + 3, "+3 Stamina while it lasts")
	game.boons.update(10000.0)
	check(game.boons.elixir == null and game.stats.snapshot().stamina.v == sta, "and it wears off")


func _bag_loc(id: String) -> String:
	for loc in game.inventory.bag_locations():
		var s = game.inventory.get_at(loc)
		if s != null and s.id == id:
			return loc
	return ""


func _save_round_trip() -> void:
	var sk = game.skills
	var data: Dictionary = game.save.serialize()
	var was: Dictionary = sk.serialize_ladder()
	sk.apply(data.skills)
	sk.apply_ladder(data.skillLadder)
	check(sk.serialize_ladder() == was and sk.cap("fishing") == 20, "the ladder survives a save")
	# an old save: Fishing 35 and no ranks -> kept up to the Apprentice's cap
	sk.apply({"fishing": 35})
	sk.apply_ladder(null)
	check(sk.rank("fishing") == 20 and sk.rank_name("fishing") == "Apprentice", "an old save keeps its skill to 20")


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)

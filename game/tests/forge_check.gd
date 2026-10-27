extends SceneTree
## Mining, smelting, the forge, gems, the law and Inspired.
##   godot --headless --path . --script res://game/tests/forge_check.gd

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
		var made: Dictionary = game.roster.create("Forge Tester", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		game.inventory.add_coins(5000)
		_mining()
		_smelting()
		_temper_and_scrap()
		_reforge()
		_gems()
		_inspired()
		_law()
		_save_round_trip()
		print("forge check: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
		quit(1 if failures else 0)
	return false


func _mining() -> void:
	var m = game.mining
	var veins: Array = m.veins()
	check(not veins.is_empty(), "veins glint at the start (%d)" % veins.size())
	var groups := {}
	for v in veins:
		groups[v.o.group.id] = true
	check(groups.size() == DB.mining.veinGroups.size(), "every vein group has a live vein")
	# outcrops stand clear of walls and of each other
	for o in m.outcrops:
		check(not game.collision.wall_between(o.x, o.z, o.x + 0.01, o.z + 0.01), "outcrop %s:%d is not inside a wall" % [o.group.id, o.i])
	var v = veins.filter(func(x): return x.rank == 1)[0]
	check(m.block(v) == "needs Mining", "a vein needs the skill")
	check(game.skills.learn("mining"), "Orrin teaches Mining")
	check(m.block(v) == "needs a mining pick", "then a pick")
	game.inventory.add_item("mining_pick")
	check(m.block(v) == "", "now the vein can be mined")
	var o: Dictionary = v.o
	game.player.place_at(o.x + 1.2, o.z)
	var swings: int = o.swings
	var stone: int = game.inventory.count("rough_stone") + game.inventory.count("granite")
	check(m.start(o), "mining starts")
	var t := 100.0
	for i in swings + 2:
		t += 3.0
		m.update(3.0, t)
	check(o.rock == "", "the vein is mined out after %d swings" % swings)
	check(game.skills.rank("mining") > 1, "Mining rose (%d)" % game.skills.rank("mining"))
	check(game.inventory.count("rough_stone") + game.inventory.count("granite") > stone or game.inventory.count("copper_ore") + game.inventory.count("tin_ore") > 0, "the swings gave stone or ore")
	check(m.regrow.size() == 1, "a vein will relight in the group")
	m.update(0.0, t + 1000.0)
	var live: Array = m.outcrops.filter(func(x): return x.group == o.group and x.rock != "")
	check(not live.is_empty() and not live.any(func(x): return is_same(x, o)), "it relights on a different outcrop")


func _smelting() -> void:
	var ck = game.cooking
	var st: Dictionary = Layout.stations.filter(func(s): return s.kind == "forge")[0]
	game.inventory.add_item("copper_ore", 4)
	game.inventory.add_item("tin_ore", 2)
	game.player.place_at(st.position[0] + 3.0, st.position[1])
	check(ck.near_station("forge") != "", "standing at %s" % st.name)
	check(ck.blocked(DB.recipes.smelt_copper) == "", "copper can be smelted here")
	check(ck.blocked(DB.recipes.smelt_bronze).begins_with("Requires Mining"), "bronze needs Mining 10")
	game.skills.ranks.mining = 10
	check(ck.blocked(DB.recipes.smelt_bronze) == "", "bronze can be smelted at Mining 10")
	var had: int = game.inventory.count("bronze_bar")
	ck._finish(DB.recipes.smelt_bronze)
	check(game.inventory.count("bronze_bar") == had + 2 and game.inventory.count("tin_ore") == 1, "copper and tin make 2 bronze bars")
	game.player.place_at(0, 0)
	check(ck.blocked(DB.recipes.smelt_copper) == "Requires a forge.", "no smelting away from a forge")


func _bag_loc(id: String) -> String:
	for loc in game.inventory.bag_locations():
		var st = game.inventory.get_at(loc)
		if st != null and st.id == id:
			return loc
	return ""


## The starter bags are small: empty them before a section that needs room.
func _clear_bags() -> void:
	for loc in game.inventory.bag_locations():
		if game.inventory.get_at(loc) != null:
			game.inventory.take(loc)


func _temper_and_scrap() -> void:
	var f = game.forge
	var inv = game.inventory
	_clear_bags()
	inv.add_item("watchmans_edge")
	var loc := _bag_loc("watchmans_edge")
	var st: Dictionary = inv.get_at(loc)
	check(f.temper_cap(st) == 2, "an enhanced item enchants twice")
	var base: Dictionary = Items.view(st)
	var c1: Dictionary = f.temper_cost(st)
	check(c1.items.size() == 1 and c1.items[0].item == "faint_dust", "rank 1 asks faint dust, no bars or whetstones")
	check(not f.temper(loc), "no enchanting without the dust")
	inv.add_item("faint_dust", 20, true)
	check(f.temper(loc), "enchanted once")
	check(f.temper(loc), "enchanted twice")
	check(not f.temper(loc), "and no further (capped)")
	var v: Dictionary = Items.view(inv.get_at(loc))
	check(v.itemLevel == base.itemLevel + 2, "item level +2 (%s)" % v.itemLevel)
	check(v.name.ends_with("+2"), "the name shows +2 (%s)" % v.name)
	var sum := func(s): return s.values().reduce(func(a, b): return a + b, 0.0)
	check(v.damage[1] > base.damage[1] and sum.call(v.stats) >= sum.call(base.stats), "its damage rose (%s -> %s)" % [base.damage, v.damage])
	check(Items.valid_rolls(st.id, inv.get_at(loc).get("rolls")), "enchanted rolls are valid")
	# epic and legendary: the last rank needs a soulshard
	var last: Dictionary = Forge.rank_cost(5, 7, 7, "legendary")
	check(last.items.any(func(x): return x.item == "soulshard"), "a legendary's last rank needs a soulshard")
	# the smith melts it for metal only; the enchantment burns off
	var sp: Dictionary = f.scrap_preview(inv.get_at(loc))
	check(sp.items.size() == 1 and sp.items[0].item.ends_with("_bar") and sp.items[0].count == 1, "scrap gives just its base bar (%s)" % [sp.items])
	check(f.scrap_text(inv.get_at(loc)).begins_with("You get back"), "the preview reads as a list")
	# disenchant: 2 dust for an enhanced item, plus 75% of the 3 + 4 put in (5)
	var p: Dictionary = f.disenchant_preview(inv.get_at(loc))
	var dust := 0
	for x in p.items:
		if x.item == "faint_dust":
			dust += x.count
	check(dust == 7, "disenchanting gives 7 faint dust back (%d)" % dust)
	check(f.disenchant_preview({"id": "worn_longsword"}).is_empty(), "plain gear has no magic to draw")
	var before: int = inv.count("faint_dust")
	check(f.disenchant(loc), "disenchanted")
	check(inv.count("watchmans_edge") == 0 and inv.count("faint_dust") == before + 7, "the item is gone and the dust is in the bags")
	check(f.disenchant_preview({"id": "bloodletter"}).items.any(func(x): return x.item == "soulshard"), "a legendary gives a soulshard")
	# the enchanter offers the work, the smith no longer does, and she stands clear of walls
	var dlg = game.dialogue
	var sab: Array = game.npcs.all.filter(func(n): return n.id == "sabeth")
	check(not sab.is_empty(), "Sabeth stands in Brackenford")
	if not sab.is_empty():
		var n = sab[0]
		check(not game.collision.wall_between(n.position.x, n.position.z, n.position.x + 0.01, n.position.z + 0.01), "Sabeth is not inside a wall")
		dlg.npc = n
		dlg.view = {"kind": "menu"}
		check(dlg.page.options.any(func(o): return o.id == "ench:enchant") and dlg.page.options.any(func(o): return o.id == "ench:disenchant"), "Sabeth enchants and disenchants")
	dlg.npc = game.npcs.all.filter(func(n): return n.id == "mara")[0]
	dlg.view = {"kind": "menu"}
	check(not dlg.page.options.any(func(o): return str(o.id).begins_with("ench") or o.id == "smith:temper"), "Mara no longer tempers")
	dlg.npc = null


func _reforge() -> void:
	var f = game.forge
	var inv = game.inventory
	inv.add_item("old_watch_helm")
	var loc := _bag_loc("old_watch_helm")
	var opts: Array = f.reforge_options(inv.get_at(loc))
	check(not opts.is_empty() and opts[0].to.size() <= 3 and opts[0].to.size() > 0, "reforge shows up to 3 options a stat")
	var from: String = opts[0].from
	var to: String = opts[0].to[0]
	var amount: float = Items.view(inv.get_at(loc)).stats[from]
	check(f.reforge(loc, from, to), "reforged %s to %s" % [from, to])
	var v: Dictionary = Items.view(inv.get_at(loc))
	check(not v.stats.has(from) and v.stats.get(to, 0) > 0, "the stat moved")
	check(not f.reforge(loc, from, "nonsense"), "an unoffered stat is refused")
	check(Items.valid_rolls("old_watch_helm", inv.get_at(loc).get("rolls")), "reforged rolls are valid")
	check(amount > 0, "it had %s to move" % from)


func _gems() -> void:
	var f = game.forge
	var inv = game.inventory
	_clear_bags()
	inv.add_item("garnet_shard", 15)
	check(f.combine("garnet_chipped"), "5 shards make a chipped garnet")
	check(f.combine("garnet_chipped") and f.combine("garnet_chipped"), "and twice more")
	check(f.combine("garnet_flawed"), "3 chipped make a flawed garnet")
	check(inv.count("garnet_flawed") == 1 and inv.count("garnet_chipped") == 0 and inv.count("garnet_shard") == 0, "the shards are used up")
	# a socketed legendary and a punched one
	inv.add_item("bloodletter")
	var loc := _bag_loc("bloodletter")
	check(Items.sockets_of(inv.get_at(loc)) == 1, "Bloodletter has a socket")
	var plain: Dictionary = Items.view({"id": "bloodletter"})
	check(f.gems_for(loc).has("garnet_flawed"), "the flawed garnet fits a weapon")
	check(f.set_gem(loc, "garnet_flawed"), "the garnet is set")
	var with: Dictionary = Items.view(inv.get_at(loc))
	var gem_stats: Dictionary = Gems.stats("garnet_flawed")
	check(not gem_stats.is_empty() and gem_stats.keys().all(func(k): return with.stats.get(k, 0) > plain.stats.get(k, 0)), "the gem adds its stats %s" % gem_stats)
	check(Items.gems_of(inv.get_at(loc)) == ["garnet_flawed"], "the socket holds it")
	check(Items.valid_rolls("bloodletter", inv.get_at(loc).get("rolls")), "socketed rolls are valid")
	inv.add_item("skyiron")
	check(not f.punch_cost(inv.get_at(loc)).is_empty() and f.punch(loc), "a forge punches a second socket")
	check(Items.sockets_of(inv.get_at(loc)) == 2 and f.punch_cost(inv.get_at(loc)).is_empty(), "two sockets, no more")
	check(f.remove_gems(loc), "the gem comes out")
	check(inv.count("garnet_flawed") == 1, "whole, back in the bags")
	f.set_gem(loc, "garnet_flawed")
	var p: Dictionary = f.scrap_preview(inv.get_at(loc))
	check(p.gems == ["garnet_flawed"], "scrapping gives the gem back")
	# the jeweller and the smith offer their work
	var dlg = game.dialogue
	dlg.npc = game.npcs.all.filter(func(n): return n.id == "ysolde")[0]
	dlg.view = {"kind": "menu"}
	check(dlg.page.options.any(func(o): return str(o.id).begins_with("jw:")), "Ysolde offers gem work")
	dlg.npc = game.npcs.all.filter(func(n): return n.id == "mara")[0]
	dlg.view = {"kind": "menu"}
	check(dlg.page.options.any(func(o): return str(o.id).begins_with("smith")), "Mara offers smith work")
	dlg.npc = null


func _inspired() -> void:
	var b = game.boons
	var pr = game.progression
	game.events.emit("documentRead", {"id": "torn_page"})
	check(b.inspired > 0, "reading a lore page for the first time Inspires you")
	var t: float = b.inspired
	b.update(10.0)
	game.events.emit("documentRead", {"id": "torn_page"})
	check(b.inspired < t, "a second read does not")
	var xp0: int = pr.xp
	var lvl: int = pr.level
	pr.add_xp(100)
	check(pr.level > lvl or pr.xp - xp0 == 110, "Inspired gives +10%% experience (%d)" % (pr.xp - xp0))
	b.inspired = 0.0
	check(b.hear_tale() != "" and b.inspired > 0, "the bard's tale Inspires")
	check(b.hear_tale() == "", "once a day")


func _law() -> void:
	var law = game.law
	var inv = game.inventory
	var pig = game.enemies.list.filter(func(e): return e.id == "corrick_sow_1")[0]
	var guard = game.enemies.list.filter(func(e): return e.id == "watch_ford_1")[0]
	check(law.protected(pig) and law.protected(guard), "livestock and the watch are protected")
	check(pig.hurt(5) == 0, "a protected pig takes no harm")
	check(not law.may_attack(pig), "no attacking it without the crime key")
	game.input.held["AltLeft"] = true
	check(law.may_attack(pig), "holding Alt you may")
	game.input.held.erase("AltLeft")
	check(not law.protected(pig), "and it is no longer protected")
	# with nobody near, it does not count
	var j: Dictionary = Law.jurisdiction_at(pig.position.x, pig.position.z)
	check(not j.is_empty(), "the pig is in %s" % j.get("name", "no jurisdiction"))
	check(not law.commit("livestock", Vector3(9999, 0, pig.position.z)), "an unseen crime does not count")
	# a watchman sees it
	guard.position = pig.position + Vector3(3, 0, 0)
	game.player.place_at(pig.position.x + 1.5, pig.position.z)
	pig.hurt(pig.health + 10)
	game.combat.on_enemy_defeated(pig)
	check(pig.dead and law.bounty.get(j.id, 0) == 20, "the sow's death is seen: 20c bounty (%s, dead %s, seen by %d)" % [law.bounty, pig.dead, law.witnesses(pig.position).size()])
	check(law.status != "" and law.nameplate_colour() != Color.WHITE, "your nameplate is not white")
	check(is_same(law.summoned, guard), "a watchman is sent over")
	law.confront(guard)
	check(law.talk != null and law.page().options.size() == 1, "the first time he only warns you")
	check(law.choose("sorry") and law.bounty.is_empty(), "you say sorry and he lets it go")
	# the second time is a fine
	law.commit("livestock", guard.position)
	law.commit("livestock", guard.position)
	law.confront(guard)
	check(law.page().options.any(func(o): return o.id == "pay"), "the second time he fines you")
	var c0: int = inv.coins
	check(law.choose("pay") and inv.coins == c0 - 40 and law.bounty.is_empty(), "the fine is paid")
	# Wanted: dying means the lock-up
	law.commit("assault", guard.position, guard)
	check(law.wanted_in(j.id) and law.hostile(guard) and not guard.passive, "assault: Wanted, the watch is hostile")
	game.player.health = 0
	check(law.jail_on_death(), "falling while Wanted means gaol")
	check(not law.wanted_in(j.id) and law.bounty.is_empty(), "the slate is clean after the lock-up")
	# Infamy lasts; enough of it makes an outlaw, with a markup and a hunter
	law.add_infamy(50)
	check(law.outlaw and law.hostile(guard), "an outlaw: the watch fights on sight")
	check(game.merchant.refuses(), "merchants refuse an outlaw")
	law.update(0.0)
	check(law.hunter_at > 0, "a hunter is on the way")
	game.world_state.time = law.hunter_at + 1
	law.update(0.0)
	check(law.hunter != null and law.hunter.alive, "%s comes for you" % (law.hunter.cfg.name if law.hunter else "the hunter"))
	var lv: int = law.hunter.cfg.level if "level" in law.hunter.cfg else 0
	law._killed(law.hunter)
	check(law.scars == 1 and law.hunter == null, "beaten, he crawls off")
	check(game.titles.available("outlaw"), "the Outlaw title is yours")
	law.atone(50)
	check(not law.outlaw, "atoning at the reeve lifts outlawry")
	check(lv >= 0, "the hunter had a level")


func _save_round_trip() -> void:
	var data: Dictionary = game.save.serialize()
	check(data.has("law") and data.has("boons"), "the save has law and boons")
	var law_was: Dictionary = game.law.serialize()
	game.law.apply(data.law)
	check(game.law.serialize() == law_was, "law survives a save")
	var boons_was: Dictionary = game.boons.serialize()
	game.boons.apply(data.boons)
	check(game.boons.serialize() == boons_was, "boons survive a save")


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL ", what)
	else:
		print("ok   ", what)

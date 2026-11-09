extends SceneTree
## Full quest-state trials use isolated saves. Combat is counted through
## the combat reward path; travelling is checked separately on the live map.
var game
var failures := 0
var checks := 0
var route_totals := {}

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING,"new")
	Store.dir = "user://intro_journey_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(game.hud.modal == "title", "Normal launch reaches the login/character screen")
	var made: Dictionary = game.roster.create("Introtrial","warden")
	check(made.ok,"A fresh character can be created")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:
		await process_frame
	game.save.autosave_enabled = false
	game.set_process(false)
	game.random = func(): return 0.5
	var start: Array = DB.world.playerStart.position
	check(game.player.position.distance_to(Vector3(start[0],Terrain.height_at(start[0],start[1]),start[1])) < 2,"A new player starts on the road in")
	check(Vector2(start[0],start[1]).distance_to(Vector2(-450,-207)) > 60,"The road in starts outside Thornford")
	_abilities()
	_map()
	_conversations()
	_opening_combat()
	for fork in ["crossingRoute","landingRoute"]:
		_route(fork)
	_choices()
	print("intro_journey_check: %d checks, %d failures; routes %s" % [checks,failures,route_totals])
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)

func _fresh(class_id := "warden") -> void:
	game.dialogue.close()
	game.archetype_id = class_id
	game.progression.level = 1
	game.progression.xp = 0
	game.progression.rested = 0
	game.world_state.flags.clear()
	game.world_state.examined.clear()
	game.world_state.puzzles.clear()
	game.world_state.collected.clear()
	game.interaction._examined_at.clear()
	game.loot.spawn_all()
	game.targeting.stop_attack()
	game.skills.all_spells = false
	game.skills.reset()
	game.builds.reset()
	game.inventory.reset()
	game.resources.reset()
	game.quests.start_new()
	game.action_bar.reset()
	game.player.dead = false
	game.player.ghost = false
	game.player.health = game.player.max_health

func _abilities() -> void:
	for class_id in DB.archetypes:
		_fresh(class_id)
		var archetype: Dictionary = game.stats.archetype
		check(game.action_bar.slots.slice(0,6).filter(func(a): return a != null).size() == 1,class_id+" begins with one core ability")
		for level in range(1,11):
			if level > 1:
				game.progression.add_xp(game.progression.xp_to_next-game.progression.xp)
			game.skills.flush_new_spells()
			for ability in archetype.coreLevels:
				check(game.skills.knows_ability(ability) == (int(archetype.coreLevels[ability])<=level),"%s unlocks %s correctly at %d" % [class_id,ability,level])
			check(game.action_bar.slots.slice(0,6).filter(func(a): return a != null).size() == mini(6,archetype.coreLevels.values().filter(func(l): return l<=level).size()),class_id+" fills free slots as lessons arrive")
		check(game.action_bar.slots.slice(0,6) == archetype.bar,class_id+" has the full core kit by level 10")
		_fresh(class_id)
		game.action_bar.apply(archetype.bar+[null,null])
		check(archetype.bar.all(func(a): return game.skills.knows_ability(a)),class_id+" retains an older saved full core bar")
	_fresh("wizard")
	game.progression.level = 10
	check(DB.builds.keyPassives.filter(func(p): return p.get("archetype")=="wizard").size() == 2,"Wizard has later passive choices")
	check(DB.abilities.firebolt.has("upgrades"),"Wizard can improve its first spell at level 10")
	check(game.builds.enhance("firebolt") and game.builds.points_free==0,"The first Wizard path point buys an actual spell improvement")
	check(game.builds.choose_passive("thermalScholar"),"The Wizard can choose a working level 10 passive")

func _map() -> void:
	check(DB.world.dungeonEntrances.size() <= 8,"Dungeon count remains capped at eight")
	var targets: Array = DB.world.npcSpawns.filter(func(n): return n.npc.begins_with("in_"))
	for spawn in targets:
		check(Terrain.walk_at(spawn.position[0],spawn.position[1]) >= 0.5,spawn.npc+" stands on walkable terrain")
		var actual = game.npcs.by_id(spawn.npc)
		check(actual != null,spawn.npc+" is spawned in the playable world")
	for pickup in DB.world.placedLoot:
		if pickup.id.begins_with("in_"):
			check(DB.items.has(pickup.reward.item),pickup.id+" has a real item")
			check(Terrain.walk_at(pickup.position[0],pickup.position[1])>=0.5,pickup.id+" lies on walkable terrain")
	for sign in Layout.signposts:
		if sign.id.begins_with("in_"):
			check(not Layout.signpost_lines(sign).is_empty(),sign.id+" has real destinations")
	for road in DB.world.roads:
		if not road.id.begins_with("in_"):
			continue
		for i in range(road.points.size()-1):
			var a := Vector2(road.points[i][0],road.points[i][1])
			var b := Vector2(road.points[i+1][0],road.points[i+1][1])
			for n in range(11):
				var at := a.lerp(b,n/10.0)
				check(Terrain.walkable(at.x,at.y),road.id+" has a continuous walkable road")
	for spawn in DB.world.enemySpawns:
		if spawn.id.begins_with("in_"):
			check(Terrain.walkable(spawn.position[0],spawn.position[1]),spawn.id+" stands on accessible ground")
	for npc_id in ["tf_elsie","tf_iren","vr_heda","vr_morrow","in_sella","in_edda"]:
		var at := Quests.npc_spot(npc_id)
		check(not DB.world.enemySpawns.any(func(e): return e.id.begins_with("in_") and Vector2(e.position[0],e.position[1]).distance_to(at)<12),npc_id+" has no new enemy at the service point")

func _conversations() -> void:
	_fresh()
	var q = game.quests
	check(q.status("ni_stretch_your_legs") == "active","The road in is in a fresh player's tracker")
	for id in ["ni_stretch_your_legs","ni_loose_boar","ni_the_road_in"]:
		q.done[id] = true
	q.accept("sf_odd_jobs", true)
	check(q.status("sf_odd_jobs") == "active","Elsie's opening job follows the road in")
	check(not q.objectives("sf_odd_jobs")[0].done,"The opening conversation is not completed merely by accepting")
	game.dialogue.open(game.npcs.by_id("tf_cook"))
	check(not q.objectives("sf_odd_jobs")[0].done,"The wrong resident does not count")
	game.dialogue.open(game.npcs.by_id("tf_iren"))
	check(q.objectives("sf_odd_jobs")[0].done,"The actual conversation counts")
	var saved: Dictionary = q.serialize()
	q.apply(saved,{})
	check(q.objectives("sf_odd_jobs")[0].done,"Conversation progress survives saving")
	q.done["in_crossing_timber"] = true
	q.accept("in_crossing_witnesses",true)
	game.dialogue.open(game.npcs.by_id("wm_lantern_crossing_worker"))
	var first: Array = q.objectives("in_crossing_witnesses")
	check(first.filter(func(o): return o.done).size() == 1,"Only the visited witness counts")
	game.dialogue.open(game.npcs.by_id("in_kit"))
	check(q.status("in_crossing_witnesses") == "ready","Both witnesses finish the conversation step")
	game.progression.level=5
	q.done.sf_calling_warden=true
	q.accept("sf_class_warden",true)
	q.count_use("cleave","vr_young_boar")
	var lesson: Dictionary=q.serialize()
	q.apply(lesson,{})
	check(q.objectives("sf_class_warden")[0].have==1,"Practical ability progress also survives saving")

func _route(fork: String) -> void:
	_fresh()
	var journey: Dictionary = DB.world.introJourney
	var path: Array = journey.opening+journey[fork]+journey.sharedFinale
	for id in path:
		_finish(id)
	check(game.progression.level == 10,fork+" reaches level 10 using only required kills and quests")
	check(game.quests.status("wm_rillbank_quays_work") == "available",fork+" opens the level 10 quay chapter")
	check(game.world_state.flags.has("in_intro_complete"),fork+" records the completed introduction")
	route_totals[fork] = {"level":game.progression.level,"xp":game.progression.xp}
	var state: Dictionary = game.quests.serialize()
	game.quests.reset()
	game.quests.apply(state,game.world_state.flags)
	check(game.quests.status("in_road_to_rillbank") == "done",fork+" retains the completed journey after loading")

func _finish(id: String) -> void:
	var q = game.quests
	var quest: Dictionary = DB.quests[id]
	if q.status(id) not in ["active","ready"]:
		check(q.status(id)=="available",id+" is naturally available at level %d" % game.progression.level)
		game.dialogue.open(game.npcs.by_id(quest.giver))
		check(q.accept(id,true),id+" can be accepted")
	if q.status(id) not in ["active","ready"]:
		return
	for objective in quest.objectives:
		match objective.type:
			"talk":
				game.dialogue.open(game.npcs.by_id(objective.target))
			"examine":
				game.interaction.examine(objective.target)
			"kill":
				var definition: Dictionary = DB.enemies[objective.target]
				for n in int(objective.get("count",1)):
					q.count_kill(objective.target)
					game.progression.add_xp(DB.kill_xp(Scaling.kill_xp_base(definition,definition.get("level",1)),game.progression.level,int(definition.get("level",1))),true)
			"collect":
				var needed: int = int(objective.get("count",1))-game.inventory.count(objective.target)
				if needed<=0:
					continue
				var nodes: Array = game.loot.active.filter(func(e): return e.def.get("quest")==id and e.def.get("reward",{}).get("item")==objective.target)
				if not nodes.is_empty():
					for node in nodes:
						if game.inventory.count(objective.target)>=int(objective.get("count",1)):
							break
						game.player.place_at(node.x,node.z+1)
						check(game.loot.start_gather(node),id+" has an available physical pickup")
						game.loot.update(2.0,0.0)
				else:
					check(objective.target in ["boar_meat","wild_garlic","firewood","trail_bread","tf_watch_token","vr_burial_roll","vr_named_token"] or not objective.target.begins_with("in_"),id+" has a pre-existing ordinary item source")
					game.inventory.add_item(objective.target,needed)
			"puzzle":
				var p := WorldPuzzles.definition(objective.target)
				check(not p.is_empty(),id+" has a placed puzzle")
				game.player.place_at(p.position[0],p.position[1])
				check(not game.puzzles.state(p.id).solved,"Reading a clue did not solve the sluice")
				for i in p.nodes.size():
					game.player.place_at(p.position[0]+p.nodes[i].offset[0],p.position[1]+p.nodes[i].offset[1])
					for n in int(p.answer[i]):
						game.puzzles.operate(p.id,i)
				game.player.place_at(p.position[0]+p.checkOffset[0],p.position[1]+p.checkOffset[1])
				check(game.puzzles.operate(p.id,"check"),"The sluice can be solved through normal nearby controls")
	q.refresh()
	check(q.status(id)=="ready",id+" reaches its hand-in state")
	game.dialogue.open(game.npcs.by_id(quest.turnIn))
	check(game.dialogue.choose("quest:"+id),id+" opens its hand-in page")
	check(game.dialogue.choose("complete") and q.status(id)=="done",id+" hands in through the actual dialogue button")
	var onward: Array=q.followups(id)
	if not onward.is_empty():
		check(game.dialogue.view.kind in ["quest","followups"],id+" presents the next step immediately")
	if id=="sf_a_meal_earned":
		check(game.skills.has("cooking") and game.cooking.knows("roast_boar"),"Supper teaches a useful everyday profession")

func _choices() -> void:
	_fresh()
	game.progression.level=2
	for id in ["ni_stretch_your_legs","ni_loose_boar","ni_the_road_in"]: game.quests.done[id]=true
	game.quests.done.sf_odd_jobs=true
	game.quests.done.vr_fence_dispute=true
	check(game.quests.accept("in_boundary_agreement",true),"A negotiated fence resolution is offered")
	check(game.quests.status("in_boundary_ruling")=="locked","The alternative fence resolution stays exclusive")
	game.quests.count_talk("vr_heda")
	game.quests.count_talk("vr_osric")
	check(game.quests.complete("in_boundary_agreement"),"A negotiated settlement can be handed in")
	check(game.world_state.flags.has("in_boundary_agreed"),"The villagers remember the local decision")

func _opening_combat() -> void:
	var original: Array = game.enemies.list
	var foe = original.filter(func(e): return e.type=="vr_young_boar")[0]
	game.enemies.list=[foe]
	for class_id in DB.archetypes:
		_fresh(class_id)
		game.recompute_max_health()
		game.player.health=game.player.max_health
		game.player.cooldowns=game.player.fresh_cooldowns()
		game.spells.reset()
		game.player.casting=null
		game.player.pending=null
		game.player.pending_off=null
		game.player.pending_shot=null
		foe.dead=false
		foe.health=foe.max_health
		foe.position=foe.home
		foe.state="idle"
		foe.engaged=0
		foe.since_struck=100
		foe.fled=false
		foe.flee_left=0
		foe.attack_timer=0.6
		foe.windup=0
		foe.casting=null
		foe.knock=Vector3.ZERO
		foe._reset_control()
		game.world_state.defeated.erase(foe.id)
		game.player.place_at(foe.home.x,foe.home.z+1.6)
		game.targeting.engage(foe)
		var elapsed := 0.0
		while not foe.dead and not game.player.dead and elapsed<60:
			var dt := 1.0/60.0
			game.time+=dt
			elapsed+=dt
			game.raw_aim=foe.position
			game.player.face_towards(foe.position.x,foe.position.z)
			game.spells.try_cast(game.stats.archetype.bar[0])
			var towards: Vector2=Vector2(foe.position.x-game.player.position.x,foe.position.z-game.player.position.z)
			var moving: Vector2=towards.normalized() if towards.length()>1.8 else Vector2.ZERO
			game.player.update(dt,{"move":{"x":moving.x,"z":moving.y},"aim":{"x":foe.position.x,"z":foe.position.z},"actions":{}})
			game.spells.update(dt)
			game.combat.update_arrows(dt)
			game.resources.update(dt)
			foe.update(dt,game.player)
			game.telegraphs.update(dt)
			game.targeting.update(dt,foe.position,DB.abilities.strike.range+1)
			game.fx.update(dt)
		check(foe.dead and not game.player.dead,class_id+" can win the opening boar fight with starting equipment and its first ability")
		check(game.player.health>game.player.max_health*0.45,class_id+" finishes its first fight with a forgiving health margin")
		print("INTRO COMBAT ",class_id," boar seconds=",snappedf(elapsed,0.1)," remaining=",snappedf(game.player.health/game.player.max_health*100,0.1),"%")
	game.enemies.list=original

extends SceneTree
## Exercise the real dialogue buttons, including the cook's meat hand-in.
var game
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING,"new")
	Store.dir="user://quest_followups_check_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made: Dictionary=game.roster.create("Followups","warden")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:
		await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.random=func(): return 0.5
	_cook_chain(true)
	_cook_chain(false)
	_full_tracker()
	_choices()
	_terminal_and_gates()
	if not OS.get_cmdline_user_args().is_empty():
		await _captures(OS.get_cmdline_user_args()[0])
	print("quest_followups_check: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)

func _fresh() -> void:
	game.dialogue.close()
	game.quests.reset()
	game.inventory.reset()
	game.progression.level=2
	game.progression.xp=0
	game.world_state.flags.clear()
	game.world_state.examined.clear()
	game.player.dead=false
	game.targeting.stop_attack()

func _talk(npc_id: String) -> void:
	var npc=game.npcs.by_id(npc_id)
	game.player.place_at(npc.position.x,npc.position.z+1.5)
	game.dialogue.open(npc)

func _hungry_work() -> void:
	game.quests.done.sf_odd_jobs=true
	_talk("tf_elsie")
	check(game.dialogue.choose("quest:sf_hungry_work"),"Elsie offers Hungry Work")
	check(game.dialogue.choose("accept"),"Hungry Work can be accepted normally")
	_talk("tf_cook")
	check(game.dialogue.choose("quest:sf_hungry_work"),"Hobb shows the first hand-in")
	check(game.dialogue.choose("complete"),"Hungry Work hands in with the normal button")
	check(game.dialogue.view=={"kind":"quest","id":"sf_a_meal_earned"},"The cook's meat quest opens automatically")
	check(game.dialogue.page.quest.status=="available","The next page shows the new offer")
	check(game.dialogue.page.options.any(func(o): return o.id=="accept"),"The new offer has an Accept button")
	check(not game.quests.accepted.has("sf_a_meal_earned"),"Opening the follow-up does not accept it for the player")
	check(game.hud.quests.dialogue.panel.visible,"The actual conversation panel is visible")

func _meal_supplies() -> void:
	game.inventory.add_item("firewood",3)
	game.inventory.add_item("wild_garlic",3)
	game.inventory.add_item("boar_meat",2)
	game.quests.refresh()

func _cook_chain(farm_done: bool) -> void:
	_fresh()
	if farm_done:
		game.quests.done.in_farm_introduction=true
		game.quests.done.vr_first_hunt=true
	_hungry_work()
	check(game.dialogue.choose("accept"),"The player accepts the cook's collection quest")
	_meal_supplies()
	_talk("tf_cook")
	game.dialogue.choose("quest:sf_a_meal_earned")
	check(game.dialogue.choose("complete"),"The meat and other supplies hand in normally")
	check(game.quests.status("sf_a_meal_earned")=="done","The cook's quest is recorded complete")
	check(game.inventory.count("boar_meat")==0,"The cook takes the requested meat")
	check(game.skills.has("cooking"),"The cooking lesson reward still works")
	check(game.dialogue.view=={"kind":"followups","id":"sf_a_meal_earned"},"The hand-in immediately opens onward directions")
	var expected := "in_watchmans_word" if farm_done else "in_farm_introduction"
	check(game.quests.followups("sf_a_meal_earned")[0]==expected,"The correct story step takes priority over optional fishing")
	check(game.quests.focus==expected,"The next giver is automatically followed")
	check(not game.quests.accepted.has(expected),"A remote quest is not accepted on behalf of its giver")
	var goal: Dictionary=game.quests.goal(expected)
	check(goal.get("npc")==DB.quests[expected].giver,"The lead points to the giver, rather than the quest's final destination")
	check(game.hud.quests.tracker.visible and game.hud.quests._way_text.contains(DB.npcs[DB.quests[expected].giver].name),"The tracker names and points to the next NPC")
	check(game.hud.minimap.markers().any(func(m): return m.kind=="goal" and m.focus and m.label==goal.label),"The minimap includes the next giver's waypoint")
	check(game.dialogue.page.options.any(func(o): return o.id=="next:"+expected),"The cook's onward page includes a named handoff")
	var saved: Dictionary=game.quests.serialize()
	game.quests.apply(saved,game.world_state.flags)
	check(game.quests.focus==expected,"The offered-quest waypoint survives saving and loading")
	check(game.dialogue.choose("next:"+expected) and not game.dialogue.is_open,"Following the handoff closes the old conversation")
	_talk(DB.quests[expected].giver)
	game.dialogue.choose("quest:"+expected)
	check(game.dialogue.choose("accept"),"The player can accept the next quest at its actual giver")
	check(game.quests.tracked.has(expected),"Accepting the lead turns it into a tracked quest")
	# A replayed completion cannot pay twice or change the onward page.
	var coins: int=game.inventory.coins
	check(not game.dialogue.choose("complete"),"An unfinished next quest cannot be completed by replaying the button")
	check(game.inventory.coins==coins,"A rejected completion grants no extra reward")

func _choices() -> void:
	_fresh()
	game.progression.level=5
	game.quests.done.in_burial_record=true
	game.quests.accept("vr_crypt",true)
	for objective in DB.quests.vr_crypt.objectives:
		if objective.type=="kill":
			for n in int(objective.get("count",1)):
				game.quests.count_kill(objective.target)
		elif objective.type=="collect":
			game.inventory.add_item(objective.target,int(objective.get("count",1)))
		elif objective.type=="examine":
			game.world_state.examined[objective.target]=true
	_talk("vr_mayor")
	game.dialogue.choose("quest:vr_crypt")
	check(game.dialogue.choose("complete"),"The burial chapter hands in")
	check(game.dialogue.view.kind=="followups","The two regional routes stay a choice")
	for id in ["in_letter_east","in_letter_west"]:
		check(game.dialogue.page.options.any(func(o): return o.id=="next:"+id),id+" is offered on the onward page")
	check(game.quests.chosen("in_first_road")=="","No regional route is chosen automatically")
	check(game.dialogue.choose("next:in_letter_west"),"The player can inspect the western route")
	check(game.quests.status("in_letter_east")=="available","Inspecting an offer does not lock the other route")
	check(game.dialogue.choose("accept"),"The selected route can be accepted")
	check(game.quests.status("in_letter_east")=="locked","Accepting the chosen route still locks its alternative")
	check(not game.quests.followups("vr_crypt").has("in_letter_east"),"A locked alternative is not offered again")

func _full_tracker() -> void:
	_fresh()
	for quest in DB.quests.values():
		if quest.get("map", "act1")!="new" or quest.id in ["sf_odd_jobs","sf_hungry_work","sf_a_meal_earned"]:
			continue
		game.quests.accepted.append(quest.id)
		game.quests.tracked[quest.id]=true
		if game.quests.tracked.size()==Quests.MAX_TRACKED:
			break
	var old: String=game.quests.tracked.keys()[0]
	_hungry_work()
	check(game.dialogue.choose("accept"),"A follow-up can be accepted with a full tracker")
	check(game.quests.tracked.size()==Quests.MAX_TRACKED,"Following a new quest respects the tracker limit")
	check(game.quests.tracked.has("sf_a_meal_earned"),"The accepted follow-up remains visible in the full tracker")
	check(game.quests.active.has(old),"Replacing a tracker entry does not abandon the older quest")

func _terminal_and_gates() -> void:
	_fresh()
	game.quests.done.in_testimony=true
	# The road quest has no minimum-level gate; do not invent one for this test.
	var original: Dictionary=DB.quests.in_road_to_rillbank.duplicate(true)
	DB.quests.in_road_to_rillbank.minLevel=10
	check(not game.quests.followups("in_testimony").has("in_road_to_rillbank"),"Level-locked follow-ups stay unavailable")
	DB.quests.in_road_to_rillbank=original
	check(not game.quests.followups("tf_lanterns").has("sf_calling_wizard"),"Another class's lesson is not offered")
	game.quests.set_focus("not_a_quest")
	check(game.quests.focus=="","Unknown quest IDs cannot become waypoints")
	game.quests.set_focus("in_foreman")
	check(game.quests.focus=="","Locked quests cannot become waypoints")
	_talk("tf_cook")
	game.quests.accepted.append("sf_a_meal_earned")
	game.dialogue.choose("quest:sf_a_meal_earned")
	check(not game.dialogue.choose("complete"),"An incomplete meat collection does not advance the dialogue")
	check(game.dialogue.view=={"kind":"quest","id":"sf_a_meal_earned"},"A failed hand-in stays on the original quest page")

func _captures(out: String) -> void:
	_fresh()
	game.hud.items.close_all()
	game.quests.done.in_farm_introduction=true
	game.quests.done.vr_first_hunt=true
	_hungry_work()
	game._snap_camera()
	for frame in 6:
		game.hud.update(1.0/60.0)
		await process_frame
	check(game.hud.quests.dialogue.panel.modulate.a>0.99,"The next offer is visibly rendered after the window settles")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("cook-next-offer.png"))
	game.dialogue.choose("accept")
	_meal_supplies()
	game.dialogue.choose("quest:sf_a_meal_earned")
	game.dialogue.choose("complete")
	for frame in 6:
		game.hud.update(1.0/60.0)
		await process_frame
	check(game.hud.quests.dialogue.panel.modulate.a>0.99,"The onward handoff is visibly rendered after the window settles")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("cook-onward-handoff.png"))

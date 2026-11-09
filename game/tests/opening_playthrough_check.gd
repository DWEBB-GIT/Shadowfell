extends SceneTree
## Physically walk the repaired opening, use its interaction and dialogue
## paths, then verify independent jobs and the later chain requirements.
var game
var failures := 0
var checks := 0
func check(ok, text):
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ",text)
func _initialize(): _run.call_deferred()
func _run():
	Store.dir="user://opening_playthrough_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made=game.roster.create("Opening", "warden")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible: await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.random=func():return 0.5
	check(Terrain.walkable(game.player.position.x,game.player.position.z),"New character stands on walkable dry land")
	check(game.quests.goal("ni_stretch_your_legs").get("npc")=="ni_abel","First objective guides player to Abel")
	walk(-622,-179,2.0)
	check(game.interaction.interact(),"F reaches Abel from the road")
	check(game.dialogue.npc != null and game.dialogue.npc.id=="ni_abel","First conversation is with Abel")
	game.dialogue.close()
	check(game.quests.objectives("ni_stretch_your_legs")[0].done,"Talking to Abel counts through normal interaction")
	walk(-594,-191,1.8)
	check(game.interaction.interact(),"F reads the physical milestone")
	check(game.quests.status("ni_stretch_your_legs")=="ready","Milestone finishes first quest objectives")
	walk(-622,-179,2.0)
	game.interaction.interact()
	game.dialogue.choose("quest:ni_stretch_your_legs")
	game.dialogue.choose("complete")
	check(game.quests.status("ni_stretch_your_legs")=="done","First quest hands in normally")
	check(game.dialogue.view.get("id")=="ni_loose_boar","Boar follow-up opens immediately")
	game.dialogue.choose("accept")
	game.dialogue.close()
	var boar=game.enemies.list.filter(func(e):return e.type=="ni_loose_boar")[0]
	walk(boar.position.x,boar.position.z,1.6)
	fight(boar)
	# its meat falls as loot; picked up (or handed over here) it ends the quest
	if game.inventory.count("boar_meat")==0:
		check(game.quests.status("ni_loose_boar")=="active","Boar kill alone does not finish the quest")
		game.inventory.add_item("boar_meat",1)
	check(game.quests.status("ni_loose_boar")=="ready","Carrying the boar meat finishes the boar quest")
	walk(-622,-179,2.0)
	game.interaction.interact()
	game.dialogue.choose("quest:ni_loose_boar")
	game.dialogue.choose("complete")
	check(game.inventory.count("boar_meat")>=1,"Abel lets you keep the boar meat")
	check(game.dialogue.view.get("id")=="ni_the_road_in","Letter quest follows boar hand-in")
	game.dialogue.choose("accept")
	game.dialogue.close()
	var approach=DB.world.roads.filter(func(r):return r.id=="ni_west_road")[0]
	for at in approach.points.slice(1)+[[-477,-204]]:
		walk(at[0],at[1],1.2)
	# The visible centreline must clear water and solid scenery, not merely
	# have a positive terrain walk mask under a pond.
	for i in range(approach.points.size()-1):
		var a=Vector2(approach.points[i][0],approach.points[i][1])
		var b=Vector2(approach.points[i+1][0],approach.points[i+1][1])
		check(not game.collision.blocked_between(a.x,a.y,b.x,b.y,game.player.radius),"Visible approach segment clears physical obstacles")
		var steps=ceili(a.distance_to(b))
		for j in range(steps+1):
			var sample=a.lerp(b,float(j)/steps)
			check(Terrain.walkable(sample.x,sample.y),"Visible approach stays on dry walkable ground")
	# Enter the pool bypass from several offsets: a tangent that works only
	# from one exact point is not a reliable starting route.
	var arrived: Vector3=game.player.position
	for offset in [-0.8,0.0,0.8]:
		game.player.place_at(approach.points[3][0],approach.points[3][1]+offset)
		for at in approach.points.slice(4):walk(at[0],at[1],0.65)
	game.player.place_at(arrived.x,arrived.z)
	print("TRIAL arrived at Thornford ",game.player.position," health=",game.player.health,"/",game.player.max_health)
	# Approach the visible south entrance, rather than walking through inn walls.
	for at in [[-477,-193],[-465,-193],[-465,-202],[-461,-205]]:
		walk(at[0],at[1],1.5)
	game.interaction.interact()
	check(game.dialogue.npc != null and game.dialogue.npc.id=="tf_elsie","Player can reach Elsie at the inn")
	if game.dialogue.npc != null and game.dialogue.npc.id=="tf_elsie":
		game.dialogue.choose("quest:ni_the_road_in")
		game.dialogue.choose("complete")
		check(game.quests.status("ni_the_road_in")=="done","Letter reaches Elsie normally")
		check(game.dialogue.view.get("id")=="sf_odd_jobs","Elsie offers the hinge job immediately")
	game.dialogue.close()
	_skip_and_gates()
	_combat_feedback()
	if OS.get_cmdline_user_args().size()>0:
		game.player.place_at(-617,-182)
		game._snap_camera()
		game.set_process(true)
		for i in 80: await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	print("opening_playthrough_check: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
func walk(x,z,reach):
	var before: Vector3=game.player.position
	game.move_to={"x":x,"z":z,"reach":reach}
	for i in 2400:
		var direction=game._click_move({"x":0.0,"z":0.0},1.0/60)
		if direction==null: break
		game.player.update(1.0/60,{"move":direction,"actions":{}})
	var d=Vector2(game.player.position.x-x,game.player.position.z-z).length()
	check(d<=reach+0.15,"Walk from %s to [%s,%s] reaches destination (remaining %.2f)" % [before,x,z,d])
	check(Terrain.walkable(game.player.position.x,game.player.position.z),"Every destination is walkable")
	game.move_to=null
func fight(foe):
	game.targeting.engage(foe)
	var dt=1.0/60
	var seconds=0.0
	while not foe.dead and not game.player.dead and seconds<50:
		seconds+=dt;game.time+=dt
		game.raw_aim=foe.position
		game.player.face_towards(foe.position.x,foe.position.z)
		game.spells.try_cast(game.stats.archetype.bar[0])
		game.player.update(dt,{"move":{"x":0.0,"z":0.0},"aim":{"x":foe.position.x,"z":foe.position.z},"actions":{}})
		game.spells.update(dt);game.combat.update_arrows(dt);game.resources.update(dt)
		foe.update(dt,game.player);game.telegraphs.update(dt)
		game.targeting.update(dt,foe.position,DB.abilities.strike.range+1)
		game.fx.update(dt)
	check(foe.dead and not game.player.dead,"Fresh starter beats "+foe.cfg.name)
	print("TRIAL fight ",foe.type," seconds=",snappedf(seconds,0.1)," remaining=",game.player.health)
	game.targeting.stop_attack()
func _skip_and_gates():
	game.quests.start_new()
	check(game.quests.status("sf_odd_jobs")=="available","Walking past the cart does not lock village work")
	check(game.quests.status("ni_loose_boar")=="locked","Skipping the milestone does not silently finish the boar chain")
	game.quests.done.sf_odd_jobs=true
	check(game.quests.status("sf_borrowed_rod")=="available","Fishing opens without hunting or cooking")
	check(game.quests.status("sf_a_meal_earned")=="locked","Cook's actual chain still requires meeting Hobb")
	game.quests.done.vr_first_hunt=true
	check(game.quests.status("in_watchmans_word")=="available","Heda's watch lead does not require cooking")
	game.quests.start_new()
	game.progression.level=2
	check(game.quests.status("tf_lanterns")=="available","Level-two explorer can take Rowan's work directly")
	check(game.quests.status("in_lost_courier")=="locked","Later story quests still require their own preceding chapter")
	check(game.quests.followups("ni_the_road_in").has("sf_odd_jobs"),"Independent village entry retains the letter handoff")
	check(game.quests.followups("in_watchmans_word").has("tf_lanterns"),"Independent watch entry retains Heda's handoff")
	# Exercise both actual input schemes; hardcoded F was incorrect in mouse aim.
	for aim in [true,false]:
		game.keys.load_scheme(aim)
		game.world_state.examined.erase("poi:ni_milestone")
		game.dialogue.close();game.quests.start_new();game.player.place_at(-620,-179)
		var event=InputEventKey.new()
		event.physical_keycode=KEY_G if aim else KEY_F
		event.pressed=true;game.input._input(event)
		game._handle_input(1.0/60)
		event.pressed=false;game.input._input(event)
		check(game.dialogue.npc!=null and game.dialogue.npc.id=="ni_abel","Mapped interaction key opens Abel in "+("mouse aim" if aim else "classic"))
		game.dialogue.choose("quest:ni_stretch_your_legs")
		check(game.dialogue.page.text.contains("Press "+("G" if aim else "F")) and not game.dialogue.page.text.contains("{interact}"),"Quest instructions show the actual scheme's interaction key")
	game.keys.load_scheme(true)
	game.keys.bind("interact","KeyZ")
	check(game.quests.wording("Press {interact}")=="Press Z","Rebound keys update quest instructions")
	game.keys.reset_all();game.dialogue.close()
func _combat_feedback():
	var foe=game.enemies.list.filter(func(e):return e.type=="vr_young_boar")[0]
	game.player.place_at(foe.position.x,foe.position.z+1.5)
	game.targeting.engage(foe)
	var before=foe.health
	var wall=game.collision.add(foe.position.x,foe.position.z+0.75,0.45,true)
	game.combat.resolve_player_strike(foe.position)
	check(foe.health==before,"A wall stops the player's melee hit")
	var hp=game.player.health
	game.combat.resolve_enemy_strike(foe)
	check(game.player.health==hp,"A wall stops an enemy's melee hit")
	wall.off=true
	game.targeting.stop_attack()

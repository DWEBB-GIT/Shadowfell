extends SceneTree
## Isolated peaceful livelihood, authored discoveries, save and combat tests.
var game
var failures:=0
var checks:=0
func _initialize(): _run.call_deferred()
func check(ok,text):
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",text)
func _run():
	Store.dir="user://district_life_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate();root.add_child(game)
	await process_frame
	var made=game.roster.create("Riverworker","warden")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible: await process_frame
	game.save.autosave_enabled=false;game.set_process(false)
	game.random=func():return 0.2
	# Walk past the cart without completing or falsifying its tutorial chain.
	talk("tf_elsie",-461,-205)
	check(game.quests.status("sf_odd_jobs")=="available","Village employment is available without Abel's combat chain")
	game.dialogue.choose("quest:sf_odd_jobs");game.dialogue.choose("accept")
	talk("tf_iren",-435,-199)
	game.dialogue.choose("quest:sf_odd_jobs");game.dialogue.choose("complete")
	check(game.inventory.tool_pack!=null,"Peaceful hinge delivery earns the tool belt")
	game.dialogue.close()
	check(game.quests.abandon("ni_stretch_your_legs"),"Optional auto-started tutorial can be abandoned and revisited")
	check(game.quests.status("ni_stretch_your_legs")=="available","Abandoning does not complete or erase the first quest")
	talk("vr_tobin",-396,-170)
	game.dialogue.choose("quest:sf_borrowed_rod");game.dialogue.choose("accept");game.dialogue.close()
	check(game.fishing.has_rod and game.skills.has("fishing"),"Tobin's real offer supplies usable tackle and Fishing")
	game.random=func():return 0.99
	check(catch_one(),"Correct first fishing strike succeeds even with an otherwise unlucky roll")
	check(game.inventory.count("gloomwater_perch")==1,"The first lesson catches its requested perch")
	talk("vr_tobin",-396,-170)
	game.dialogue.choose("quest:sf_borrowed_rod");game.dialogue.choose("complete")
	check(game.quests.status("sf_borrowed_rod")=="done","Fishing lesson hands in without hunting or cooking")
	var tobin=game.npcs.by_id("vr_tobin")
	game.merchant.open(DB.npcs.vr_tobin.shop,tobin)
	check(game.merchant.buy("fishing_rod"),"A peaceful worker can afford a permanent rod from the real vendor")
	check(game.fishing.has_rod,"Bought rod is usable on the belt")
	game.merchant.close();game.dialogue.close()
	talk("tf_cook",-466.5,-209.5)
	check(game.quests.status("in_pond_to_pot")=="available","Hobb's peaceful cooking order follows the fishing lesson")
	game.dialogue.choose("quest:in_pond_to_pot");game.dialogue.choose("accept");game.dialogue.close()
	check(game.skills.has("cooking"),"Hobb teaches basic Cooking when the lesson is accepted")
	game.random=func():return 0.2
	for i in 15:
		if game.inventory.count("gloomwater_perch")>=4: break
		catch_one()
	check(game.inventory.count("gloomwater_perch")>=4,"Ordinary fishing provides the order and a meal for the worker")
	game.player.place_at(-468.8,-206.5)
	game.player.moving=false
	check(game.cooking.start("grilled_perch",4),"Real hearth crafting can start from caught fish")
	for i in 3600:
		game.cooking.update(1.0/60)
		if game.cooking.crafting==null:break
	check(game.inventory.count("grilled_perch")==4,"Cooking consumes fish and makes four real meals")
	talk("tf_cook",-466.5,-209.5)
	var paid_before=game.inventory.coins
	game.dialogue.choose("quest:in_pond_to_pot");game.dialogue.choose("complete")
	check(game.quests.status("in_pond_to_pot")=="done","Cooked meals finish the actual order")
	check(game.inventory.coins==paid_before+12,"The finite lunch order pays its stated wage")
	check(not game.quests.complete("in_pond_to_pot") and game.inventory.coins==paid_before+12,"Completed order cannot be paid twice")
	check(not game.quests.done.has("ni_loose_boar") and not game.quests.done.has("vr_first_hunt") and not game.quests.done.has("sf_a_meal_earned"),"Livelihood loop does not secretly complete combat quests")
	game.dialogue.close()
	game.player.health=game.player.max_health-30
	game.resources.since_combat=100
	var meal=game.inventory._find("grilled_perch")
	check(meal!=null and game.cooking.eat(meal),"A leftover crafted meal can be eaten")
	for i in 960:game.cooking.update(1.0/60)
	check(game.player.health==game.player.max_health,"Own cooked food restores health between outings")
	await capture("pond",-396,-170)
	_discoveries()
	await capture("bell-garden",-421,-209)
	_feedback()
	await capture_combat()
	print("district_life_check: %d checks, %d failures" % [checks,failures])
	game.queue_free();await process_frame;quit(1 if failures else 0)
func talk(id,x,z):
	game.player.place_at(x,z);game.npcs.talk(game.npcs.by_id(id))
func catch_one():
	game.player.place_at(-396,-170);game.player.moving=false
	if not game.fishing.cast(Vector3(-389,Terrain.height_at(-389,-171),-171)):
		printerr("FISH_CAST_FAILED pending=",game.player.pending," casting=",game.player.casting," facing=",game.player.facing)
		return false
	for i in 900:
		game.fishing.update(1.0/60)
		if game.fishing.biting:break
	if not game.fishing.biting:return false
	var before=game.inventory.count("gloomwater_perch")
	game.fishing.strike()
	for i in 60:game.fishing.update(1.0/60)
	return game.inventory.count("gloomwater_perch")>before
func chest(id):return game.chests.list.filter(func(c):return c.def.id==id)[0]
func _discoveries():
	for id in ["in_road_reserve","in_fishers_cache"]:
		var c=chest(id)
		game.player.place_at(c.x,c.z+1.3)
		check(Terrain.walkable(c.x,c.z),id+" is on dry traversable ground")
		game.interaction.update(true)
		check(game.interaction.current!=null and game.interaction.current.key=="chest:"+id,id+" has a reachable normal interaction")
		game.interaction.interact()
		check(game.chests.opened(c),id+" opens and records its real loot")
		var coins=game.inventory.coins
		check(not game.chests.open(c) and game.inventory.coins==coins,id+" cannot be looted twice")
	var c=chest("in_avel_casket")
	var p=WorldPuzzles.definition("in_avel_bells")
	game.player.place_at(c.x,c.z+1)
	check(not game.chests.open(c),"Garden casket cannot open before the mechanism is solved")
	game.interaction.examine("poi:in_avel_garden")
	check(not game.puzzles.solved("in_avel_bells"),"Reading the clue does not substitute for solving the puzzle")
	game.player.place_at(p.position[0]-2.6,p.position[1]+0.8)
	check(not game.puzzles.operate("in_avel_bells",0),"A wrong first bell gives a safe retry")
	check(game.puzzles.state("in_avel_bells").progress==0,"Wrong notes reset the sequence without a penalty")
	for i in [2,0,1]:
		var at=Vector2(p.position[0]+p.nodes[i].offset[0],p.position[1]+p.nodes[i].offset[1])
		game.player.place_at(at.x,at.y+0.8)
		check(Terrain.walkable(at.x,at.y),"Each bell stands on reachable ground")
		game.interaction.update(true)
		check(game.interaction.current!=null and game.interaction.current.key=="puzzle:in_avel_bells:%d"%i,"F finds the intended bell")
		game.interaction.interact()
	check(game.puzzles.solved("in_avel_bells"),"Operating Bridge, Hearth, Watch solves the verse physically")
	game.player.place_at(c.x,c.z+1)
	check(game.chests.open(c),"Solving the bells unlocks their casket")
	var saved=game.save.serialize()
	check(saved.world.puzzles.in_avel_bells.solved,"Puzzle solution is included in character persistence")
	var remembered=game.world_state.serialize()
	game.world_state.reset();game.world_state.apply(remembered)
	check(game.puzzles.solved("in_avel_bells") and game.chests.opened(c),"Puzzle and unique rewards survive state restoration")
	check(not game.chests.open(c),"Restoring a save cannot duplicate the casket reward")
func _feedback():
	var e=game.enemies.list.filter(func(foe):return foe.type=="vr_young_boar")[0]
	game.player.place_at(e.position.x,e.position.z+1.6)
	game.targeting.select(e)
	var n=game.fx.items.filter(func(i):return i.tag=="HitContact").size()
	game.events.emit("enemyHit",{"enemy":e,"damage":5,"kind":"strike","periodic":true})
	check(game.fx.items.filter(func(i):return i.tag=="HitContact").size()==n,"Periodic damage does not replay a weapon contact flash")
	game.events.emit("enemyHit",{"enemy":e,"damage":5,"kind":"strike","hand":"main"})
	check(game.fx.items.filter(func(i):return i.tag=="HitContact").size()>n,"An actual weapon hit creates a visible contact effect")
	game.archetype_id="wizard";game.skills.reset();game.resources.reset();game.spells.reset()
	game.player.cooldowns=game.player.fresh_cooldowns();game.player.casting=null;game.player.pending=null
	game.player.face_towards(e.position.x,e.position.z)
	var wall=game.collision.add(e.position.x,e.position.z+0.8,0.4,true)
	var mana=game.resources.mana
	check(not game.spells.try_cast("firebolt"),"Targeted spells cannot start through a wall")
	check(game.resources.mana==mana,"A blocked spell does not spend mana")
	wall.off=true
	check(game.spells.try_cast("firebolt"),"The same spell can start with a clear line of sight")
	wall.off=false;game.spells.update(0.01)
	check(game.player.casting==null and game.resources.mana==mana,"Moving behind cover interrupts a cast without spending its release cost")
	wall.off=true
	game.targeting.clear()
	var boar=game.enemies.list.filter(func(foe):return foe.type=="ni_loose_boar")[0]
	game.player.place_at(boar.position.x,boar.position.z+2)
	var health=game.player.health
	boar._start_cast("special",game.player)
	check(boar.casting!=null,"First boar produces an actual ground telegraph")
	game.player.place_at(boar.position.x,boar.position.z-2)
	game.telegraphs.update(1.3)
	check(game.player.health==health,"Stepping behind the committed Tusk Sweep avoids its damage")
func capture(label,x,z):
	if OS.get_cmdline_user_args().is_empty():return
	game.hud.items.close_all()
	# The fixture compresses several errands into one frame. Let their normal
	# UI timers expire before judging scenery rather than photographing a queue.
	for i in 12:game.hud.update(6.0)
	game.player.place_at(x,z);game._snap_camera();game.set_process(true)
	for i in 100:await process_frame
	game.set_process(false)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("district-"+label+".png"))
func capture_combat():
	if OS.get_cmdline_user_args().is_empty():return
	var boar=game.enemies.list.filter(func(e):return e.type=="ni_loose_boar")[0]
	game.player.hold_rod(false)
	await capture("cart-road",-617,-182)
	game.player.place_at(boar.position.x,boar.position.z+2)
	game.player.face_towards(boar.position.x,boar.position.z)
	game._snap_camera()
	boar._start_cast("special",game.player)
	game.telegraphs.update(0.6);boar.rig.update(0.6,0)
	game.targeting.select(boar);game.hud.update(0)
	await process_frame;await RenderingServer.frame_post_draw
	var out=OS.get_cmdline_user_args()[0]
	root.get_texture().get_image().save_png(out.path_join("district-boar-telegraph.png"))
	game.events.emit("enemyHit",{"enemy":boar,"damage":5,"crit":true,"kind":"strike","hand":"main"})
	game.hud.update(0)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join("district-contact.png"))

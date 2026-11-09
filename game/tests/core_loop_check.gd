extends SceneTree
var game
var checks:=0
var failures:=0
var output:=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func place(x:float,z:float) -> void:
	game.player.place_at(x,z)
	game.player.moving=false
	game.player.rig.action=null
	game.player.rig.off_action=null
	game.player.rig.pose=null
	game.player.rig.held=0
func bag(item:String) -> String:
	for loc in game.inventory.bag_locations():
		var stack=game.inventory.get_at(loc)
		if stack!=null and stack.id==item:return loc
	return ""
func possessions() -> String:
	var inv:Dictionary=game.inventory.serialize()
	var totals:Dictionary={}
	var stacks:Array=inv.bank.duplicate()
	stacks.append_array(inv.equipment.values())
	for socket in inv.sockets:
		if socket!=null:stacks.append_array(socket.slots)
	for stack in stacks:
		if stack==null:continue
		var identity:Dictionary=stack.duplicate(true)
		identity.erase("count")
		var key:=JSON.stringify(identity,"",true)
		totals[key]=totals.get(key,0)+int(stack.count)
	return JSON.stringify({"coins":inv.coins,"items":totals},"",true)
func picture(label:String) -> void:
	if output=="":return
	game._snap_camera()
	for i in 12:
		game.world.update(0,game.time)
		await process_frame
	game.hud.update(0.016)
	for i in 5:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		output=OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://core_loop_check_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made:Dictionary=game.roster.create("Loopcheck","rogue")
	game.enter_world(made.character.id)
	while not game.started or game.hud.blocks_gameplay:await process_frame
	game.set_process(false)
	game.save.autosave_enabled=false
	game.random=func():return 0.5
	await _daggers()
	_resource_placements()
	_prompt()
	game.inventory.add_coins(1000)
	check(game.skills.offered_by("vr_morrow").any(func(s):return s.id=="herbalism"),"current herbalism teacher offers the skill")
	check(game.skills.learn("herbalism"),"Herbalism can be learned")
	var herbs:Array=game.gathering.live().filter(func(n):return n.n.kind=="ditchbell")
	check(herbs.size()>=2,"novice herbs are live on the current map")
	for v in herbs.slice(0,2):
		place(v.x+1.3,v.z)
		var before:int=game.inventory.count("ditchbell")
		check(game.gathering.start(v.n),"a nearby novice herb can be gathered")
		game.gathering.update(3,game.time)
		check(game.inventory.count("ditchbell")>before,"gathering awards its real herb")
	check(game.gathering.regrow.size()==2,"gathered herbs enter regrowth")
	game.gathering.update(0,game.time+1000)
	check(game.gathering.live().size()==8,"gathering replenishes the authored population")
	check(game.skills.learn("alchemy"),"Alchemy can be learned")
	var bench:Array=Layout.stations.filter(func(s):return s.kind=="alchemy")
	check(bench.size()>0,"current map has an alchemy bench")
	if not bench.is_empty():
		place(bench[0].position[0]+1.4,bench[0].position[1])
		check(game.cooking.near_station("alchemy")!="","alchemy bench is usable from beside it")
		var before:int=game.inventory.count("healing_draught")
		check(game.cooking.start("brew_healing_draught"),"gathered herbs start a draught at the bench")
		game.cooking.update(10)
		check(game.inventory.count("healing_draught")==before+1,"brewing produces a draught")
		game.resources.since_combat=INF
		game.resources.engaged=false
		game.player.health=game.player.max_health*0.5
		var health:float=game.player.health
		game.player.cooldowns.draught=0
		check(game.inventory.use(bag("healing_draught")) and game.player.health>health,"a crafted draught restores health")
		await picture("alchemy-loop")
	check(game.skills.learn("mining"),"Iren's Mining skill can be learned")
	game.inventory.add_item("mining_pick",1,true)
	var veins:Array=game.mining.veins().filter(func(v):return v.rank==1)
	check(veins.size()>0,"novice copper veins are live")
	if not veins.is_empty():
		var v:Dictionary=veins[0]
		place(v.x+1.4,v.z)
		check(game.mining.pick!=null,"a carried mining pick is on the tool belt")
		check(game.mining.start(v.o),"a novice vein can be mined")
		for i in 8:game.mining.update(3,game.time+i*3)
		check(game.inventory.count("copper_ore")>0,"mining yields actual copper ore")
		check(game.mining.regrow.size()>0,"mined-out veins enter regrowth")
		var forge:Dictionary=Layout.stations.filter(func(s):return s.kind=="forge")[0]
		place(forge.position[0]+1.5,forge.position[1])
		var recipe:Dictionary=DB.recipes.smelt_copper
		var before:int=game.inventory.count(recipe.output.item)
		check(game.cooking.start("smelt_copper"),"mined ore can be smelted at Iren's forge")
		game.cooking.update(10)
		check(game.inventory.count(recipe.output.item)==before+1,"smelting produces a copper bar")
		await picture("mining-smelting-loop")
	_fishing()
	for skill in ["fishing","herbalism","alchemy"]:
		game.skills.ranks[skill]=10
		check(game.skills.next_rank(skill).trainer in ["vr_tobin","vr_morrow"],skill+" rank lesson belongs to a current teacher")
		check(game.skills.rank_blocked(skill)=="",skill+" is not blocked by an inaccessible old-map quest")
		check(game.skills.train_rank(skill) and game.skills.cap(skill)==20,skill+" can progress beyond novice")
	var markers:Array=game.hud.minimap.markers()
	check(markers.any(func(m):return m.kind=="vein") and markers.any(func(m):return m.kind=="herb"),"learned gathering skills expose resource markers on the minimap")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(game.save.serialize()))
	var errors:Array=SaveManager.validate_save(saved)
	check(errors.is_empty(),"core-loop progress is a valid save: "+str(errors))
	var before_inventory:String=possessions()
	game.save.apply(saved)
	check(possessions()==before_inventory,"crafted and gathered possessions survive loading and tool-belt migration")
	for skill in ["fishing","herbalism","alchemy"]:check(game.skills.cap(skill)==20,skill+" rank upgrade survives loading")
	print("core_loop_check: %d checks, %d failures"%[checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)
func _daggers() -> void:
	for sex in ["male","female"]:
		var look:=ForgeCharacter.defaults()
		look.sex=sex
		game.player.set_appearance(look)
		game.player.draw_weapons("melee")
		var rig=game.player.rig
		for type in ["strike","diagonal","rip","scissor"]:
			rig.play(type,0.8,0.4)
			rig.update(0.32,0)
			check(rig.last_action_clip.begins_with("Sword_"),sex+" dagger "+type+" uses a slash")
			if type=="strike":await _dagger_picture(sex+"-dagger-slash")
		for type in ["jab","thrust","upstab"]:
			rig.play(type,0.8,0.4)
			rig.update(0.32,0)
			check(rig.last_action_clip=="Dagger_Stab",sex+" explicit "+type+" uses the dagger stab")
			if type=="thrust":await _dagger_picture(sex+"-dagger-thrust")
		rig.play_off(0.8,0.4)
		rig.update(0.32,0)
		check(rig.last_off_clip=="Sword_Attack",sex+" normal off-hand dagger attack slashes")
		check(rig.resolve_action("scissor")=="Sword_Regular_Combo" and rig.resolve_action("rip")=="Sword_Regular_B",sex+" slash abilities retain distinct clips")
	game.player.rig.action=null
	game.player.rig.off_action=null
func _dagger_picture(label:String) -> void:
	if output=="":return
	game.camera.position=game.player.position+Vector3(3.2,2.4,4.4)
	game.camera.look_at(game.player.position+Vector3.UP*1.2)
	game.hud.root.visible=false
	for i in 4:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	game.hud.root.visible=true
func _resource_placements() -> void:
	for g in DB.nodes.nodeGroups:
		for p in g.spots:
			check(Terrain.walkable(p[0],p[1]),g.id+" herb stands on dry walkable ground "+str(p))
			check(_approachable(p),g.id+" herb has an unobstructed interaction position "+str(p))
	for g in DB.mining.veinGroups:
		for p in g.outcrops:
			check(Terrain.walkable(p[0],p[1]),g.id+" outcrop stands on dry walkable ground "+str(p))
			check(_approachable(p),g.id+" outcrop has an unobstructed interaction position "+str(p))
	check(DB.nodes.nodeGroups.all(func(g):return g.id.begins_with("tf_") or g.id.begins_with("vr_")),"new map does not inherit retired herb placements")
func _approachable(p:Array) -> bool:
	for i in 8:
		var at:=Vector2(p[0],p[1])+Vector2.from_angle(i*TAU/8)*1.8
		if not Terrain.walkable(at.x,at.y):continue
		var position_:=Vector3(at.x,Terrain.height_at(at.x,at.y),at.y)
		var resolved:Vector3=game.collision.resolve(position_,game.player.radius)
		if Vector2(resolved.x-at.x,resolved.z-at.y).length()<0.05:return true
	return false
func _prompt() -> void:
	place(-620,-179)
	game.dialogue.close()
	game.hud.modal=null
	game.interaction.update(true)
	game.hud.update(0.016)
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	game.input.mouse.clicked=true
	game.move_to={"x":-610,"z":-179,"reach":0.2}
	check(game.hud.prompt.visible and game.hud.over_hud(game.hud.prompt.get_global_rect().get_center()),"visible interaction prompt blocks world clicks")
	game.hud.prompt.gui_input.emit(event)
	check(game.dialogue.npc!=null and game.dialogue.npc.id=="ni_abel","clicking the prompt talks to the nearby carrier")
	check(game.move_to==null and not game.input.consume_click(),"prompt consumes the click without walking behind it")
	game.dialogue.close()
func _fishing() -> void:
	game.quests.done.sf_odd_jobs=true
	check(game.quests.accept("sf_borrowed_rod",true),"Tobin's current fishing lesson can be accepted")
	check(game.skills.has("fishing") and game.fishing.has_rod,"lesson supplies its skill and tool-belt rod")
	place(-393,-171)
	check(game.fishing.cast(Vector3(-388,Terrain.height_at(-388,-171),-171)),"Willow Pond accepts a cast from the shore")
	for i in 200:
		if game.fishing.state==null or game.fishing.state.phase=="bite":break
		game.fishing.update(0.1)
	check(game.fishing.state!=null and game.fishing.state.phase=="bite","the first lesson produces a readable bite window")
	if game.fishing.state!=null:
		check(game.fishing.strike(),"a timely strike succeeds")
		check(game.inventory.count("gloomwater_perch")>0,"fishing awards the actual quest fish")
		game.fishing.update(3)
	check(game.quests.status("sf_borrowed_rod")=="ready","caught fish advances the current quest")

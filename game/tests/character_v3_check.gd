extends SceneTree
var game
var foe
var checks:=0
var failures:=0
var arrows:Array=[]
func _initialize() -> void:_run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func clear_combat() -> void:
	game.enemies.reset_engaged()
	game.resources.since_combat=INF
	game.resources.engaged=false
	game.targeting.stop_attack()
	game.spells.reset()
	game.player.pending=null
	game.player.pending_off=null
	game.player.pending_shot=null
	game.player.casting=null
	game.player.moving=false
	game.player.rig.action=null
	game.player.rig.off_action=null
	game.player.rig.pose=null
	for id in game.player.cooldowns:game.player.cooldowns[id]=0
	game.player.ranged_ready_at=game.time
func ranger() -> void:
	game.archetype_id="ranger"
	game.inventory.reset()
	game.skills.reset()
	game.skills.all_spells=true
	game.resources.reset()
	for bar in game.resources.bars:game.resources.add(bar.id,bar.max)
	game.player.reset_weapon_stance(true)
	game.player.show_equipment(game.inventory.equipment)
	clear_combat()
	foe.dead=false
	foe.health=100000
	foe.max_health=100000
	foe.position=game.player.position+Vector3(0,0,10)
	game.player.facing=0
	game.targeting.current=foe
	game.raw_aim=foe.position
func tick(dt:float,actions:Dictionary={}) -> void:
	game.time+=dt
	game.player.update(dt,{"move":{"x":0.0,"z":0.0},"aim":foe.position,"actions":actions})
	game.spells.update(dt)
	game.combat.update_arrows(dt)
func _run() -> void:
	Store.dir="user://character_v3_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	check(not game.settings.get_value("classicCamera"),"fresh profiles default to lower-view toggle off")
	game.hud.loading.open()
	var first:String=game.hud.loading.tip.text
	game.hud.loading._process(6.1)
	check(first!="" and game.hud.loading.tip.text!=first,"loading tips are visible and rotate")
	game.hud.loading.visible=false
	var made:Dictionary=game.roster.create("Vtrial","ranger")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.set_process(false)
	game.save.autosave_enabled=false
	for enemy in game.enemies.list:
		if not enemy.protected and not enemy.cfg.get("dummy",false):
			foe=enemy
			break
	check(foe!=null,"live world supplies a normal target")
	game.events.on("projectile",func(e):
		if e.get("kind")=="arrow":arrows.append({"look":e.get("look","auto"),"time":game.time})
	)
	ranger()
	check(game.player.weapon_stance=="ranged" and game.player.bow_in_hand,"ranger starts with bow drawn")
	for expected in ["melee","sheathed","ranged"]:
		game.player.cycle_weapons()
		check(game.player.weapon_stance==expected,"ranger cycle reaches "+expected)
	game.player.reset_weapon_stance(false)
	game.player.show_equipment(game.inventory.equipment)
	for expected in ["ranged","sheathed","melee"]:
		game.player.cycle_weapons()
		check(game.player.weapon_stance==expected,"other classes cycle reaches "+expected)
	ranger()
	var bow:Node3D=game.player.bow
	check(bow.has_method("set_draw") and bow.get_node_or_null("LimbAssembly")!=null,"rebuilt bow has batched curved limbs")
	check(bow.find_children("*","MeshInstance3D",true,false).size()<=6,"bow geometry uses a bounded mesh count")
	bow.call("set_draw",1.0,true)
	check(is_equal_approx(bow.get("pull"),0.42) and bow.get_node("NockedArrow").visible,"bow string and nocked arrow reach full draw")
	var string:MeshInstance3D=bow.get_node("UpperString")
	check((string.transform*Vector3(0,-0.5,0)).distance_to(bow.TIP)<0.001 and (string.transform*Vector3(0,0.5,0)).distance_to(Vector3(0,0,-0.42))<0.001,"bow cylinder endpoints stay aligned after local length scaling")
	var duplicate:Node3D=bow.duplicate()
	check(duplicate.find_children("*","MeshInstance3D",true,false).size()==bow.find_children("*","MeshInstance3D",true,false).size(),"preview duplication does not duplicate procedural geometry")
	duplicate.free()
	foe.position=game.player.position+Vector3(10,0,0)
	game.targeting.engage(foe)
	var before:float=game.player.facing
	tick(0.1,{"shoot":true})
	check(is_equal_approx(game.player.facing,before),"auto attacks do not rotate the player towards a selected target")
	check(not game.spells.try_cast("quickShot") and is_equal_approx(game.player.facing,before),"a target behind the facing cone is refused without auto-turn")
	clear_combat()
	game.player.facing=PI/2
	for i in 8:game.player.update(1.0/60,{"move":{"x":-1.0,"z":0.0}})
	check(absf(wrapf(game.player.facing+PI/2,-PI,PI))<0.15,"a 180-degree movement turn completes in about 0.13 seconds")
	ranger()
	arrows.clear()
	game.targeting.engage(foe)
	game.player.pending_shot={"t":0.001,"total":0.6}
	var start:float=game.time
	tick(1.0/60,{"quickShot":true,"shoot":true})
	check(arrows.is_empty(),"a manual ranged special wins over an auto-shot due in the same frame")
	for i in 12:tick(1.0/60,{"shoot":true})
	check(arrows.size()==1 and arrows[0].look=="quickShot","Quick Shot releases one ability arrow after its visible wind-up")
	check(game.player.pending_shot==null,"Quick Shot does not inject an extra auto-shot draw")
	var cadence:float=game.stats.attack_cooldown_for("ranged")
	for i in int(ceil(cadence*60))+12:tick(1.0/60,{"shoot":true})
	var autos:Array=arrows.filter(func(a):return a.look=="auto")
	check(not autos.is_empty() and autos[0].time-start>=cadence-0.05,"the next auto-shot respects the bow cadence")
	var ready:float=game.player.ranged_ready_at
	game.player.cooldowns.ranged=0
	game.player.pending_shot=null
	game.player.try_shoot(foe.position)
	check(game.player.cooldowns.ranged>=ready-game.time-0.001,"retarget timer resets cannot bypass ranged readiness")
	ranger()
	arrows.clear()
	game.targeting.engage(foe)
	game.player.pending_shot={"t":0.001,"total":0.45}
	game.time+=1.0/60
	game.player.update(1.0/60,{"move":{"x":1.0,"z":0.0},"actions":{"shoot":true},"aim":foe.position})
	check(arrows.is_empty() and game.player.pending_shot==null,"movement cancels an auto-shot even on its release frame")
	ranger()
	check(game.spells.try_cast("longShot") and game.player.casting!=null,"Long Shot starts while facing its target")
	game.player.facing=PI
	game.spells.update(0.05)
	check(game.player.casting==null and is_equal_approx(game.player.facing,PI),"turning away interrupts a ranged cast without turning the player back")
	clear_combat()
	for sex in ["male","female"]:
		var look:=ForgeCharacter.defaults()
		look.sex=sex
		look.hair="long"
		game.player.set_appearance(look)
		game.inventory.equipment.mainHand={"id":"worn_longsword","count":1}
		game.inventory.equipment.offHand={"id":"rusty_dirk","count":1}
		game.player.draw_weapons("melee")
		game.player.rig.play("strike",0.8,0.4)
		game.player.rig.play_off(0.8,0.4)
		game.player.rig.update(0.32,0)
		check(game.player.rig.last_action_clip=="Sword_Attack" and game.player.rig.last_off_clip=="Dagger_Stab",sex+" sword and off-hand dagger choose independent swing/stab clips")
		var detail:=0
		var armour_lod:=false
		for mi:MeshInstance3D in game.player.model.find_children("*","MeshInstance3D",true,false):
			if mi.has_meta("forge_head_detail"):
				detail+=1
				check(mi.lod_bias>=128,sex+" head/hair stays at fitted detail")
			elif mi.has_meta("forge_body"):armour_lod=armour_lod or mi.lod_bias<128
		check(detail>0 and armour_lod,sex+" zoom fix leaves body/armour LOD enabled")
		var sk:Skeleton3D=game.player.rig._skel
		var dagger_grip:Transform3D=sk.get_bone_global_pose(sk.find_bone("hand_l"))*(game.player.model.get_meta("palm_grip_l") as Transform3D)
		check(dagger_grip.basis.y.normalized().dot(Vector3(0,0,1))>0.95,sex+" left dagger points forward independently of the sword's torso twist")
		var finger:=sk.find_bone("middle_01_l")
		game.player.rig._curl_fingers("l")
		var held:Quaternion=sk.get_bone_pose_rotation(finger)
		for i in 12:game.player.rig._curl_fingers("l")
		check(held.angle_to(sk.get_bone_pose_rotation(finger))<0.001,sex+" an unkeyed finger does not keep rotating between frames")
		game.player.rig.action=null
		game.player.rig.off_action=null
		for i in 20:game.player.rig.update(0.02,DB.CONFIG.player.runGait)
		check(game.player.rig.gait_rate>1.5,sex+" shorter gait retains responsive cadence")
		game.player.rig.pose=null
		for i in 20:game.player.rig.update(0.02,0)
		var standing:float=sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y
		game.player.set_sitting(true)
		for i in 30:game.player.rig.update(1.0/60,0)
		var seated:float=sk.get_bone_global_pose(sk.find_bone("pelvis")).origin.y
		print("POSE ",sex," standing=",standing," seated=",seated)
		check(seated<standing-0.6 and seated>0.15,sex+" sitting lowers hips to a grounded resting height")
		for side in ["l","r"]:
			check(absf(sk.get_bone_global_pose(sk.find_bone("foot_"+side)).origin.y-sk.get_bone_global_rest(sk.find_bone("foot_"+side)).origin.y)<0.03,sex+" sitting keeps "+side+" foot on the ground")
	clear_combat()
	game.hud.modal=null
	game.resources.since_combat=0
	game.hud.main_menu._start("logout")
	check(game.hud.main_menu.leaving=="","combat prevents the logout countdown from starting")
	game.log_out()
	check(current_scene==game,"direct logout also refuses combat")
	clear_combat()
	game.hud.main_menu._start("logout")
	check(game.player.sitting and game.hud.main_menu.leaving=="logout","starting logout sits the character down")
	check(game.player.sheathed,"logout stows weapons before sitting")
	game.player.update(0.1,{"move":{"x":1.0,"z":0.0}})
	game.hud.main_menu.update(0.1)
	check(game.hud.main_menu.leaving=="","movement cancels logout")
	clear_combat()
	game.hud.main_menu._start("logout")
	game.resources.since_combat=0
	game.hud.main_menu.update(0.1)
	check(game.hud.main_menu.leaving=="","entering combat cancels logout")
	clear_combat()
	game.inventory.coins=123
	game.player.take_damage(game.player.health+1)
	game.on_player_death()
	check(game.player.dead and game.world_state.grave!=null,"defeat creates a real grave")
	game.hud.show_death(0,game.respawn_point().kind)
	game.hud.main_menu._start("logout")
	check(game.hud.main_menu.leaving=="logout","defeated character can start logout")
	var id:String=game.character.id
	game.hud.main_menu.update(MainMenu.COUNTDOWN+0.01)
	await scene_changed
	game=current_scene
	game.enter_world(id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.set_process(false)
	game.save.autosave_enabled=false
	check(game.player.dead and game.player.health==0,"re-entry preserves defeated state")
	check(game.world_state.grave!=null and int(game.world_state.grave.coins)==123 and game.inventory.coins==0,"logout preserves grave possessions without duplicating them")
	game.release_spirit()
	while game.hud.loading.visible:await process_frame
	check(game.afterlife.ghost and game.afterlife.corpse!=null,"defeated re-entry can release its spirit")
	check(game.save.save(true,true).ok,"ghost state can be saved")
	var saved:Dictionary=game.save.read().data
	game.afterlife.reset()
	game.player.revive(game.player.position.x,game.player.position.z)
	game.save.apply(saved)
	check(game.player.ghost and game.afterlife.ghost and game.afterlife.corpse!=null,"ghost reload preserves the recovery body")
	print("character_v3_check: %d checks, %d failures"%[checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

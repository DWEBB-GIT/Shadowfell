extends SceneTree
var game
var output: String
func _initialize() -> void:_run.call_deferred()
func picture(label:String) -> void:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("CAPTURE ",label)
func _run() -> void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://character_v3_shots_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.hud.show_loading()
	await picture("loading-tips")
	var made:Dictionary=game.roster.create("Aldren","ranger")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.player.facing=0
	game.player._sync()
	game.player.rig.update(0.1,0)
	game._snap_camera()
	await picture("default-higher-view")
	var player=game.player
	var origin:Vector3=player.position
	var foe
	for e in game.enemies.list:
		if not e.protected and not e.cfg.get("dummy",false):
			foe=e
			break
	game.hud.root.visible=false
	for sex in ["male","female"]:
		game.archetype_id="ranger"
		game.inventory.reset()
		var look:=ForgeCharacter.defaults()
		look.sex=sex
		look.hair="long"
		player.set_appearance(look)
		player.reset_weapon_stance(true)
		player.show_equipment(game.inventory.equipment)
		game.camera.position=origin+Vector3(3.2,2.4,4.4)
		game.camera.look_at(origin+Vector3.UP*1.2)
		player.rig.update(0.2,0)
		await picture(sex+"-bow-idle")
		game.spells.reset()
		game.resources.reset()
		game.skills.all_spells=true
		for bar in game.resources.bars:game.resources.add(bar.id,bar.max)
		for id in player.cooldowns:player.cooldowns[id]=0
		player.ranged_ready_at=game.time
		foe.dead=false
		foe.health=10000
		foe.position=player.position+Vector3(0,0,8)
		game.targeting.current=foe
		game.raw_aim=foe.position
		for i in 18:
			game.time+=1.0/60
			player.update(1.0/60,{"move":{"x":0.0,"z":0.0},"actions":{"quickShot":i==0},"aim":foe.position})
			game.spells.update(1.0/60)
			game.fx.update(1.0/60)
			if i in [3,6,12]:await picture(sex+"-quick-shot-%02d"%i)
		game.targeting.stop_attack()
		game.fx.update(10)
		for stance in ["melee","sheathed","ranged"]:
			player.draw_weapons(stance)
			player.rig.action=null
			player.rig.update(0.2,0)
			await picture(sex+"-stance-"+stance)
		game.inventory.equipment.mainHand={"id":"worn_longsword","count":1}
		game.inventory.equipment.offHand={"id":"rusty_dirk","count":1}
		player.draw_weapons("melee")
		player.rig.play("strike",0.8,0.4)
		player.rig.play_off(0.8,0.4)
		player.rig.update(0.32,0)
		await picture(sex+"-sword-and-dagger")
		player.rig.action=null
		player.rig.off_action=null
		for i in 12:
			player.rig.update(1.0/60,DB.CONFIG.player.runGait)
			if i in [2,6,10]:await picture(sex+"-short-run-%02d"%i)
		for hair in ["buzzed","long"]:
			look.hair=hair
			player.set_appearance(look)
			player.rig.update(0.2,0)
			game.hud.root.visible=true
			game.hud.zone_banner.visible=false
			for zoom in [0.5,1.3]:
				game.zoom=zoom
				game._snap_camera()
				await picture(sex+"-"+hair+"-zoom-"+str(zoom))
			game.hud.root.visible=false
	game.hud.root.visible=true
	game.zoom=DB.CONFIG.camera.zoomDefault
	game._snap_camera()
	game.enemies.reset_engaged()
	game.resources.since_combat=INF
	game.resources.engaged=false
	player.moving=false
	player.pending=null
	player.pending_shot=null
	player.rig.pose=null
	player.rig.action=null
	game.hud.main_menu._start("logout")
	for i in 30:player.rig.update(1.0/60,0)
	print("SIT ",player.sitting," pose=",player.rig.pose," clip=",player.rig.clip)
	await picture("seated-logout")
	game.hud.root.visible=false
	game.camera.position=origin+Vector3(3.2,2.4,4.4)
	game.camera.look_at(origin+Vector3.UP*0.7)
	await picture("seated-close")
	game.hud.main_menu.cancel()
	print("character_v3_shots complete")
	game.queue_free()
	await process_frame
	quit()

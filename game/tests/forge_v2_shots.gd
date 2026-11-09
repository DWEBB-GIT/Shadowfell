extends SceneTree
var game
var output := ""
func _initialize() -> void: _run.call_deferred()
func picture(label: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("CAPTURE ",label)
func item_for(model: String) -> Dictionary:
	for id in DB.items:
		if DB.items[id].get("model")==model:return {"id":id,"count":1}
	return {}
func _run() -> void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://forge_v2_shots_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made: Dictionary=game.roster.create("Aldren","warden")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.settings.values.classicCamera=true
	game.player.rig.update(0.1,0.0)
	game.camera.fov=35
	game.player.model.scale*=1.2/DB.CONFIG.player.visualScale
	var target:Vector3=game._camera_follow_position()+Vector3.UP
	game.camera.position=target+Vector3(0,25.5,25.5)*0.98
	game.camera.look_at(target)
	await picture("camera-before")
	game.camera.fov=DB.CONFIG.camera.fov
	game.player.model.scale*=DB.CONFIG.player.visualScale/1.2
	game._snap_camera()
	await picture("camera-after")
	var player=game.player
	var ground:Vector3=player.position
	for sex in ["male","female"]:
		var look:=ForgeCharacter.defaults()
		look.sex=sex
		player.set_appearance(look)
		player.place_at(ground.x,ground.z,0)
		# An independent camera on the actual world actor, for hand inspection.
		game.camera.position=ground+Vector3(3,2.5,4.2)
		game.camera.look_at(ground+Vector3.UP*1.1)
		for style in ["worn_sword","bone_knife","oak_club","greatsword","dual","shield","bow"]:
			var gear:Dictionary=game.inventory.equipment.duplicate(true)
			gear.mainHand=item_for(style if style not in ["dual","shield","bow"] else "arming_sword")
			gear.offHand=null
			gear.ranged=null
			if style=="dual":gear.offHand=item_for("dirk")
			if style=="shield":gear.offHand=item_for("iron_shield")
			if style=="bow":gear.ranged=item_for("hunting_bow")
			game.inventory.equipment=gear
			player.show_equipment(gear)
			if style=="bow":player.hold_bow(true)
			player.rig.action=null
			player.rig.update(0.1,0.0)
			await picture(sex+"-"+style+"-idle")
			player.rig.play("shoot" if style=="bow" else "strike",0.8,0.4)
			player.rig.update(0.32,0.0)
			await picture(sex+"-"+style+"-impact")
		player.hold_bow(false)
		player.rig.action=null
		player.place_at(ground.x,ground.z,0)
		game._snap_camera()
		for i in 48:
			player.update(1.0/60,{"move":{"x":0.0,"z":0.0},"jump":i==0})
			if i in [2,10,20,35,43]:await picture(sex+"-jump-%02d" % i)
		game._snap_camera()
		for i in 20:
			player.update(1.0/60,{"move":{"x":1.0,"z":0.0}})
			game._update_camera(1.0/60)
		await picture(sex+"-running")
		player.place_at(ground.x,ground.z,0)
	print("forge_v2_shots complete")
	game.queue_free()
	await process_frame
	quit()

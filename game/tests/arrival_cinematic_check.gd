extends SceneTree
var game
var failures:=0
var checks:=0
func _initialize():_run.call_deferred()
func check(ok,text):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",text)
func _run():
	Store.dir="user://arrival_cinematic_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate();root.add_child(game)
	await process_frame
	var made=game.roster.create("Arrivaltrial","warden");game.enter_world(made.character.id)
	# Normal native launch should automatically begin; headless deliberately
	# leaves legacy gameplay tests fast, and this test explicitly starts it.
	while not game.started:await process_frame
	if DisplayServer.get_name()=="headless":
		while game.hud.loading.visible:await process_frame
		check(game.arrival.begin(),"The cinematic can be exercised deterministically headless")
	else:
		while not game.arrival.active and game.hud.loading.visible:await process_frame
		check(game.arrival.active,"A fresh native login automatically plays its arrival")
	game.save.autosave_enabled=false;game.set_process(false)
	var film=game.arrival
	var start:Vector3=game.player.position
	var hp=game.player.health
	var clock=game.world_state.time
	var quest_before=game.quests.serialize()
	var pose:Transform3D=game.camera.global_transform
	var original_fov=game.camera.fov
	var original_facing=game.player.facing
	check(game.npcs.by_id("ni_abel").group.is_inside_tree(),"Abel is attached before the reveal rather than popping in at handoff")
	check(film._music.bus=="Music","The cinematic score uses the existing music volume bus")
	check(root.get_camera_3d()==film.film_camera,"Godot's current camera is the cinematic Camera3D")
	check(game.hud.blocks_gameplay,"The arrival blocks gameplay")
	check(game.hud.root.modulate.a==0,"Gameplay HUD starts hidden")
	check(film.timeline.has_animation("arrival"),"The scene contains an editable AnimationPlayer timeline")
	check(film.rail.curve.get_point_count()>=4,"The shot follows an editable Curve3D rail")
	var samples=[]
	for moment in [1.8,3.8,6.5,8.8,11.6]:
		while film.elapsed<moment and film.active:game.step(minf(1.0/60,moment-film.elapsed))
		var p=film.film_camera.global_position
		samples.append(p)
		check(p.y>=Terrain.height_at(p.x,p.z)+1.5,"Camera stays above the terrain")
		check(not film.film_camera.is_position_behind(game.player.position+Vector3.UP),"Player remains in front of the cinematic camera")
		check(film.film_camera.is_position_in_frustum(game.player.position+Vector3.UP),"Player remains inside the actual camera frustum")
		if moment<8.5:check(game.hud.root.modulate.a<0.01,"HUD stays out of the main shots")
		await capture("arrival-%02d"%int(moment*10))
	check(samples[0].distance_to(samples[2])>12,"The camera makes a real travelling swoop")
	for i in 60:
		if not film.active:break
		game.step(1.0/60)
	check(not film.active,"The sequence finishes without a timer or input deadlock")
	check(root.get_camera_3d()==game.camera,"Gameplay Camera3D regains control")
	check(game.camera.global_transform.is_equal_approx(pose) and is_equal_approx(game.camera.fov,original_fov),"Final view exactly matches the existing gameplay camera")
	check(game.player.position==start and game.player.health==hp,"Cinematic does not move or harm the player")
	check(game.player.facing==original_facing,"The opening preserves player-facing control")
	check(game.quests.serialize()==quest_before,"No quest is completed or accepted on the player's behalf")
	check(game.world_state.time==clock,"Enemy respawn/combat simulation stays paused")
	check(not game.hud.loading.visible and game.hud.modal==null and not game.hud.blocks_gameplay,"Loading and gameplay locks release on completion")
	check(game.hud.root.modulate.a==1,"The normal HUD returns at full opacity")
	check(game.save.serialize().world.flags.has("mk_arrival_seen"),"The seen marker is persisted by the existing save system")
	var saved=game.save.save(false)
	var read_back=game.save.read()
	check(saved.ok and read_back.status=="ok" and read_back.data.world.flags.has("mk_arrival_seen"),"Completed arrival saves and reads back through normal character persistence")
	check(not film.should_play(true),"Returning-character login does not replay the introduction")
	check(not film.should_play(false),"A seen introduction does not replay on the same character")
	await capture("arrival-gameplay")
	# Skip early, late, and through the actual skip key. No buffered spell/jump.
	for moment in [0.05,6.5,10.8]:
		check(film.begin(),"The director can be safely exercised again")
		for i in ceili(moment*60):game.step(1.0/60)
		game.input.pressed.Escape=true;game.step(1.0/60)
		for i in 40:game.step(1.0/60)
		check(not film.active and root.get_camera_3d()==game.camera,"Esc safely skips from every shot")
		check(game.player.position==start and game.player.jump_h==0,"Skip does not buffer a jump or movement")
		check(game.hud.modal==null and not game.hud.loading.arrival_hold,"Skip releases all modal/loading state")
	film.hero_focus.position=Vector3(0,1.4,0)
	film.begin()
	check(film.hero_focus.position==Vector3(0,1.4,0),"Hero focus edits made in Godot are honoured at runtime")
	film._skip_button.pressed.emit()
	for i in 40:game.step(1.0/60)
	check(not film.active,"The visible Skip button works")
	film.begin();game.input.pressed.Space=true;game.step(1.0/60)
	for i in 40:game.step(1.0/60)
	check(not film.active and game.player.jump_h==0,"Space skips without making the player jump")
	game.settings.set_value("reducedOpeningMotion",true)
	film.begin()
	for i in 54:game.step(1.0/60)
	check(not film.active and game.camera.global_transform.is_equal_approx(pose),"Reduced motion gives a short fade without a rail flight")
	game.settings.set_value("openingCinematic",false)
	check(not film.should_play(false),"Cinematic preference can disable future opening flights")
	# Motion continues normally immediately after the handoff.
	game.player.update(0.1,{"move":{"x":1.0,"z":0.0},"actions":{}})
	check(game.player.position.distance_to(start)>0.2,"Movement works after the camera hands control back")
	print("arrival_cinematic_check: %d checks, %d failures"%[checks,failures])
	game.queue_free();await process_frame;quit(1 if failures else 0)
func capture(label):
	if OS.get_cmdline_user_args().is_empty():return
	# Scene is already warmed, but let layout settle before taking the frame.
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(label+".png"))

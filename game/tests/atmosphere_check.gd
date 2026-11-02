extends SceneTree
## Real title buttons, character persistence, native atmospheric captures and budgets.
var game
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	print("ok: " if ok else "FAIL: ", message)
	if not ok: failures += 1
func _loaded() -> void:
	var start := Time.get_ticks_msec()
	while not game.started or game.hud.loading.visible:
		await process_frame
		if Time.get_ticks_msec() - start > 240000:
			check(false,"world loads within four minutes")
			quit(1)
			return
	game.save.autosave_enabled = false
func _run() -> void:
	Store.dir = "user://atmosphere_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	check(Terrain.is_new_map(),"default project opens the new continent")
	var title: TitleScreen = game.hud.title
	title.main.new.pressed.emit()
	check(title.view == "create","New character opens character creation")
	title.create.name.text = "Lantern Tester"
	title.create.confirm.pressed.emit()
	await _loaded()
	await process_frame
	await process_frame
	check(game.started and game.character.name == "Lantern Tester","Create and enter reaches the playable world")
	if DisplayServer.get_name() != "headless":
		check(game.hud.icons.find_children("*","SubViewport",true,false).is_empty(),"one-shot icon and portrait rendering worlds are released")
	check(game.atmosphere.sources.size() > 100,"village lamps, hearths and windows have light sources")
	check(game.atmosphere.lamps.size() == 16,"point lights have a fixed pool of sixteen")
	var forward := RenderingServer.get_current_rendering_method() == "forward_plus"
	check(not forward or game.env.volumetric_fog_enabled,"Forward+ enables real volumetric fog")
	check(not forward or game.atmosphere.volumes.size() == 8,"ground fog uses eight local volumes")
	for id in Assets.model_ids():
		check(ResourceLoader.exists(Assets.model_path(id)),"organised model: "+id)
	var output := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else ""
	if output != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(output)
		for spot in [["thornford-lanterns",-450,-207],["briarwood-mist",-555,-300],["lantern-crossing",-208,-176],["haunted-woods",412,-556],["graveyard-torches",-344,-472],["cosy-inn",-465,-204],["fishing-pond",-394,-177]]:
			if OS.get_cmdline_user_args().size()>1 and spot[0] not in (["graveyard-torches"] if OS.get_cmdline_user_args()[1]=="graveyard" else ["cosy-inn", "graveyard-torches", "briarwood-mist"]): continue
			game.player.place_at(spot[1],spot[2])
			game._snap_camera()
			game.world.land.update(game.player.position,true)
			game._bwk = -1
			game._update_region(2)
			for i in 45: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(spot[0]+".png"))
			if spot[0] == "cosy-inn":
				check(game.atmosphere._window_groups["vr_lantern_inn"].all(func(w):return not w.visible),"window panes hide with the inn's cutaway walls")
			print("capture: ",spot[0]," fps=",Engine.get_frames_per_second()," active lights=",game.atmosphere.lamps.filter(func(l):return l.visible).size())
	if OS.get_cmdline_user_args().size()>1:
		game.queue_free()
		await process_frame
		await process_frame
		print("atmosphere visual review: %d failed" % failures)
		quit(1 if failures else 0)
		return
	game.player.place_at(-450,-207)
	check(game.save.save().ok,"character saves from the new world")
	var key: String = game.character.id
	game.queue_free()
	await process_frame
	await process_frame
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	check(game.roster.last == key,"saved character is offered on the title screen")
	game.hud.title.main["continue"].pressed.emit()
	await _loaded()
	check(game.started and game.character.id == key,"Continue resumes the same character in the new world")
	check(game.player.position.distance_to(Vector3(-450,Terrain.height_at(-450,-207),-207))<2,"saved world position survives restart")
	print("atmosphere_check: %d failed" % failures)
	game.queue_free()
	await process_frame
	await process_frame
	quit(1 if failures else 0)

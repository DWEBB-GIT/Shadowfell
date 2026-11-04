extends SceneTree
var game
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	Store.dir="user://step_profile_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var c:Dictionary=game.roster.create("Step","warden")
	game.enter_world(c.character.id)
	while game.hud.loading.visible: await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	var controls=game._handle_input(0)
	var calls={"input":func():game._handle_input(0),"player":func():game.player.update(0,controls),"enemies":func():game.enemies.update(0),"npcs":func():game.npcs.update(0),"interaction":func():game.interaction.update(),"world":func():game.world.update(0,game.time),"camera":func():game._update_camera(0),"hud":func():game.hud.update(0),"discovery":func():game.discovery.update(0),"puzzles":func():game.puzzles.update(0),"gathering":func():game.gathering.update(0,game.time),"mining":func():game.mining.update(0,game.time),"water":func():game.water_and_dark.update(0,game.time),"audio":func():game.audio.update(0),"loot":func():game.loot.update(0,game.time),"fx":func():game.fx.update(0)}
	for part in ["refresh_stats","_refresh_slots","_refresh_spells","_update_target","_update_enemy_bars","layout"]:
		calls["hud."+part] = Callable(game.hud,part)
	calls["hud.quest_marks"]=Callable(game.hud.quests,"update_marks")
	calls["hud.labels"]=Callable(game.hud.labels,"update").bind(0)
	for key in calls:
		var start:=Time.get_ticks_usec()
		for i in 20: calls[key].call()
		print("STEP ",key," ms=",(Time.get_ticks_usec()-start)/20000.0)
	game.queue_free()
	await process_frame
	await process_frame
	quit()

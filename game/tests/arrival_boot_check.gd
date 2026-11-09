extends SceneTree
var failures:=0
var checks:=0
func _initialize():_run.call_deferred()
func check(ok,message):
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",message)
func _run():
	Store.dir="user://arrival_boot_%d"%Time.get_ticks_usec()
	var entry:String=ProjectSettings.get_setting("application/run/main_scene")
	check(entry=="res://game/boot/lobby.tscn","The project's existing lobby remains the normal entry scene")
	change_scene_to_file(entry)
	for i in 600:
		await process_frame
		if current_scene is Game and current_scene.hud!=null:break
	check(current_scene is Game,"Normal editor/desktop boot reaches the game through the lobby")
	if not current_scene is Game:quit(1);return
	var game=current_scene
	var made=game.roster.create("Bootarrival","ranger")
	check(made.ok,"Lobby/game roster can create a fresh character")
	# The split web lobby uses this same handoff after loading its world pack.
	Game.enter_id=made.character.id
	change_scene_to_file("res://game/main.tscn")
	await process_frame
	game=current_scene
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	check(game.started and game.character.id==made.character.id,"The lobby's selected-character handoff still enters that character")
	check(game.quests.status("ni_stretch_your_legs")=="active","The original first quest remains ready to play")
	check(Terrain.walkable(game.player.position.x,game.player.position.z),"Entry still lands on the repaired playable road")
	game.world_state.flags.erase("mk_arrival_seen")
	check(game.save.save(false).ok,"A legacy-style existing save can be written without a cinematic marker")
	Game.enter_id=made.character.id
	change_scene_to_file("res://game/main.tscn")
	await process_frame
	game=current_scene
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	check(game.boot_save.status=="ok","Returning character resumes its existing save")
	check(not game.arrival.active and not game.arrival.should_play(true),"Returning characters skip the cinematic even without a new seen marker")
	check(not game.hud.blocks_gameplay and game.camera.current,"The returning login hands control straight to gameplay")
	print("arrival_boot_check: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

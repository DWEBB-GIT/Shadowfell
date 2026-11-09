extends SceneTree
var game
var seconds:=0.0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	Store.dir=OS.get_cmdline_user_args()[0] if not OS.get_cmdline_user_args().is_empty() else "user://core_loop_review_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	var id=game.roster.last
	if id==null:
		var made:Dictionary=game.roster.create("Rowan Trial","rogue")
		id=made.character.id
	game.enter_world(id)
	DisplayServer.window_set_title("Shadowfell - Core Loop Review")
	print("REVIEW isolated_store=",Store.dir)
func _process(dt:float) -> bool:
	if game==null or not game.started:return false
	seconds+=dt
	if seconds>=10:
		seconds=0
		print("REVIEW ",JSON.stringify({"position":str(game.player.position),"health":game.player.health,"level":game.progression.level,"modal":game.hud.modal,"quests":game.quests.active}))
	return false

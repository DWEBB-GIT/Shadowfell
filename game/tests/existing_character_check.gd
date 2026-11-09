extends SceneTree
## Read actual saves only; every launch, migration and save uses an isolated copy.
const IO := preload("res://addons/shadowfell_data/json_io.gd")
var game
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,message: String) -> void:
	print("ok: " if ok else "FAIL: ",message)
	if not ok:failures+=1

func possessions(data: Dictionary) -> Dictionary:
	# A material-pouch upgrade can move stacks between bags on load.
	# Compare actual possessions independently of their slot positions.
	var totals:Dictionary={}
	var stacks:Array=data.get("bank",[]).duplicate()
	for socket in data.sockets:
		if socket!=null:stacks.append_array(socket.slots)
	stacks.append_array(data.equipment.values())
	for item in stacks:
		if item==null:continue
		var identity:Dictionary=item.duplicate(true)
		identity.erase("count")
		var key:=JSON.stringify(JSON.parse_string(JSON.stringify(identity)),"",true)
		totals[key]=totals.get(key,0)+int(item.count)
	return JSON.parse_string(JSON.stringify({"coins":data.coins,"ammo":data.get("ammo"),"items":totals}))
func _run() -> void:
	var original := Store.dir
	var folder := "user://existing_character_copy_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	for file in DirAccess.get_files_at(original):
		if file.ends_with(".json") and not file.contains("unreadable"):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(original.path_join(file)),ProjectSettings.globalize_path(folder.path_join(file)))
	Store.dir=folder
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var id=game.roster.last
	check(id!=null,"an existing character is offered on the copied roster")
	if id==null:
		game.queue_free()
		quit(1)
		return
	var entry=game.roster.by_id(id)
	var before=JSON.parse_string(Store.get_item(entry.key))
	game.hud.title.main["continue"].pressed.emit()
	while not game.started or game.hud.loading.visible: await process_frame
	game.save.autosave_enabled=false
	check(game.started and game.character.id==id,"Continue loads an existing copied character")
	check(game.progression.level==int(before.progression.level),"existing level is retained")
	var after:Dictionary=game.save.serialize()
	# Sort keys and normalise JSON numbers before comparing nested inventory data.
	check(JSON.stringify(possessions(after.inventory),"",true)==JSON.stringify(possessions(before.inventory),"",true),"existing possessions are retained through bag-layout upgrades")
	check(game.quests.done.size()==before.get("quests",{}).get("done",[]).size(),"finished quests are retained")
	check(Terrain.walkable(game.player.position.x,game.player.position.z),"existing character arrives on walkable ground")
	var start:Array=DB.world.playerStart.position
	if before.get("worldId", "") != "new":
		check(Vector2(game.player.position.x-start[0],game.player.position.z-start[1]).length()<2,"older character arrives safely in Thornford")
		check(Store.get_item(entry.key+".before_world_new") != null,"an untouched copy of the older save is retained before migration")
	check(after.worldId=="new" and game.save.save().ok,"copied save records its new world identity")
	game.queue_free()
	await process_frame
	await process_frame
	print("existing_character_check: %d failed" % failures)
	quit(1 if failures else 0)

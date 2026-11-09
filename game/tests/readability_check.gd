extends SceneTree
var game
var failures := 0
var output := ""
var hit_seen := false
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ",label)
	if not ok: failures+=1
func _run() -> void:
	Store.dir="user://readability_%d"%Time.get_ticks_usec()
	output=OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else "user://readability-shots"
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary=game.roster.create("Readability","warden")
	game.enter_world(made.character.id)
	var began:=Time.get_ticks_msec()
	while game.hud.loading.visible:
		await process_frame
		if Time.get_ticks_msec()-began>240000:
			check(false,"world loads")
			quit(1)
			return
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.settings.set_value("classicControls",true)
	game.settings.set_value("clickToMove",true)
	game.settings.set_value("tankControls",false)
	for b in game.world.buildings:
		var d: Dictionary=b.def
		var x: float=d.position[0]
		var z: float=d.position[1]+d.size[1]*0.5
		var clear:=true
		for i in 13:
			var at:=Vector3(x,Terrain.height_at(x,z+3-i*0.5),z+3-i*0.5)
			var resolved: Vector3=game.collision.resolve(at,game.player.radius)
			if Vector2(resolved.x-at.x,resolved.z-at.z).length()>0.2: clear=false
		check(clear,"front doorway and approach have clear collision: "+d.id)
		game.player.place_at(x,z-1.5)
		game.world.update_indoors(1,game.player.position)
		check(game.world.indoors!=null and game.world.indoors.def.id==d.id,"front entrance reaches the real interior: "+d.id)
	var houses_ok:=true
	for h in Layout.houses:
		var across: bool=h.size[1]>h.size[0]
		var dir:=Town._door_side(Town.visible_door_side(h),across)
		var turn:=deg_to_rad(float(h.get("rotation",0)))+(PI*0.5 if across else 0.0)
		if (Basis(Vector3.UP,turn)*Vector3(dir.x,0,dir.y)).dot(Vector3.BACK)<0.45: houses_ok=false
	check(houses_ok,"every decorative house door faces into the fixed camera view")
	for item in [["vr_lantern_inn","inn-front"],["vr_town_hall","town-hall-front"]]:
		var definition: Dictionary=Layout.buildings.filter(func(b):return b.id==item[0])[0]
		game.player.place_at(definition.position[0],definition.position[1]+definition.size[1]*0.5+5)
		game.world.land.update(game.player.position,true)
		game.world.update_indoors(1,game.player.position)
		game._snap_camera()
		await _picture(item[1])
		# Walk forward through the same opening, without teleporting across its wall.
		for i in 75:
			game.player.update(1.0/60.0,{"move":{"x":0.0,"z":-1.0},"actions":{}})
			game.world.update_indoors(1.0/60.0,game.player.position)
		check(game.world.indoors!=null and game.world.indoors.def.id==definition.id,"walking through the visible front door works: "+definition.id)
		game._snap_camera()
		await _picture(item[1]+"-inside")
	# Check an actual quest conversation/reward page within normal talking reach.
	game.player.place_at(-450,-165)
	game._snap_camera()
	# the mayor's own errand (the boundary stones), once the quests before it are handed in
	_mark_done_before("vr_fence_dispute")
	game.progression.level=2 # (the errand is offered from level 2)
	check(game.quests.accept("vr_fence_dispute"),"the mayor's errand can be taken")
	var coins_before: int=game.inventory.coins
	game.interaction.examine("poi:vr_boundary")
	game.quests.refresh()
	game.dialogue.open(game.npcs.by_id("vr_mayor"))
	game.dialogue.choose("quest:vr_fence_dispute")
	game.hud.update(0)
	await _picture("mayor-quest-page")
	game.dialogue.choose("complete")
	check(game.quests.status("vr_fence_dispute")=="done" and game.inventory.coins==coins_before+10,"visible town hall supports the real dialogue reward action")
	game.dialogue.close()
	var e=game.enemies.by_id("vr_young_boar_1")
	game.player.place_at(e.position.x,e.position.z+2.0)
	game.player.face_towards(e.position.x,e.position.z)
	game.world.land.update(game.player.position,true)
	game._snap_camera()
	game.targeting.engage(e)
	game.hud.update(0)
	game.events.on("enemyHit",func(ev):
		if ev.get("damage",0)>0:hit_seen=true)
	game.hud.numbers.clear()
	var rendered:=false
	for i in 360:
		game.step(1.0/60.0)
		if hit_seen and not rendered and game.hud.numbers.items.any(func(n):return n.clearance>0) and game.fx.items.any(func(it):return it.obj.name=="HitContact"):
			rendered=true
			check(game.fx.items.any(func(it):return it.obj.name=="HitContact"),"a real landed auto-attack produces an immediate contact flash")
			game.hud.numbers.update(0)
			var plate=game.hud.enemy_bars.get(e.id)
			var clear_numbers:=true
			var found:=false
			for number in game.hud.numbers.items:
				if number.clearance>0:
					found=true
					if number.label.position.y+number.label.size.y > plate.root.position.y-6:clear_numbers=false
			for number in game.hud.numbers.items:
				print("NUMBER clearance=",number.clearance," y=",number.label.position.y," bottom=",number.label.position.y+number.label.size.y," plate_top=",plate.root.position.y)
			check(found and clear_numbers,"damage numbers begin clearly above the whole enemy nameplate")
			check(game.fx.items.any(func(it):return it.obj.name=="BloodDroplet"),"living beast hits have small blood droplets")
			await _picture("combat-contact-and-numbers")
		await process_frame
	check(rendered,"normal frame-by-frame combat lands a real hit")
	game.targeting.stop_attack()
	for i in 100:
		game.fx.update(1.0/60.0)
		await process_frame
	check(not game.fx.items.any(func(it):return it.obj.name=="HitContact" or it.obj.name=="BloodDroplet"),"temporary impact effects expire")
	game.settings.set_value("bloodEffects",false)
	game.events.emit("enemyHit",{"enemy":e,"damage":1,"kind":"strike","swing":false})
	check(not game.fx.items.any(func(it):return it.obj.name=="BloodDroplet"),"blood setting disables droplets while keeping the contact flash")
	var n: int=game.fx.items.filter(func(it):return it.obj.name=="HitContact").size()
	game.events.emit("enemyHit",{"enemy":e,"damage":0,"kind":"strike","swing":false})
	check(game.fx.items.filter(func(it):return it.obj.name=="HitContact").size()==n,"misses and zero-damage hits do not produce a false contact flash")
	game.settings.set_value("bloodEffects",true)
	var undead=game.enemies.by_id("tf_revenant_1")
	game.events.emit("enemyHit",{"enemy":undead,"damage":1,"kind":"strike","swing":false})
	check(not game.fx.items.any(func(it):return it.obj.name=="BloodDroplet"),"undead do not use living-beast blood")
	print("readability_check: %d failed"%failures)
	game.queue_free()
	game=null
	await process_frame
	await process_frame
	quit(1 if failures else 0)
func _picture(label: String) -> void:
	game.world.update_indoors(1,game.player.position)
	game.atmosphere._process(0.25)
	game.hud.update(0)
	if DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))


## Every quest `id` needs, all the way back, marked handed in.
func _mark_done_before(id: String) -> void:
	for need in DB.quests[id].get("requires", []):
		_mark_done_before(need)
		game.quests.accepted.erase(need)
		game.quests.done[need] = true

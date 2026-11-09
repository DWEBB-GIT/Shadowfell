extends SceneTree
var game
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	Store.dir="user://character_select_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var names: Array=["Aldren","Beren","Corvin","Della","Edda","Fenner","Gareth","Hale","Iren","Jory"]
	var classes: Array=DB.archetypes.keys()
	for i in 10:
		check(game.roster.create(names[i],classes[i%classes.size()]).ok,"Character can be created")
	check(game.roster.full and not game.roster.create("Kit","warden").ok,"The eleventh character is refused")
	var screen=game.hud.title
	screen.show_view("select")
	check(screen.sel.slots.size()==10,"Exactly ten slots are shown")
	check(screen.sel.create.disabled,"Create is disabled at ten characters")
	var before: Dictionary=game.inventory.serialize()
	for c in game.roster.list:
		screen.select(c.id)
		check(screen.sel.preview.equipment.mainHand.id==DB.archetypes[c.classId].startingGear.mainHand,"Preview shows the selected class equipment")
	check(game.inventory.serialize()==before,"Inspecting characters does not mutate live inventory")
	for card in screen.sel.cards.values():
		check(card.get_meta("emblem").texture!=null,"Every character displays its class emblem")
		var words: String=card.get_meta("details").get_parsed_text()
		check(words.contains("Level") and words.contains("Not yet set out"),"Character cards show level and last location")
		check(words.split("\n")[0]==game.roster.by_id(card.get_meta("char")).name,"Names appear without slot numbers")
	var phase: float=screen.sel.preview.actor.rig.time
	screen.sel.preview._process(0.1)
	check(screen.sel.preview.actor.rig.time>phase,"The preview runs the actual idle rig")
	var press:=InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	screen.sel.preview._gui_input(press)
	var drag:=InputEventMouseMotion.new()
	drag.relative=Vector2(50,0)
	screen.sel.preview._gui_input(drag)
	check(screen.sel.preview.turn>0,"Mouse dragging rotates the selected model")
	for resolution in [Vector2i(1280,800),Vector2i(960,540),Vector2i(1920,1080)]:
		root.content_scale_size=resolution
		root.size=resolution
		for i in 5:
			screen.layout()
			await process_frame
		check(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(screen.sel.scroll.get_global_rect()),"Roster scroll area remains on screen")
		check(screen.sel.preview.get_global_rect()==Rect2(Vector2.ZERO,Vector2(resolution)),"The backdrop fills the screen")
		for slot in screen.sel.slots:
			check(slot.custom_minimum_size.y>=50,"Cards preserve readable name, level, class and location")
		screen.sel.scroll.ensure_control_visible(screen.sel.slots[-1])
		await process_frame
		check(screen.sel.scroll.get_global_rect().intersects(screen.sel.slots[-1].get_global_rect()),"The last slot is reachable by scrolling")
		check(screen.sel.enter.size.x<=300,"Enter World remains a compact primary action")
		for control in [screen.sel.enter,screen.sel.create,screen.sel.delete]:
			check(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(control.get_global_rect()),"Main action %s stays on screen at %s: %s" % [control.text,resolution,control.get_global_rect()])
	root.size=Vector2i(1280,800)
	root.content_scale_size=Vector2i(1280,800)
	screen.select(game.roster.list[0].id)
	var id: String=screen.selected
	var entry: Dictionary=game.roster.by_id(id).duplicate(true)
	var fixture: Dictionary=game.save.serialize()
	fixture.inventory.equipment.mainHand={"id":"oak_club","count":1}
	fixture.progression.level=7
	var original_save:=JSON.stringify(fixture)
	Store.set_item(entry.key,original_save)
	check(game.save.read(entry.key).status=="ok","Saved preview fixture passes real save validation")
	screen.select(id)
	check(screen.sel.preview.equipment.mainHand.id=="oak_club","An existing hero previews their saved weapon")
	screen.ask_delete()
	screen.sel.delete_name.text="wrong"
	screen.do_delete()
	check(game.roster.list.size()==10,"Wrong confirmation cannot delete a character")
	screen.sel.delete_name.text=entry.name
	screen.do_delete()
	check(game.roster.list.size()==9 and game.roster.deleted.size()==1,"Deletion frees a slot and retains a recovery entry")
	check(not screen.sel.create.disabled,"A freed slot enables Create Character")
	screen.sel.create.pressed.emit()
	check(screen.view=="create","Create Character opens character creation")
	screen.back()
	check(screen.view=="select","Creation can be cancelled without changing characters")
	check(Store.get_item(entry.key)==original_save,"Deleting preserves the character's save")
	var reload:=Roster.new()
	reload.load_roster(func(_key): return {"status":"ok"})
	check(reload.list.size()==9 and reload.deleted.size()==1,"Reload does not resurrect a deleted legacy-slot character")
	var replacement: Dictionary=reload.create("Kit","warden")
	check(replacement.ok and not reload.restore(id).ok,"Restoring requires an available character slot")
	reload.remove(replacement.character.id)
	check(reload.restore(id).ok and reload.list.size()==10,"Deleted character can be restored")
	check(Store.get_item(entry.key)==original_save,"Restoration preserves the save exactly")
	var expired: Dictionary=entry.duplicate(true)
	expired.id="expired"
	expired.key="expiry-fixture"
	expired.deletedAt=Time.get_unix_time_from_system()-31*86400
	Store.set_item(expired.key,"expired fixture")
	reload.deleted.append(expired)
	reload._write()
	var after_expiry:=Roster.new()
	after_expiry.load_roster(func(_key): return {"status":"ok"})
	check(not after_expiry.deleted.any(func(c): return c.id=="expired") and Store.get_item(expired.key)==null,"Expired recovery entries are removed after thirty days")
	check(Store.get_item(entry.key)==original_save,"Recovery expiry does not affect active character saves")
	# Restore clean readable state for native UI captures.
	game.roster=after_expiry
	screen.selected=id
	screen.show_view("select")
	if not OS.get_cmdline_user_args().is_empty():
		for i in 20:
			screen.layout()
			screen.sel.preview._process(1.0/30)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0])
	screen.enter_selected()
	while game.hud.loading.visible:
		await process_frame
	check(game.started and game.character.id==id,"Enter World loads the selected restored character")
	check(game.progression.level==7 and game.inventory.equipment.mainHand.id=="oak_club","The entered hero retains saved level and equipment")
	print("character_select_check: %d checks, %d failures" % [checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

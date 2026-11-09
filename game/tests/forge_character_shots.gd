extends SceneTree
var game
var out := ""
func _initialize() -> void: _run.call_deferred()
func item_for(model: String) -> Dictionary:
	for id in DB.items:
		if DB.items[id].get("model", DB.items[id].get("cosmetic", "")) == model:
			return {"id":id, "count":1}
	return {}
func picture(label: String) -> void:
	for i in 12: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(label + ".png"))
	print("CAPTURE ", label)
func _run() -> void:
	out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	Store.dir = "user://forge_shots_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var title = game.hud.title
	title.show_view("create")
	title.layout()
	await picture("creator-male")
	title.creator_appearance.sex = "female"
	title.creator_appearance.hair = "long"
	title._refresh_creator_preview()
	await picture("creator-female")
	for resolution in [Vector2i(960,540), Vector2i(1920,1080)]:
		root.content_scale_size = resolution
		root.size = resolution
		title.layout()
		await picture("creator-%dx%d" % [resolution.x, resolution.y])
	root.content_scale_size = Vector2i(1280,720)
	root.size = Vector2i(1280,720)
	title.layout()
	for sex in ["male", "female"]:
		var look := ForgeCharacter.defaults()
		look.sex = sex
		for style in ["shield", "twohand", "bow", "cosmetic", "helm-cloak"]:
			var gear := {"chest":item_for("warden_hauberk"), "mainHand":item_for("worn_sword")}
			if style == "shield": gear.offHand = item_for("iron_shield")
			if style == "twohand": gear.mainHand = item_for("greatsword")
			if style == "bow": gear.ranged = item_for("hunting_bow")
			if style == "cosmetic":
				gear.head = item_for("horns")
				gear.back = item_for("wings")
			if style == "helm-cloak":
				gear.head = item_for("watch_helm")
				gear.back = item_for("clothes")
				# Choose the back-slot garment rather than the first clothes item.
				for id in DB.items:
					if DB.items[id].get("slot") == "back" and not DB.items[id].get("cosmetic"):
						gear.back = {"id":id,"count":1}
						break
			title.create.preview.show_character(gear, look)
			var preview = title.create.preview
			preview.set_process(false)
			preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			var actor = preview.actor
			if style == "bow": actor.hold_bow(true)
			actor.rig.play("shoot" if style == "bow" else "strike", 1.0, 0.4)
			actor.rig.update(0.3, 0.0)
			await picture("equipment-" + sex + "-" + style)
	title.create.preview.set_process(true)
	title.creator_appearance.sex = "male"
	title.creator_appearance.hair = "buzzed"
	var made: Dictionary = game.roster.create("Aldren", "warden", title.creator_appearance)
	title.selected = made.character.id
	title.show_view("select")
	await picture("selection-male")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible: await process_frame
	game.save.autosave_enabled = false
	game.set_process(false)
	game.camera.position = game.player.position + Vector3(5, 5, 6)
	game.camera.look_at(game.player.position + Vector3.UP * 0.9)
	game.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	game.camera.size = 7.0
	await picture("world-male")
	var origin: Vector3 = game.player.position
	for sex in ["male", "female"]:
		var look := ForgeCharacter.defaults()
		look.sex = sex
		game.player.set_appearance(look)
		game.hud.hide_title()
		game.player.rig.update(0.1, 0.0)
		await picture("world-" + sex + "-idle")
		for pose in ["strike", "cast", "guard", "shoot"]:
			game.player.rig.play(pose, 1.0, 0.4)
			for i in 4: game.player.rig.update(0.1, 0.0)
			await picture("world-" + sex + "-" + pose)
		game.player.rig.action = null
		game.player.rig.update(0.1, 1.0)
		await picture("world-" + sex + "-run")
		game.player.rig.airborne = true
		game.player.rig.update(0.15, 1.0)
		await picture("world-" + sex + "-jump")
		game.player.rig.airborne = false
		game.player.rig.update(0.15, 0.0)
		game.player.position = origin
	print("forge_character_shots: complete")
	game.queue_free()
	await process_frame
	quit()

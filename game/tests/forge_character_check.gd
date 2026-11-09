extends SceneTree
var game
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message)
func _run() -> void:
	Store.dir = "user://forge_character_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	for sex in ["male", "female"]:
		var appearance := ForgeCharacter.defaults()
		appearance.sex = sex
		appearance.face = "broad"
		appearance.hair = "ponytail"
		appearance.hair_colour = "silver"
		appearance.eye_colour = "green"
		appearance.beard = "short"
		var made: Dictionary = game.roster.create("Aldren" if sex == "male" else "Edda", "warden", appearance)
		check(made.ok, sex + " roster creation")
		game.character = made.character
		game.start_game(false)
		check(game.player.appearance == appearance, sex + " appearance enters actual player")
		check(game.player.rig is ForgeRig, sex + " supplied animations drive actual player")
		var saved: Dictionary = game.save.serialize()
		check(saved.player.appearance == appearance, sex + " appearance serialized per character")
		var before_inventory := JSON.stringify(saved.inventory)
		game.player.set_appearance(ForgeCharacter.defaults())
		game.save.apply(saved)
		check(game.player.appearance == appearance, sex + " appearance restored")
		check(JSON.stringify(game.inventory.serialize()) == before_inventory, sex + " possessions preserved")
		game.hud.title._preview_selected(made.character)
		# The roster preview reads saved data, so persist to the isolated store.
		game.save.key = made.character.key
		check(game.save.save().ok, sex + " isolated character save")
		game.hud.title._preview_selected(made.character)
		check(game.hud.title.sel.preview.actor.appearance == appearance, sex + " selection reads saved appearance")
		var actor = game.player
		var sk: Skeleton3D = actor.model.find_children("*", "Skeleton3D", true, false)[0]
		check(sk.get_bone_count() == 68, sex + " canonical 68 bone rig")
		for socket in ["Torso", "Head", "Arm_L", "Arm_R", "Weapon"]:
			check(actor.model.find_child(socket, true, false) != null, sex + " gear socket " + socket)
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ForgeCharacter.ROOT + "animation_catalog.json"))
		for key in catalog:
			check(actor.rig.anim.has_animation(key), sex + " supplied clip " + key)
			check(actor.rig.anim.get_animation(key).loop_mode == (Animation.LOOP_LINEAR if catalog[key].loop else Animation.LOOP_NONE), sex + " source loop flag " + key)
		for type in DB.spell_poses.keys() + ["strike", "cast", "shoot", "brace", "drink", "castLine", "reel"]:
			actor.rig.play(type, 0.6, 0.35)
			for i in 8: actor.rig.update(0.1, 0.0)
			check(actor.rig.action == null, sex + " recovery finishes " + type)
			check(actor.rig.last_action_clip != "A_TPose", sex + " gameplay clip " + type)
		for key in ForgeCharacter.defaults():
			if key == "version": continue
			for value in ForgeCharacter.choices(key, sex):
				var look := appearance.duplicate(true)
				look[key] = value
				actor.set_appearance(look)
				check(actor.appearance[key] == value, sex + " appearance option " + key + ":" + value)
		actor.set_appearance(appearance)
		var legacy := saved.duplicate(true)
		legacy.player.erase("appearance")
		game.save.apply(legacy)
		check(actor.appearance == ForgeCharacter.defaults(), sex + " safe legacy default")
		game.started = false
	# Use the actual creator and logout/reload paths as well as direct save tests.
	current_scene = game
	var title = game.hud.title
	title.creator_appearance = ForgeCharacter.defaults()
	title.creator_appearance.sex = "female"
	title.creator_appearance.hair = "ponytail"
	title.create.name.text = "Fenna"
	title.class_id = "ranger"
	title.do_create()
	while not game.started or game.hud.loading.visible: await process_frame
	game.set_process(false)
	game.save.autosave_enabled = false
	var hero_id: String = game.character.id
	var expected: Dictionary = game.player.appearance.duplicate(true)
	check(expected.sex == "female" and expected.hair == "ponytail", "actual creator applies the chosen body and hair")
	var possessions: String = JSON.stringify(game.inventory.serialize())
	game.log_out()
	await scene_changed
	game = current_scene
	check(game.hud.title.view == "select", "actual logout returns to selection")
	game.enter_world(hero_id)
	while not game.started or game.hud.loading.visible: await process_frame
	game.set_process(false)
	game.save.autosave_enabled = false
	check(game.player.appearance == expected, "actual re-entry reloads the saved appearance")
	check(JSON.stringify(game.inventory.serialize()) == possessions, "actual re-entry reloads the saved possessions")
	print("forge_character_check: %d checks, %d failures" % [checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

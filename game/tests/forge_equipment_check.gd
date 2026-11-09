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
	Store.dir = "user://forge_equipment_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var representatives := {}
	for id in DB.items:
		var item: Dictionary = DB.items[id]
		if item.get("slot") in ["mainHand", "oneHand", "offHand", "ranged", "head", "back", "chest", "hands", "legs", "feet"]:
			var key := str(item.get("slot")) + ":" + str(item.get("model", item.get("cosmetic", "")))
			if not representatives.has(key): representatives[key] = id
	var player = game.player
	for sex in ["male", "female"]:
		var look := ForgeCharacter.defaults()
		look.sex = sex
		player.set_appearance(look)
		for key in representatives:
			var id: String = representatives[key]
			var definition: Dictionary = DB.items[id]
			var slot: String = definition.slot
			if slot == "oneHand": slot = "mainHand"
			var equipment := {}
			equipment[slot] = {"id":id, "count":1}
			game.inventory.equipment = equipment
			var before := JSON.stringify(equipment)
			player.show_equipment(equipment)
			check(JSON.stringify(equipment) == before, sex + " identity preserved " + id)
			for action in ["strike", "cast", "guard"]:
				player.rig.play(action, 0.6, 0.4)
				for i in 4: player.rig.update(0.1, 0.5)
				await process_frame
				var sk: Skeleton3D = player.model.find_children("*", "Skeleton3D", true, false)[0]
				var finite := true
				for bone in sk.get_bone_count():
					finite = finite and sk.get_bone_global_pose(bone).is_finite()
				check(finite, sex + " stable pose " + id + ":" + action)
				if definition.get("weaponType") == "twoHand":
					check(player.rig.secondary_grip_error < 0.08, sex + " secondary grip within 8 cm " + action + ":" + str(player.rig.secondary_grip_error))
			player.sheathed = true
			player._show_sheath()
			check(player.weapon_part == null or not player.weapon_part.visible, sex + " sheathed visibility " + id)
			player.sheathed = false
			player.show_equipment(equipment)
			if slot == "ranged":
				player.hold_bow(true)
				player.rig.play("shoot", 0.8, 0.5)
				player.rig.update(0.2, 0.0)
				check(player.bow != null and player.bow.get_parent() == player._part("Arm_L"), sex + " bow uses left hand " + id)
				player.hold_bow(false)
		var pair := {"mainHand":{"id":"oak_club", "count":1}, "offHand":{"id":"ironwood_club", "count":1}}
		game.inventory.equipment = pair
		player.show_equipment(pair)
		player.rig.play("strike", 0.8, 0.4)
		player.rig.play_off(0.8, 0.6)
		for i in 10: player.rig.update(0.1, 1.0)
		check(player.rig.action == null and player.rig.off_action == null, sex + " both dual wield clocks recover")
	print("forge_equipment_check: %d representative paths, %d checks, %d failures" % [representatives.size(), checks, failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

extends SceneTree
## The test vendor by the start sells the fancy test gear for nothing, and
## the gear shows on the character: glowing weapons (both hands), wings on
## the back, a halo or horns on the head (FancyGear).
##   godot --headless --path . --script res://game/tests/fancy_gear_check.gd
## With SHOT=<folder> (and a real display) it saves fancy.png there.

var game
var frame := 0
var failed := 0


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Fancy", "warden")
		game.enter_world(made.character.id)
	elif frame == 3:
		var n = game.npcs.by_id("test_vendor")
		_ok(n != null, "the test vendor is in the world")
		if n == null:
			return _end()
		var p: Vector3 = game.player.position
		var d := Vector2(p.x - n.position.x, p.z - n.position.z).length()
		_ok(d < 20, "and stands by the start (%.1f m)" % d)
		var stock: Array = DB.shops.test_curios.stock
		game.merchant.open("test_curios", n)
		_ok(stock.all(func(id): return game.merchant.price_of(id) == 0), "every piece is free")
		var inv = game.inventory
		# the warden dual wields; the shield goes so the off hand is free
		inv.equipment.offHand = null
		var worn := 0
		for id in ["test_emberbrand", "test_voidfang", "test_glow_wings", "test_halo"]:
			if game.merchant.buy(id) and inv.equip(id):
				worn += 1
		_ok(worn == 4, "a new character can buy and wear them (%d of 4)" % worn)
		game.merchant.close()
		game.player.show_equipment(inv.equipment)
		var pl = game.player
		_ok(pl.weapon_part and pl.weapon_part.find_child("Glow", false, false) is FancyGear, "the main hand weapon glows")
		_ok(pl.shield and pl.shield.find_child("Glow", false, false) is FancyGear, "an off hand weapon glows too")
		_ok(pl.helm is FancyGear and pl.helm.name == "Cosmetic_halo", "the halo is worn")
		_ok(pl.cloak is FancyGear and pl.cloak.flap.size() == 2, "the wings are worn, two of them")
		# the small backpack is full by now: make room for the horns
		for l in inv.bag_locations():
			if inv.get_at(l) != null:
				inv.remove_all(inv.get_at(l).id)
		game.merchant.open("test_curios", n)
		_ok(game.merchant.buy("test_horns") and inv.equip("test_horns"), "the horns can be bought and worn")
		game.merchant.close()
		pl.show_equipment(inv.equipment)
		_ok(pl.helm is FancyGear and pl.helm.name == "Cosmetic_horns", "horns replace the halo")
		pl.set_sheathed(true)
		pl.set_sheathed(false)
		_ok(pl.weapon_part.find_child("Glow", false, false) is FancyGear, "sheathing and drawing keeps the glow")
		if OS.get_environment("SHOT") == "":
			return _end()
	elif frame == 40:
		game.player.facing = PI * 0.25
		game.player.position.x = game.npcs.by_id("test_vendor").position.x + 2.0
		game.player.position.z = game.npcs.by_id("test_vendor").position.z + 2.0
	elif frame == 120:
		root.get_texture().get_image().save_png(OS.get_environment("SHOT") + "/fancy.png")
		return _end()
	return false


func _end() -> bool:
	print("fancy gear check: %s" % ("all checks pass" if failed == 0 else "%d failed" % failed))
	quit(1 if failed else 0)
	return true


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
	print(("  ok    " if cond else "  FAIL  ") + what)

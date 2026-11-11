extends SceneTree
## Quest ! and ? hide behind houses and off the minimap; ability hits get
## their own number colour; the blob shadow stays flat through a flip.
## Run: godot --headless -s game/tests/quest_mark_check.gd
var game
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok: failures += 1
func _run() -> void:
	Store.dir = "user://quest_mark_check_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var made: Dictionary = game.roster.create("Marker", "warden")
	game.enter_world(made.character.id)
	var began := Time.get_ticks_msec()
	while game.hud.loading.visible:
		await process_frame
		if Time.get_ticks_msec() - began > 240000:
			check(false, "world loads")
			quit(1)
			return
	game.save.autosave_enabled = false
	# a house between the camera and a point hides it; open air does not
	var st = game.world.see_through
	var h = null
	for x in st.houses:
		if is_instance_valid(x.mi) and x.mi.is_inside_tree():
			h = x
			break
	check(h != null, "a house is drawn with the see-through circle")
	if h:
		var c: Vector3 = h.mi.global_transform * h.mi.get_aabb().get_center()
		check(st.hides(c + Vector3(0, 40, 30), c - Vector3(0, 0.5, 0)), "a point behind a house is hidden")
		check(not st.hides(c + Vector3(0, 40, 30), c + Vector3(0, 30, 22)), "a point in open air shows")
	# ability numbers read apart from auto attacks
	check(DamageNumbers.COLOURS.has("ability") and DamageNumbers.COLOURS.ability != DamageNumbers.COLOURS.dealt, "ability hits have their own colour")
	# the contact shadow stays flat on the ground during a front flip
	var p = game.player
	p.flip = 0.2
	p.jump_h = 1.0
	p.position.y += 1.0
	p._sync()
	var b: Basis = p.ground_shadow.global_transform.basis
	# it lies along the slope under the feet, never turned by the flip
	var n := Land.ground_normal(p.position.x, p.position.z)
	check(absf(b.y.normalized().dot(n) - 1.0) < 0.001, "shadow does not turn with the flip")
	check(absf(p.ground_shadow.global_position.y - (p.position.y - 1.0 + 0.03)) < 0.001, "shadow stays on the ground mid-jump")
	print("quest mark check: %d failed" % failures)
	quit(1 if failures else 0)

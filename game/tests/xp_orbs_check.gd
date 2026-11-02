extends SceneTree
## Cosmetic XP orbs (Dan 2026-11-02): a kill bursts small purple orbs that
## home in on the player, follow them as they run, and all arrive; the XP is
## granted at once and the orbs never touch it. A big pack stays in the pool.
##   godot --headless --path . --script res://game/tests/xp_orbs_check.gd
## With a window and a folder argument it also saves a screenshot:
##   godot --path . --script res://game/tests/xp_orbs_check.gd -- out/

var failures := 0
var game
var frame := 0
var started := false


func _process(_dt: float) -> bool:
	if started:
		return false
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_orbs_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Orb Tester", "warden")
		game.enter_world(made.character.id)
	elif frame > 2 and not (game.hud.modal == "loading" or game.hud.blocks_gameplay):
		started = true
		game.set_process(false)
		_run()
	elif frame > 3000:
		check(false, "the world loads")
		quit(1)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _run() -> void:
	var orbs = game.xp_orbs
	var p: Vector3 = game.player.position
	var xp_before: int = game.progression.xp
	var body := {"position": p + Vector3(6, 0, 0)}
	game.events.emit("xpGained", {"target": body, "amount": 60})
	check(orbs.orbs.size() == orbs.count_for(60) and orbs.count_for(60) >= 3, "a kill bursts a few orbs (%d)" % orbs.orbs.size())
	check(orbs.count_for(5) == 3 and orbs.count_for(100000) == 8, "orb count stays between 3 and 8 a kill")
	check(game.progression.xp == xp_before, "the orbs never grant XP themselves")
	# a huge pack: the pool caps out instead of growing
	for i in 40:
		orbs.spawn(p + Vector3(randf_range(-8, 8), 0, randf_range(-8, 8)), 8)
	check(orbs.orbs.size() <= orbs.MAX_ORBS, "a huge pack stays within the pool (%d)" % orbs.orbs.size())
	var shot := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else ""
	if shot != "" and DisplayServer.get_name() != "headless":
		for i in 22:
			orbs.update(1.0 / 60.0)
		for i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(shot)
		root.get_texture().get_image().save_png(shot.path_join("xp-orbs.png"))
		game.events.emit("xpGained", {"target": body, "amount": 60})
	# the player runs away; every orb still catches up within a few seconds
	var dt := 1.0 / 60.0
	var peak_heads := 0
	for i in 300:
		game.player.position += Vector3(0, 0, 6.2 * dt)
		orbs.update(dt)
		peak_heads = maxi(peak_heads, orbs.heads.visible_instance_count)
	check(peak_heads > 0, "orbs are drawn (%d at once)" % peak_heads)
	check(orbs.orbs.is_empty(), "every orb reaches a running player within 5 s (%d left)" % orbs.orbs.size())
	for i in 30:
		orbs.update(dt)
	check(not orbs.nodes[0].visible and orbs.heads.visible_instance_count == 0, "nothing left on screen once they land")
	print("xp orb checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)

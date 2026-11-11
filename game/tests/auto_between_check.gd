extends SceneTree
## Enemies with telegraphed attacks auto attack between them (Dan,
## 2026-11-11, DB.CONFIG.autoBetween): a cleaver opens with a cleave, then
## swings untelegraphed until its next cleave; an archer looses quick shots
## between its aimed shots. Autos hit for less, telegraphs for more:
##   godot --headless --path . --script res://game/tests/auto_between_check.gd

var failures := 0
var game
var frame := 0
var started := false


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://test_store_autob_%d" % Time.get_ticks_usec()
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 2:
		var made: Dictionary = game.roster.create("Autob", "warden")
		game.enter_world(made.character.id)
	if frame <= 2 or started:
		return false
	if game.hud.modal == "loading" or game.hud.blocks_gameplay:
		if frame > 3000:
			check(false, "the world loads")
			quit(1)
		return false
	started = true
	game.set_process(false)
	_run()
	print("auto between checks: %s" % ("all passed" if failures == 0 else "%d failed" % failures))
	quit(1 if failures else 0)
	return false


func check(ok: bool, label: String) -> void:
	print("ok: " if ok else "FAIL: ", label)
	if not ok:
		failures += 1


func _find(key: String):
	for e in game.enemies.list:
		if e.alive and e.cfg.get(key) and not e.cfg.get("special") and not e.cfg.get("circle"):
			return e
	return null


## Run a fight for `seconds`, the player kept alive and in place `dist` m
## from the foe; returns the order of attacks: T telegraph, A auto.
func _fight(foe, dist: float, seconds: float) -> String:
	var pl = game.player
	var dt := 1.0 / 60.0
	pl.position = foe.position + Vector3(dist, 0, 0)
	foe.state = "attack"
	foe.charge = 5.0
	foe.attack_timer = 0.0
	foe.slots = 99
	var seq := ""
	var was_casting := false
	var last_timer := 0.0
	for i in int(seconds / dt):
		pl.health = pl.max_health
		pl.position = foe.position + Vector3(dist, 0, 0)
		foe.update(dt, pl)
		game.telegraphs.update(dt)
		var casting: bool = foe.casting != null
		if casting and not was_casting:
			seq += "T"
		elif not casting and foe.attack_timer > last_timer + 0.2:
			seq += "A"
		was_casting = casting
		last_timer = foe.attack_timer
	return seq


func _run() -> void:
	var ab: Dictionary = DB.CONFIG.autoBetween
	var cleaver = _find("telegraph")
	check(cleaver != null, "an enemy with a telegraphed cleave is in the world")
	if cleaver:
		print("  cleaver: ", cleaver.cfg.name)
		var seq := _fight(cleaver, 1.2, 12.0)
		check(seq.begins_with("TAAT"), "a cleaver opens with a cleave, then autos between cleaves (%s)" % seq)
		check(seq.count("A") >= seq.count("T"), "a cleaver autos at least as often as it cleaves (%s)" % seq)
	var archer = _find("ranged")
	check(archer != null, "an archer is in the world")
	if archer:
		print("  archer: ", archer.cfg.name)
		var seq2 := _fight(archer, 9.0, 12.0)
		check(seq2.begins_with("TAT"), "archer opens with an aimed shot, then quick shots between them (%s)" % seq2)
	check(ab.autoShare < 1.0 and ab.telegraphScale > 1.0, "autos hit softer than the telegraph")

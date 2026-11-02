extends SceneTree
## Telegraphs can be dodged (Dan, 2026-11-02): an enemy that starts a
## ground-marked attack commits to it; the player walking away does not
## cancel it, and the enemy holds still until it lands.
##   godot --headless --path . --script res://game/tests/telegraph_dodge_check.gd

var game
var frame := 0
var failed := 0
var cases := []
var cur = null
var t = null
var start: Vector3
var pstart: Vector3
var waited := 0


func _process(dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://telegraph_check_%d" % Time.get_ticks_usec()
		DB.ready = false
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
		var made: Dictionary = game.roster.create("Dodge Tester", OS.get_environment("DODGE_CLASS") if OS.get_environment("DODGE_CLASS") != "" else "warden")
		game.enter_world(made.character.id)
	elif not game.started or game.hud.blocks_gameplay or game.hud.loading.visible:
		frame = 2
		return false
	elif frame == 3:
		game.player.max_health = 99999
		game.player.health = 99999
		for e in game.enemies.list:
			for kind in ["normal", "special", "circle", "shot"]:
				var c = e.cfg
				if (kind == "normal" and c.get("telegraph")) or (kind == "special" and c.get("special") != null) \
						or (kind == "circle" and c.get("circle") != null) or (kind == "shot" and c.get("ranged") != null and c.get("circle") == null):
					if not cases.any(func(x): return x[0].cfg.name == c.name and x[1] == kind):
						cases.append([e, kind])
	elif cur == null:
		if cases.is_empty():
			print("telegraph dodge check: %s" % ("all passed" if failed == 0 else "%d failed" % failed))
			quit(1 if failed else 0)
			return false
		_begin(cases.pop_front())
	else:
		var e = cur[0]
		var p = game.player
		# walk away from the enemy at run speed
		game.input.held["KeyS"] = true
		waited += 1
		if t.done or waited > 400:
			_ok(t.done and waited < 400, "%s %s landed" % [e.cfg.name, cur[1]])
			game.input.held.erase("KeyS")
			print("checked %s %s after %d frames (%.2fs), player moved %.1f m, still inside %s" % [e.cfg.name, cur[1], waited, waited * dt, p.position.distance_to(pstart), t.shape.contains(p.position.x, p.position.z, p.radius)])
			cur = null
		elif e.casting == null:
			game.input.held.erase("KeyS")
			_ok(false, "%s %s was dropped when the player moved (state %s)" % [e.cfg.name, cur[1], e.state])
			cur = null
		elif e.position.distance_to(start) > 0.3:
			_ok(false, "%s moved while casting %s" % [e.cfg.name, cur[1]])
			cur = null
	return false


func _begin(c) -> void:
	cur = c
	var e = c[0]
	var p = game.player
	for o in game.enemies.list:
		if o != e:
			o.position = Vector3(9999, 0, 9999)
			o.state = "idle"
	e.reset()
	var kind: String = c[1]
	var d: float = 1.2 if kind == "normal" or kind == "special" else 4.0 if kind == "circle" else e.cfg.ranged.range * 0.7
	p.position = e.position + Vector3(0, 0, d)
	e.state = "attack" if kind == "normal" else "chase"
	e.mana = e.cfg.get("mana", 0)
	e.special_timer = 0.0 if kind == "special" else 99.0
	e.circle_timer = 0.0 if kind == "circle" else 99.0
	e.attack_timer = 0.0
	game.targeting.select(e)
	game.targeting.engage(e)
	e.update(0.016, p)
	start = e.position
	pstart = p.position
	waited = 0
	if e.casting == null:
		_ok(false, "%s did not start %s" % [e.cfg.name, kind])
		cur = null
		return
	t = e.casting.telegraph


func _ok(cond: bool, what: String) -> void:
	if not cond:
		failed += 1
		print("FAILED: ", what)

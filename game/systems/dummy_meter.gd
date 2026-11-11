class_name DummyMeter
extends RefCounted
## The training yard's readout: a line over a training dummy (enemies.json
## `dummy: true`) while you hit it: damage per second since your first blow,
## the total, hits, crits and misses. It clears once the dummy mends (6 s
## after the last hit). Counts every blow the game shows a number for.

const IDLE := 6.0 ## seconds without a hit before the meter clears (the dummy's `engaged`)

var game
var meters := {} ## enemy -> {start, last, total, hits, crits, misses, label}


func _init(g) -> void:
	game = g
	game.events.on("damageNumber", _on_number)


func _on_number(e: Dictionary) -> void:
	var enemy = e.get("target")
	if not (enemy is Enemy):
		return
	if not enemy.cfg.get("dummy", false):
		return
	var kind: String = e.get("kind", "")
	if kind != "dealt" and kind != "miss":
		return
	var now := Time.get_ticks_msec() / 1000.0
	var m: Dictionary = meters.get(enemy, {})
	if m.is_empty():
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = true
		label.pixel_size = 0.0011
		label.font_size = 22
		label.outline_size = 8
		label.modulate = Color("ffe9a8")
		label.position = Vector3(0, 2.9, 0)
		enemy.group.add_child(label)
		m = {"start": now, "last": now, "total": 0.0, "hits": 0, "crits": 0, "misses": 0, "label": label}
		meters[enemy] = m
	m.last = now
	if kind == "miss":
		m.misses += 1
	else:
		m.total += float(e.get("amount", 0))
		m.hits += 1
		if e.get("crit", false):
			m.crits += 1
	_show(m)


func dps(m: Dictionary) -> float:
	return m.total / maxf(1.0, m.last - m.start)


func _show(m: Dictionary) -> void:
	m.label.text = "%s DPS\n%s dealt · %d hits · %d crits · %d misses" % [U.n(snappedf(dps(m), 0.1)), U.n(roundi(m.total)), m.hits, m.crits, m.misses]


func update() -> void:
	if meters.is_empty():
		return
	var now := Time.get_ticks_msec() / 1000.0
	for enemy in meters.keys():
		var m: Dictionary = meters[enemy]
		if not is_instance_valid(m.label) or now - m.last > IDLE:
			if is_instance_valid(m.label):
				m.label.queue_free()
			meters.erase(enemy)

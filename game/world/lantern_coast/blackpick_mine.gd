extends RefCounted
## An optional local solo run. Its combat and geometry are scoped to this visit.

const ORIGIN := Vector2(-892.0, -470.0)
const FLOOR := 54.0
const ROOMS := [Rect2(-8, 14, 16, 14), Rect2(-3, 6, 6, 8), Rect2(-10, -10, 20, 16),
	Rect2(3, -20, 6, 10), Rect2(-3, -38, 24, 18)]
const ENTRANCE := Vector2(0, 24)
const CHECKPOINT := Vector2(6, -6)
const FIRST := Vector2(2, -2)
const BOSS := Vector2(8, -29)
const REWARD := Vector2(14, -32)
const RECEIPT := "lc_blackpick_paid"
const WEAPONS := {"warden":"arming_sword", "rogue":"rusty_dirk", "ranger":"hunting_bow",
	"wizard":"ritual_knife", "occultist":"ritual_knife", "paladin":"arming_sword"}

var game
var entrance: Dictionary
var interior: Node3D
var actor: Enemy
var stage := -1
var brake := false
var paid := false
var restarting := false
var hints := false
var practice_owner := {"position":Vector3.ZERO, "dead":false}
var gate: Node3D


func _init(g, placement: Dictionary) -> void:
	game = g
	entrance = placement
	_build_entrance()


func _build_entrance() -> void:
	var at := outside()
	var lift := Node3D.new()
	lift.name = "BlackpickMineLift"
	lift.position = Vector3(at.x, Terrain.height_at(at.x, at.y), at.y)
	game.world.group.add_child(lift)
	var timber := Color("60442f")
	var iron := Color("595351")
	for x in [-1.10, 1.10]:
		_box(Vector3(x, 1.31, 0), Vector3(0.26, 2.62, 0.34), timber, lift)
		_box(Vector3(x, 0.23, 0), Vector3(0.40, 0.46, 0.46), iron, lift)
	_box(Vector3(0, 2.64, 0), Vector3(2.72, 0.32, 0.43), timber, lift)
	_box(Vector3(0, 2.13, 0), Vector3(0.07, 0.73, 0.07), iron, lift)
	for row in 6:
		_box(Vector3(0, 0.045, row * 0.29 - 0.73), Vector3(1.86, 0.10, 0.26), timber.lightened(0.03 * (row % 3)), lift)
	var sign := Label3D.new()
	sign.text = "BLACKPICK MINE"
	sign.position.y = 3.05
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.font_size = 40
	sign.pixel_size = 0.009
	sign.modulate = Color("f8d3a0")
	sign.outline_size = 9
	lift.add_child(sign)
	game.atmosphere.add_coast_lamp(lift.position + Vector3(1.12, 2.08, 0.12), "amber")


func outside() -> Vector2:
	return Vector2(entrance.position[0], entrance.position[1])


func active() -> bool:
	return stage >= 0


func floor_at(p: Vector2, radius := 0.0) -> bool:
	var local := p - ORIGIN
	if not ROOMS.any(func(room): return room.has_point(local)):
		return false
	for axis in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		if not ROOMS.any(func(room): return room.has_point(local + axis * radius)):
			return false
	return brake or local.y >= -10.0 + radius


func occupies(p: Vector2) -> bool:
	return Rect2(ORIGIN + Vector2(-20, -45), Vector2(55, 82)).has_point(p)


func interactions() -> Array:
	if not active():
		var site := outside()
		return [_action("entry", site, "Take the lift into Blackpick Mine (Level 8)", enter)]
	var result := [_action("exit", ORIGIN + ENTRANCE, "Take the lift back to Bellharbor", leave),
		_action("practice", ORIGIN + Vector2(-5, 22), "Read the miner’s notes and demonstrate the danger marks", practice)]
	if stage >= 1 and not brake:
		result.append(_action("brake", ORIGIN + Vector2(6, -8), "Release the haulage brake", release_brake))
	if stage == 2 and not paid:
		result.append(_action("payroll", ORIGIN + REWARD, "Recover the miners’ payroll", claim))
	if stage == 2:
		result.append(_action("ladder", ORIGIN + Vector2(17, -24), "Take the service ladder to Bellharbor", leave))
	return result


func _action(id: String, point: Vector2, prompt: String, run: Callable) -> Dictionary:
	return {"key":"dungeon:blackpick_" + id, "x":point.x, "z":point.y, "reach":3.0,
		"bias":0.1, "prompt":prompt, "name":"Blackpick Mine", "cursor":"talk", "run":run}


func enter() -> bool:
	if game.progression.level < int(entrance.minimum):
		game.hud.error("Blackpick Mine opens at level 8.")
		return false
	if active() or game.player.dead or game.releasing or game.combat_blocks_logout():
		return false
	stage = 0
	brake = false
	paid = false
	hints = false
	practice_owner.dead = false
	game._coast_surface.dungeon = self
	_build()
	game.world.coast_scene.hide()
	game.targeting.clear()
	game.move_to = null
	_spawn()
	var at := ORIGIN + ENTRANCE
	game.travel_to(at.x, at.y, PI, "Descending into Blackpick Mine…")
	game.events.emit("log", {"kind":"lore", "text":"A foreman’s chalk mark points to the practice bay. The paymaster is further in."})
	return true


func leave() -> bool:
	if not active():
		return false
	if game.player.dead or game.releasing or game.combat_blocks_logout():
		game.hud.error("You can leave once the fighting has stopped.")
		return false
	_end()
	var at := outside()
	game.travel_to(at.x, at.y, 0.0, "Returning to Bellharbor…")
	return true


func update() -> void:
	if active() and not restarting and not occupies(Vector2(game.player.position.x, game.player.position.z)):
		_end() # Return Home or another permitted travel spell left the mine.


func _end() -> void:
	_remove_actor()
	game.telegraphs.cancel_for(practice_owner)
	practice_owner.dead = true
	stage = -1
	game._coast_surface.dungeon = null
	interior.queue_free()
	game.world.coast_scene.show()


func _spawn() -> void:
	var second := stage == 1
	var at := ORIGIN + (BOSS if second else FIRST)
	actor = Enemy.new(game, {"id":"lc_blackpick_foreman" if second else "lc_blackpick_hobb",
		"type":"blackhedge_cutthroat", "level":10 if second else 8, "position":[at.x, at.y]})
	actor.cfg = actor.cfg.duplicate(true)
	actor.cfg.merge({"name":"Foreman Blackpick" if second else "Hobb the Paymaster", "detection":8,
		"flees":false, "roam":1.0, "leash":20.0, "telegraph":true, "scale":1.2 if second else 1.06,
		"special":{"name":"Timber Sweep" if second else "Paymaster’s Swing", "windup":2.35,
			"cooldown":8.0, "trigger":3.8, "range":4.8, "arc":115, "interruptible":true,
			"damage":snappedf(actor.cfg.damage * 1.8, 0.1), "impactEvent":""}}, true)
	actor.max_health *= 1.6 if second else 1.18
	actor.health = actor.max_health
	game.enemies.list.append(actor)


func _remove_actor() -> void:
	if actor == null:
		return
	game.targeting.clear()
	game.telegraphs.cancel_for(actor)
	game.enemies.list.erase(actor)
	if is_instance_valid(actor.group):
		actor.group.queue_free()
	actor = null


func defeated(enemy: Enemy) -> bool:
	if not active() or enemy != actor:
		return false
	if stage == 0:
		stage = 1
		game.events.emit("log", {"kind":"quest", "text":"Hobb is down. Release the marked haulage brake to reach the foreman. Checkpoint secured."})
	elif stage == 1 and brake:
		stage = 2
		game.events.emit("log", {"kind":"quest", "text":"Blackpick is down. Recover the payroll from his chest, then take the service ladder."})
	return true


func release_brake() -> bool:
	if stage != 1 or brake:
		return false
	brake = true
	gate.hide()
	_remove_actor()
	_spawn()
	return true


func on_death() -> void:
	if not restarting:
		restarting = true
		_retry.call_deferred()


func _retry() -> void:
	game.telegraphs.clear()
	if stage == 0 or (stage == 1 and brake):
		_remove_actor()
		_spawn()
	var at := ORIGIN + (CHECKPOINT if stage >= 1 else ENTRANCE)
	game.player.revive(at.x, at.y)
	game._snap_camera()
	game.hud.toast("Returned to the mine checkpoint")
	restarting = false


func practice() -> void:
	if hints:
		return
	hints = true
	game.events.emit("log", {"kind":"lore", "text":"Chalkboard: leave any filled shape before it completes. Step sideways out of a line, back from a sweep, or outside a circle. An interrupt can stop an interruptible swing."})
	practice_owner.position = Vector3(ORIGIN.x + 0.0, FLOOR, ORIGIN.y + 18)
	game.telegraphs.cone(practice_owner, {"angle":PI * 0.5, "range":4.0, "arc":100, "duration":3.0})
	game.telegraphs.line(practice_owner, {"angle":PI * 1.5, "length":4.5, "width":1.1, "duration":3.0})
	game.telegraphs.circle(practice_owner, {"x":ORIGIN.x + 3.3, "z":ORIGIN.y + 24.0, "radius":1.6, "duration":3.0})


func claim() -> bool:
	if stage != 2 or paid:
		return false
	var first: bool = not game.world_state.flags.get(RECEIPT, false)
	if first:
		var weapon: String = "wm_rillbank_quays_" + WEAPONS.get(game.archetype_id, "arming_sword")
		if not game.inventory.add_item(weapon, 1):
			game.hud.error("Make room in your bags for the miners’ reward.")
			return false
		game.world_state.flags[RECEIPT] = true
		game.progression.add_xp(roundi(game.progression.xp_to_next * 0.35))
	paid = true
	game.inventory.add_coins(45 if first else 18, "from the Blackpick payroll")
	game.save.autosave()
	game.hud.toast("Blackpick Mine cleared")
	return true


func _build() -> void:
	interior = Node3D.new()
	interior.name = "BlackpickMine"
	interior.position = Vector3(ORIGIN.x, FLOOR, ORIGIN.y)
	game.world.group.add_child(interior)
	for rect in ROOMS:
		var centre: Vector2 = rect.get_center()
		_box(Vector3(centre.x, -0.33, centre.y), Vector3(rect.size.x, 0.66, rect.size.y), Color("554537"))
		_wall(rect.position, Vector2.RIGHT, Vector2.UP, int(rect.size.x), 2.1)
		_wall(Vector2(rect.position.x, rect.end.y), Vector2.RIGHT, Vector2.DOWN, int(rect.size.x), 0.85)
		_wall(rect.position, Vector2.DOWN, Vector2.LEFT, int(rect.size.y), 1.25)
		_wall(Vector2(rect.end.x, rect.position.y), Vector2.DOWN, Vector2.RIGHT, int(rect.size.y), 0.85)
	for i in range(-34, 27, 4):
		for j in range(-7, 20):
			var p := Vector2(j, i)
			if not ROOMS.any(func(rect): return rect.has_point(p + Vector2(0.12, 0.08))):
				continue
			if j % 4 == 0:
				var wash := Color("685440") if (i + j) % 3 else Color("493e37")
				_box(Vector3(p.x, 0.008, p.y), Vector3(1.5, 0.02, 1.7), wash)
	for check in [Vector2(-7, 22), Vector2(7, 21), Vector2(-9, -3), Vector2(9, -5), Vector2(-1, -36), Vector2(19, -29)]:
		_box(Vector3(check.x, 1.2, check.y), Vector3(0.46, 2.4, 0.46), Color("4a3021"))
		var light := Tex.point_light(Color("ffab60"), 2.9, 12, 1.3)
		light.position = Vector3(check.x, 2.4, check.y)
		interior.add_child(light)
	for z in range(6, 15, 2):
		_box(Vector3(0, 0.04, z), Vector3(2.6, 0.08, 0.27), Color("593b27"))
	for x in [-0.85, 0.85]:
		_box(Vector3(x, 0.1, 10), Vector3(0.12, 0.12, 8.0), Color("827673"))
	for prop in [["cart", Vector2(-6, -5)], ["crate", Vector2(-5, -4)], ["crate_broken", Vector2(17, -34)]]:
		var model := Assets.instance(prop[0])
		model.position = Vector3(prop[1].x, 0.0, prop[1].y)
		model.rotation.y = 0.55
		interior.add_child(model)
	for marker in [[ENTRANCE, "Lift to Bellharbor"], [Vector2(-5, 22), "Practice Bay"],
			[Vector2(6, -8), "Haulage Brake"], [REWARD, "Payroll Chest"], [Vector2(17, -24), "Service Ladder"]]:
		var p: Vector2 = marker[0]
		var sign := Label3D.new()
		sign.text = marker[1]
		sign.position = Vector3(p.x, 1.85, p.y)
		sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sign.font_size = 34
		sign.pixel_size = 0.005
		interior.add_child(sign)
	gate = _box(Vector3(6, 0.8, -10), Vector3(6.0, 1.6, 0.4), Color("63452a"))
	var chest := Assets.instance("chest")
	chest.position = Vector3(REWARD.x, 0.0, REWARD.y)
	interior.add_child(chest)


func _wall(start: Vector2, along: Vector2, outward: Vector2, length: int, height: float) -> void:
	var run_start := -1
	for step in range(length + 1):
		var probe := start + along * (step + 0.5) + outward * 0.12
		if step < length and not ROOMS.any(func(room): return room.has_point(probe)):
			if run_start < 0:
				run_start = step
			continue
		if run_start < 0:
			continue
		var width := float(step - run_start)
		var centre := start + along * (run_start + width * 0.5) + outward * 0.45
		var size := Vector3(width, height, 0.95) if along.x > 0.0 else Vector3(0.95, height, width)
		_box(Vector3(centre.x, height * 0.5, centre.y), size, Color("403934"))
		run_start = -1


func _box(at: Vector3, size: Vector3, colour: Color, parent: Node3D = null) -> MeshInstance3D:
	var box := World._box(size, colour, false)
	box.position = at
	(parent if parent != null else interior).add_child(box)
	return box

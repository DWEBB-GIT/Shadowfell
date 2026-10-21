class_name Targeting
extends RefCounted
## Targeting, WoW style (src/systems/targeting.js).
##
## Selecting: left-click an enemy (or Tab / R3 to cycle through those near
## you) to make it your target. A ring marks it and the HUD shows its frame.
## Left-clicking a townsperson selects them as a friendly target. Escape
## clears the target.
##
## Auto attack: right-click an enemy (RT on a pad), or use any ability on it,
## to engage it. Abilities go to the selected enemy; with nothing selected
## they go to the enemy nearest your aim, which a faint ring shows.
##
## Only what you can see: soft lock, Tab and RT pick only enemies inside the
## camera view, or ones already fighting you.

var game
var current = null ## the selected enemy, or null
var friendly = null ## a selected townsperson (Npc), or null
var attacking := false ## auto attack on the selected enemy
var soft = null ## who an ability would go to with nothing selected
var target_moving := false
var marker: MeshInstance3D
var soft_marker: MeshInstance3D
var _last = null
var _last_for = null


## Is this enemy chasing or striking the player?
static func in_combat_with_player(e) -> bool:
	return e != null and e.alive and (e.state == "chase" or e.state == "attack")


func _init(g) -> void:
	game = g
	# the selection ring: yellow for anyone selected (left click), red once
	# you are fighting it (right click, or an ability on it)
	marker = _ring(Color("ffd040"), "TargetMarker")
	soft_marker = _ring(Color(Color("d8d0c0"), 0.3), "SoftTargetMarker")


func _ring(colour: Color, name: String) -> MeshInstance3D:
	var m := Tex.ground_quad(Tex.fx_material(Tex.ring(), colour))
	m.material_override.render_priority = 3
	m.visible = false
	m.name = name
	game.scene.add_child(m)
	return m


func _dist(e) -> float:
	var p: Vector3 = game.player.position
	return U.hyp(e.position.x - p.x, e.position.z - p.z)


## Is the enemy inside the camera view (with a small margin in from the
## screen's edge)?
func on_screen(e) -> bool:
	var cam: Camera3D = game.camera
	if cam == null:
		return true
	var p := Vector3(e.position.x, e.position.y + 1, e.position.z)
	if cam.is_position_behind(p):
		return false
	var sp := cam.unproject_position(p)
	var size := cam.get_viewport().get_visible_rect().size
	var nx := sp.x / size.x * 2 - 1
	var ny := sp.y / size.y * 2 - 1
	var m: float = DB.CONFIG.targeting.screenMargin
	return absf(nx) <= 1 - m and absf(ny) <= 1 - m


## Can a key or soft lock pick this enemy? Living, and either on screen or
## already fighting you.
func targetable(e) -> bool:
	return e != null and e.alive and (in_combat_with_player(e) or on_screen(e))


## The enemy a soft lock picks for an ability with reach `range`, given an
## aim point: inside the arc around the aim direction (or right under the
## cursor), favouring the smallest angle and then the nearest.
func soft_target(aim, range_: float):
	var player = game.player
	var p: Vector3 = player.position
	var ax: float = aim.x - p.x if aim != null else sin(player.facing)
	var az: float = aim.z - p.z if aim != null else cos(player.facing)
	var al := U.hyp(ax, az)
	if al < 0.6:
		ax = sin(player.facing) # cursor on the player: use facing
		az = cos(player.facing)
	else:
		ax /= al
		az /= al
	var arc := deg_to_rad(DB.CONFIG.targeting.softArc)
	var best = null
	var best_score := INF
	for e in game.enemies.list:
		if not targetable(e):
			continue
		var dx: float = e.position.x - p.x
		var dz: float = e.position.z - p.z
		var d := U.hyp(dx, dz)
		if d > range_ + e.radius:
			continue
		var near_cursor: bool = aim != null and U.hyp(e.position.x - aim.x, e.position.z - aim.z) <= DB.CONFIG.targeting.softAimRadius
		var angle := acos(clampf((dx * ax + dz * az) / d, -1, 1)) if d > 0.01 else 0.0
		if angle > arc and not near_cursor:
			continue
		var score := (0.0 if near_cursor else angle) + d * 0.04
		if score < best_score:
			best_score = score
			best = e
	return best


## Where an ability should go. `kind`: 'enemy' (melee or ranged at a
## target), 'ground' (lands at the aim point) or 'self'.
func aim_for(raw_aim, range_: float, kind := "enemy"):
	if kind == "ground" or kind == "self":
		return raw_aim
	var t = current if current != null and _dist(current) <= DB.CONFIG.targeting.dropRange else soft_target(raw_aim, range_)
	return t.position if t != null else raw_aim


## Make an enemy the target. Picking a different one stops auto attack.
func select(enemy):
	var next = enemy if enemy != null and enemy.alive else null
	if next != null:
		friendly = null
	if next == current:
		return next
	current = next
	attacking = false
	game.events.emit("targetChanged", {"target": current})
	return current


func select_friendly(npc) -> void:
	select(null)
	friendly = npc
	game.events.emit("targetChanged", {"target": null, "friendly": npc})


func clear():
	friendly = null
	return select(null)


## Select an enemy and start swinging at it.
func engage(enemy) -> bool:
	if select(enemy) == null:
		return false
	if not attacking:
		attacking = true
		# WoW: a fresh fight opens the moment the target is in reach: the
		# clocks are ready, and the first blow comes after a short, visible
		# windup. Switching targets mid-fight keeps the running clocks.
		var p = game.player
		var T: float = game.stats.attack_cooldown
		if not (p.last_swing_at != null and game.time - p.last_swing_at < T):
			p.cooldowns.attack = 0.0
			p.cooldowns.attackOff = 0.0
			p.cooldowns.ranged = 0.0
			p.opener = true
			p.opener_off = true
		game.events.emit("autoAttack", {"on": true, "target": enemy})
	return true


func stop_attack() -> void:
	if not attacking:
		return
	attacking = false
	game.events.emit("autoAttack", {"on": false})


## Is the target close enough to hit with a swing? Melee reach stretches a
## little (`movingLeeway`) while you and it are both moving.
var target_in_reach: bool:
	get:
		var t = current
		if t == null or not t.alive:
			return false
		var leeway: float = DB.attack.movingLeeway if game.player.moving and target_moving else 0.0
		return _dist(t) <= DB.attack.range + t.radius * 0.6 + leeway

## Beyond melee reach but within the bow's: Auto Shot's turn.
var target_in_shot: bool:
	get:
		var t = current
		var st = game.stats
		return t != null and t.alive and st.has_ranged and not target_in_reach and _dist(t) <= st.ranged_reach + t.radius * 0.6


## Tab / R3: the enemy you are aiming at first, then the next nearest each
## press, round all those in range.
func cycle(aim):
	var near: Array = game.enemies.list.filter(func(e): return targetable(e) and _dist(e) <= DB.CONFIG.targeting.range)
	near.sort_custom(func(a, b): return _dist(a) < _dist(b))
	if near.is_empty():
		return select(null)
	if current == null or not near.has(current):
		var s = soft_target(aim, DB.CONFIG.targeting.range)
		return select(s if s != null else near[0])
	return select(near[(near.find(current) + 1) % near.size()])


## Called each frame with the raw aim, to show the soft-lock ring.
func update(dt: float, raw_aim = null, soft_range := 0.0) -> void:
	var t = current
	# is the target on the move? (for melee leeway)
	if t != null and _last != null and _last_for == t and dt > 0:
		target_moving = U.hyp(t.position.x - _last.x, t.position.z - _last.y) / dt > 0.5
	else:
		target_moving = false
	_last_for = t
	_last = Vector2(t.position.x, t.position.z) if t != null else null
	if t != null and (not t.alive or _dist(t) > DB.CONFIG.targeting.dropRange or game.player.dead):
		select(null)
	var f = friendly
	if f != null and U.hyp(f.position.x - game.player.position.x, f.position.z - game.player.position.z) > DB.CONFIG.targeting.dropRange:
		friendly = null
	soft = soft_target(raw_aim, soft_range) if current == null and soft_range > 0 else null
	var c := Color("ff4a30") if current != null and attacking else Color("ffd040")
	marker.material_override.albedo_color = c
	_place(marker, current if current != null else friendly, dt)
	_place(soft_marker, soft, dt)


func _place(m: MeshInstance3D, e, dt: float) -> void:
	m.visible = e != null
	if e == null:
		return
	var r = e.get("radius")
	var s: float = (r if r else 0.45) * 2.6
	m.scale = Vector3(s, 1, s)
	m.position = Vector3(e.position.x, Terrain.height_at(e.position.x, e.position.z) + 0.08, e.position.z)
	m.rotation.y += dt * 0.8

class_name Player
extends RefCounted
## The player (src/entities/player.js): movement, facing, guards and the
## timing of auto attack. Whether a blow hits is the combat system's call.
## Spells are run by the spell engine; the player only holds the cast.

var game
var group := Node3D.new()
var model: Node3D
var rig: Rig
var materials: Array
var weapon_part: Node3D
var default_weapon_mesh: Node3D
var torch_light := OmniLight3D.new()
var helm: Node3D
var shield: Node3D
var shield_id = null
var bow: Node3D
var bow_id = null
var bow_in_hand := false
var rod: Node3D
var rod_tip: Node3D

var position := Vector3.ZERO
var facing := 0.0 ## radians; 0 faces +z (south)
## Mouse aim: after an ability turns you, you keep that facing this long even
## while walking, so the blow is seen to go where it was aimed
const AIM_HOLD := 0.45
var aim_hold := 0.0
var radius: float = DB.CONFIG.player.radius
var max_health := 100
var health := 100.0
var dead := false
var ghost := false
var dead_time := 0.0
var cooldowns := {}
var braced := 0.0
var guard_rule = null
var lunge = null
var pending = null
var pending_off = null
var pending_shot = null
var casting = null
var moving := false
var light_radius := 0.0
var opener := false
var opener_off := false
var last_swing_at = null
var last_main_impact_at = null
var eating = null
var sheathed := false ## weapons put away on the back (Z)
var sheath_parts: Array = [] ## the copies worn on the back while sheathed
## where a sheathed blade and shield sit on the torso
const SHEATH_BLADE := Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.15, -0.24))
const SHEATH_TILT := 0.45
const SHEATH_SHIELD := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -0.26))
var hidden := false


func _init(g) -> void:
	game = g
	group.name = "Player"
	model = Assets.instance("warden")
	group.add_child(model)
	rig = Rig.new(model, "warden")
	materials = Rig.isolate_materials(model)
	weapon_part = model.find_child("Weapon", true, false)
	default_weapon_mesh = weapon_part
	group.add_child(Fx.blob_shadow(1.3))
	torch_light.light_color = Color("ffa860")
	torch_light.light_energy = 0
	torch_light.omni_range = 9
	torch_light.position = Vector3(0.3, 1.8, 0.2)
	group.add_child(torch_light)
	cooldowns = fresh_cooldowns()
	var start: Dictionary = DB.world.playerStart
	place_at(start.position[0], start.position[1], deg_to_rad(start.get("facing", 0)))


func place_at(x: float, z: float, f = null) -> void:
	position = Vector3(x, Terrain.height_at(x, z), z)
	if f != null:
		facing = f
	lunge = null
	braced = 0
	pending = null
	pending_shot = null
	casting = null
	_sync()


func _sync() -> void:
	group.position = position
	group.rotation.y = facing


func _part(name: String) -> Node3D:
	return model.find_child(name, true, false) as Node3D


func _free(n: Node) -> void:
	if n and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.queue_free()


## Show what is equipped: the blade in hand, a helm, the off hand.
func show_equipment(equipment: Dictionary) -> void:
	var arm := _part("Arm_R")
	var head := _part("Head")
	if arm and default_weapon_mesh:
		if weapon_part and weapon_part != default_weapon_mesh:
			_free(weapon_part)
		var id = equipment.mainHand.id if equipment.get("mainHand") else null
		default_weapon_mesh.visible = id == "worn_longsword"
		weapon_part = default_weapon_mesh
		if id and id != "worn_longsword":
			var blade := Assets.instance(Items.get_def(id).get("model", id))
			blade.transform = default_weapon_mesh.transform
			arm.add_child(blade)
			weapon_part = blade
	if head:
		_free(helm)
		helm = null
		if equipment.get("head") and equipment.head.id == "watch_helm":
			helm = Assets.instance("watch_helm")
			helm.position = Vector3(0, 0.2, 0.02)
			helm.scale = Vector3.ONE * 1.15
			head.add_child(helm)
	var larm := _part("Arm_L")
	if larm:
		_free(shield)
		shield = null
		var off := Items.get_def(equipment.offHand.id) if equipment.get("offHand") else {}
		light_radius = off.get("light", 8.0) if off.get("kind") == "torch" else 0.0
		torch_light.omni_range = light_radius
		torch_light.light_energy = 1.5 if light_radius else 0.0
		if not off.is_empty():
			shield_id = equipment.offHand.id
		if off.get("kind") == "torch":
			shield = Assets.instance(off.model)
			shield.position = Vector3(0, -0.62, 0.02)
			shield.rotation = Vector3(-0.5, 0, 0)
			larm.add_child(shield)
		elif off.get("kind") == "weapon" and default_weapon_mesh:
			shield = Assets.instance(off.model)
			shield.transform = default_weapon_mesh.transform
			shield.position.x *= -1
			larm.add_child(shield)
		elif off.get("kind") == "shield":
			shield = Assets.instance(off.model)
			shield.position = Vector3(0.11, -0.42, 0.04)
			shield.rotation_order = EULER_ORDER_XYZ
			shield.rotation = Vector3(0, 1.25, 0)
			shield.scale = Vector3.ONE * 0.95
			larm.add_child(shield)
	hold_bow(false)
	_show_sheath()


var sitting: bool:
	get:
		return rig.pose == "rest"


## X: sit on the ground, or stand. Moving, fighting or casting stands you up.
func set_sitting(on: bool) -> void:
	if on == sitting or (on and (rig.pose != null or eating != null)):
		return
	rig.pose = "rest" if on else null


## Z: put your weapons away on your back, or draw them again. Fighting
## draws them on its own.
func set_sheathed(on: bool) -> void:
	if on == sheathed:
		return
	sheathed = on
	if on:
		_show_sheath()
	else:
		show_equipment(game.inventory.equipment)
	game.events.emit("log", {"text": "You sheathe your weapons." if on else "You draw your weapons.", "kind": "muted", "throttle": "sheathe"})


## While sheathed, copies of what is in your hands ride on your back
## (crossed when there are two) and the hands are empty.
func _show_sheath() -> void:
	for n in sheath_parts:
		_free(n)
	sheath_parts = []
	var torso := _part("Torso")
	if not sheathed or not torso:
		return
	var held := []
	if weapon_part and weapon_part.visible:
		held.append([weapon_part, "weapon"])
	var off = game.inventory.equipment.get("offHand")
	var off_kind: String = Items.get_def(off.id).get("kind", "") if off else ""
	if shield and shield.visible and off_kind != "torch":
		held.append([shield, off_kind])
	for i in held.size():
		var n: Node3D = held[i][0]
		var copy := n.duplicate() as Node3D
		torso.add_child(copy)
		if held[i][1] == "shield":
			copy.transform = SHEATH_SHIELD
		else:
			var side := -1.0 if i == 0 else 1.0
			copy.transform = Transform3D(Basis(Vector3.BACK, side * SHEATH_TILT) * SHEATH_BLADE.basis, SHEATH_BLADE.origin + Vector3(side * 0.04, 0, 0))
		sheath_parts.append(copy)
		n.visible = false


## Fishing: the rod in the right hand (the weapon put away) and the fishing pose.
func hold_rod(on: bool) -> void:
	var arm := _part("Arm_R")
	if not arm:
		return
	if on and not rod:
		rod = Assets.instance("fishing_rod")
		rod.name = "HeldRod"
		rod.position = Vector3(0, -0.62, 0.04)
		rod.rotation = Vector3(1.875, 0, 0)
		rod_tip = Node3D.new()
		rod_tip.position = Vector3(0, 1.42, 0)
		rod.add_child(rod_tip)
		arm.add_child(rod)
	elif not on and rod:
		_free(rod)
		rod = null
		rod_tip = null
	rig.pose = "fish" if on else null
	if on and weapon_part:
		weapon_part.visible = false
	elif not on:
		show_equipment(game.inventory.equipment)


## where the line leaves the rod, in world space
func rod_tip_position() -> Vector3:
	if not rod_tip or not rod_tip.is_inside_tree():
		return position + Vector3(0, 1.8, 0)
	return rod_tip.global_position


func face_towards(x: float, z: float) -> void:
	var dx := x - position.x
	var dz := z - position.z
	if dx * dx + dz * dz > 0.0001:
		facing = atan2(dx, dz)
		aim_hold = AIM_HOLD


func update(dt: float, controls) -> void:
	for k in cooldowns:
		cooldowns[k] = maxf(0, cooldowns[k] - dt)
	braced = maxf(0, braced - dt)
	aim_hold = maxf(0, aim_hold - dt)

	if ghost:
		# a spirit walks fast, fights nothing and passes unseen
		var mv: Dictionary = controls.move if controls else {"x": 0.0, "z": 0.0}
		var mag := minf(1, U.hyp(mv.x, mv.z))
		if mag > 0:
			var sp: float = DB.CONFIG.player.speed * DB.CONFIG.death.ghostSpeed
			position.x += mv.x * sp * dt
			position.z += mv.z * sp * dt
			facing = U.turn_towards(facing, atan2(mv.x, mv.z), dt * 14)
		position = game.collision.resolve(position, radius)
		position.y = Terrain.height_at(position.x, position.z) + 0.15 + sin(game.time * 2) * 0.06
		moving = mag > 0
		rig.update(dt, mag)
		_sync()
		return
	if dead:
		dead_time += dt
		rig.update(dt, 0)
		_sync()
		return

	# queued attacks land after a short windup, independent of frame rate
	if pending != null:
		pending.t -= dt
		if pending.t <= 1e-6:
			var p: Dictionary = pending
			pending = null
			if p.type == "strike":
				_impact("main", p, dt)
			elif p.type == "spell":
				game.spells.resolve(p.id)
	if not game.combat.shown_later.is_empty():
		game.combat.update_shown(dt)
	if pending_off != null:
		pending_off.t -= dt
		if pending_off.t <= 1e-6:
			var p: Dictionary = pending_off
			pending_off = null
			_impact("off", p, dt)
	if pending_shot != null:
		pending_shot.t -= dt
		if pending_shot.t <= 1e-6:
			var p: Dictionary = pending_shot
			pending_shot = null
			_release(p, dt)

	var speed01 := 0.0
	if lunge != null:
		# a charge carries you, then strikes on arrival
		var d: Dictionary = lunge
		d.t += dt
		position.x += d.dir.x * d.speed * dt
		position.z += d.dir.z * d.speed * dt
		if d.t >= d.duration:
			pending = {"type": "spell", "id": d.id, "t": 0.0}
			lunge = null
		speed01 = 1.0
	elif controls:
		var mv: Dictionary = controls.move
		var acts: Dictionary = controls.get("actions", {})
		var aim = controls.get("aim")
		# keyboard turning: turning on the spot is not moving, so it never
		# breaks a cast; walking goes the way you face, backing up slower
		var tank = controls.get("tank")
		var turning := false
		if tank != null:
			turning = tank.x != 0
			if turning:
				facing = wrapf(facing - tank.x * DB.CONFIG.player.turnRate * dt, -PI, PI)
				aim_hold = 0
			var walk: float = tank.y * (DB.CONFIG.player.backpedal if tank.y < 0 else 1.0)
			mv = {"x": sin(facing) * walk, "z": cos(facing) * walk}
		var mag := minf(1, U.hyp(mv.x, mv.z))
		if mag > 0:
			position.x += mv.x * DB.CONFIG.player.speed * dt
			position.z += mv.z * DB.CONFIG.player.speed * dt
			if tank != null:
				# you face where the keys turn you; the left button held
				# (mouse aim) still turns you to the cursor
				var face_aim = controls.get("faceAim")
				if face_aim != null and not turning:
					facing = U.turn_towards(facing, atan2(face_aim.x - position.x, face_aim.z - position.z), dt * 14)
			elif game.mouse_aim:
				# Mouse aim: you face the way you walk, unless you aim on
				# purpose (left button or right stick held), or an ability
				# has just turned you
				var face_aim = controls.get("faceAim")
				if face_aim != null:
					facing = U.turn_towards(facing, atan2(face_aim.x - position.x, face_aim.z - position.z), dt * 14)
				elif aim_hold <= 0:
					facing = U.turn_towards(facing, atan2(mv.x, mv.z), dt * 14)
			else:
				# fighting, you keep your target in front of you as you move (strafe)
				var look := atan2(aim.x - position.x, aim.z - position.z) if (acts.get("strike") or acts.get("shoot")) and aim != null else atan2(mv.x, mv.z)
				facing = U.turn_towards(facing, look, dt * 14)
			speed01 = mag
		elif turning:
			pass
		elif (acts.get("strike") or acts.get("shoot")) and aim != null:
			facing = U.turn_towards(facing, atan2(aim.x - position.x, aim.z - position.z), dt * DB.attack.turnRate)
		elif game.mouse_aim and controls.get("faceAim") != null:
			var fa = controls.faceAim
			facing = U.turn_towards(facing, atan2(fa.x - position.x, fa.z - position.z), dt * 14)
		# spells first, so a swing coming due never swallows a key press
		for id in acts:
			if acts[id] and DB.spells.has(id):
				game.spells.try_cast(id)
		# fighting draws your weapons
		if sheathed and (acts.get("strike") or acts.get("shoot")):
			set_sheathed(false)
		if acts.get("strike"):
			try_strike(aim)
			try_strike_off(aim)
		# Auto Shot needs you to stand still: moving calls off a draw
		if speed01 > 0 and pending_shot != null:
			_cancel_shot()
		if acts.get("shoot") and speed01 == 0:
			try_shoot(aim)
		if acts.get("fish"):
			game.fishing.cast(controls.get("rawAim"))
		if acts.get("cook"):
			game.hud.toggle_window("cooking")

	if sitting and (speed01 > 0 or casting != null or pending != null or pending_off != null or pending_shot != null):
		set_sitting(false)
	position = game.collision.resolve(position, radius)
	position.y = Terrain.height_at(position.x, position.z)
	moving = speed01 > 0
	rig.update(dt, speed01 * DB.CONFIG.player.runGait)
	_sync()


var is_braced: bool:
	get:
		return braced > 0

## % less damage taken from a guard that softens blows (Brace with a weapon alone)
var damage_reduction: float:
	get:
		var guard: float = guard_rule.get("reduction", 0) if braced > 0 and guard_rule else 0.0
		# Fortified (Rallying Cry, Bulwark) stacks with it
		return minf(80, guard + (game.spells.fortify if game.spells else 0.0))


## Called by combat when a blow lands: "" or how the guard took it.
func consume_brace() -> String:
	if braced <= 0:
		return ""
	var rule: Dictionary = guard_rule if guard_rule else {"blocks": 1}
	if rule.get("reduction", 0):
		return ""
	if rule.blocks > 0:
		rule.blocks -= 1
		if rule.blocks <= 0:
			braced = 0
	rig.play("brace", 0.35, 0.2)
	if rule.get("miss", false):
		return "miss"
	var off = game.inventory.equipment.offHand
	return "block" if off and Items.get_def(off.id).get("kind") == "shield" else "parry"


## Shadow: the Rogue fades to a shade of itself
func set_hidden(on: bool) -> void:
	hidden = on
	if ghost:
		return
	Rig.set_alpha(materials, 0.35 if on else 1.0)


## Auto attack, as WoW does it: each hand has a swing clock that counts down
## to the moment the blow lands. See src/entities/player.js for the full story.
func try_strike(aim) -> bool:
	if pending != null or casting != null:
		return false
	var stats = game.stats
	var windup: float = stats.swing_windup
	if cooldowns.attack > windup:
		return false
	if aim != null and not facing_point(aim.x, aim.z, DB.attack.coneDegrees / 2.0):
		return false
	var anim: float = stats.swing_animation
	if bow_in_hand:
		hold_bow(false)
	var aim2 = {"x": aim.x, "z": aim.z} if aim != null else null
	if opener:
		opener = false
		var show := minf(DB.attack.openerWindup, anim * 0.7)
		rig.play("strike", anim, show / anim)
		rig.action.auto = true
		game.events.emit("playerSwing")
		_impact("main", {"t": 0.0, "aim": aim2}, 0, show)
		return true
	var t := maxf(cooldowns.attack, minf(windup, DB.attack.readyWindup))
	pending = {"type": "strike", "t": t, "aim": aim2}
	rig.play("strike", anim, t / anim)
	rig.action.auto = true
	game.events.emit("playerSwing")
	return true


## The off hand when dual wielding: its own clock, staggered from the main hand.
func try_strike_off(aim) -> bool:
	var stats = game.stats
	if not stats.dual_wielding or pending_off != null or casting != null or lunge != null:
		return false
	if pending != null and pending.type == "spell":
		return false
	var windup: float = stats.swing_windup_for("off")
	if cooldowns.attackOff > windup:
		return false
	if aim != null and not facing_point(aim.x, aim.z, DB.attack.coneDegrees / 2.0):
		return false
	var gap: float = DB.attack.staggerGap
	var anim: float = stats.swing_animation_for("off")
	# the off-hand opener needs no windup of its own: the half-swing rule below places it
	var ready: float = minf(windup, DB.attack.readyWindup)
	var t := maxf(cooldowns.attackOff, ready)
	# WoW style: the off hand lands half a swing after the main hand, so blows
	# alternate main, off, main rather than coming in pairs
	var half: float = minf(stats.attack_cooldown_for("main"), stats.attack_cooldown_for("off")) * 0.5
	var main: float = pending.t if pending != null and pending.type == "strike" else cooldowns.attack
	var since: float = game.time - (last_main_impact_at if last_main_impact_at != null else -INF)
	if absf(main - t) < gap:
		cooldowns.attackOff = main + half
		return false
	if since + t < half - 1e-3:
		cooldowns.attackOff = half - since
		if cooldowns.attackOff > windup:
			return false
		t = cooldowns.attackOff
	opener_off = false
	pending_off = {"t": t, "aim": {"x": aim.x, "z": aim.z} if aim != null else null}
	rig.play_off(anim, t / anim)
	game.events.emit("playerSwing", {"hand": "off"})
	return true


## A blow's impact frame: it lands only if the target is still in reach.
func _impact(hand: String, p: Dictionary, dt: float, show := 0.0) -> void:
	var off := hand == "off"
	var tg = game.targeting
	if not tg.attacking or not tg.target_in_reach:
		if off:
			rig.off_action = null
		elif rig.action != null and rig.action.type == "strike":
			rig.action = null
		return
	var late := minf(minf(-p.t, dt), DB.attack.catchUp)
	cooldowns["attackOff" if off else "attack"] = maxf(0, game.stats.attack_cooldown_for(hand) - late)
	last_swing_at = game.time
	if not off:
		last_main_impact_at = game.time
	game.combat.resolve_player_strike(p.aim, hand, show)


## Auto Shot: with a bow, while the target is beyond melee reach.
func try_shoot(aim) -> bool:
	if pending_shot != null or casting != null or lunge != null:
		return false
	var stats = game.stats
	if not game.inventory.ammo:
		# WoW style, red in the middle of the screen
		if game.hud:
			game.hud.error("Out of Ammo")
		game.events.emit("log", {"text": "You have no arrows. Buy them from Mara or Tam.", "kind": "muted", "throttle": "no-ammo"})
		return false
	var draw := minf(DB.auto_shot.draw, stats.attack_cooldown_for("ranged") * 0.4)
	if cooldowns.ranged > draw:
		return false
	if aim != null and not facing_point(aim.x, aim.z, DB.attack.coneDegrees / 2.0):
		return false
	var t := maxf(cooldowns.ranged, minf(draw, DB.attack.readyWindup * 2))
	pending_shot = {"t": t}
	hold_bow(true)
	rig.play("shoot", t + 0.35, t / (t + 0.35))
	rig.action.auto = true
	return true


func _cancel_shot() -> void:
	pending_shot = null
	if rig.action != null and rig.action.type == "shoot":
		rig.action = null


func _release(p: Dictionary, dt: float) -> void:
	var tg = game.targeting
	var inv = game.inventory
	var ammo = inv.ammo
	if not tg.attacking or not tg.target_in_shot or not ammo:
		if rig.action != null and rig.action.type == "shoot":
			rig.action = null
		hold_bow(false)
		return
	inv.remove_count(ammo, 1)
	var late := minf(minf(-p.t, dt), DB.attack.catchUp)
	cooldowns.ranged = maxf(0, game.stats.attack_cooldown_for("ranged") - late)
	last_swing_at = game.time
	game.combat.loose_player_arrow(tg.current, ammo)


## The bow rides on the back, and comes to the left hand to shoot.
func hold_bow(in_hand: bool) -> void:
	var torso := _part("Torso")
	var larm := _part("Arm_L")
	var r = game.inventory.equipment.get("ranged") if game.inventory else null
	var want = r.id if r and Items.get_def(r.id).get("kind") == "weapon" else null
	if bow and (bow_id != want or bow_in_hand != in_hand):
		_free(bow)
		bow = null
	if want and not bow:
		bow = Assets.instance(Items.get_def(want).model)
		bow_id = want
		bow_in_hand = in_hand
		if in_hand and larm:
			bow.position = Vector3(0, -0.62, 0.02)
			bow.rotation = Vector3(-PI / 2, 0, 0)
			larm.add_child(bow)
		elif torso:
			bow.position = Vector3(0, 0.25, -0.2)
			bow.rotation = Vector3(0, 0, 0.7)
			torso.add_child(bow)
	if weapon_part:
		var mh = game.inventory.equipment.get("mainHand") if game.inventory else null
		weapon_part.visible = not in_hand and (weapon_part != default_weapon_mesh or (mh != null and mh.id == "worn_longsword"))
	if shield:
		shield.visible = not in_hand


## is (x, z) within `half_degrees` of where you face? (very close counts)
func facing_point(x: float, z: float, half_degrees: float) -> bool:
	var dx := x - position.x
	var dz := z - position.z
	var d := U.hyp(dx, dz)
	if d < 0.8:
		return true
	return (dx * sin(facing) + dz * cos(facing)) / d >= cos(deg_to_rad(half_degrees))


func take_damage(amount: float) -> bool:
	if dead:
		return false
	health = maxf(0, health - amount)
	rig.hit()
	if health <= 0:
		dead = true
		dead_time = 0
		pending = null
		pending_off = null
		lunge = null
		casting = null
		braced = 0
		rig.die()
	return true


func heal(amount: float) -> float:
	var before := health
	health = minf(max_health, health + amount)
	return health - before


## Rise as a spirit at (x, z).
func become_ghost(x: float, z: float) -> void:
	ghost = true
	rig.revive()
	place_at(x, z, PI)
	Rig.set_alpha(materials, 0.45)
	Rig.set_emissive(materials, Color(0.35, 0.55, 0.8), 1)


func revive(x: float, z: float, health_fraction := 1.0) -> void:
	dead = false
	if ghost:
		ghost = false
		Rig.set_alpha(materials, 1.0)
		Rig.set_emissive(materials, Color.BLACK, 0)
	health = maxf(1, U.jround(max_health * health_fraction))
	rig.revive()
	cooldowns = fresh_cooldowns()
	if game.spells:
		game.spells.reset()
	if game.resources:
		game.resources.reset()
	place_at(x, z, PI)


static func fresh_cooldowns() -> Dictionary:
	var c := {"attack": 0.0, "attackOff": 0.0, "ranged": 0.0, "shieldBreak": 0.0, "lunge": 0.0, "brace": 0.0, "draught": 0.0, "gcd": 0.0}
	for id in DB.spells:
		c[id] = 0.0
	return c

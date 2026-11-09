class_name Player
extends RefCounted
## The player (src/entities/player.js): movement, facing, guards and the
## timing of auto attack. Whether a blow hits is the combat system's call.
## Spells are run by the spell engine; the player only holds the cast.

var game
var group := Node3D.new()
var model: Node3D
var appearance: Dictionary = ForgeCharacter.defaults()
var rig: Rig
var materials: Array
var weapon_part: Node3D
var default_weapon_mesh: Node3D
var ground_shadow: MeshInstance3D
var torch_light := OmniLight3D.new()
var helm: Node3D
var cloak: Node3D ## a built back piece (FancyGear wings)
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
var root := 0.0 ## seconds an attack on the move holds you in place (Lost Ark / D4)
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
var ranged_ready_at := 0.0
var casting = null
var moving := false
var light_radius := 0.0
var opener := false
var opener_off := false
var last_swing_at = null
var last_main_impact_at = null
var eating = null
var sheathed := false ## weapons put away on the back (Z)
var weapon_stance := "melee" ## melee | ranged | sheathed
var prefer_ranged := false
var sheath_parts: Array = [] ## the copies worn on the back while sheathed
## where a sheathed blade and shield sit on the torso
const SHEATH_BLADE := Transform3D(Basis(Vector3.RIGHT, PI), Vector3(0, 0.15, -0.24))
const SHEATH_TILT := 0.45
const SHEATH_SHIELD := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0.05, -0.26))
var hidden := false


func _init(g) -> void:
	game = g
	group.name = "Player"
	# the imported body (on its own skeleton, with gear sockets) or the
	# code-built warden, by DB.CONFIG.models
	var body := "forge_v6"
	model = ForgeCharacter.build(appearance)
	# A readability scale on the body and attached gear. World distances,
	# collision, attack ranges and movement stay in the same units.
	model.scale *= DB.CONFIG.player.visualScale
	group.add_child(model)
	rig = ForgeRig.new(model, self)
	rig.track_steps = true
	materials = Rig.isolate_materials(model)
	weapon_part = model.find_child("Weapon", true, false)
	default_weapon_mesh = weapon_part
	ground_shadow = Fx.blob_shadow(1.3)
	# top level: the group's jump and front flip never lift or turn it
	ground_shadow.top_level = true
	group.add_child(ground_shadow)
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
	_reset_jump()
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
	if ghost:
		# a spirit floats a hand above the ground, bobbing
		group.position.y += 0.15 + sin(game.time * 2) * 0.06
	group.rotation.y = facing
	group.rotation.x = 0.0
	if flip >= 0.0:
		# a front flip, turned about the waist rather than the feet
		group.rotation.x = TAU * clampf(flip / (2.0 * JUMP_SPEED / JUMP_GRAVITY), 0.0, 1.0)
		var pivot := Vector3(0, 0.9 * DB.CONFIG.player.visualScale, 0)
		group.position += pivot - group.basis * pivot
	# The contact shadow stays flat on the ground while the body leaves it
	# (it is top level, so it ignores the group's hop and flip).
	ground_shadow.position = Vector3(position.x, position.y - jump_h + 0.03, position.z)


func _part(name: String) -> Node3D:
	return model.find_child(name, true, false) as Node3D


func set_appearance(value = null) -> void:
	var next := ForgeCharacter.clean(value)
	if next == appearance:
		return
	appearance = next
	var previous := model
	model = ForgeCharacter.build(appearance)
	model.scale *= DB.CONFIG.player.visualScale
	group.add_child(model)
	rig = ForgeRig.new(model, self)
	rig.track_steps = true
	materials = Rig.isolate_materials(model)
	weapon_part = model.find_child("Weapon", true, false)
	default_weapon_mesh = weapon_part
	helm = null
	cloak = null
	shield = null
	bow = null
	rod = null
	rod_tip = null
	bow_id = null
	bow_in_hand = false
	sheath_parts.clear()
	group.remove_child(previous)
	previous.queue_free()
	show_equipment(game.inventory.equipment)


func _free(n: Node) -> void:
	if n and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.queue_free()


## Show what is equipped: the blade in hand, a helm, the off hand.
func show_equipment(equipment: Dictionary) -> void:
	_show_equipment(equipment)
	# gear changed on a spirit casts no shadow either
	if ghost:
		_set_casts_shadow(false)


func _show_equipment(equipment: Dictionary) -> void:
	ForgeCharacter.dress(model, equipment)
	var arm := _part("Arm_R")
	var head := _part("Head")
	if arm and default_weapon_mesh:
		if weapon_part and weapon_part != default_weapon_mesh:
			_free(weapon_part)
		var id = equipment.mainHand.id if equipment.get("mainHand") else null
		# the worn longsword is built into the warden model, unless an
		# imported model stands in for it (DB.with_imported)
		var built_in: bool = id == "worn_longsword" and Items.get_def(id).get("model") == "worn_sword" and Runes.of(equipment.mainHand) == ""
		default_weapon_mesh.visible = built_in
		weapon_part = default_weapon_mesh
		if id and not built_in:
			var blade := Assets.instance(Items.get_def(id).get("model", id))
			blade.transform = ForgeCharacter.held_transform(model, "r", Items.get_def(id))
			arm.add_child(blade)
			weapon_part = blade
			# a rune's glow (runes.json), or the item's own (the test weapons)
			FancyGear.apply(blade, Runes.glow_for(equipment.mainHand))
	if head:
		_free(helm)
		helm = null
		var hdef := Items.get_def(equipment.head.id) if equipment.get("head") else {}
		if hdef.get("cosmetic"):
			helm = FancyGear.build(hdef.cosmetic, hdef.get("glow", {}))
			if hdef.cosmetic in ["horns", "halo"]:
				helm.position.y = -0.14
				if hdef.cosmetic == "horns": helm.scale *= 0.85
			head.add_child(helm)
		elif equipment.get("head") and equipment.head.id in ["watch_helm", "old_watch_helm"]:
			helm = Assets.instance(hdef.get("model", "watch_helm"))
			helm.position = Vector3(0, 0, 0.02)
			helm.scale = Vector3.ONE * 0.9
			head.add_child(helm)
	var torso := _part("Torso")
	if torso:
		_free(cloak)
		cloak = null
		var bdef := Items.get_def(equipment.back.id) if equipment.get("back") else {}
		if bdef.get("cosmetic"):
			cloak = FancyGear.build(bdef.cosmetic, bdef.get("glow", {}))
			torso.add_child(cloak)
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
			shield.transform = ForgeCharacter.held_transform(model, "l", off)
			larm.add_child(shield)
		elif off.get("kind") == "weapon" and default_weapon_mesh:
			shield = Assets.instance(off.model)
			shield.transform = ForgeCharacter.held_transform(model, "l", off)
			larm.add_child(shield)
			FancyGear.apply(shield, Runes.glow_for(equipment.offHand))
		elif off.get("kind") == "shield":
			shield = Assets.instance(off.model)
			shield.scale = Vector3.ONE * 0.95
			_part("ShieldGrip").add_child(shield)
	hold_bow(weapon_stance=="ranged" and not sheathed)
	_show_sheath()


var sitting: bool:
	get:
		return rig.pose == "rest"


## X: sit on the ground, or stand. Moving, fighting or casting stands you up.
func set_sitting(on: bool) -> void:
	if on == sitting or (on and (rig.pose != null or eating != null or jump_h > 0 or jump_v != 0)):
		return
	rig.pose = "rest" if on else null


## Z: put your weapons away on your back, or draw them again. Fighting
## draws them on its own.
func set_sheathed(on: bool) -> void:
	draw_weapons("sheathed" if on else primary_stance(),true)

func stance_order() -> Array:
	var equipment:Dictionary=game.inventory.equipment
	var order:Array=[]
	if equipment.get("mainHand") or equipment.get("offHand"):order.append("melee")
	if equipment.get("ranged"):order.append("ranged")
	if prefer_ranged:order.reverse()
	order.append("sheathed")
	return order

func primary_stance() -> String:
	return stance_order()[0]

func reset_weapon_stance(ranged_first: bool) -> void:
	prefer_ranged=ranged_first
	weapon_stance=primary_stance()
	sheathed=weapon_stance=="sheathed"

func cycle_weapons() -> void:
	var order:=stance_order()
	var index:=order.find("sheathed" if sheathed else weapon_stance)
	game.targeting.stop_attack()
	pending=null
	pending_off=null
	pending_shot=null
	game.spells.cancel_ranged_windup()
	rig.action=null
	rig.off_action=null
	draw_weapons(order[(index+1)%order.size()],true)

func draw_weapons(stance: String, sound := false) -> void:
	if stance=="ranged" and not game.inventory.equipment.get("ranged"):stance="melee"
	weapon_stance=stance
	sheathed=stance=="sheathed"
	show_equipment(game.inventory.equipment)
	if sound:
		game.audio.sfx("sheathe" if sheathed else "unsheathe",0.35)
		game.events.emit("log",{"text":{"sheathed":"You stow your weapons.","ranged":"You draw your bow.","melee":"You draw your melee weapons."}[stance],"kind":"muted","throttle":"sheathe"})


## While sheathed, copies of what is in your hands ride on your back
## (crossed when there are two) and the hands are empty.
func _show_sheath() -> void:
	for n in sheath_parts:
		_free(n)
	sheath_parts = []
	var torso := _part("Torso")
	if (not sheathed and not bow_in_hand) or not torso:
		return
	var held := []
	if weapon_part and game.inventory.equipment.get("mainHand"):
		held.append([weapon_part, "weapon"])
	var off = game.inventory.equipment.get("offHand")
	var off_kind: String = Items.get_def(off.id).get("kind", "") if off else ""
	if shield and off != null and off_kind != "torch":
		held.append([shield, off_kind])
	for i in held.size():
		var n: Node3D = held[i][0]
		var copy := n.duplicate() as Node3D
		copy.visible=true
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
		rod.transform = ForgeCharacter.held_transform(model, "r", {})
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


## About 1.15 m high and 0.68 s long on level ground. Horizontal controls
## remain live, including an existing click destination.
const JUMP_SPEED := 6.8
const JUMP_GRAVITY := 20.0
const JUMP_BUFFER_TIME := 0.12
var jump_v := 0.0
var jump_h := 0.0
var jump_buffer := 0.0
var flip := -1.0 ## seconds into a front flip, or -1 for a plain hop
const FLIP_CHANCE := 0.12 ## now and then a jump turns into a front flip (Dan, 2026-11-03)


func _reset_jump() -> void:
	jump_v = 0.0
	jump_h = 0.0
	jump_buffer = 0.0
	flip = -1.0
	rig.airborne = false
	if rig is ForgeRig:
		rig.was_airborne = false
		rig.air_time = 0.0
		rig.landing = 0.0
	position.y = Terrain.height_at(position.x, position.z)
	ground_shadow.position = position + Vector3(0, 0.03, 0)


func _update_jump(dt: float, requested: bool) -> void:
	jump_buffer = JUMP_BUFFER_TIME if requested else maxf(0.0, jump_buffer - dt)
	if jump_buffer > 0.0 and jump_h == 0.0 and jump_v == 0.0:
		set_sitting(false)
		position.y = Terrain.height_at(position.x, position.z)
		jump_v = JUMP_SPEED
		jump_buffer = 0.0
		# The v6 rig owns its take-off/air/landing poses; whole-body random
		# flips would rotate that pose and the attached weapons a second time.
		flip = 0.0 if not rig is ForgeRig and not ghost and randf() < FLIP_CHANCE else -1.0
		game.events.emit("playerJumped", {"position": position})
		# A buffered second hop needs a fresh animation even without an idle frame.
		if rig.clip == "Jump":
			rig.clip = ""
	var ground := Terrain.height_at(position.x, position.z)
	if jump_v != 0.0 or jump_h > 0.0:
		# Integrate world height, so a slope cannot drag an airborne player up
		# or down with the terrain. Land on the ground under the current x/z.
		position.y += jump_v * dt - 0.5 * JUMP_GRAVITY * dt * dt
		jump_v -= JUMP_GRAVITY * dt
		if position.y <= ground:
			position.y = ground
			game.events.emit("playerLanded", {"position": position, "speed": -jump_v})
			jump_v = 0.0
			jump_h = 0.0
			flip = -1.0
		else:
			if flip >= 0.0:
				flip += dt
			jump_h = maxf(0.0, position.y - ground)
	else:
		position.y = ground
		jump_h = 0.0
	rig.airborne = jump_h > 0.0 or jump_v > 0.0


## a red flash on the body as a blow lands, so a hit reads from the
## zoomed-out camera (Dan, 2026-11-02); the head snap is Rig._apply_snap
var hit_flash := 0.0
var _hit_flash_shown := false


func update(dt: float, controls) -> void:
	if (hit_flash > 0 or _hit_flash_shown) and not dead:
		hit_flash = maxf(0, hit_flash - dt * 4)
		Rig.set_emissive(materials, Rig.FLASH_RED, hit_flash * 0.55)
		_hit_flash_shown = hit_flash > 0
	for k in cooldowns:
		cooldowns[k] = maxf(0, cooldowns[k] - dt)
	braced = maxf(0, braced - dt)
	aim_hold = maxf(0, aim_hold - dt)
	root = maxf(0, root - dt)

	if ghost:
		# a spirit walks fast, fights nothing and passes unseen
		var mv: Dictionary = controls.move if controls else {"x": 0.0, "z": 0.0}
		var mag := minf(1, U.hyp(mv.x, mv.z))
		if mag > 0:
			var sp: float = DB.CONFIG.player.speed * DB.CONFIG.death.ghostSpeed
			position.x += mv.x * sp * dt
			position.z += mv.z * sp * dt
			facing = U.turn_towards(facing, atan2(mv.x, mv.z), dt * 14)
		position = game.collision.resolve(position, radius, jump_h)
		_update_jump(dt, controls != null and controls.get("jump", false))
		moving = mag > 0 or rig.airborne
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
		# Release after this frame's movement, facing and special input.
		# A due auto-shot must still cancel if the player starts moving.

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
		# a key pressed near the end of a charge waits in the spell queue
		if controls:
			var lacts: Dictionary = controls.get("actions", {})
			for id in lacts:
				if lacts[id] and DB.spells.has(id):
					game.spells.try_cast(id)
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
		else:
			mv = _melee_steer(mv, dt)
		if root > 0:
			mv = {"x": 0.0, "z": 0.0}
		var mag := minf(1, U.hyp(mv.x, mv.z))
		if mag > 0:
			position.x += mv.x * DB.CONFIG.player.speed * game.spells.movement_scale * dt
			position.z += mv.z * DB.CONFIG.player.speed * game.spells.movement_scale * dt
			if tank != null:
				# you face where the keys turn you; the left button held
				# (mouse aim) still turns you to the cursor
				var face_aim = controls.get("faceAim")
				if face_aim != null and not turning:
					facing = U.turn_towards(facing, atan2(face_aim.x - position.x, face_aim.z - position.z), dt * 14)
			else:
				# Running, you face the way you run (WoW): nothing turns you
				# back at your target, so to hit something behind you, you
				# stop (or turn) to face it. No shooting while kiting backwards.
				facing = U.turn_towards(facing, atan2(mv.x, mv.z), dt * 14)
			speed01 = mag
		elif turning:
			pass
		elif game.mouse_aim and controls.get("faceAim") != null:
			var fa = controls.faceAim
			facing = U.turn_towards(facing, atan2(fa.x - position.x, fa.z - position.z), dt * 14)
		# spells first, so a swing coming due never swallows a key press
		for id in acts:
			if acts[id] and DB.spells.has(id):
				# a spell draws sheathed weapons properly (no copies left on the back)
				if game.spells.try_cast(id) and sheathed:
					draw_weapons("ranged" if DB.spells[id].get("ranged") else "melee")
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
	# A ranged special gets first refusal over an auto-shot due this frame.
	# If the special failed, the already-drawn auto-shot still releases.
	if pending_shot != null and pending_shot.t <= 1e-6:
		var shot: Dictionary = pending_shot
		pending_shot = null
		_release(shot,dt)

	if sitting and (speed01 > 0 or casting != null or pending != null or pending_off != null or pending_shot != null):
		set_sitting(false)
	# high in a hop you pass over low things (a fence, Collision `h`)
	position = game.collision.resolve(position, radius, jump_h)
	_update_jump(dt, controls != null and controls.get("jump", false))
	# Stationary activities (fishing, eating, gathering and casting) also
	# see a standing jump as movement, rather than continuing in mid-air.
	moving = speed01 > 0 or rig.airborne
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


## Auto attack - each hand has a swing clock that counts down
## to the moment the blow lands. See src/entities/player.js for the full story.
func try_strike(aim) -> bool:
	if pending != null or casting != null:
		return false
	var stats = game.stats
	var windup: float = stats.swing_windup
	if cooldowns.attack > windup:
		return false
	if aim != null and not _swing_facing(aim):
		return false
	var anim: float = stats.swing_animation
	if bow_in_hand or sheathed:
		draw_weapons("melee")
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
	if aim != null and not _swing_facing(aim):
		return false
	var gap: float = DB.attack.staggerGap
	var anim: float = stats.swing_animation_for("off")
	# the off-hand opener needs no windup of its own: the half-swing rule below places it
	var ready: float = minf(windup, DB.attack.readyWindup)
	var t := maxf(cooldowns.attackOff, ready)
	# The off hand lands half a swing after the main hand, so blows
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
	# Aimed combat: the blow falls where it was aimed, on whoever stands in
	# its arc now; a foe that stepped out of it is missed, and a whiff
	# still costs the swing
	if game.aimed_combat:
		var late_a := minf(minf(-p.t, dt), DB.attack.catchUp)
		cooldowns["attackOff" if off else "attack"] = maxf(0, game.stats.attack_cooldown_for(hand) - late_a)
		last_swing_at = game.time
		if not off:
			last_main_impact_at = game.time
		game.combat.resolve_aimed_strike(p.aim, hand, show)
		return
	# a swing already begun still lands if the target stepped a little out
	if not tg.attacking or not tg.in_reach(DB.attack.get("impactGrace", 0.0)):
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
	cooldowns.ranged=maxf(cooldowns.ranged,ranged_ready_at-game.time)
	if not game.inventory.ammo:
		# Red in the middle of the screen
		if game.hud:
			game.hud.error("Out of Ammo")
		game.events.emit("log", {"text": "Out of Ammo.", "kind": "muted", "throttle": "no-ammo"})
		return false
	var draw := minf(DB.auto_shot.draw, stats.attack_cooldown_for("ranged") * 0.4)
	if cooldowns.ranged > draw:
		return false
	if aim != null:
		face_towards(aim.x, aim.z)
	var t := maxf(cooldowns.ranged, draw)
	pending_shot = {"t": t,"total":t}
	if not bow_in_hand or sheathed:draw_weapons("ranged")
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
		hold_bow(weapon_stance=="ranged" and not sheathed)
		return
	face_towards(tg.current.position.x, tg.current.position.z)
	inv.spend_arrow(ammo)
	var late := minf(minf(-p.t, dt), DB.attack.catchUp)
	cooldowns.ranged = maxf(0, game.stats.attack_cooldown_for("ranged") - late)
	ranged_ready_at=game.time+cooldowns.ranged
	last_swing_at = game.time
	game.combat.loose_player_arrow(tg.current, ammo)


## The bow rides on the back, and comes to the left hand to shoot.
func hold_bow(in_hand: bool) -> void:
	var torso := _part("Torso")
	var larm := _part("Arm_L")
	var r = game.inventory.equipment.get("ranged") if game.inventory else null
	var want = r.id if r and Items.get_def(r.id).get("kind") == "weapon" else null
	in_hand=in_hand and want != null
	# the key carries the rune too, so a new rune rebuilds the bow's glow
	var key = "%s:%s" % [want, Runes.of(r)] if want else null
	if bow and (bow_id != key or bow_in_hand != in_hand):
		_free(bow)
		bow = null
	bow_in_hand=in_hand
	if want and not bow:
		bow = Assets.instance(Items.get_def(want).model)
		bow_id = key
		FancyGear.apply(bow, Runes.glow_for(r))
		bow_in_hand = in_hand
		if in_hand and larm:
			bow.transform = ForgeCharacter.held_transform(model, "l", {})
			larm.add_child(bow)
		elif torso:
			bow.position = Vector3(0, 0.25, -0.2)
			bow.rotation = Vector3(0, 0, 0.7)
			torso.add_child(bow)
	if weapon_part:
		var mh = game.inventory.equipment.get("mainHand") if game.inventory else null
		weapon_part.visible = not in_hand and not sheathed and (weapon_part != default_weapon_mesh or (mh != null and mh.id == "worn_longsword"))
	if shield:
		shield.visible = not in_hand and not sheathed

func bow_muzzle() -> Vector3:
	if bow != null and bow.has_method("muzzle_local"):
		return bow.global_transform*bow.call("muzzle_local")
	return position+Vector3(0,1.35,0)+Vector3(sin(facing),0,cos(facing))*0.4


## Every swing, shot and ability at a foe turns you to it at once, and one
## started on the move holds you in place for `rootSeconds` (Dan picked
## Lost Ark / Diablo 4 style, 2026-11-09): facing never gets in the way,
## and attacking costs ground, so nobody shoots on while outrunning a foe
## (the anti-kite rule, PvP-safe: it is all positions and timers).
func square_up(x: float, z: float) -> void:
	face_towards(x, z)
	if moving and not rig.airborne:
		root = maxf(root, DB.attack.get("rootSeconds", 0.25))


## Auto attack is not a key you press, so it never roots you: standing,
## a swing snaps you to your foe; running, it only swings at a foe in your
## front half (the upper body swings, the legs keep running), so you can
## still run from a fight with auto attack on.
func _swing_facing(aim) -> bool:
	if moving:
		return facing_point(aim.x, aim.z, DB.attack.coneDegrees / 2.0)
	face_towards(aim.x, aim.z)
	return true


## The enemy you are fighting, while it is in melee reach (else null).
func _melee_foe():
	var tg = game.targeting
	if tg == null or not tg.attacking or not tg.in_reach(DB.attack.movingLeeway):
		return null
	return tg.current


## Turning in a melee fight (Dan, 2026-11-09): you face where you run, so
## stepping back towards a foe you had passed used to carry you through it
## and out the other side before you had turned. Now, with your foe in reach,
## pushing towards it turns you on the spot first. Bodies are never solid
## (Dan, 2026-11-09): once turned you walk on, through it if you hold the
## key. Moving away is untouched, so kiting rules hold.
func _melee_steer(mv: Dictionary, dt: float) -> Dictionary:
	var foe = _melee_foe()
	var ml := U.hyp(mv.x, mv.z)
	if foe == null or ml < 0.01:
		return mv
	var fx: float = foe.position.x - position.x
	var fz: float = foe.position.z - position.z
	var d := U.hyp(fx, fz)
	if d < 0.01:
		return mv
	fx /= d
	fz /= d
	var inward: float = (mv.x * fx + mv.z * fz) / ml
	if inward < cos(deg_to_rad(DB.attack.get("pivotDegrees", 70))):
		return mv
	if not facing_point(foe.position.x, foe.position.z, 30):
		facing = U.turn_towards(facing, atan2(fx, fz), dt * 24)
		return {"x": 0.0, "z": 0.0}
	return mv # facing it: walk on, straight through its body if you hold the key


## is (x, z) within `half_degrees` of where you face? (very close counts)
## Running, an attack or spell at an enemy needs it in your front half
## standing still, it turns you to it.
func can_hit_while_moving(x: float, z: float) -> bool:
	return facing_point(x, z, DB.attack.coneDegrees / 2.0)


func facing_point(x: float, z: float, half_degrees: float) -> bool:
	var dx := x - position.x
	var dz := z - position.z
	var d := U.hyp(dx, dz)
	if d < 0.001:
		return true
	return (dx * sin(facing) + dz * cos(facing)) / d >= cos(deg_to_rad(half_degrees))


func take_damage(amount: float) -> bool:
	if dead:
		return false
	health = maxf(0, health - amount)
	rig.hit()
	if amount > 0:
		hit_flash = 1.0
	if health <= 0:
		dead = true
		dead_time = 0
		pending = null
		pending_off = null
		lunge = null
		casting = null
		braced = 0
		_reset_jump()
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
	_set_casts_shadow(false)


## A spirit casts no shadow and fades whole: the body and everything hung
## on it (gear, weapons, shields; the blob under the feet goes). Gear put on
## while a spirit is caught by show_equipment; all comes back on revive.
var _shadow_off: Array = [] ## [instance, its cast_shadow]
var _gear_faded: Array = [] ## [mesh, surface, its own override before]
func _set_casts_shadow(on: bool) -> void:
	if on:
		for pair in _shadow_off:
			if is_instance_valid(pair[0]):
				pair[0].cast_shadow = pair[1]
		_shadow_off.clear()
		for g in _gear_faded:
			if is_instance_valid(g[0]):
				g[0].set_surface_override_material(g[1], g[2])
		_gear_faded.clear()
		ground_shadow.visible = true
		return
	for gi: GeometryInstance3D in model.find_children("*", "GeometryInstance3D", true, false):
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_shadow_off.append([gi, gi.cast_shadow])
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# gear meshes share their materials with the item models: fade copies
	var copies := []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null or m in materials or copies.has(m):
				continue
			var c := m.duplicate()
			_gear_faded.append([mi, i, mi.get_surface_override_material(i)])
			mi.set_surface_override_material(i, c)
			copies.append(c)
	Rig.set_alpha(copies, 0.45)
	Rig.set_emissive(copies, Color(0.35, 0.55, 0.8), 1)
	ground_shadow.visible = false


func revive(x: float, z: float, health_fraction := 1.0) -> void:
	dead = false
	if ghost:
		ghost = false
		Rig.set_alpha(materials, 1.0)
		Rig.set_emissive(materials, Color.BLACK, 0)
		_set_casts_shadow(true)
	health = maxf(1, U.jround(max_health * health_fraction))
	rig.revive()
	cooldowns = fresh_cooldowns()
	ranged_ready_at=0.0
	if game.spells:
		game.spells.reset()
	if game.resources:
		game.resources.reset()
	place_at(x, z, PI)
	game.events.emit("playerRevived", {})


static func fresh_cooldowns() -> Dictionary:
	var c := {"attack": 0.0, "attackOff": 0.0, "ranged": 0.0, "shieldBreak": 0.0, "lunge": 0.0, "brace": 0.0, "draught": 0.0, "gcd": 0.0}
	for id in DB.spells:
		c[id] = 0.0
	return c

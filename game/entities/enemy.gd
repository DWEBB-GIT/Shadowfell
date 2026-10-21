class_name Enemy
extends RefCounted
## One enemy (src/entities/enemy.js). AI states: idle -> chase -> attack,
## return home when the player escapes, dead when health reaches zero.
##
## What an enemy can do comes from its config: a melee swing (every enemy),
## a telegraphed cleave and special (the brute), a pack that wakes together
## (hounds), an aimed shot down a painted line that keeps its distance
## (archers, and the seer's bolt), and a circle cast under the player's feet
## that costs mana (the seer). Out of mana, a caster closes to melee.

var game
var id: String
var type: String
var cfg: Dictionary
var home: Vector3
var position: Vector3
var facing: float
var radius: float
var max_health: float
var health: float
var mana: float
var state := "idle"
var attack_timer := 0.6
var windup := 0.0 ## > 0 while an attack is being telegraphed
var casting = null ## ground-telegraphed attack in progress: { kind, telegraph, label, interruptible }
var special_timer := 3.0 ## first Grave Slam comes a few seconds into a fight
var circle_timer := 2.5
var stagger := 0.0
var mods := {}
var asleep := false
var staggered := 0.0
var dr := {}
var stagger_bar = null
var knock := Vector3.ZERO
var flash := 0.0
var flash_colour := Rig.FLASH_RED
var engaged := 0.0 ## seconds to keep showing the health bar
var since_struck := INF ## seconds since the player last hurt it

## While the player keeps hurting it, an enemy chases past its leash: it
## gives up only after this long without being struck.
const LEASH_GRACE := 6.0
var dead := false
var corpse := false ## a body from a saved game, still waiting to be looted
var wander := {}
var path := [] ## waypoints (Vector2, x/z) round obstacles to where it is going
var path_timer := 0.0
var path_goal := Vector2(INF, INF)
var group: Node3D
var model: Node3D
var rig: Rig
var materials: Array


func _init(g, spawn: Dictionary) -> void:
	game = g
	id = spawn.id
	type = spawn.type
	cfg = DB.enemy_cfg_at(type, id)
	home = Vector3(spawn.position[0], 0, spawn.position[1])
	position = home
	position.y = Terrain.height_at(position.x, position.z)
	facing = randf() * TAU
	radius = cfg.radius
	# each spawn point's enemy is a little leaner or bigger than its type (+-10%)
	max_health = cfg.health if cfg.get("type") == "boss" or cfg.get("dummy", false) else Scaling.spawn_health(cfg.health, id)
	health = max_health
	mana = cfg.get("mana", 0)
	_reset_control()
	wander = {"t": randf() * 3, "target": home}

	group = Node3D.new()
	group.name = "Enemy_" + id
	model = Assets.instance(cfg.model)
	group.add_child(model)
	rig = Rig.new(model, cfg.model)
	materials = Rig.isolate_materials(model)
	# a rare elite reuses its kin's model, sized and tinted
	if cfg.get("scale"):
		model.scale *= cfg.scale
	if cfg.get("tint"):
		Rig.tint(materials, Color(cfg.tint))
	_sync()


var alive: bool:
	get:
		return not dead


# ---- control: stuns, sleeps, slows and the boss stagger bar
func _reset_control() -> void:
	mods = {"slow": 0.0, "taken": 1.0, "dealt": 1.0} # set each frame by your auras (spells.gd)
	asleep = false
	staggered = 0.0
	dr = {"n": 0, "quiet": 0.0}
	stagger_bar = {"value": 0.0, "need": DB.CONFIG.control.bossStaggerNeed} if cfg.get("type") == "boss" else null


## passive (data `attitude`): leaves you be until you strike it; shown yellow
var passive: bool:
	get:
		return cfg.get("attitude", "aggressive") == "passive"

var is_elite: bool:
	get:
		return cfg.get("type") == "elite" or cfg.get("elite", false)

var move_speed: float:
	get:
		return cfg.speed * (1 - minf(90, mods.slow) / 100.0)

var damage_taken_scale: float:
	get:
		return mods.taken * (1 + DB.CONFIG.control.staggeredDamageTaken / 100.0 if staggered > 0 else 1.0)

var damage_dealt_scale: float:
	get:
		return mods.dealt


## A stun or sleep of `seconds`: returns how long it holds (0 if it does
## not). A boss takes none and staggers; an elite wears it off.
func control(kind: String, seconds: float) -> float:
	if dead or cfg.get("dummy", false):
		return 0.0
	var c: Dictionary = DB.CONFIG.control
	if stagger_bar != null:
		var b: Dictionary = stagger_bar
		if staggered > 0:
			return 0.0
		b.value += seconds
		if b.value >= b.need:
			b.value = 0.0
			b.need *= c.staggerGrowth
			staggered = c.staggered
			_hold(c.staggered)
			game.events.emit("log", {"text": "The %s is Staggered!" % cfg.name, "kind": "level"})
			if game.hud:
				game.hud.toast("Staggered!")
		return 0.0
	if is_elite:
		if dr.n >= c.eliteDr.size():
			return 0.0
		var share: float = c.eliteDr[dr.n]
		dr.n += 1
		dr.quiet = 0.0
		seconds *= share
	_hold(seconds)
	asleep = kind == "sleep"
	return seconds


## frozen in place: the swing or cast being made is broken
func _hold(seconds: float) -> void:
	stagger = maxf(stagger, seconds)
	windup = 0.0
	rig.action = null
	_cancel_cast()


## the player slipped into Shadow: stop chasing and stand looking about
func lose_track() -> void:
	if dead or cfg.get("dummy", false):
		return
	state = "idle"
	windup = 0.0
	wander.target = position


func _sync() -> void:
	group.position = position
	group.rotation.y = facing


## used on player respawn: surviving enemies return to their posts
func reset() -> void:
	if dead:
		return
	position = home
	position.y = Terrain.height_at(home.x, home.z)
	health = max_health
	mana = cfg.get("mana", 0)
	state = "idle"
	windup = 0.0
	_cancel_cast()
	special_timer = 3.0
	circle_timer = 2.5
	stagger = 0.0
	_reset_control()
	engaged = 0.0
	since_struck = INF
	rig.action = null
	_sync()


## opts: stagger, knockFrom, knockback, heavy, quiet (the damage only; its
## flash and flinch are shown later)
func hurt(amount: float, opts := {}) -> float:
	if dead:
		return 0.0
	var stag: float = opts.get("stagger", 0.15)
	var heavy: bool = opts.get("heavy", false)
	var dealt := minf(health, amount)
	health -= dealt
	engaged = 6.0
	since_struck = 0.0
	# damage wakes a sleeper
	if amount > 0 and asleep:
		asleep = false
		stagger = minf(stagger, stag)
	if not opts.get("quiet", false):
		flash = 1.0
		flash_colour = Rig.FLASH_WHITE if heavy else Rig.FLASH_RED
		rig.hit()
	if not asleep:
		stagger = maxf(stagger, stag)
	if heavy and not (casting != null and not casting.interruptible):
		# a heavy blow interrupts an ordinary swing or an interruptible cast;
		# casts marked `interruptible: false` in the data (Grave Slam) go on
		windup = 0.0
		rig.action = null
		_cancel_cast()
	var from = opts.get("knockFrom")
	var kb: float = opts.get("knockback", 0)
	if from != null and kb > 0:
		var dir := Vector3(position.x - from.x, 0, position.z - from.z)
		if dir.length_squared() > 0.0001:
			knock = dir.normalized() * kb * 6
	if not cfg.get("dummy", false) and (state == "idle" or state == "return"):
		state = "chase"
		_wake_pack()
	if health <= 0 and cfg.get("dummy", false):
		# the training dummy never dies: it is whole again (beating it still
		# counts, for the Dummy Slayer title)
		health = max_health
		game.events.emit("dummyBeaten", {"enemy": self})
	elif health <= 0:
		dead = true
		state = "dead"
		windup = 0.0
		_cancel_cast()
		rig.die()
	return dealt


## An interrupt (Rebuke): breaks an interruptible cast and holds off the
## next attack for `lockout` seconds. Returns the broken cast's label, false
## when it cannot be broken, or null when nothing is being cast.
func interrupt(lockout: float):
	if dead or casting == null:
		return null
	if not casting.interruptible:
		return false
	var label = casting.label
	_cancel_cast()
	rig.action = null
	attack_timer = maxf(attack_timer, lockout)
	circle_timer = maxf(circle_timer, lockout)
	return label


func _cancel_cast() -> void:
	if casting != null:
		game.telegraphs.cancel(casting.telegraph)
	casting = null


## A hound that wakes brings the rest of its pack.
func _wake_pack() -> void:
	if not cfg.get("pack"):
		return
	for o in game.enemies.list:
		if o == self or not o.alive or o.type != type or o.state != "idle":
			continue
		if U.hyp(o.position.x - position.x, o.position.z - position.z) <= cfg.pack:
			o.state = "chase"


## An aimed shot: a line is painted towards the player; when it fills, the
## arrow (or bolt) flies down it and hits whoever is still on it.
func _start_shot(player) -> void:
	var r: Dictionary = cfg.ranged
	var angle := atan2(player.position.x - position.x, player.position.z - position.z)
	facing = angle
	var bolt: bool = r.get("projectile") == "bolt"
	var telegraph = game.telegraphs.line(self, {
		"angle": angle,
		"length": r.range + 1,
		"width": r.width,
		"duration": r.windup,
		"color": Color("8a6cff") if bolt else Color("e8a040"),
		# `lock` in the data: the shot follows the player until that many
		# seconds before it looses
		"track": (func():
			facing = atan2(game.player.position.x - position.x, game.player.position.z - position.z)
			return facing) if r.has("lock") else null,
		"lock": r.get("lock", 0.0),
		"onComplete": func(shape):
			casting = null
			var end := Vector3(shape.x + sin(shape.angle) * shape.length, 0, shape.z + cos(shape.angle) * shape.length)
			var p: Vector3 = game.player.position
			var on_line: bool = shape.contains(p.x, p.z, game.player.radius)
			# the shot stops at the player if it hits, otherwise flies on
			var to := Vector3(p.x, 0, p.z) if on_line else end
			game.events.emit("projectile", {"kind": r.get("projectile"), "from": Vector3(position.x, position.y + 1.3, position.z), "to": to, "speed": r.speed})
			game.combat.resolve_telegraph(self, shape, r.damage, r.name, {"canCrit": true, "canBlock": true, "school": r.get("school", "physical")}),
	})
	if r.get("mana"):
		mana -= r.mana
	casting = {"kind": "shot", "telegraph": telegraph, "label": r.name, "interruptible": r.get("interruptible", true) != false}
	attack_timer = r.interval
	rig.play("cast" if bolt else "shoot", r.windup + 0.25, r.windup / (r.windup + 0.25))
	game.events.emit("enemyWindup", {"enemy": self})


## A circle under the player's feet that fills, then strikes; walk out of it.
func _start_circle(player) -> void:
	var c: Dictionary = cfg.circle
	facing = atan2(player.position.x - position.x, player.position.z - position.z)
	var telegraph = game.telegraphs.circle(self, {
		"x": player.position.x,
		"z": player.position.z,
		"radius": c.radius,
		"duration": c.windup,
		"onComplete": func(shape):
			casting = null
			game.events.emit("darkCircle", {"x": shape.x, "z": shape.z, "radius": shape.range})
			game.combat.resolve_telegraph(self, shape, c.damage, c.name, {"canCrit": false, "canBlock": false, "school": c.get("school", "physical")}),
	})
	mana -= c.mana
	circle_timer = c.cooldown
	attack_timer = maxf(attack_timer, c.windup + 0.5)
	casting = {"kind": "circle", "telegraph": telegraph, "label": c.name, "interruptible": c.get("interruptible", true) != false}
	rig.play("cast", c.windup + 0.3, c.windup / (c.windup + 0.3))
	game.events.emit("log", {"text": "The %s calls the dark up out of the earth. Move!" % cfg.name, "kind": "hurt", "throttle": "circle-warn"})
	game.events.emit("enemyWindup", {"enemy": self, "special": true})


## Telegraphed attacks: the area is fixed now and lands when it fills.
func _start_cast(kind: String, player) -> void:
	var sp = cfg.get("special")
	var angle := atan2(player.position.x - position.x, player.position.z - position.z)
	facing = angle
	var special := kind == "special"
	var duration: float = sp.windup if special else cfg.windup
	var range_: float = sp.range if special else cfg.meleeRange + radius + 0.9
	var telegraph = game.telegraphs.cone(self, {
		"angle": angle,
		"range": range_,
		"arc": sp.arc if special else 100.0,
		"duration": duration,
		"heavy": special,
		"onComplete": func(shape):
			casting = null
			var hit = game.combat.resolve_telegraph(self, shape, sp.damage if special else cfg.damage, sp.name if special else null)
			if special:
				game.events.emit("graveSlam", {"enemy": self, "shape": shape, "hit": hit}),
	})
	casting = {"kind": kind, "telegraph": telegraph, "label": sp.name if special else "Cleave", "interruptible": sp.get("interruptible", true) != false if special else true}
	if special:
		special_timer = sp.cooldown
		attack_timer = maxf(attack_timer, sp.windup + 0.6)
		rig.play("slam", sp.windup + 0.4, sp.windup / (sp.windup + 0.4))
		game.events.emit("log", {"text": "The %s raises its cleaver high. Get clear!" % cfg.name, "kind": "hurt", "throttle": "slam-warn"})
	else:
		attack_timer = cfg.attackInterval
		rig.play("cleave", duration + 0.3, duration / (duration + 0.3))
	game.events.emit("enemyWindup", {"enemy": self, "special": special})


const ANIMATE_RANGE := 45.0
var _flash_shown := false


func update(dt: float, player) -> void:
	# the hit flash: materials are only touched while it shows (and once
	# more to clear it), not every frame for every enemy in the world
	if flash > 0 or _flash_shown:
		flash = maxf(0, flash - dt * 5)
		Rig.set_emissive(materials, flash_colour, flash * (0.35 if flash_colour == Rig.FLASH_WHITE else 0.6))
		_flash_shown = flash > 0
	engaged = maxf(0, engaged - dt)

	if dead or cfg.get("dummy", false):
		# the dummy just stands there, and mends a few seconds after the last hit
		if cfg.get("dummy", false):
			if engaged <= 0:
				health = max_health
			# ...and never leaves its post: no knockback, no shoving
			knock = Vector3.ZERO
			position.x = home.x
			position.z = home.z
		rig.update(dt, 0)
		_sync()
		return

	var dx: float = player.position.x - position.x
	var dz: float = player.position.z - position.z
	var dist := U.hyp(dx, dz)
	var from_home := U.hyp(position.x - home.x, position.z - home.z)
	var reach: float = cfg.meleeRange + player.radius + radius * 0.5
	var speed01 := 0.0

	# knockback slides, easing out exponentially so the distance is the same
	# at any frame rate
	if knock.length_squared() > 0.001:
		var fade := exp(-9 * dt)
		position += knock * ((1 - fade) / 9)
		knock *= fade

	staggered = maxf(0, staggered - dt)
	since_struck += dt
	dr.quiet += dt
	if dr.quiet >= DB.CONFIG.control.eliteDrReset:
		dr.n = 0
	var hidden: bool = game.spells != null and game.spells.hidden
	if stagger > 0:
		stagger -= dt
		if stagger <= 0:
			asleep = false
	elif player.dead:
		if state != "idle":
			state = "return"
	else:
		match state:
			"idle":
				# a passive beast (yellow) pays you no mind until struck
				if dist < cfg.detection and not hidden and not passive:
					state = "chase"
					game.events.emit("enemyAlert", {"enemy": self})
					_wake_pack()
			"chase", "attack":
				# lost in Shadow: it stops where it is, unhurt and unhealed, and looks about
				if hidden:
					lose_track()
				elif (from_home > DB.leash_distance or dist > cfg.detection * 2) and since_struck >= LEASH_GRACE:
					state = "return"
					windup = 0.0
				else:
					state = "attack" if dist <= reach else "chase"
					engaged = maxf(engaged, 2)
			"return":
				if dist < cfg.detection * 0.8 and from_home < DB.leash_distance * 0.6 and not hidden and not passive:
					state = "chase"
				elif from_home < 0.6:
					state = "idle"

	attack_timer = maxf(0, attack_timer - dt)
	special_timer = maxf(0, special_timer - dt)
	circle_timer = maxf(0, circle_timer - dt)
	if cfg.get("mana"):
		mana = minf(cfg.mana, mana + cfg.get("manaRegen", 0) * dt)
	if player.dead and casting != null:
		_cancel_cast()
	var fighting := state == "chase" or state == "attack"
	var rg = cfg.get("ranged")
	var can_shoot: bool = rg != null and mana >= rg.get("mana", 0)
	var cc = cfg.get("circle")

	if casting != null:
		# committed: hold position while the telegraph fills
		speed01 = 0.0
	elif stagger <= 0 and not player.dead:
		var sp = cfg.get("special")
		if sp != null and special_timer <= 0 and dist < sp.trigger and fighting:
			_start_cast("special", player)
		elif cc != null and fighting and circle_timer <= 0 and mana >= cc.mana and dist <= cc.range:
			_start_circle(player)
		elif can_shoot and fighting and dist > reach:
			# a ranged enemy holds its distance: closes to range, backs off
			# when the player gets close, and shoots when it is ready
			facing = atan2(dx, dz)
			if dist > rg.range * 0.9:
				_steer_towards(player.position.x, player.position.z, move_speed, dt, rg.range * 0.8)
				speed01 = 1.0
			elif dist < rg.keep:
				position.x -= (dx / dist) * move_speed * 0.75 * dt
				position.z -= (dz / dist) * move_speed * 0.75 * dt
				speed01 = 0.7
				if attack_timer <= 0:
					_start_shot(player)
			elif attack_timer <= 0:
				_start_shot(player)
		elif state == "chase":
			_steer_towards(player.position.x, player.position.z, move_speed, dt, reach * 0.85)
			speed01 = 1.0
			if windup > 0:
				windup = 0.0
		elif state == "attack" and cfg.get("telegraph"):
			facing = atan2(dx, dz)
			if attack_timer <= 0:
				_start_cast("normal", player)
		elif state == "attack":
			facing = atan2(dx, dz)
			if windup > 0:
				windup -= dt
				if windup <= 0:
					windup = 0.0
					game.combat.resolve_enemy_strike(self)
			elif attack_timer <= 0:
				# telegraph, then strike; the interval runs from the start of the swing
				windup = cfg.windup
				attack_timer = cfg.attackInterval
				rig.play(cfg.get("meleeAnim", "cleave" if type == "brute" else "claw"), cfg.windup + 0.3, cfg.windup / (cfg.windup + 0.3))
				game.events.emit("enemyWindup", {"enemy": self})
	if casting != null:
		pass # nothing else moves while committed to a telegraphed attack
	elif state == "return" and stagger <= 0:
		_steer_towards(home.x, home.z, move_speed * 0.8, dt, 0.3)
		speed01 = 0.8
		health = minf(max_health, health + dt * 6)
	elif state == "idle":
		speed01 = _idle_shuffle(dt)

	position = game.collision.resolve(position, radius)
	position.y = Terrain.height_at(position.x, position.z)
	# limbs only move where someone could see them (the camera shows about
	# 30 m around the Warden)
	if state != "idle" or U.hyp(dx, dz) < ANIMATE_RANGE:
		rig.update(dt, speed01 * (0.8 if type == "brute" else 1.0 if cfg.model == "hound" else 0.7))
	_sync()


## Go to x/z the way a person would: straight when nothing is in the way,
## else round the fence, wall or rock by a path (Collision.find_path),
## looked for again every so often or when the goal moves.
func _steer_towards(x: float, z: float, speed: float, dt: float, stop_at: float) -> void:
	var col = game.collision
	path_timer -= dt
	var goal := Vector2(x, z)
	if not col.blocked_between(position.x, position.z, x, z, radius):
		path = []
		_move_towards(x, z, speed, dt, stop_at)
		return
	if path_timer <= 0 or goal.distance_to(path_goal) > 1.5:
		path = col.find_path(position.x, position.z, x, z, radius)
		path_goal = goal
		path_timer = 0.6 + randf() * 0.3
	# drop the waypoints already reached
	while not path.is_empty() and Vector2(position.x, position.z).distance_to(path[0]) < 0.35:
		path.pop_front()
	if path.is_empty() or path.size() == 1:
		_move_towards(x, z, speed, dt, stop_at)
		return
	_move_towards(path[0].x, path[0].y, speed, dt, 0.0)


func _move_towards(x: float, z: float, speed: float, dt: float, stop_at: float) -> void:
	var dx := x - position.x
	var dz := z - position.z
	var d := U.hyp(dx, dz)
	if d < 0.0001:
		return
	facing = atan2(dx, dz)
	if d <= stop_at:
		return
	var step := minf(d - stop_at, speed * dt)
	position.x += (dx / d) * step
	position.z += (dz / d) * step


## stay near the post, shuffling now and then
func _idle_shuffle(dt: float) -> float:
	var w := wander
	w.t -= dt
	if w.t <= 0:
		w.t = 3 + randf() * 4
		var a := randf() * TAU
		# `roam` (metres): wanders that far from its post instead of shuffling
		var r: float = randf() * cfg.get("roam", 2.0)
		w.target = Vector3(home.x + cos(a) * r, 0, home.z + sin(a) * r)
	var d := U.hyp(w.target.x - position.x, w.target.z - position.z)
	if d > 0.2:
		var pace := 0.45 if cfg.get("roam") else 0.25
		_move_towards(w.target.x, w.target.z, move_speed * pace, dt, 0.1)
		return pace + 0.1
	return 0.0

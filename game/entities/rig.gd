class_name Rig
extends RefCounted
## Procedural animation for the Blender characters (src/entities/rig.js).
## Each part's origin sits at its joint, so rotating a part swings it. All
## timing is in seconds. Parts turn in X-Y-Z order, as three.js turns them.

const PART_NAMES := ["Torso", "Head", "Arm_L", "Arm_R", "Leg_L", "Leg_R", "Weapon"]

var model: Node3D
var style: String
var parts := {}
var base := {}
var phase := 0.0
var move := 0.0 ## 0 idle .. 1 full walk
var time := 0.0
var action = null ## { type, t, duration, impact, auto }
var off_action = null
var flinch := 0.0
var death := -1.0 ## -1 alive, otherwise seconds since death
var pose = null ## a held pose ('fish', 'sit') when no action plays


static func ease_(t: float) -> float:
	return t * t * (3 - 2 * t)


func _init(m: Node3D, s := "warden") -> void:
	model = m
	style = s
	for name in PART_NAMES:
		var obj := m.find_child(name, true, false) as Node3D
		if obj:
			obj.rotation_order = EULER_ORDER_XYZ
			parts[name] = obj
			base[name] = {"rot": obj.rotation, "pos": obj.position}
	time = randf() * 10


func play(type: String, duration: float, impact := 0.5) -> void:
	action = {"type": type, "t": 0.0, "duration": duration, "impact": impact, "auto": false}


## a second weapon's swing on the left arm, on its own timing (dual wielding)
func play_off(duration: float, impact := 0.4) -> void:
	off_action = {"t": 0.0, "duration": duration, "impact": impact}


func hit() -> void:
	flinch = 1.0


func die() -> void:
	death = 0.0
	action = null
	off_action = null


func revive() -> void:
	death = -1.0
	model.rotation.x = 0
	model.rotation.z = 0
	model.position.y = 0


func reset() -> void:
	for name in parts:
		parts[name].rotation = base[name].rot
		parts[name].position = base[name].pos


func _rot(name: String, axis: int, add: float) -> void:
	if parts.has(name):
		parts[name].rotation[axis] += add


func update(dt: float, speed01: float) -> void:
	time += dt
	move += (speed01 - move) * minf(1, dt * 10)
	var stride := 6.0 if style == "brute" else 7.0 if style == "ghoul" else 13.0 if style == "hound" else 9.0
	phase += dt * stride * maxf(0.2, move)
	flinch = maxf(0, flinch - dt * 4)
	reset()

	var s := sin(phase)
	var m := move
	var breathe := sin(time * 1.8) * 0.03
	_rot("Leg_L", 0, s * 0.65 * m)
	_rot("Leg_R", 0, -s * 0.65 * m)
	_rot("Arm_L", 0, -s * 0.45 * m)
	_rot("Arm_R", 0, s * 0.45 * m)
	if parts.has("Torso"):
		parts.Torso.position.y += absf(cos(phase)) * 0.04 * m
		_rot("Torso", 0, breathe - flinch * 0.35)
		_rot("Torso", 2, sin(phase) * 0.05 * m)

	if style == "ghoul":
		_rot("Arm_L", 0, -(0.9 + sin(time * 2.1) * 0.1))
		_rot("Arm_R", 0, -(0.8 + sin(time * 2.4) * 0.1))
		_rot("Head", 2, sin(time * 1.3) * 0.15)
	if style == "brute":
		_rot("Torso", 0, -0.08)

	if pose == "sit" and action == null:
		_rot("Leg_L", 0, -1.45)
		_rot("Leg_R", 0, -1.35)
		_rot("Arm_R", 0, -0.9 + sin(time * 3) * 0.25)
		_rot("Arm_L", 0, -0.5)
		model.position.y = -0.5
	elif death < 0:
		model.position.y = 0
	if pose == "fish" and action == null:
		_rot("Arm_R", 0, -1.0)
		_rot("Arm_L", 0, -0.35)
	if action != null:
		_apply_action(dt)
	if off_action != null:
		_apply_off_action(dt)
	if death >= 0:
		_apply_death(dt)


func _apply_off_action(dt: float) -> void:
	var a: Dictionary = off_action
	a.t += dt
	var k := minf(1, a.t / a.duration)
	var impact: float = a.impact
	var up := impact * 0.65
	var arm: float
	if k < up:
		arm = -2.4 * ease_(k / up)
	elif k < impact:
		arm = -2.4 + 2.0 * ease_((k - up) / (impact - up))
	else:
		arm = -0.4 * (1 - ease_((k - impact) / (1 - impact)))
	_rot("Arm_L", 0, arm)
	_rot("Arm_L", 1, -0.3 * minf(1, -arm / 2.4))
	_rot("Torso", 1, -0.25 * minf(1, -arm / 2.4))
	if k >= 1:
		off_action = null


func _apply_action(dt: float) -> void:
	var a: Dictionary = action
	a.t += dt
	var k := minf(1, a.t / a.duration)
	var impact: float = a.impact
	var raise := ease_(k / impact) if k < impact else 1 - ease_((k - impact) / (1 - impact))
	var swing := 0.0 if k < impact else ease_(minf(1, (k - impact) / 0.35))
	match a.type:
		"strike":
			# an overhand cut: up and back through most of the windup, then down hard
			var up := impact * 0.65
			var arm: float
			if k < up:
				arm = -2.7 * ease_(k / up)
			elif k < impact:
				arm = -2.7 + 2.3 * ease_((k - up) / (impact - up))
			else:
				arm = -0.4 * (1 - ease_((k - impact) / (1 - impact)))
			_rot("Arm_R", 0, arm)
			_rot("Arm_R", 1, 0.35 * minf(1, -arm / 2.7))
			_rot("Torso", 1, 0.35 * minf(1, -arm / 2.7) - 0.2 * swing * (1 - k))
			_rot("Torso", 0, 0.12 if k >= up and k < impact + 0.15 else 0.0)
		"slam":
			_rot("Arm_R", 0, -2.9 * raise - 0.8 * swing * (1 - k))
			_rot("Arm_L", 0, -2.7 * raise - 0.8 * swing * (1 - k))
			_rot("Torso", 0, -0.25 * raise + 0.45 * swing * (1 - k))
		"dodge":
			_rot("Torso", 0, 0.55 * sin(k * PI))
			_rot("Leg_L", 0, 0.8 * sin(k * PI))
			_rot("Leg_R", 0, -0.5 * sin(k * PI))
			model.position.y = -0.25 * sin(k * PI)
		"brace":
			_rot("Arm_L", 0, -1.5 * minf(1, k * 4))
			_rot("Arm_L", 1, 0.5 * minf(1, k * 4))
			_rot("Torso", 0, 0.12 * minf(1, k * 4))
		"drink":
			_rot("Arm_L", 0, -2.2 * sin(k * PI))
			_rot("Head", 0, -0.4 * sin(k * PI))
		"claw":
			_rot("Arm_L", 0, -1.6 * raise + 0.6 * swing * (1 - k))
			_rot("Arm_R", 0, -1.8 * raise + 0.6 * swing * (1 - k))
			_rot("Torso", 0, -0.3 * raise + 0.4 * swing * (1 - k))
		"bite":
			_rot("Torso", 0, 0.25 * raise - 0.15 * swing * (1 - k))
			_rot("Head", 0, -0.5 * raise + 0.7 * swing * (1 - k))
			_rot("Arm_L", 0, -0.6 * raise)
			_rot("Arm_R", 0, -0.6 * raise)
			model.position.z = 0.25 * swing * (1 - k)
		"shoot":
			var draw := minf(1, k / maxf(0.01, impact) * 1.6) * (1.0 if k < impact else 1 - ease_((k - impact) / (1 - impact)))
			_rot("Arm_L", 0, -1.55 * draw)
			_rot("Arm_R", 0, -1.4 * raise)
			_rot("Arm_R", 2, 0.5 * raise)
			_rot("Torso", 1, 0.35 * raise)
		"castLine":
			_rot("Arm_R", 0, -1.0 - 1.7 * raise)
			_rot("Arm_L", 0, -0.35)
			_rot("Torso", 0, -0.12 * raise + 0.1 * swing * (1 - k))
		"reel":
			# the rod snaps up and back as the line comes out of the water
			var yank := ease_(minf(1, k * 3)) * (1 - maxf(0, (k - 0.65) / 0.35))
			_rot("Arm_R", 0, -1.0 - 1.9 * yank)
			_rot("Arm_L", 0, -0.35 - 0.4 * yank)
			_rot("Torso", 0, -0.22 * yank)
		"cast":
			_rot("Arm_R", 0, -2.2 * raise + 0.6 * swing * (1 - k))
			_rot("Arm_L", 0, -1.8 * raise)
			_rot("Head", 0, -0.3 * raise)
		"cleave":
			_rot("Arm_R", 0, -2.8 * raise)
			_rot("Arm_L", 0, -1.2 * raise)
			_rot("Torso", 0, -0.3 * raise + 0.5 * swing * (1 - k))
	if k >= 1:
		action = null
		if a.type == "dodge":
			model.position.y = 0
		if a.type == "bite":
			model.position.z = 0


func _apply_death(dt: float) -> void:
	death += dt
	var k := minf(1, death / 0.7)
	# hounds roll onto their side; everything else topples backwards
	if style == "hound":
		model.rotation.z = ease_(k) * (PI / 2) * 0.9
	else:
		model.rotation.x = -ease_(k) * (PI / 2) * 0.95
	if death > 2.5:
		model.position.y = -minf(1.2, (death - 2.5) * 0.4)
	_rot("Arm_L", 0, -1.2 * k)
	_rot("Arm_R", 0, -1.0 * k)


## Give every mesh its own copies of its materials, so tints, flashes and
## fades touch only this model. Returns the copies.
static func isolate_materials(root: Node) -> Array:
	var out := []
	var cache := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_active_material(i)
			if m == null:
				continue
			if not cache.has(m):
				cache[m] = m.duplicate()
				out.append(cache[m])
			mi.set_surface_override_material(i, cache[m])
	return out


static func set_emissive(materials: Array, colour: Color, amount: float) -> void:
	for m in materials:
		if m is BaseMaterial3D:
			m.emission_enabled = amount > 0.001
			m.emission = colour * amount


## Fade (ghost, Shadow) or restore every material.
static func set_alpha(materials: Array, alpha: float) -> void:
	for m in materials:
		if m is BaseMaterial3D:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1 else BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = alpha


static func tint(materials: Array, colour: Color) -> void:
	for m in materials:
		if m is BaseMaterial3D:
			m.albedo_color = m.albedo_color * colour


const FLASH_RED := Color(0.9, 0.25, 0.15)
const FLASH_WHITE := Color(1, 0.9, 0.75)

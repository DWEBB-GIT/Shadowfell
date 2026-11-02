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
var held := 0.0 ## hit-stop left (hold)
var death := -1.0 ## -1 alive, otherwise seconds since death
var pose = null ## a held pose ('fish', 'sit' to eat, 'rest' to sit) when no action plays
## footfalls: counts up each time a foot comes down in the walk or run (the
## player's footstep sounds follow it, see AudioSystem._footsteps). Set
## track_steps to watch an imported skeleton's feet.
var steps := 0
var track_steps := false
var _feet := [] ## { bone, y, dy, low } per foot of an imported skeleton
var _skel: Skeleton3D
var _step_gap := 0.0
## Upper and lower body apart (imported skeletons): moving while an action or
## a flinch plays, the legs keep the Walk/Run/Jump clip and only the bones
## from the waist up take the action clip, so the body never slides along in
## a standing swing pose. { name, t } of the clip on the upper body, its
## weight (eased in and out) and the bones it moves.
var _upper = null
var _upper_w := 0.0
var _upper_bones = null ## bone index -> true, from the waist up
var _upper_tracks := {} ## clip name -> [[track, bone], ...]
## the weight the upper body eases at (per second)
const UPPER_FADE := 10.0


static func ease_(t: float) -> float:
	return t * t * (3 - 2 * t)


## Imported models (assets/blender/import_models.py) bring their own skeleton
## and clips (Idle, Walk, Run, Attack, Cast, Sit, Hit, Death) instead of parts to
## swing: `anim` plays them from the same calls (play, hit, die, update).
var anim: AnimationPlayer
var clip := ""
## off the ground (the player's hop): plays the Jump clip
var airborne := false
## how fast each imported model's Walk clip plays at full speed
const WALK_RATE := {"rat": 2.4, "chicken": 1.8, "base_male": 1.0, "battle_mage": 2.5, "skeleton": 1.3}
## and its Run clip: the battle mage's Mixamo run covers 4.6 m a second, the
## player runs 6.2 (CONFIG.player speed, runGait; 5.6 until 2026-11-02)
const RUN_RATE := {"battle_mage": 1.04}
## which clip an action plays; any other action plays Attack, and these
## hold still (gathering, crafting, looting: the bar shows the progress)
const ACTION_CLIPS := {"cast": "Cast", "shoot": "Cast", "castLine": "Cast", "reel": "Cast", "drink": "Cast", "brace": ""}
## where the blow falls in an action clip, as a share of its length
const CLIP_IMPACT := 0.5
## parts the game hangs gear on (player.gd), as frames on the bones of an
## imported skeleton: a frame sits at its bone and turns with it, lined up
## with the model at rest like the built models' parts. The arms' frames sit
## at the shoulder, as the built arms do, but ride the hand, so what is held
## stays in the hand however the elbow and wrist bend.
const SOCKETS := {"Torso": "mixamorig_Hips", "Head": "mixamorig_Head", "Arm_R": "mixamorig_RightHand", "Arm_L": "mixamorig_LeftHand"}
const SOCKET_AT := {"Arm_R": "mixamorig_RightArm", "Arm_L": "mixamorig_LeftArm"}


## Give an imported humanoid the parts the built models have (see SOCKETS),
## with the held weapon's place at the right hand.
static func add_sockets(m: Node3D) -> void:
	var found := m.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	var sk: Skeleton3D = found[0]
	for part in SOCKETS:
		var bone := sk.find_bone(SOCKETS[part])
		if bone < 0:
			continue
		var at := BoneAttachment3D.new()
		at.name = "Socket_" + part
		at.bone_name = SOCKETS[part]
		sk.add_child(at)
		var rest := sk.get_bone_global_rest(bone)
		var at_bone := sk.find_bone(SOCKET_AT.get(part, SOCKETS[part]))
		var origin := sk.get_bone_global_rest(at_bone if at_bone >= 0 else bone).origin
		var frame := Node3D.new()
		frame.name = part
		frame.transform = rest.affine_inverse() * Transform3D(Basis(), origin)
		at.add_child(frame)
		if part == "Arm_R":
			# the grip, a little past the wrist; the blade tilted forward as
			# the warden holds it
			var weapon := Node3D.new()
			weapon.name = "Weapon"
			weapon.transform = Transform3D(Basis(Quaternion(0.6427876, 0, 0, 0.7660445)), rest.origin - origin + Vector3(0, -0.07, 0.02))
			frame.add_child(weapon)


func _init(m: Node3D, s := "warden") -> void:
	model = m
	style = s
	anim = m.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim and not anim.has_animation("Idle"):
		anim = null
	if anim:
		# stepped by update(), so clips keep the game's time (and far
		# creatures that skip update stand still, as the part rigs do)
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for n in ["Idle", "Walk", "Run", "Sit"]:
			if anim.has_animation(n):
				anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		_clip("Idle", 1.0)
		anim.seek(randf() * anim.get_animation("Idle").length, true)
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
	# an imported model with a Hit clip flinches with it (never mid-swing);
	# on the move only the upper body flinches, the legs keep running
	if anim and anim.has_animation("Hit") and action == null and death < 0:
		if _moving():
			_upper = {"name": "Hit", "t": 0.0, "speed": 1.0, "hit": true}
		else:
			_clip("Hit", 1.0, true)


func _moving() -> bool:
	return move > 0.12 or airborne


## A visual recoil from a heavy blow or a crit: the body jolts away from the
## attacker along `dir` (world space, flat) and leans back, then settles.
## Only the model moves; the creature itself stays where it stands (Dan,
## 2026-11-02: no shoving enemies around).
func knock(dir: Vector3, amount: float) -> void:
	if death >= 0 or dir.length_squared() < 0.0001:
		return
	var local := dir.normalized().rotated(Vector3.UP, -model.get_parent().rotation.y) if model.get_parent() is Node3D else dir.normalized()
	recoil_dir = local
	recoil_amp = amount
	recoil = 1.0
	_apply_recoil()


var recoil := 0.0 ## 1 at the blow, easing to 0
var recoil_amp := 0.0
var recoil_dir := Vector3.ZERO
var _recoil_pos := Vector3.ZERO
var _recoil_rot := Vector2.ZERO
const RECOIL_TILT := 0.9 ## radians of lean per metre of jolt


func _apply_recoil() -> void:
	var k := recoil * recoil
	var off := recoil_dir * recoil_amp * k
	var lean := Vector2(recoil_dir.z, -recoil_dir.x) * recoil_amp * RECOIL_TILT * k
	model.position += off - _recoil_pos
	model.rotation.x += lean.x - _recoil_rot.x
	model.rotation.z += lean.y - _recoil_rot.y
	_recoil_pos = off
	_recoil_rot = lean


## Hit-stop: hold the whole body still for `t` seconds as a blow lands, so it
## reads as meeting something solid. Only the look pauses; the game runs on.
func hold(t: float) -> void:
	held = maxf(held, t)


func die() -> void:
	recoil = 0.0
	_apply_recoil()
	death = 0.0
	action = null
	off_action = null


func revive() -> void:
	death = -1.0
	clip = ""
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


func _clip(name: String, speed: float, restart := false) -> void:
	if not anim.has_animation(name):
		name = "Idle"
	if name != clip or restart:
		anim.play(name, 0.0 if restart else 0.15)
		if restart:
			anim.seek(0, true)
		clip = name
	anim.speed_scale = speed


func _update_anim(dt: float, speed01: float) -> void:
	_pick_clip(dt, speed01)
	anim.advance(dt)
	_apply_upper(dt)
	if track_steps:
		_watch_feet(dt)


## A foot that has been coming down and stops, near the ground, is a step.
func _watch_feet(dt: float) -> void:
	if _skel == null:
		var found := model.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			track_steps = false
			return
		_skel = found[0]
		var hips := _skel.find_bone("mixamorig_Hips")
		for n in ["mixamorig_LeftFoot", "mixamorig_RightFoot"]:
			var b := _skel.find_bone(n)
			if b < 0 or hips < 0:
				continue
			var rest := _skel.get_bone_global_rest(b).origin.y
			var leg := _skel.get_bone_global_rest(hips).origin.y - rest
			_feet.append({"bone": b, "y": rest, "dy": 0.0, "low": rest + leg * 0.12})
		if _feet.is_empty():
			track_steps = false
			return
	_step_gap -= dt
	var walking := clip == "Walk" or clip == "Run"
	for f in _feet:
		var y := _skel.get_bone_global_pose(f.bone).origin.y
		var dy: float = y - f.y
		if walking and f.dy < 0 and dy >= 0 and y < f.low and _step_gap <= 0:
			steps += 1
			_step_gap = 0.15
		f.y = y
		f.dy = dy


func _pick_clip(dt: float, speed01: float) -> void:
	move += (speed01 - move) * minf(1, dt * 10)
	if death >= 0:
		death += dt
		_clip("Death", 1.0)
		# the body sinks into the ground after a while, as the built models do
		model.position.y = -minf(1.2, (death - 2.5) * 0.4) if death > 2.5 else 0.0
		return
	if off_action != null:
		off_action.t += dt
		if off_action.t >= off_action.duration:
			off_action = null
	if clip == "Hit" and action == null and anim.is_playing() and not _moving():
		return # the flinch plays out
	if action != null:
		var fresh: bool = action.t == 0.0
		action.t += dt
		# a spell's own pose is a clip of its name; else the kind's clip
		var name: String = action.type if anim.has_animation(action.type) else ACTION_CLIPS.get(action.type, "Attack")
		if name != "" and not anim.has_animation(name):
			name = "Attack" # a creature without a Cast clip bites instead
		var done: bool = action.t >= action.duration
		if name == "" or not anim.has_animation(name):
			if not _moving():
				_clip("Idle", 1.0)
				if done:
					action = null
				return
		else:
			# the clip's blow (half way through) lands on the action's impact
			var hit := maxf(0.05, action.impact * action.duration)
			var rate: float = anim.get_animation(name).length * CLIP_IMPACT / hit
			# once on the move, the action stays on the upper body to its end
			if action.get("upper", false) or _moving():
				action.upper = true
				_upper = {"name": name, "t": action.t * rate, "speed": 0.0}
			else:
				_clip(name, rate, fresh)
				if done:
					action = null
				return
		if done:
			action = null
	if _upper != null and _upper.speed > 0:
		_upper.t += dt * _upper.speed # a flinch on the move
		if _upper.t >= anim.get_animation(_upper.name).length:
			_upper.speed = 0.0
	if (pose == "sit" or pose == "rest") and anim.has_animation("Sit"):
		_clip("Sit", 1.0)
	elif airborne and anim.has_animation("Jump"):
		_clip("Jump", 0.6) # the push off and rise, held to the landing
	elif move > 0.9 and anim.has_animation("Run"):
		_clip("Run", move * RUN_RATE.get(style, 0.8))
	elif move > 0.12:
		_clip("Walk", maxf(0.3, move) * WALK_RATE.get(style, 1.0))
	else:
		_clip("Idle", 1.0)


## Lays the upper body clip over what the AnimationPlayer just posed: the
## waist up turns to the action's pose, eased in as it starts and out after
## it ends (or once a flinch has played), the legs keep walking.
func _apply_upper(dt: float) -> void:
	if _upper == null:
		return
	var live: bool = (action != null and action.get("upper", false)) or (_upper.get("hit", false) and _upper.speed > 0)
	_upper_w = move_toward(_upper_w, 1.0 if live else 0.0, dt * UPPER_FADE)
	if not live and _upper_w <= 0.0:
		_upper = null
		return
	if death >= 0 or not _find_upper():
		_upper = null
		_upper_w = 0.0
		return
	var a := anim.get_animation(_upper.name)
	var t := minf(float(_upper.t), a.length)
	for tb in _tracks_of(_upper.name, a):
		var q := a.rotation_track_interpolate(tb[0], t)
		var b: int = tb[1]
		_skel.set_bone_pose_rotation(b, _skel.get_bone_pose_rotation(b).slerp(q, _upper_w))


## The bones from the waist up: walking up from the head, every bone that
## carries no leg (CC and Mixamo rigs alike).
func _find_upper() -> bool:
	if _upper_bones != null:
		return not _upper_bones.is_empty()
	_upper_bones = {}
	if _skel == null:
		var found := model.find_children("*", "Skeleton3D", true, false)
		if found.is_empty():
			return false
		_skel = found[0]
	var legs := {}
	var head := -1
	for b in _skel.get_bone_count():
		var n := _skel.get_bone_name(b).to_lower()
		if n.ends_with("head") and head < 0:
			head = b
		if n.contains("foot"):
			var p := b
			while p >= 0:
				legs[p] = true
				p = _skel.get_bone_parent(p)
	if head < 0:
		return false
	var root := head
	while _skel.get_bone_parent(root) >= 0 and not legs.has(_skel.get_bone_parent(root)):
		root = _skel.get_bone_parent(root)
	if legs.has(root):
		return false
	var todo := [root]
	while not todo.is_empty():
		var b: int = todo.pop_back()
		_upper_bones[b] = true
		todo.append_array(_skel.get_bone_children(b))
	return true


func _tracks_of(name: String, a: Animation) -> Array:
	if _upper_tracks.has(name):
		return _upper_tracks[name]
	var list := []
	for i in a.get_track_count():
		if a.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var b := _skel.find_bone(a.track_get_path(i).get_concatenated_subnames())
		if b >= 0 and _upper_bones.has(b):
			list.append([i, b])
	_upper_tracks[name] = list
	return list


func update(dt: float, speed01: float) -> void:
	if recoil > 0:
		# held at full jolt through the hit-stop, then it settles
		if held <= 0:
			recoil = maxf(0.0, recoil - dt * 4.0)
		_apply_recoil()
	# hit-stop: the body holds still for a moment as a blow connects
	if held > 0:
		held -= dt
		return
	time += dt
	if anim:
		_update_anim(dt, speed01)
		return
	move += (speed01 - move) * minf(1, dt * 10)
	var stride := 6.0 if style == "brute" else 7.0 if style == "ghoul" else 13.0 if style == "hound" else 9.0
	var was := phase
	phase += dt * stride * maxf(0.2, move)
	# a foot is down at each end of the leg swing (sin(phase) at +-1)
	if move > 0.12 and floori(was / PI + 0.5) != floori(phase / PI + 0.5):
		steps += 1
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
	elif pose == "rest" and action == null:
		# sitting on the ground, hands on the knees
		_rot("Leg_L", 0, -1.45)
		_rot("Leg_R", 0, -1.35)
		_rot("Arm_R", 0, -0.55)
		_rot("Arm_L", 0, -0.55)
		_rot("Torso", 0, 0.08 + breathe)
		model.position.y = -0.5
	elif death < 0:
		model.position.y = 0
	if airborne and action == null and death < 0:
		# Built-in characters without a Jump clip tuck their knees as well.
		_rot("Leg_L", 0, -0.5)
		_rot("Leg_R", 0, -0.65)
		_rot("Arm_L", 0, -0.2)
		_rot("Arm_R", 0, -0.2)
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


## Each spell's own cast pose is data (data/abilities/spell_fx.json `poses`, read
## into DB.spell_poses): [part, axis, windup, blow] keys, and how far into
## the windup the strike starts. Axis 0 raises an arm forward when negative;
## 1 twists (positive turns left); 2 swings an arm out (negative for the
## right arm, positive for the left). Built models turn their parts here; the
## rigged player plays a Blender clip of the same name, keyed the same way
## (assets/blender/import_models.py).
##
## Three keys of a blow, Diablo style: snapped into the windup at once (no
## slow pull back after a key press), held, whipped through to the blow by
## `impact`, held a moment there (the follow-through), then back to rest.
static func _key3(k: float, up: float, impact: float, a: float, b: float) -> float:
	if k < up:
		var x := minf(1, k / maxf(0.001, up * SNAP))
		return a * (1 - (1 - x) * (1 - x))
	if k < impact:
		var x := (k - up) / (impact - up)
		return lerpf(a, b, x * x)
	var after := impact + (1 - impact) * FOLLOW
	if k < after:
		return b
	return b * (1 - ease_((k - after) / (1 - after)))


## the share of the windup spent snapping into it, and of the time after the
## blow spent holding it (the follow-through)
const SNAP := 0.3
const FOLLOW := 0.3


func _apply_action(dt: float) -> void:
	var a: Dictionary = action
	a.t += dt
	var k := minf(1, a.t / a.duration)
	var impact: float = a.impact
	var raise := ease_(k / impact) if k < impact else 1 - ease_((k - impact) / (1 - impact))
	var swing := 0.0 if k < impact else ease_(minf(1, (k - impact) / 0.35))
	if DB.spell_poses.has(a.type):
		var b: Dictionary = DB.spell_poses[a.type]
		var up: float = impact * b.up
		for key in b.keys:
			_rot(key[0], key[1], _key3(k, up, impact, key[2], key[3]))
		if b.has("hop"):
			model.position.y = b.hop * sin(PI * minf(1, k / impact))
		if b.has("sink"):
			# down into a kneel or a crouch by the blow, up again after
			model.position.y = -b.sink * raise
		if b.has("spin"):
			# a full turn (or `spin` turns) through the windup to the blow
			model.rotation.y = -TAU * b.spin * ease_(minf(1, k / impact))
	match a.type:
		"guard":
			# Brace: up fast behind the shield, low and wide, held while it lasts
			var g := minf(1, a.t / 0.15) * (1 - ease_(maxf(0, (k - 0.85) / 0.15)))
			_rot("Arm_L", 0, -1.6 * g)
			_rot("Arm_L", 1, 0.6 * g)
			_rot("Arm_R", 0, -0.9 * g)
			_rot("Torso", 0, 0.2 * g)
			_rot("Leg_L", 0, -0.35 * g)
			_rot("Leg_R", 0, 0.3 * g)
			model.position.y = -0.07 * g
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
		var b: Dictionary = DB.spell_poses.get(a.type, {})
		if a.type == "dodge" or a.type == "guard" or b.has("hop") or b.has("sink"):
			model.position.y = 0
		if b.has("spin"):
			model.rotation.y = 0
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

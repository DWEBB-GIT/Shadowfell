class_name ForgeRig
extends Rig
## Plays the supplied non-root-motion library on the v6 skeleton.
var _actor_ref: WeakRef
var actor:
	get: return _actor_ref.get_ref() if _actor_ref else null
	set(value): _actor_ref = weakref(value) if value != null else null
var landing := 0.0
var was_airborne := false
var last_action_clip := ""
var play_count := 0
var secondary_grip_error := 0.0
var air_time := 0.0
var gait_rate := 1.0
const TAKEOFF_TIME := 0.22
const LAND_TIME := 0.36
const RUN_REFERENCE_SPEED := 4.1
var last_off_clip := ""

func revive() -> void:
	super()
	air_time = 0
	landing = 0
	was_airborne = false

func play(type: String, duration: float, impact := 0.5) -> void:
	play_count += 1
	super(type, duration, impact)

func _init(m: Node3D, owner_player = null) -> void:
	super(m, "forge_v6")
	actor = owner_player
	_skel = m.find_children("*", "Skeleton3D", true, false)[0]

func weapon_clip(hand: String="main") -> String:
	if actor==null:return "Sword_Attack"
	var item=actor.game.inventory.equipment.get("offHand" if hand=="off" else "mainHand")
	var kind:String=Items.get_def(item.id).get("weaponType","") if item else ""
	if kind=="dagger":return "Dagger_Stab"
	if kind=="twoHand":return "Sword_Heavy_Combo"
	return "Sword_Attack"

func _make_dagger_clip() -> void:
	if anim.has_animation("Dagger_Stab"):return
	var track_root:=_track_root(anim.get_animation("Sword_Attack"))
	var height:=1.23 if model.get_meta("forge_appearance").sex=="male" else 1.18
	for side in ["r","l"]:
		var result:=Animation.new()
		result.length=0.65
		result.loop_mode=Animation.LOOP_NONE
		var tracks:Dictionary={}
		for part in ["clavicle_","upperarm_","lowerarm_","hand_"]:
			var bone:=_skel.find_bone(part+side)
			var track:=result.add_track(Animation.TYPE_ROTATION_3D)
			result.track_set_path(track,NodePath(track_root+":"+part+side))
			tracks[bone]=track
		var sign_:float=-1 if side=="r" else 1
		for key in [[0.0,Vector3(sign_*0.2,height,0.08)],[0.25,Vector3(sign_*0.22,height,0.02)],[0.5,Vector3(sign_*0.13,height+0.04,0.55)],[0.65,Vector3(sign_*0.13,height+0.04,0.55)],[1.0,Vector3(sign_*0.2,height,0.08)]]:
			anim.play("Idle")
			anim.seek(0,true)
			anim.advance(0)
			_reach_grip(side,Transform3D(Basis(Vector3.RIGHT,PI/2),key[1]),Vector3(sign_*0.55,height-0.1,-0.1))
			for bone in tracks:
				result.rotation_track_insert_key(tracks[bone],key[0]*result.length,_skel.get_bone_pose_rotation(bone))
		anim.get_animation_library("").add_animation("Dagger_Stab" if side=="r" else "Dagger_Stab_L",result)
	clip=""
	_clip("Idle",1.0,true)

func resolve_action(type: String) -> String:
	if type in ["strike","diagonal","overhead","thrust","jab","upstab","rip","quickStrike","slam","cleave","sweep","spinStrike","scissor","heavyOverhead","gavel"]:
		return weapon_clip()
	match type:
		"shoot", "snapShot", "twistDraw", "fanShot", "longDraw", "loose": return "Spell_Simple_Shoot"
		"guard", "brace", "liftShield", "shieldSlam", "shieldThrust": return "Shield_OneShot"
		"slam", "overhead", "heavyOverhead", "gavel": return "Sword_Heavy_Combo"
		"cleave", "sweep", "spinStrike", "scissor": return "Sword_Regular_Combo"
		"thrust", "jab", "upstab", "rip", "quickStrike": return "Sword_Regular_B"
		"dodge", "sidestep", "backflip", "pounce": return "Roll"
		"drink": return "Consume"
		"castLine", "reel", "pull": return "OverhandThrow"
		"roar", "raiseHands", "gather", "push", "clutch", "earthPress", "trace", "throwWide", "point", "pressDown", "blowDust", "kindle", "cast": return "Spell_Simple_Shoot"
		"kneelSet", "plantBlade", "crouch": return "Fixing_Kneeling"
	if anim.has_animation(type) and type != "A_TPose":
		return type
	return "Sword_Attack"

func _locomotion() -> String:
	if airborne: return "Jump_Start" if air_time < TAKEOFF_TIME else "Jump"
	if landing > 0: return "Jump_Land"
	if pose in ["sit", "rest"]: return "Sitting_Idle"
	if pose == "fish": return "Idle_Lantern"
	if move > 0.9: return "Jog_Fwd"
	if move > 0.12: return "Walk"
	return "Idle"

func _update_anim(dt: float, speed01: float) -> void:
	_make_dagger_clip()
	move = move_toward(move, speed01, dt * 10)
	if death >= 0:
		death += dt
		_clip("Death01", 1.0)
		anim.advance(dt)
		return
	if airborne and not was_airborne:
		air_time = 0
		landing = 0
	if was_airborne and not airborne:
		landing = LAND_TIME
	if airborne:
		air_time += dt
	was_airborne = airborne
	if flinch > 0 and action == null:
		flinch = maxf(0, flinch - dt * 4)
		_upper = {"name":"Hit_Chest", "t":(1.0 - flinch) * anim.get_animation("Hit_Chest").length, "speed":0.0, "hit":true}
	var base_clip := _locomotion()
	var magnitude := clampf(move / DB.CONFIG.player.runGait,0,1)
	var speed: float = magnitude*DB.CONFIG.player.speed
	if actor != null and not actor.game is Dictionary:
		speed *= actor.game.spells.movement_scale
	gait_rate = clampf(speed/RUN_REFERENCE_SPEED,0.4,2.4) if base_clip == "Jog_Fwd" else maxf(0.4,move)
	var seek_pose := base_clip in ["Jump_Start","Jump","Jump_Land"]
	_clip(base_clip, gait_rate if base_clip in ["Walk","Jog_Fwd"] else 1.0,seek_pose and clip != base_clip)
	if base_clip == "Jump_Start":
		anim.seek(anim.get_animation(base_clip).length*clampf(air_time/TAKEOFF_TIME,0,1),true)
	elif base_clip == "Jump":
		anim.seek(fmod(maxf(0,air_time-TAKEOFF_TIME),anim.get_animation(base_clip).length),true)
	elif base_clip == "Jump_Land":
		anim.seek(anim.get_animation(base_clip).length*clampf(1-(landing-dt)/LAND_TIME,0,1),true)
	else:
		anim.advance(dt)
	if seek_pose:
		anim.advance(0)
	if base_clip=="Sitting_Idle":
		_ground_sit()
	if airborne:
		# Physics owns vertical travel. Source pelvis/root translations must
		# not add another authored leap on top of the gameplay trajectory.
		for bone_name in ["root","pelvis"]:
			var b := _skel.find_bone(bone_name)
			var p := _skel.get_bone_pose_position(b)
			var up := (_skel.global_basis.inverse()*model.global_basis*Vector3.UP).normalized()
			var parent := _skel.get_bone_parent(b)
			if parent >= 0:up=(_skel.get_bone_global_pose(parent).basis.inverse()*up).normalized()
			p -= up*(p-_skel.get_bone_rest(b).origin).dot(up)
			_skel.set_bone_pose_position(b,p)
	var active := action != null
	if active:
		action.t += dt
		if actor != null and actor.casting != null:
			action.t = actor.casting.t
			action.duration = maxf(0.01, actor.casting.total)
		var name := resolve_action(action.type)
		last_action_clip = name
		var a := anim.get_animation(name)
		var k := clampf(action.t / maxf(0.01, action.duration), 0, 1)
		var impact := clampf(action.impact, 0.01, 0.99)
		# Keep both the strike and the recovery aligned to the game's clock.
		var at := (k / impact * 0.5 if k < impact else 0.5 + (k - impact) / (1 - impact) * 0.5) * a.length
		var casting_now = actor.casting if actor != null else null
		if casting_now != null:
			name = "Spell_Simple_Idle"
			a = anim.get_animation(name)
			at = fmod(action.t, a.length)
			last_action_clip = name
		var weight := minf(1, minf(k * 15, (1 - k) * 10))
		_sample(name, at, weight, _moving())
		if action.t >= action.duration:
			action = null
	elif _upper != null:
		_sample(_upper.name, _upper.t, flinch, true)
		if flinch <= 0:
			_upper = null
	if off_action != null:
		off_action.t += dt
		# The supplied sword clip is retargeted through mirrored rest bases.
		_mirror_off()
		if off_action.t >= off_action.duration:
			off_action = null
	_fit_hands()
	if base_clip=="Jump_Land":landing=maxf(0,landing-dt)
	if track_steps and move > 0.12 and not airborne:
		var previous := phase
		phase += dt * (TAU/anim.get_animation("Jog_Fwd").length if move > 0.9 else 7.0) * gait_rate
		if floori(previous / PI) != floori(phase / PI): steps += 1

func _sample(name: String, at: float, weight: float, upper_only: bool) -> void:
	var a := anim.get_animation(name)
	_find_upper()
	for i in a.get_track_count():
		var bone := _skel.find_bone(a.track_get_path(i).get_concatenated_subnames())
		if bone < 0 or (upper_only and not _upper_bones.has(bone)):
			continue
		match a.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				_skel.set_bone_pose_rotation(bone, _skel.get_bone_pose_rotation(bone).slerp(a.rotation_track_interpolate(i, at), weight))
			Animation.TYPE_POSITION_3D:
				# Keep root placement controlled by gameplay, never a clip.
				if bone > 0:
					_skel.set_bone_pose_position(bone, _skel.get_bone_pose_position(bone).lerp(a.position_track_interpolate(i, at), weight))

func _mirror_off() -> void:
	last_off_clip=weapon_clip("off")
	var clip_name:= "Dagger_Stab_L" if last_off_clip=="Dagger_Stab" else last_off_clip
	var a := anim.get_animation(clip_name)
	var k := clampf(off_action.t / maxf(0.01, off_action.duration), 0, 1)
	var impact := clampf(off_action.impact, 0.01, 0.99)
	var at := (k / impact * 0.5 if k < impact else 0.5 + (k - impact) / (1 - impact) * 0.5) * a.length
	var weight := minf(1, minf(k, 1-k) * 8)
	if clip_name=="Dagger_Stab_L":
		_sample(clip_name,at,weight,true)
		return
	for part in ["clavicle", "upperarm", "lowerarm", "hand"]:
		var right := _skel.find_bone(part + "_r")
		var left := _skel.find_bone(part + "_l")
		var track := a.find_track(NodePath("%s:%s" % [_track_root(a), part + "_r"]), Animation.TYPE_ROTATION_3D)
		if track < 0: continue
		var rest_r := _skel.get_bone_rest(right).basis.get_rotation_quaternion()
		var rest_l := _skel.get_bone_rest(left).basis.get_rotation_quaternion()
		var delta := a.rotation_track_interpolate(track, at) * rest_r.inverse()
		var mirrored := Quaternion(delta.x, -delta.y, -delta.z, delta.w) * rest_l
		_skel.set_bone_pose_rotation(left, _skel.get_bone_pose_rotation(left).slerp(mirrored, weight))


func _ground_sit() -> void:
	# The supplied sitting clip expects a chair. Lower the hips to the
	# ground and fold the legs forward without burying the feet.
	var pelvis:=_skel.find_bone("pelvis")
	var parent:=_skel.get_bone_parent(pelvis)
	var up:=(_skel.global_basis.inverse()*model.global_basis*Vector3.UP).normalized()
	var local_up:=(_skel.get_bone_global_pose(parent).basis.inverse()*up).normalized()
	_skel.set_bone_pose_position(pelvis,_skel.get_bone_pose_position(pelvis)-local_up*0.34)
	for side in ["l","r"]:
		var sign_:float=1 if side=="l" else -1
		var thigh:=_skel.find_bone("thigh_"+side)
		var calf:=_skel.find_bone("calf_"+side)
		var foot:=_skel.find_bone("foot_"+side)
		var hip:=_skel.get_bone_global_pose(thigh).origin
		var knee:=_skel.get_bone_global_pose(calf).origin
		var ankle:=_skel.get_bone_global_pose(foot).origin
		var foot_basis:=_skel.get_bone_global_pose(foot).basis
		var a:=hip.distance_to(knee)
		var b:=knee.distance_to(ankle)
		var target:=Vector3(sign_*0.23,_skel.get_bone_global_rest(foot).origin.y,0.55)
		var direction:Vector3=(target-hip).normalized()
		var distance:=clampf(hip.distance_to(target),absf(a-b)+0.001,a+b-0.001)
		var along:float=(a*a-b*b+distance*distance)/(2*distance)
		var hint:=Vector3(sign_*0.4,0.5,0.4)-hip
		var bend:Vector3=(hint-direction*hint.dot(direction)).normalized()
		var desired:=hip+direction*along+bend*sqrt(maxf(0,a*a-along*along))
		_turn_bone(thigh,knee-hip,desired-hip)
		knee=_skel.get_bone_global_pose(calf).origin
		ankle=_skel.get_bone_global_pose(foot).origin
		_turn_bone(calf,ankle-knee,hip+direction*distance-knee)
		_skel.set_bone_pose_rotation(foot,(_skel.get_bone_global_pose(calf).basis.inverse()*foot_basis).orthonormalized().get_rotation_quaternion())

func _fit_hands() -> void:
	if actor == null or actor.sheathed:
		return
	if actor.bow_in_hand:
		var height := 1.38 if actor.appearance.sex == "male" else 1.33
		var drawing:bool=actor.pending_shot != null or (action != null and (action.type in ["shoot","snapShot","twistDraw","longDraw","fanShot","loose"] or action.get("ranged",false))) or (actor.casting != null and actor.casting.spell.get("ranged",false))
		if _moving() and not drawing:
			# Carry the bow with the authored arm swing while travelling.
			# Only a deliberate draw should pin the hand in an aiming pose.
			if actor.bow!=null and actor.bow.has_method("set_draw"):actor.bow.call("set_draw",0,false)
			_curl_fingers("l")
			return
		var draw := 0.0
		var nocked := false
		if actor.casting != null and actor.casting.spell.get("ranged",false):
			draw=clampf(actor.casting.t/maxf(0.01,actor.casting.total),0,1)
			nocked=true
		elif action != null and drawing:
			var k:float=action.t/maxf(0.01,action.duration)
			draw=clampf(k/maxf(0.01,action.impact),0,1) if k<=action.impact else maxf(0,1-(k-action.impact)/0.12)
			nocked=k<=action.impact
		var grip:=Vector3(0.08,height,0.47) if drawing else Vector3(0.32,height-0.37,0.12)
		_reach_grip("l",Transform3D(Basis.IDENTITY,grip),Vector3(0.65,height-0.1,0.1))
		if drawing:
			_reach_grip("r",Transform3D(Basis(Vector3.UP,PI/2),grip-Vector3(0,0,0.08+0.34*draw)),Vector3(-0.65,height+0.1,0.05))
		if actor.bow != null and actor.bow.has_method("set_draw"):
			actor.bow.call("set_draw",draw,nocked)
		_curl_fingers("l")
		return
	var equipment: Dictionary = actor.game.inventory.equipment
	var item = equipment.get("mainHand")
	if actor.casting != null:
		if item:_curl_fingers("r")
		if equipment.get("offHand"):_curl_fingers("l")
		return
	if action!=null and weapon_clip()=="Dagger_Stab" and resolve_action(action.type)=="Dagger_Stab":
		_fit_dagger_stab("r",action)
	if off_action!=null and weapon_clip("off")=="Dagger_Stab":
		_fit_dagger_stab("l",off_action)
	if item and Items.get_def(item.id).get("weaponType") == "twoHand":
		var local_grip: Transform3D = model.get_meta("palm_grip_r")
		var primary := _skel.get_bone_global_pose(_skel.find_bone("hand_r"))*local_grip
		var target := primary*Transform3D(Basis(Vector3.UP,PI),Vector3(0,-0.12,0))
		var shoulder := _skel.get_bone_global_pose(_skel.find_bone("upperarm_l")).origin
		var elbow := _skel.get_bone_global_pose(_skel.find_bone("lowerarm_l")).origin
		var palm := _skel.get_bone_global_pose(_skel.find_bone("hand_l")).origin
		var reach := shoulder.distance_to(elbow)+elbow.distance_to(palm)-0.045
		if target.origin.distance_to(shoulder)>reach:
			primary.origin += shoulder+(target.origin-shoulder).normalized()*reach-target.origin
			_reach_grip("r",primary,Vector3(-0.6,1.1,0.2))
			primary = _skel.get_bone_global_pose(_skel.find_bone("hand_r"))*local_grip
			target = primary*Transform3D(Basis(Vector3.UP,PI),Vector3(0,-0.12,0))
		_reach_grip("l",target,Vector3(0.6,1.0,0.2))
		var actual := _skel.get_bone_global_pose(_skel.find_bone("hand_l"))*(model.get_meta("palm_grip_l") as Transform3D)
		secondary_grip_error = actual.origin.distance_to(target.origin)
		_curl_fingers("l")
	if item or actor.rod != null:
		_curl_fingers("r")
	if equipment.get("offHand"):
		_curl_fingers("l")

func _fit_dagger_stab(side: String, act: Dictionary) -> void:
	# A simultaneous sword swing rotates the torso. Keep the dagger's
	# palm target in character space so its stab still points forward.
	var k:float=clampf(act.t/maxf(0.01,act.duration),0,1)
	var impact:float=clampf(act.impact,0.01,0.99)
	var at:float=k/impact*0.5 if k<impact else 0.5+(k-impact)/(1-impact)*0.5
	var height:=1.23 if actor.appearance.sex=="male" else 1.18
	var sign_:float=-1 if side=="r" else 1
	var keys:Array=[[0.0,Vector3(sign_*0.2,height,0.08)],[0.25,Vector3(sign_*0.22,height,0.02)],[0.5,Vector3(sign_*0.13,height+0.04,0.55)],[0.65,Vector3(sign_*0.13,height+0.04,0.55)],[1.0,Vector3(sign_*0.2,height,0.08)]]
	var position_:Vector3=keys.back()[1]
	for i in range(1,keys.size()):
		if at<=keys[i][0]:
			position_=(keys[i-1][1] as Vector3).lerp(keys[i][1],inverse_lerp(keys[i-1][0],keys[i][0],at))
			break
	var palm:Transform3D=_skel.get_bone_global_pose(_skel.find_bone("hand_"+side))*(model.get_meta("palm_grip_"+side) as Transform3D)
	var desired:=Transform3D(Basis(Vector3.RIGHT,PI/2),position_)
	_reach_grip(side,palm.interpolate_with(desired,minf(1,minf(k,1-k)*8)),Vector3(sign_*0.55,height-0.1,-0.1))

func _reach_grip(side: String, desired: Transform3D, elbow_hint: Vector3) -> void:
	var local_grip: Transform3D = model.get_meta("palm_grip_"+side)
	var hand := desired*local_grip.affine_inverse()
	_reach_hand(side,hand.origin,elbow_hint)
	var wrist := _skel.find_bone("hand_"+side)
	var parent := _skel.get_bone_parent(wrist)
	_skel.set_bone_pose_rotation(wrist,(_skel.get_bone_global_pose(parent).basis.inverse()*hand.basis).orthonormalized().get_rotation_quaternion())

func _curl_fingers(side: String) -> void:
	var wrist := _skel.get_bone_global_pose(_skel.find_bone("hand_"+side))
	var grip := wrist*(model.get_meta("palm_grip_"+side) as Transform3D)
	for finger in ["index","middle","ring","pinky"]:
		for segment in [1,2,3]:
			var bone := _skel.find_bone("%s_0%d_%s" % [finger,segment,side])
			var parent := _skel.get_bone_parent(bone)
			var axis := (_skel.get_bone_global_pose(parent).basis.inverse()*grip.basis.y).normalized()
			var angle := 1.0 if segment < 3 else 0.65
			# Several clips omit finger tracks; accumulating on the previous
			# frame makes those fingers continuously rotate around the grip.
			_skel.set_bone_pose_rotation(bone,Quaternion(axis,angle)*_skel.get_bone_rest(bone).basis.get_rotation_quaternion())

func _reach_hand(side: String, target: Vector3, elbow_hint: Vector3) -> void:
	var upper := _skel.find_bone("upperarm_" + side)
	var lower := _skel.find_bone("lowerarm_" + side)
	var wrist := _skel.find_bone("hand_" + side)
	var shoulder := _skel.get_bone_global_pose(upper).origin
	var elbow := _skel.get_bone_global_pose(lower).origin
	var palm := _skel.get_bone_global_pose(wrist).origin
	var first := shoulder.distance_to(elbow)
	var second := elbow.distance_to(palm)
	var direction := (target - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target), absf(first-second) + 0.001, first+second-0.001)
	var along := (first*first-second*second+distance*distance)/(2*distance)
	var height := sqrt(maxf(0, first*first-along*along))
	var hint := elbow_hint-shoulder
	var perpendicular := (hint-direction*hint.dot(direction)).normalized()
	var desired_elbow := shoulder+direction*along+perpendicular*height
	_turn_bone(upper, elbow-shoulder, desired_elbow-shoulder)
	elbow = _skel.get_bone_global_pose(lower).origin
	palm = _skel.get_bone_global_pose(wrist).origin
	_turn_bone(lower, palm-elbow, shoulder+direction*distance-elbow)

func _turn_bone(bone: int, from: Vector3, to: Vector3) -> void:
	if from.length_squared() < 0.000001 or to.length_squared() < 0.000001:
		return
	var rotation := Basis(Quaternion(from.normalized(), to.normalized())) * _skel.get_bone_global_pose(bone).basis
	var parent := _skel.get_bone_parent(bone)
	_skel.set_bone_pose_rotation(bone, (_skel.get_bone_global_pose(parent).basis.inverse()*rotation).orthonormalized().get_rotation_quaternion())

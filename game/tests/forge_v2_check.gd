extends SceneTree
var game
var failed := 0
var checks := 0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		printerr("FAIL ",message)
func _run() -> void:
	root.size=Vector2i(1280,720)
	root.content_scale_size=Vector2i(1280,720)
	Store.dir = "user://forge_v2_%d" % Time.get_ticks_usec()
	game = load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	var player = game.player
	for sex in ["male","female"]:
		var look := ForgeCharacter.defaults()
		look.sex = sex
		player.set_appearance(look)
		var rig = player.rig
		rig.update(0.2,DB.CONFIG.player.runGait)
		check(rig.clip == "Jog_Fwd" and rig.gait_rate > 1.4,sex+" running cadence accelerates for full movement speed")
		rig.airborne = true
		rig.update(0.04,0.0)
		check(rig.clip == "Jump_Start",sex+" takeoff uses supplied start clip")
		rig.update(0.15,0.0)
		check(rig.clip == "Jump",sex+" airborne clip follows takeoff")
		var sk: Skeleton3D = player.model.find_children("*","Skeleton3D",true,false)[0]
		var pelvis := sk.find_bone("pelvis")
		var parent:=sk.get_bone_parent(pelvis)
		var up:=(_skel_up(sk,player.model))
		up=(sk.get_bone_global_pose(parent).basis.inverse()*up).normalized()
		check(absf((sk.get_bone_pose_position(pelvis)-sk.get_bone_rest(pelvis).origin).dot(up))<0.001,sex+" clip cannot add another vertical leap")
		var foot:=sk.find_bone("foot_l")
		check((sk.get_bone_global_pose(foot).origin-sk.get_bone_global_rest(foot).origin).dot(_skel_up(sk,player.model))>0.1,sex+" jump actually raises and tucks the foot relative to the body")
		rig.airborne = false
		rig.update(0.04,0.0)
		check(rig.clip == "Jump_Land",sex+" stationary landing uses landing clip")
		for i in 12: rig.update(0.03,0.0)
		check(rig.clip == "Idle",sex+" landing recovers to idle")
		var preview:=CharPreview.new(game)
		root.add_child(preview)
		preview.size=Vector2(330,356)
		preview.render()
		check(preview._rig is ForgeRig,sex+" equipment-panel preview uses fitted hand rig")
		preview.queue_free()
		for pair in [["worn_longsword",null],["oak_club","ironwood_club"],["roadwarden_greatsword",null]]:
			var equipment := {"mainHand":{"id":pair[0],"count":1}}
			if pair[1] != null: equipment.offHand={"id":pair[1],"count":1}
			game.inventory.equipment=equipment
			player.show_equipment(equipment)
			for action in ["idle","strike","cast","guard","run"]:
				rig.action=null
				if action not in ["idle","run"]:rig.play(action,0.8,0.4)
				rig.update(0.2,DB.CONFIG.player.runGait if action == "run" else 0.0)
				await process_frame
				for side in ["r","l"]:
					if side == "l" and pair[1] == null:continue
					var held: Node3D=player.weapon_part if side == "r" else player.shield
					var hand:=sk.get_bone_global_pose(sk.find_bone("hand_"+side))
					var grip: Transform3D=player.model.get_meta("palm_grip_"+side)
					var definition: Dictionary=Items.get_def(pair[0] if side == "r" else pair[1])
					var actual:=held.global_transform*Vector3(0,ForgeCharacter.handle_center(definition),0)
					var desired:=sk.global_transform*(hand*grip).origin
					check(actual.distance_to(desired)<0.015,sex+" "+str(pair)+" "+action+" "+side+" handle meets palm within 1.5 cm")
	var camera:Camera3D=game.camera
	game.started=true
	game.settings.set_value("classicCamera",true)
	game._snap_camera()
	var new_height:=absf(camera.unproject_position(player.position+Vector3.UP*1.84*DB.CONFIG.player.visualScale).y-camera.unproject_position(player.position).y)
	var new_far=Plane(Vector3.UP,player.position.y).intersects_ray(camera.project_ray_origin(Vector2(640,60)),camera.project_ray_normal(Vector2(640,60)))
	var row:=camera.unproject_position(player.position).y
	var new_width:float=_ground_width(camera,row,player.position.y)
	camera.fov=35
	camera.position=game.camera_target+Vector3(0,1,0)+Vector3(0,25.5,25.5)*0.98
	camera.look_at(game.camera_target+Vector3.UP)
	var old_height:=absf(camera.unproject_position(player.position+Vector3.UP*1.84*1.2).y-camera.unproject_position(player.position).y)
	var old_far=Plane(Vector3.UP,player.position.y).intersects_ray(camera.project_ray_origin(Vector2(640,60)),camera.project_ray_normal(Vector2(640,60)))
	var old_width:float=_ground_width(camera,camera.unproject_position(player.position).y,player.position.y)
	check(new_height>old_height*1.2,"new default makes player at least 20 percent taller on screen")
	check(new_far != null and old_far != null and absf(new_far.z-player.position.z)>absf(old_far.z-player.position.z),"new default exposes more distant ground")
	check(new_width>old_width*0.9,"lateral ground coverage is retained within ten percent")
	print("CAMERA pixels old=",old_height," new=",new_height," distant ground old=",old_far," new=",new_far," width old=",old_width," new=",new_width)
	var disposable=Player.new({"inventory":{"equipment":{}},"time":0.0})
	root.add_child(disposable.group)
	var weak_player:WeakRef=weakref(disposable)
	disposable.group.queue_free()
	disposable=null
	await process_frame
	check(weak_player.get_ref()==null,"preview player and rig do not retain each other after disposal")
	print("forge_v2_check: %d checks, %d failures" % [checks,failed])
	game.queue_free()
	await process_frame
	quit(1 if failed else 0)
func _skel_up(sk: Skeleton3D,model: Node3D) -> Vector3:
	return (sk.global_basis.inverse()*model.global_basis*Vector3.UP).normalized()
func _ground_width(camera:Camera3D,row:float,height:float) -> float:
	var plane:=Plane(Vector3.UP,height)
	var left:Vector3=plane.intersects_ray(camera.project_ray_origin(Vector2(0,row)),camera.project_ray_normal(Vector2(0,row)))
	var right:Vector3=plane.intersects_ray(camera.project_ray_origin(Vector2(1280,row)),camera.project_ray_normal(Vector2(1280,row)))
	return left.distance_to(right)

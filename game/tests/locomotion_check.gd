extends SceneTree
var game
var checks:=0
var failures:=0
var output:=""
func _initialize() -> void:run.call_deferred()
func check(ok:bool,label:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",label)
func picture(label:String) -> void:
	if output=="":return
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func run() -> void:
	if OS.get_cmdline_user_args().size()>0:
		output=OS.get_cmdline_user_args()[0]
		DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://locomotion_check_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made:Dictionary=game.roster.create("Motion","ranger")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.set_process(false)
	game.save.autosave_enabled=false
	game.hud.root.visible=false
	var player=game.player
	var origin:Vector3=player.position
	game.camera.position=origin+Vector3(3.0,2.5,4)
	game.camera.look_at(origin+Vector3.UP*1.3)
	for sex in ["male","female"]:
		var look:=ForgeCharacter.defaults()
		look.sex=sex
		player.set_appearance(look)
		var reference:=ForgeCharacter.build(look)
		root.add_child(reference)
		reference.visible=false
		var ref_rig:=Rig.new(reference,"forge_v6")
		var ref_sk:Skeleton3D=reference.find_children("*","Skeleton3D",true,false)[0]
		for stance in ["ranged","melee"]:
			player.draw_weapons(stance)
			player.rig.action=null
			player.rig.off_action=null
			player.rig.pose=null
			player.rig.held=0
			player.pending_shot=null
			for i in 30:player.rig.update(1.0/60,DB.CONFIG.player.runGait)
			var max_arm_error:=0.0
			var max_leg_error:=0.0
			for i in 36:
				player.rig.update(1.0/60,DB.CONFIG.player.runGait)
				ref_rig.anim.play("Jog_Fwd",0)
				ref_rig.anim.seek(player.rig.anim.current_animation_position,true)
				ref_rig.anim.advance(0)
				for part in ["clavicle_l","clavicle_r","upperarm_l","upperarm_r","lowerarm_l","lowerarm_r"]:
					var b:=ref_sk.find_bone(part)
					max_arm_error=maxf(max_arm_error,ref_sk.get_bone_pose_rotation(b).angle_to(player.rig._skel.get_bone_pose_rotation(b)))
				for part in ["thigh_l","thigh_r","calf_l","calf_r","foot_l","foot_r"]:
					var b:=ref_sk.find_bone(part)
					max_leg_error=maxf(max_leg_error,ref_sk.get_bone_pose_rotation(b).angle_to(player.rig._skel.get_bone_pose_rotation(b)))
				if i in [4,16,28]:await picture(sex+"-"+stance+"-run-%02d"%i)
			print("RUN ",sex," ",stance," arm_error=",max_arm_error," leg_error=",max_leg_error)
			check(max_arm_error<0.01,sex+" "+stance+" arms follow the original run, without a held aiming pose")
			check(max_leg_error<0.01,sex+" "+stance+" legs follow the original authored gait")
		reference.queue_free()
		for moving in [false,true]:
			player.position=origin
			player._reset_jump()
			player.rig.move=DB.CONFIG.player.runGait if moving else 0
			player.rig.held=0
			var takeoff_frames:=0
			var landing_frames:=0
			var max_landing_progress:=0.0
			var moving_land:=false
			for i in 90:
				game.time+=1.0/60
				player.update(1.0/60,{"move":{"x":1.0 if moving else 0.0,"z":0.0},"jump":i==0})
				if player.rig.clip=="Jump_Start":takeoff_frames+=1
				if player.rig.clip=="Jump_Land":
					landing_frames+=1
					max_landing_progress=maxf(max_landing_progress,player.rig.anim.current_animation_position/player.rig.anim.get_animation("Jump_Land").length)
					moving_land=moving_land or player.moving
				if not moving and i in [2,10,22,36,42,48,58,76]:await picture(sex+"-jump-%02d"%i)
			print("JUMP ",sex," moving=",moving," takeoff_frames=",takeoff_frames," landing_frames=",landing_frames," completed=",max_landing_progress)
			check(takeoff_frames>=10,sex+" takeoff has time to read")
			check(landing_frames>=20 and max_landing_progress>0.999,sex+" landing plays through its final pose, moving="+str(moving))
			check(not player.rig.airborne and player.rig.landing==0,sex+" jump returns to locomotion")
			if moving:check(moving_land and player.rig.clip=="Jog_Fwd",sex+" moving landing preserves control and returns to running")
		player.position=origin
		player._reset_jump()
	for fps in [30.0,60.0,120.0]:
		player.facing=PI/2
		var frames:=0
		var largest_step:=0.0
		while frames<int(fps):
			var before:float=player.facing
			player.update(1.0/fps,{"move":{"x":-1.0,"z":0.0}})
			largest_step=maxf(largest_step,absf(wrapf(player.facing-before,-PI,PI)))
			frames+=1
			if absf(wrapf(player.facing+PI/2,-PI,PI))<0.001:break
		check(largest_step<=14.0/fps+0.001,"WASD turn stays at the restored angular rate at "+str(fps)+" FPS")
		check(float(frames)/fps>=0.22 and float(frames)/fps<0.27,"WASD reversal takes a consistent natural interval at "+str(fps)+" FPS")
	print("locomotion_check: %d checks, %d failures"%[checks,failures])
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

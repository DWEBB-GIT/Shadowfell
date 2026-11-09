extends SceneTree
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var m:=ForgeCharacter.build(ForgeCharacter.defaults())
	root.add_child(m)
	var ap:=m.find_child("AnimationPlayer",true,false) as AnimationPlayer
	ap.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var sk:Skeleton3D=m.find_children("*","Skeleton3D",true,false)[0]
	print("SKELETON BASIS ",sk.global_basis)
	for label in ["Jump_Start","Jump","Jump_Land"]:
		ap.play(label)
		var length:=ap.get_animation(label).length
		for fraction in [0.0,0.2,0.4,0.6,0.8,1.0]:
			ap.seek(length*fraction,true)
			ap.advance(0)
			var calf:=sk.get_bone_pose_rotation(sk.find_bone("calf_l")).get_euler()
			print(label," phase=",fraction," pelvis=",sk.get_bone_pose_position(sk.find_bone("pelvis"))," foot=",sk.get_bone_global_pose(sk.find_bone("foot_l")).origin," calf=",calf)
	ap.play("Jog_Fwd")
	var foot:=sk.find_bone("foot_l")
	var previous:=Vector3.ZERO
	var stance:Array=[]
	for i in 121:
		ap.seek(ap.get_animation("Jog_Fwd").length*i/120.0,true)
		ap.advance(0)
		var p:=sk.global_transform*sk.get_bone_global_pose(foot).origin
		if i>0:
			var speed:float=(previous.z-p.z)*120.0/ap.get_animation("Jog_Fwd").length
			if p.y<0.18 and speed>0:stance.append(speed)
		previous=p
	stance.sort()
	print("STANCE samples=",stance.size()," median local m/s=",stance[stance.size()/2] if not stance.is_empty() else 0)
	m.queue_free()
	await process_frame
	quit()

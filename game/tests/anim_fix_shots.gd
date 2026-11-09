extends SceneTree
## Pictures for the animation/weapon-hold pass: weapon close-ups, sitting,
## run and jump phases, gait foot-slide numbers (gait) and the curled
## fingers in grip space (palm). Usage: godot --path . -s game/tests/anim_fix_shots.gd -- <out dir> [what]
var game
var output: String
func _initialize() -> void:_run.call_deferred()
func picture(label:String) -> void:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("CAPTURE ",label)
func bone_at(name:String) -> Vector3:
	var sk:Skeleton3D=game.player.rig._skel
	return sk.global_transform*sk.get_bone_global_pose(sk.find_bone(name)).origin
func look(at:Vector3, from:Vector3) -> void:
	game.camera.position=at+from
	game.camera.look_at(at)
func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	output=args[0]
	var what:String=args[1] if args.size()>1 else "all"
	DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://anim_fix_shots_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made:Dictionary=game.roster.create("Aldren","rogue")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.hud.root.visible=false
	var player=game.player
	player.facing=0
	player._sync()
	var fov:float=game.camera.fov
	if what in ["all","weapons"]:
		game.camera.fov=30
		for id in ["rusty_dirk","ritual_knife","ghoulbone_knife","worn_longsword","arming_sword","militia_sword","watchmans_edge","rusted_falchion","blackwood_cleaver","witchbane","oak_club","ironwood_club","roadwarden_greatsword"]:
			game.inventory.equipment.mainHand={"id":id,"count":1}
			game.inventory.equipment.offHand={"id":"rusty_dirk","count":1} if id=="rusty_dirk" else null
			player.show_equipment(game.inventory.equipment)
			player.draw_weapons("melee")
			player.rig.action=null
			player.rig.off_action=null
			player.rig.update(0.3,0)
			var hand:=bone_at("hand_r")
			look(hand,Vector3(-1.1,0.25,0.5))
			await picture("hold-%s-out"%id)
			look(hand,Vector3(0.2,0.3,1.2))
			await picture("hold-%s-front"%id)
			if id in ["rusty_dirk","worn_longsword","roadwarden_greatsword"]:
				player.rig.play("strike",0.8,0.4)
				player.rig.update(0.3,0)
				look(bone_at("spine_03"),Vector3(-2.2,0.6,1.6))
				await picture("swing-%s"%id)
				player.rig.action=null
		game.camera.fov=fov
	if what=="palm":
		game.inventory.equipment.mainHand={"id":"rusty_dirk","count":1}
		game.inventory.equipment.offHand={"id":"rusty_dirk","count":1}
		player.show_equipment(game.inventory.equipment)
		player.draw_weapons("melee")
		player.rig.update(0.3,0)
		var sk:Skeleton3D=player.rig._skel
		for side in ["l","r"]:
			var g:Transform3D=sk.get_bone_global_pose(sk.find_bone("hand_"+side))*(player.model.get_meta("palm_grip_"+side) as Transform3D)
			for b in ["index_01_","index_02_","index_03_","middle_01_","middle_02_","middle_03_","ring_01_","ring_02_","ring_03_","pinky_01_","pinky_02_","pinky_03_","thumb_01_","thumb_02_","thumb_03_"]:
				var at:=g.affine_inverse()*sk.get_bone_global_pose(sk.find_bone(b+side)).origin
				print("PALM ",side," ",b," grip-local ",at)
	if what in ["all","grips"]:
		game.camera.fov=30
		var ids:Array=args[2].split(",") if args.size()>2 else ["rusty_dirk","ritual_knife","ghoulbone_knife","oak_club","ironwood_club","worn_longsword","roadwarden_greatsword"]
		for id in ids:
			game.inventory.equipment.mainHand={"id":id,"count":1}
			game.inventory.equipment.offHand=null
			player.show_equipment(game.inventory.equipment)
			player.draw_weapons("melee")
			for t in [-1.0,0.2,0.4,0.6]:
				player.rig.action=null
				player.rig.off_action=null
				if t>=0:
					player.rig.play("strike",1.0,0.4)
					player.rig.update(t,0)
				else:
					player.rig.update(0.3,0)
				var hand:=bone_at("hand_r")
				var n:=0
				for from in [Vector3(-1.6,0.5,0.6),Vector3(0.3,1.7,0.2),Vector3(0.9,0.4,1.4)]:
					look(hand,from)
					await picture("grip-%s-%s-%d"%[id,"idle" if t<0 else "t%.1f"%t,n])
					n+=1
		player.rig.action=null
		game.camera.fov=fov
	if what in ["all","sit"]:
		game.inventory.equipment.offHand=null
		player.show_equipment(game.inventory.equipment)
		player.set_sheathed(true)
		player.set_sitting(true)
		for i in 30:player.rig.update(1.0/30,0)
		var pel:=bone_at("pelvis")
		look(bone_at("pelvis"),Vector3(-4.2,0.15,0.3))
		await picture("sit-side")
		look(bone_at("pelvis"),Vector3(-2.0,1.6,3.8))
		await picture("sit-front")
		player.set_sitting(false)
	if what in ["all","move"]:
		player.set_sheathed(false)
		var log_:=[]
		for i in 120:
			var jump:= i==40
			game.time+=1.0/60
			player.update(1.0/60,{"move":{"x":0.0,"z":1.0},"actions":{},"jump":jump})
			var foot_l:=bone_at("foot_l")
			var foot_r:=bone_at("foot_r")
			log_.append("%3d clip=%-12s air=%s land=%.2f move=%.2f px=%.3f footL=%.3f,%.3f footR=%.3f,%.3f" % [i,player.rig.clip,player.rig.airborne,player.rig.landing,player.rig.move,player.position.z,foot_l.z,foot_l.y,foot_r.z,foot_r.y])
			if (i>=10 and i<=34 and i%3==1) or (i>=40 and i%3==0 and i<=90):
				look(player.position+Vector3.UP*1.1,Vector3(-6.5,1.4,0.3))
				await picture("move-%03d"%i)
		var f:=FileAccess.open(output.path_join("move-log.txt"),FileAccess.WRITE)
		f.store_string("\n".join(log_))
	if what in ["all","gait"]:
		# Ground speed of the planted foot versus the body, per locomotion clip.
		var out:=[]
		for speed01 in [0.3,0.6,1.0]:
			var rel:=[]
			for i in 240:
				game.time+=1.0/60
				player.update(1.0/60,{"move":{"x":0.0,"z":speed01},"actions":{}})
				var sk:Skeleton3D=player.rig._skel
				var bb:=sk.global_transform.basis
				var l:Vector3=bb*sk.get_bone_global_pose(sk.find_bone("foot_l")).origin
				var r:Vector3=bb*sk.get_bone_global_pose(sk.find_bone("foot_r")).origin
				rel.append([l,r,player.rig.clip,player.rig.gait_rate])
			var body:=0.0
			var sums:=0.0
			var n:=0
			var p0:Vector3=player.position
			var miny:=INF
			for i in range(121,240):miny=minf(miny,minf(rel[i][0].y,rel[i][1].y))
			for i in range(121,240):
				var a:Array=rel[i]
				var b:Array=rel[i-1]
				for f in 2:
					if a[f].y<miny+0.03 and b[f].y<miny+0.03:
						sums+=(a[f].z-b[f].z)*60
						n+=1
			var dump:=[]
			for i in range(121,240):dump.append("%.4f %.4f %.4f %.4f"%[rel[i][0].z,rel[i][0].y,rel[i][1].z,rel[i][1].y])
			FileAccess.open(output.path_join("gait-%.1f.txt"%speed01),FileAccess.WRITE).store_string("\n".join(dump))
			out.append("speed01=%.1f clip=%s gait=%.2f contact-foot rel speed=%.2f m/s over %d frames (body moves at %.2f)"%[speed01,rel[200][2],rel[200][3],sums/maxf(1,n),n,DB.CONFIG.player.speed*speed01])
		print("\n".join(out))
	print("anim_fix_shots complete")
	game.queue_free()
	await process_frame
	quit()

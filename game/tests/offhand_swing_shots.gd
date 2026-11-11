extends SceneTree
## Main-hand and off-hand swings side by side, two 1h clubs, to compare the
## off-hand mirror with the main swing. Usage:
## godot --path . -s game/tests/offhand_swing_shots.gd -- <out dir>
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
func _run() -> void:
	output=OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	Store.dir="user://offhand_shots_%d"%Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	var made:Dictionary=game.roster.create("Aldren","warrior")
	game.enter_world(made.character.id)
	while not game.started or game.hud.loading.visible:await process_frame
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.hud.root.visible=false
	var player=game.player
	player.facing=0
	player._sync()
	game.inventory.equipment.mainHand={"id":"oak_club","count":1}
	game.inventory.equipment.offHand={"id":"oak_club","count":1}
	player.show_equipment(game.inventory.equipment)
	player.draw_weapons("melee")
	game.camera.fov=35
	var rig=player.rig
	for run in [0.0,1.0]:
		for hand in ["main","off"]:
			for k in [0.15,0.3,0.4,0.55,0.75]:
				rig.action=null
				rig.off_action=null
				for i in 10:rig.update(0.03,run)
				if hand=="main":rig.play("strike",1.0,0.4)
				else:rig.play_off(1.0,0.4)
				var t:=0.0
				while t<k-1e-4:
					rig.update(minf(1.0/30,k-t),run)
					t+=1.0/30
				var c:=bone_at("spine_03")
				game.camera.position=c+Vector3(0.0,0.9,3.2)
				game.camera.look_at(c)
				await picture("%s%s-%.2f"%[hand,"-run" if run>0 else "",k])
	quit()

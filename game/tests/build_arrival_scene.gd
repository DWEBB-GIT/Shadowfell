extends SceneTree
func _initialize():
	var root=Node3D.new();root.name="ArrivalIntro"
	root.set_script(load("res://game/cinematics/arrival_intro.gd"))
	var path=Path3D.new();path.name="FlightPath";root.add_child(path);path.owner=root
	var curve=Curve3D.new();curve.bake_interval=0.12
	var points=[Vector3(22,16,30),Vector3(7,10,20),Vector3(-7,5.6,11),Vector3(-5.2,3.4,6.5),Vector3(1,7.8,14)]
	for i in points.size():
		var previous=points[maxi(0,i-1)];var next=points[mini(points.size()-1,i+1)]
		var handle=(next-previous)/6.0
		curve.add_point(points[i],-handle,handle)
	path.curve=curve
	var dolly=PathFollow3D.new();dolly.name="Dolly";dolly.rotation_mode=PathFollow3D.ROTATION_NONE;dolly.loop=false
	path.add_child(dolly);dolly.owner=root
	var camera=Camera3D.new();camera.name="Camera3D";camera.fov=48;camera.near=.18;camera.far=100
	dolly.add_child(camera);camera.owner=root
	for pair in [["CartFocus",Vector3(-6,1.6,5)],["HeroFocus",Vector3(0,1.25,0)]]:
		var marker=Marker3D.new();marker.name=pair[0];marker.position=pair[1];root.add_child(marker);marker.owner=root
	var player=AnimationPlayer.new();player.name="AnimationPlayer";player.callback_mode_process=2
	root.add_child(player);player.owner=root
	var library=AnimationLibrary.new();var anim=Animation.new();anim.length=12.0
	var tracks={
		"FlightPath/Dolly:progress_ratio":[[0,0.0],[2.8,.29],[5.0,.62],[6.7,.79],[8.7,1.0],[12,1.0]],
		"FlightPath/Dolly/Camera3D:fov":[[0,49.0],[3,44.0],[5.8,38.0],[7.4,37.0],[9,39.0],[12,39.0]],
		".:aim_blend":[[0,0.0],[2.2,.15],[4.9,1.0],[12,1.0]],
		".:handoff":[[0,0.0],[8.3,0.0],[11.6,1.0],[12,1.0]],
		".:veil_alpha":[[0,1.0],[1.1,0.0],[12,0.0]],
		".:chapter_alpha":[[0,0.0],[1.1,0.0],[2.0,1.0],[4.2,1.0],[5.0,0.0],[12,0.0]],
		".:caption_alpha":[[0,0.0],[5.5,0.0],[6.2,1.0],[7.6,1.0],[8.5,0.0],[12,0.0]],
		".:matte_amount":[[0,1.0],[9.3,1.0],[11.6,0.0],[12,0.0]],
		".:hud_reveal":[[0,0.0],[10.7,0.0],[11.9,1.0],[12,1.0]]
	}
	for property in tracks:
		var index=anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(index,NodePath(property))
		anim.track_set_interpolation_type(index,Animation.INTERPOLATION_CUBIC)
		for key in tracks[property]:anim.track_insert_key(index,key[0],key[1])
	library.add_animation("arrival",anim);player.add_animation_library("",library)
	var packed=PackedScene.new();var error=packed.pack(root)
	if error==OK:error=ResourceSaver.save(packed,"res://game/cinematics/arrival_intro.tscn")
	print("ARRIVAL_SCENE saved=",error)
	root.free();quit(error)

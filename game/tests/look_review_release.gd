extends SceneTree
## Real rendered A/B views and camera/readability checks, with isolated saves.
var game
var failures:=0
var sources:Array
var images:Dictionary
var gpu:Array=[]
var output:String
const SPOTS:=[['graveyard',-344,-472],['village',-450,-207],['pond',-394,-177],['forest',-555,-300],['inn',-465,-204]]
func _initialize()->void: _run.call_deferred()
func check(ok:bool,label:String)->void:
	print('ok: ' if ok else 'FAIL: ',label)
	if not ok:failures+=1
func _run()->void:
	Store.dir='user://look_release_%d'%Time.get_ticks_usec()
	game=load('res://game/main.tscn').instantiate()
	root.add_child(game)
	game.hud.title.main.new.pressed.emit()
	game.hud.title.create.name.text='Look Reviewer'
	game.hud.title.create.confirm.pressed.emit()
	while game.hud.loading.visible:await process_frame
	check(game.started,'title character creation enters the new world')
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.settings.values.classicCamera=false
	sources=game.atmosphere.sources.duplicate(true)
	output=OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else 'user://look_review_release'
	DirAccess.make_dir_recursive_absolute(output)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for spot in SPOTS:
		if OS.get_cmdline_user_args().size()>1 and spot[0] not in ['graveyard','inn']:continue
		game.player.place_at(spot[1],spot[2])
		game.world.land.update(game.player.position,true)
		game._bwk=-1
		game._update_region(3)
		game.world.update_indoors(3,game.player.position)
		game.enemies.update(0)
		game.npcs.update(0)
		images={}
		for variant in ['before','light','after']:
			_apply(variant=='before')
			_pose(variant!='after')
			await _picture(spot[0]+'-'+variant)
			if DisplayServer.get_name()!='headless':images[variant]=root.get_texture().get_image()
			print('REVIEW ',spot[0],' ',variant,' pitch=',rad_to_deg(-game.camera.rotation.x),' player_px=',_player_height(),' lights=',game.atmosphere.lamps.filter(func(l):return l.visible).size(),' shadows=',game.atmosphere.lamps.filter(func(l):return l.visible and l.shadow_enabled).size())
		if spot[0]=='graveyard':
			var count:int=game.atmosphere.lamps.filter(func(l):return l.visible and l.shadow_enabled).size()
			check(count>=1 and count<=2,'nearby fixture shadows stay within the two-light budget')
			check(game.atmosphere.lamps.all(func(l):return (l.shadow_caster_mask & World.LIGHT_FIXTURE_LAYER)==0),'fixture lights cannot be blocked by their own flame or bowl')
			check(game.atmosphere.lamps.size()==16,'fixture pool remains sixteen lights')
			if DisplayServer.get_name()!='headless':
				_pose(true)
				var ground:=[[ -349.5,-472],[-354.5,-472],[-352,-469.5],[-352,-474.5],[-344,-468]]
				var before:=_surface_luma(images.before,ground)
				var lit:=_surface_luma(images.light,ground)
				print('PIXELS ground before=',before,' after=',lit,' gain=',lit/maxf(before,0.0001))
				check(lit>before*1.15,'actual nearby ground becomes visibly brighter in the rendered image')
				await _fog_test()
		if spot[0]=='inn':
			check(game.atmosphere._window_groups['vr_lantern_inn'].all(func(w):return not w.visible),'warm window panes still hide with the inn cutaway')
	check(is_equal_approx(float(DB.CONFIG.camera.lookAhead),0.0),'camera retains zero look-ahead')
	game.player.place_at(-450,-207)
	game.world.update_indoors(3,game.player.position)
	for zoom in [0.72,0.98,1.3]:
		game.zoom=zoom
		game._snap_camera()
		check(absf(rad_to_deg(-game.camera.rotation.x)-50.0)<0.05,'camera keeps its 50-degree pitch at zoom '+str(zoom))
	var mm:Minimap=game.hud.minimap
	check(mm.overhead_camera!=null and mm.overhead_camera.projection==Camera3D.PROJECTION_ORTHOGONAL,'minimap keeps its independent overhead projection')
	game.queue_free()
	await process_frame
	await process_frame
	print('look_review_release: %d failed'%failures)
	quit(1 if failures else 0)
func _apply(legacy:bool)->void:
	game.atmosphere.sources=sources.duplicate(true)
	for s in game.atmosphere.sources:
		if legacy:
			s.energy=s.base_energy
			s.radius=s.base_radius
			s.attenuation=1.0
			s.fog=0.35
			s.shadows=false
	game.atmosphere._wait=0
	game.atmosphere._process(0.25)
func _pose(legacy:bool)->void:
	game._snap_camera()
	if legacy:
		var o:Vector3=Vector3(0,29.5,20.7)*game.zoom*(1.0-DB.CONFIG.camera.indoorZoom*game.world.indoor_blend)
		var at:Vector3=game.camera_target+Vector3.UP
		game.camera.position=at+o
		game.camera.look_at(at)
	game.world.set_cutaway(game.camera.position,game.player.position+Vector3(0,1.2,0))
	game.hud.zone_left=0
	game.hud.banner_time=0
	game.hud.banner.visible=false
	game.hud.update(0)
	game.hud.zone_banner.visible=false
func _picture(label:String)->void:
	var times:Array=[]
	for i in 36:
		await process_frame
		if i>=24:times.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	times.sort()
	print('RENDER ',label,' gpu_median_ms=',times[6])
	if DisplayServer.get_name()!='headless':
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label+'.png'))
func _player_height()->float:
	return game.camera.unproject_position(game.player.position).distance_to(game.camera.unproject_position(game.player.position+Vector3.UP*2.4))
func _surface_luma(image:Image,points:Array)->float:
	var total:=0.0
	for p in points:
		var pos:Vector2=game.camera.unproject_position(Vector3(p[0],Terrain.height_at(p[0],p[1])+0.03,p[1]))
		for x in range(-2,3):
			for y in range(-2,3):
				total+=image.get_pixel(clampi(int(pos.x)+x,0,image.get_width()-1),clampi(int(pos.y)+y,0,image.get_height()-1)).get_luminance()
	return total/(points.size()*25.0)
func _fog_test()->void:
	_pose(false)
	await _picture('graveyard-fog-on')
	var on:Image=root.get_texture().get_image()
	for light in game.atmosphere.lamps:light.light_volumetric_fog_energy=0.0
	await _picture('graveyard-fog-off')
	var off:Image=root.get_texture().get_image()
	var difference:=0.0
	for x in range(250,650,4):
		for y in range(200,470,4):
			difference+=absf(on.get_pixel(x,y).get_luminance()-off.get_pixel(x,y).get_luminance())
	print('PIXELS local fog scattering difference=',difference)
	check(difference>0.5,'fixture fog scattering changes actual rendered mist while surface light remains enabled')

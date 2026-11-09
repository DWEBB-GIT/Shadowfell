extends SceneTree
var game
func _initialize() -> void: _run.call_deferred()
func _sample(label: String) -> void:
	for i in 12: await process_frame
	var frames: Array = []
	var process: Array = []
	var gpu: Array = []
	var last := Time.get_ticks_usec()
	for i in 60:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now-last)/1000.0)
		last=now
		process.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	frames.sort()
	print("PROFILE ",label," frame_ms=",frames[30]," p95=",frames[57]," process_ms=",_mean(process)," gpu_ms=",_mean(gpu)," draws=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," nodes=",get_node_count()," objects=",Performance.get_monitor(Performance.OBJECT_COUNT))
func _mean(a: Array) -> float:
	var sum := 0.0
	for v in a: sum += float(v)
	return sum/a.size()
func _run() -> void:
	Store.dir="user://lighting_profile_%d" % Time.get_ticks_usec()
	game=load("res://game/main.tscn").instantiate()
	root.add_child(game)
	var c: Dictionary=game.roster.create("Profile","warden")
	game.enter_world(c.character.id)
	while game.hud.loading.visible: await process_frame
	game.save.autosave_enabled=false
	print("PROFILE display vsync=",DisplayServer.window_get_vsync_mode()," engine_limit=",Engine.max_fps)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await _sample("all")
	game.atmosphere.set_process(false)
	game.atmosphere.visible=false
	game.env.volumetric_fog_enabled=false
	await _sample("without_atmosphere")
	game.set_process(false)
	await _sample("without_game_loop")
	game.sun.shadow_enabled=false
	game.env.ssao_enabled=false
	await _sample("without_shadows_ssao")
	game.queue_free()
	await process_frame
	await process_frame
	quit()

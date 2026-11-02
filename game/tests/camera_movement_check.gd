extends SceneTree
## Actual input, projected direction, walking speed and mixed-input priority.
class TestPad extends Pad:
	func poll()->void:pass
var game
var failures:=0
var origin:=Vector3.ZERO
func _initialize()->void:_run.call_deferred()
func check(ok:bool,label:String)->void:
	print('ok: ' if ok else 'FAIL: ',label)
	if not ok:failures+=1
func _run()->void:
	Store.dir='user://camera_movement_%d'%Time.get_ticks_usec()
	game=load('res://game/main.tscn').instantiate()
	root.add_child(game)
	var c:Dictionary=game.roster.create('Movement Tester','warden')
	game.enter_world(c.character.id)
	var began:=Time.get_ticks_msec()
	while game.hud.loading.visible:
		await process_frame
		if Time.get_ticks_msec()-began>240000:
			check(false,'world loads')
			quit(1)
			return
	game.save.autosave_enabled=false
	game.set_process(false)
	game.atmosphere.set_process(false)
	game.pad=TestPad.new()
	for i in 16:game.pad.now.append(false)
	game.pad.prev=game.pad.now.duplicate()
	game.settings.set_value('classicControls',true)
	game.settings.set_value('clickToMove',true)
	game.settings.set_value('tankControls',false)
	game.targeting.stop_attack()
	origin=game.player.position
	for yaw in [0.0,35.0,45.0,90.0,180.0,270.0]:
		_pose(yaw)
		for item in [[KEY_W,Vector2.UP],[KEY_S,Vector2.DOWN],[KEY_A,Vector2.LEFT],[KEY_D,Vector2.RIGHT]]:
			_reset()
			_key(item[0],true)
			var controls:Dictionary=game._handle_input(0.05)
			var move:=Vector2(controls.move.x,controls.move.z)
			check(_screen_matches(move,item[1]),'key '+OS.get_keycode_string(item[0])+' follows the screen at yaw '+str(yaw))
			var start:Vector3=game.player.position
			game.player.update(0.05,controls)
			var travelled:=Vector2(game.player.position.x-start.x,game.player.position.z-start.z).length()
			check(absf(travelled-DB.CONFIG.player.speed*0.05)<0.01,'normal world running speed at yaw '+str(yaw))
			_key(item[0],false)
		_reset()
		_key(KEY_W,true)
		_key(KEY_D,true)
		var diagonal:Dictionary=game._handle_input(0.05)
		check(is_equal_approx(Vector2(diagonal.move.x,diagonal.move.z).length(),1.0),'diagonal input has no speed bonus at yaw '+str(yaw))
		_reset()
		game.pad.left=Vector3(0.25,0,0.25)
		var stick:Dictionary=game._handle_input(0.05)
		check(is_equal_approx(Vector2(stick.move.x,stick.move.z).length(),0.25) and _screen_matches(Vector2(stick.move.x,stick.move.z),Vector2.RIGHT),'left stick preserves analogue speed and screen direction at yaw '+str(yaw))
		game.pad.left=Vector3.ZERO
		game.pad.right=Vector3(0,-1,1)
		var aim:Vector3=game._pad_aim()-game.player.position
		check(_screen_matches(Vector2(aim.x,aim.z),Vector2.UP),'right-stick aim uses the same camera orientation at yaw '+str(yaw))
		game.pad.right=Vector3.ZERO
		game.player.facing=1.1
		var facing:Vector3=game._pad_aim()-game.player.position
		check(Vector2(facing.x,facing.z).normalized().dot(Vector2(sin(1.1),cos(1.1)))>0.999,'idle pad aim retains world-facing direction at yaw '+str(yaw))
	_pose(45)
	_reset()
	game.player.ghost=true
	_key(KEY_W,true)
	var ghost:Dictionary=game._handle_input(0.05)
	check(_screen_matches(Vector2(ghost.move.x,ghost.move.z),Vector2.UP),'ghost movement follows the same screen directions')
	game.player.ghost=false
	_reset()
	game.settings.set_value('tankControls',true)
	game.player.facing=0
	_key(KEY_D,true)
	var turning:Dictionary=game._handle_input(0.1)
	game.player.update(0.1,turning)
	check(game.player.position.distance_to(origin)<0.01 and game.player.facing<0,'optional keyboard turning still turns in place')
	_key(KEY_D,false)
	_key(KEY_W,true)
	var forward:=Vector2(sin(game.player.facing),cos(game.player.facing))
	var start:Vector3=game.player.position
	game.player.update(0.05,game._handle_input(0.05))
	var delta:=Vector2(game.player.position.x-start.x,game.player.position.z-start.z)
	check(delta.normalized().dot(forward)>0.99,'optional keyboard turning still walks along character facing')
	game.settings.set_value('tankControls',false)
	_reset()
	var goal:=_click_ground()
	check(game.move_to!=null,'actual right-click on clear ground queues a destination')
	_release_mouse()
	_pose(90)
	var route:Dictionary=game._handle_input(0.05)
	var wanted:=Vector2(goal.x-origin.x,goal.z-origin.z).normalized()
	check(Vector2(route.move.x,route.move.z).normalized().dot(wanted)>0.999,'click destination remains in world space when the camera changes')
	_key(KEY_W,true)
	var takeover:Dictionary=game._handle_input(0.05)
	check(game.move_to==null and _screen_matches(Vector2(takeover.move.x,takeover.move.z),Vector2.UP),'WASD immediately takes over from a clicked destination')
	_key(KEY_W,false)
	_reset()
	_key(KEY_W,true)
	_click_ground()
	check(game.move_to==null,'a click during manual movement cannot leave a queued route')
	_key(KEY_W,false)
	_release_mouse()
	var idle:Dictionary=game._handle_input(0.05)
	check(Vector2(idle.move.x,idle.move.z).is_zero_approx(),'releasing WASD does not resume an old click destination')
	_reset()
	var field:=LineEdit.new()
	game.hud.root.add_child(field)
	field.grab_focus()
	_key(KEY_W,true)
	check(not game.input.is_held('KeyW'),'typing into a focused text field does not start walking')
	field.release_focus()
	field.queue_free()
	game.queue_free()
	await process_frame
	await process_frame
	print('camera_movement_check: %d failed'%failures)
	quit(1 if failures else 0)
func _reset()->void:
	game.input.held.clear()
	game.input.end_frame()
	game.input.mouse.onCanvas=false
	game.input.mouse.leftHeld=false
	game.input.mouse.rightHeld=false
	game.pad.left=Vector3.ZERO
	game.pad.right=Vector3.ZERO
	game.move_to=null
	game.player.place_at(origin.x,origin.z)
func _pose(yaw:float)->void:
	var at:=origin+Vector3.UP
	game.camera.position=at+(DB.CONFIG.camera.offset as Vector3).rotated(Vector3.UP,deg_to_rad(yaw))
	game.camera.look_at(at)
func _key(code:int,down:bool)->void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.pressed=down
	game.input._input(event)
func _screen_matches(move:Vector2,wanted:Vector2)->bool:
	if move.is_zero_approx():return false
	var base:Vector2=game.camera.unproject_position(origin)
	var end:Vector2=game.camera.unproject_position(origin+Vector3(move.x,0,move.y))
	return (end-base).normalized().dot(wanted)>0.999
func _click_ground()->Vector3:
	var goal:=origin+Vector3(4,0.5,0)
	for offset in [Vector3(4,0.5,0),Vector3(-4,0.5,-3),Vector3(3,0.5,-5)]:
		goal=origin+offset
		var at:Vector2=game.camera.unproject_position(goal)
		game.input.mouse.x=at.x
		game.input.mouse.y=at.y
		game.input.mouse.onCanvas=true
		if game._pick_under_cursor()==null:break
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_RIGHT
	event.position=Vector2(game.input.mouse.x,game.input.mouse.y)
	event.pressed=true
	game.input._unhandled_input(event)
	game.input.mouse.onCanvas=true
	game._handle_input(0.0)
	return Vector3(goal.x,origin.y,goal.z)
func _release_mouse()->void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_RIGHT
	event.pressed=false
	game.input._input(event)
	game.input.end_frame()

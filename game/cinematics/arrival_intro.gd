@tool
extends Node3D
## An authored Camera3D rail, driven by the scene's AnimationPlayer.
## The gameplay camera stays intact and supplies the final matching frame.
signal finished(skipped: bool)

const SEEN_FLAG := "mk_arrival_seen"
@export var chapter_title := "The West Road"
@export var chapter_location := "Thornford Reach"
@export_multiline var hero_caption := "No coin. No title.\nA place to begin."
@export var aim_blend := 0.0
@export var handoff := 0.0
@export var chapter_alpha := 0.0
@export var caption_alpha := 0.0
@export var veil_alpha := 1.0
@export var matte_amount := 1.0
@export var hud_reveal := 0.0

@onready var rail: Path3D = $FlightPath
@onready var dolly: PathFollow3D = $FlightPath/Dolly
@onready var film_camera: Camera3D = $FlightPath/Dolly/Camera3D
@onready var cart_focus: Marker3D = $CartFocus
@onready var hero_focus: Marker3D = $HeroFocus
@onready var timeline: AnimationPlayer = $AnimationPlayer

var game
var active := false
var elapsed := 0.0
var reduced := false
var skipping := false
var skip_elapsed := 0.0
var _skip_switched := false
var _game_pose := Transform3D.IDENTITY
var _game_fov := 39.0
var _hud_colour := Color.WHITE
var _old_modal = null
var _layer: CanvasLayer
var _screen: Control
var _top: ColorRect
var _bottom: ColorRect
var _top_rule: ColorRect
var _bottom_rule: ColorRect
var _vignette: ColorRect
var _veil: ColorRect
var _chapter: VBoxContainer
var _caption: Label
var _skip_button: Button
var _music: AudioStreamPlayer

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	if Engine.is_editor_hint(): return
	_build_presentation()

func _process(_dt: float) -> void:
	# Allows the rail and target blend to be scrubbed in Godot's editor.
	if Engine.is_editor_hint(): _point_camera()

func bind(g) -> void:
	game = g

func should_play(resumed: bool) -> bool:
	if game == null or resumed or Terrain.chosen_map() != "new": return false
	if DisplayServer.get_name() == "headless": return false
	if not game.settings.get_value("openingCinematic"): return false
	if game.player.dead or game.world_state.flags.get(SEEN_FLAG, false): return false
	var start: Array = Layout.player_start.position
	return Vector2(game.player.position.x-start[0], game.player.position.z-start[1]).length() < 8.0

func begin() -> bool:
	if game == null or active or game.player.dead: return false
	game._snap_camera()
	_game_pose = game.camera.global_transform
	_game_fov = game.camera.fov
	_hud_colour = game.hud.root.modulate
	_old_modal = game.hud.modal
	global_position = game.player.position
	# Follow an authored cart when the designer moves the starting area.
	cart_focus.position = Vector3(-6, 1.6, 5)
	for prop in Layout.props:
		if prop.get("id") == "ni_cart":
			var at := Vector3(prop.position[0], Terrain.height_at(prop.position[0],prop.position[1])+1.2, prop.position[1])
			if at.distance_to(global_position) < 35: cart_focus.global_position = at
			break
	hero_focus.position = Vector3(0, 1.25, 0)
	film_camera.near = 0.18
	film_camera.far = game.camera.far
	game.move_to = null
	game.targeting.clear()
	game.player.pending = null
	game.player.pending_off = null
	game.player.pending_shot = null
	game.player.casting = null
	game.player.moving = false
	game.player.rig.action = null
	elapsed = 0.0
	skipping = false
	skip_elapsed = 0.0
	_skip_switched = false
	reduced = bool(game.settings.get_value("reducedOpeningMotion"))
	active = true
	game.hud.modal = "arrival"
	game.hud.loading.arrival_hold = true
	game.hud.loading.close()
	game.hud.root.modulate.a = 0
	_layer.show()
	timeline.play(&"arrival")
	timeline.advance(0)
	if reduced:
		film_camera.global_transform = _game_pose
		film_camera.fov = _game_fov
	else:
		_point_camera()
	film_camera.make_current()
	_start_music()
	_present()
	return true

func advance(dt: float) -> void:
	if not active: return
	game.pad.poll()
	var B = Pad.BUTTONS
	if game.input.consume("Escape") or game.input.consume("Space") or game.input.consume("Enter") or game.pad.pressed(B.B) or game.pad.pressed(B.START):
		request_skip()
	game.time += dt
	game.player.rig.update(dt, 0)
	game.player._sync()
	# Keep the air, water and idle pose alive; enemies and gameplay do not advance.
	game.world.update(dt, Time.get_ticks_msec()/1000.0)
	game.water_and_dark.update(dt, game.time)
	game._update_region(dt)
	game._update_daylight()
	game.hud.update(dt)
	game.audio.update(dt)
	if skipping:
		skip_elapsed += dt
		var k := clampf(skip_elapsed/0.55, 0, 1)
		veil_alpha = smoothstep(0, 0.48, k) if k < 0.5 else 1-smoothstep(0.5,1,k)
		chapter_alpha = 0
		caption_alpha = 0
		if k >= 0.5 and not _skip_switched:
			_skip_switched = true
			film_camera.global_transform = _game_pose
			film_camera.fov = _game_fov
			hud_reveal = 1
			matte_amount = 0
		_present()
		if k >= 1: _finish(true)
		return
	elapsed += dt
	if reduced:
		veil_alpha = 1-smoothstep(0,0.8,elapsed)
		chapter_alpha = 0
		caption_alpha = 0
		matte_amount = 0
		hud_reveal = 1-veil_alpha
		film_camera.global_transform = _game_pose
		film_camera.fov = _game_fov
	else:
		timeline.advance(dt)
		_point_camera()
	_present()
	if elapsed >= (0.85 if reduced else timeline.get_animation(&"arrival").length):
		_finish(false)

func _point_camera() -> void:
	if not is_instance_valid(film_camera) or not film_camera.is_inside_tree(): return
	film_camera.transform = Transform3D.IDENTITY
	var aim := cart_focus.global_position.lerp(hero_focus.global_position, clampf(aim_blend,0,1))
	if game != null:
		var p := film_camera.global_position
		p.y = maxf(p.y, Terrain.height_at(p.x,p.z)+1.6)
		film_camera.global_position = p
	film_camera.look_at(aim)
	if game != null:
		film_camera.global_transform = film_camera.global_transform.interpolate_with(_game_pose, smoothstep(0,1,handoff))
		film_camera.fov = lerpf(film_camera.fov, _game_fov, smoothstep(0,1,handoff))
		game.world.set_cutaway(film_camera.global_position, hero_focus.global_position)

func request_skip() -> void:
	if not active or skipping: return
	skipping = true
	timeline.pause()
	skip_elapsed = 0

func _finish(was_skipped: bool) -> void:
	if not active: return
	timeline.stop(true)
	game.camera.global_transform = _game_pose
	game.camera.fov = _game_fov
	game.camera.make_current()
	game.hud.root.modulate = _hud_colour
	game.hud.loading.arrival_hold = false
	game.hud.loading.visible = false
	game.hud.loading.fade = 0
	game.hud.modal = null if _old_modal in [null,"loading","arrival"] else _old_modal
	game.world_state.flags[SEEN_FLAG] = true
	game.move_to = null
	game.input.pressed.clear()
	game.input.mouse.clicked = false
	game.input.mouse.rightClicked = false
	game.input.mouse.leftHeld = false
	game.input.mouse.rightHeld = false
	game.world.set_cutaway(game.camera.global_position, game.player.position+Vector3(0,1.2,0))
	_music.stop()
	_layer.hide()
	active = false
	finished.emit(was_skipped)

func _start_music() -> void:
	_music.stop()
	if reduced or game.audio.music == null or game.audio.music.stream == null: return
	_music.stream = game.audio.music.stream
	_music.volume_db = -80
	_music.play()

func _present() -> void:
	if not is_instance_valid(_screen): return
	var size := get_viewport().get_visible_rect().size
	_screen.size = size
	var bar := clampf((size.y-size.x/2.35)*0.5,0,size.y*0.16)*clampf(matte_amount,0,1)
	_top.size = Vector2(size.x,bar)
	_bottom.position = Vector2(0,size.y-bar)
	_bottom.size = Vector2(size.x,bar)
	_top_rule.position = Vector2(0,maxf(0,bar-1))
	_top_rule.size = Vector2(size.x,1)
	_bottom_rule.position = Vector2(0,size.y-bar)
	_bottom_rule.size = Vector2(size.x,1)
	_top_rule.modulate.a = matte_amount*0.3
	_bottom_rule.modulate.a = matte_amount*0.3
	_chapter.modulate.a = clampf(chapter_alpha,0,1)
	_chapter.position = Vector2(maxf(28,size.x*0.055),size.y-bar-155)
	_chapter.size.x = maxf(260,minf(600,size.x-64))
	_caption.modulate.a = clampf(caption_alpha,0,1)
	_caption.position = Vector2(28,size.y-bar-110)
	_caption.size = Vector2(size.x-56,74)
	_skip_button.text = "Skip intro  ·  B" if game.pad.active else "Skip intro  ·  Esc / Space"
	_skip_button.position = Vector2(size.x-232,size.y-maxf(48,bar*0.56)-18)
	_skip_button.size = Vector2(204,36)
	_veil.color.a = clampf(veil_alpha,0,1)
	_vignette.modulate.a = 1-clampf(hud_reveal,0,1)
	game.hud.root.modulate.a = _hud_colour.a*clampf(hud_reveal,0,1)
	if _music.playing:
		var gain := minf(smoothstep(0,1.8,elapsed),1-smoothstep(9.3,12,elapsed))
		if skipping: gain *= 1-clampf(skip_elapsed/0.3,0,1)
		_music.volume_db = -13+linear_to_db(maxf(0.0001,gain))

func _build_presentation() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "CinematicPresentation"
	_layer.layer = 30
	add_child(_layer)
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_screen)
	_vignette = _rect(_screen,Color.WHITE)
	var material := ShaderMaterial.new()
	material.shader = preload("res://game/cinematics/arrival_vignette.gdshader")
	_vignette.material = material
	_top = _rect(_screen,Color("080a0b"),false)
	_bottom = _rect(_screen,Color("080a0b"),false)
	_top_rule = _rect(_screen,UI.GOLD,false)
	_bottom_rule = _rect(_screen,UI.GOLD,false)
	_chapter = VBoxContainer.new()
	_chapter.add_theme_constant_override("separation",8)
	_screen.add_child(_chapter)
	var kicker := UI.label(_chapter,"MYTHKEEP  ·  CHAPTER I",13,UI.GOLD)
	kicker.add_theme_constant_override("outline_size",4)
	kicker.add_theme_color_override("font_outline_color",Color.BLACK)
	var title := UI.logo(_chapter,chapter_title,38)
	title.add_theme_color_override("font_color",Color("fff0cd"))
	title.add_theme_color_override("font_outline_color",Color("17100a"))
	title.add_theme_constant_override("outline_size",5)
	var line := ColorRect.new()
	line.color = Color("bb985a")
	line.custom_minimum_size = Vector2(140,1)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_chapter.add_child(line)
	UI.label(_chapter,chapter_location,17,Color("d9d0b9"))
	_caption = UI.label(_screen,hero_caption,20,Color("f1e7d0"))
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_color_override("font_shadow_color",Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x",1)
	_caption.add_theme_constant_override("shadow_offset_y",2)
	_caption.add_theme_constant_override("outline_size",4)
	_caption.add_theme_color_override("font_outline_color",Color("10100c"))
	_skip_button = Button.new()
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.add_theme_font_override("font",UI.font)
	_skip_button.add_theme_font_size_override("font_size",13)
	_skip_button.add_theme_color_override("font_color",UI.GOLD)
	_skip_button.add_theme_stylebox_override("normal",UI.box(Color("100e0bd9"),Color("78603b"),3,1,Vector4(12,6,12,6)))
	_skip_button.add_theme_stylebox_override("hover",UI.box(Color("211a11ee"),UI.GOLD,3,1,Vector4(12,6,12,6)))
	_skip_button.pressed.connect(request_skip)
	_screen.add_child(_skip_button)
	_veil = _rect(_screen,Color.BLACK)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_music = AudioStreamPlayer.new()
	_music.name = "ArrivalScore"
	_music.bus = "Music"
	add_child(_music)
	_layer.hide()

func _rect(parent: Node, colour: Color, fill := true) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = colour
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	if fill: rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return rect

func _exit_tree() -> void:
	active = false
	game = null

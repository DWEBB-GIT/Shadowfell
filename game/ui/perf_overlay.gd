extends CanvasLayer
## F3 toggles a small readout of what each frame costs: FPS, frame and
## process time, draw calls, objects and triangles drawn, and video memory.
## Use it while playtesting to see what a place costs before guessing.

var label: Label
var _t := 0.0


func _ready() -> void:
	layer = 120
	label = Label.new()
	label.position = Vector2(8, 8)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("e8f0c8"))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	visible = false


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not visible:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 0.25
	label.text = "%d fps  %.1f ms  (scripts %.1f ms)\ndraw calls %d  objects %d  tris %dk\nnodes %d  vram %d MB  %s" % [
		Performance.get_monitor(Performance.TIME_FPS),
		1000.0 / maxf(1.0, Performance.get_monitor(Performance.TIME_FPS)),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
		RenderingServer.get_current_rendering_method(),
	]

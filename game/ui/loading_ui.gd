class_name LoadingScreen
extends Control
## The loading screen between character select and the world (style.css
## #loading: dark, quiet, "Lighting the lamps..."), with a bar for each
## stage of the warm-up in Game.load_world(). It covers the screen while the
## world is drawn once behind it, so nothing stalls once you can move.

var title_label: Label
var stage: Label
var bar: Dictionary
var fade := 0.0 ## counts down while fading out


func _init() -> void:
	name = "Loading"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP # nothing reaches the world underneath
	var bg := ColorRect.new()
	bg.color = Color("0d0b09")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	var v := UI.vbox(centre, 14)
	v.custom_minimum_size = Vector2(360, 0)
	title_label = UI.label(v, "SHADOWFALL", 34, UI.GOLD)
	var f := FontVariation.new()
	f.base_font = UI.font
	f.spacing_glyph = 10
	title_label.add_theme_font_override("font", f)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage = UI.label(v, "Lighting the lamps…", 14, UI.TEXT_DIM)
	stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var track := Panel.new()
	track.custom_minimum_size = Vector2(360, 10)
	track.add_theme_stylebox_override("panel", UI.box(Color("0b0908"), UI.BORDER_DIM, 0))
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(track)
	var fill := ColorRect.new()
	fill.color = UI.GOLD.darkened(0.25)
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.offset_left = 1
	fill.offset_top = 1
	fill.offset_bottom = -1
	fill.anchor_right = 0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	bar = {"track": track, "fill": fill}
	visible = false


func open() -> void:
	fade = 0.0
	modulate.a = 1.0
	visible = true
	show_progress("Lighting the lamps…", 0.0)


## `what` the warm-up is doing, and how far through it is (0..1)
func show_progress(what: String, k: float) -> void:
	stage.text = what
	bar.fill.anchor_right = clampf(k, 0, 1)
	bar.fill.offset_right = 0


func close() -> void:
	fade = 0.4


func _process(dt: float) -> void:
	if fade <= 0:
		return
	fade -= dt
	modulate.a = clampf(fade / 0.4, 0, 1)
	if fade <= 0:
		visible = false

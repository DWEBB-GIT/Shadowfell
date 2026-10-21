class_name CharPreview
extends TextureRect
## The character panel's figure (src/ui/charPreview.js): the player's own
## model, live, with whatever they wear and carry, as in WoW's paper doll.
## A copy of the model stands in a small world of its own, lit from the
## front, and copies the real one's pose every frame the panel is open, so
## it animates, swaps gear and fades as a ghost as the player does. Drag on
## the figure to turn it.

var game
var turn := 0.0 ## radians the viewer has turned the figure
var vp: SubViewport
var pivot: Node3D
var copy: Node3D
var _shape := ""
var _drag = null


func _init(g) -> void:
	game = g
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	vp = SubViewport.new()
	vp.size = Vector2i(330, 356)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff0dc")
	env.ambient_light_energy = 2.2 * Tex.LIGHT_SCALE
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var cam := Camera3D.new()
	cam.fov = 26
	cam.environment = env
	# frame the whole figure (it stands about 2 m with a helm)
	cam.transform = Transform3D(Basis(), Vector3(0, 1.15, 5.1)).looking_at(Vector3(0, 1.0, 0), Vector3.UP)
	vp.add_child(cam)
	for l in [[Color("ffe2c0"), 2.6, Vector3(1.6, 2.6, 2.4)], [Color("9ab0ff"), 1.4, Vector3(-2, 1.8, -2.2)]]:
		var d := DirectionalLight3D.new()
		d.light_color = l[0]
		d.light_energy = l[1] * Tex.LIGHT_SCALE * Game.SUN_MATCH
		d.transform = Transform3D(Basis(), l[2]).looking_at(Vector3.ZERO, Vector3.UP)
		vp.add_child(d)
	pivot = Node3D.new()
	vp.add_child(pivot)
	add_child(vp)
	texture = vp.get_texture()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		_drag = e.position.x if e.pressed else null
		accept_event()
	elif e is InputEventMouseMotion and _drag != null:
		turn += (e.position.x - _drag) * 0.012
		_drag = e.position.x


## Called every frame the panel is open.
func render() -> void:
	var model: Node3D = game.player.model
	if model == null:
		return
	var want := Vector2i(maxi(64, int(size.x)), maxi(64, int(size.y)))
	if vp.size != want:
		vp.size = want
	var shape := _signature(model)
	if shape != _shape or copy == null:
		_shape = shape
		if copy:
			copy.queue_free()
		copy = model.duplicate() as Node3D
		pivot.add_child(copy)
	_sync(model, copy)
	copy.transform = model.transform
	# from the front: the model's own facing is on its parent, then the viewer's turn
	pivot.rotation.y = turn
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE


## what the model is made of (gear swaps add and remove parts)
static func _signature(n: Node) -> String:
	var s := n.name + "("
	for c in n.get_children():
		s += _signature(c)
	return s + ")"


## copy the pose (and a ghost's fade) part by part
static func _sync(from: Node, to: Node) -> void:
	if from is Node3D:
		to.transform = from.transform
		to.visible = from.visible
	if from is GeometryInstance3D:
		to.transparency = from.transparency
	var n := mini(from.get_child_count(), to.get_child_count())
	for i in n:
		_sync(from.get_child(i), to.get_child(i))

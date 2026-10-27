@tool
extends EditorPlugin
## Sculpt brushes for the World editor (addons/shadowfell_data/world_editor.tscn).
## Select its root node, pick a brush on the 3D view's toolbar and paint with
## the left mouse button: Raise, Lower, Smooth, Flatten (to the height where
## the stroke began), Walkable / Blocked (where players can go) and Paint
## ground (its surface). Shift swaps Raise/Lower and Walkable/Blocked;
## [ and ] change the size. Ctrl+Z undoes a stroke; Ctrl+S saves.

const Sculpt := preload("sculpt.gd")
const WorldEditor := preload("res://addons/shadowfell_data/world_editor.gd")
const SURFACES := ["Meadow", "Marsh", "Downs", "Blackwood", "Rock", "Moor", "Sand", "Farmland", "Forest", "Snow", "Desert", "Ash", "Swamp", "Jungle", "Haunted"]

var bar: HBoxContainer
var mode_pick: OptionButton
var size_box: SpinBox
var strength_box: SpinBox
var surface_pick: OptionButton
var editor: Node3D
var sculpt
var _painting := false
var _mouse := Vector2.ZERO
var _camera: Camera3D
var _shift := false
var _target := 0.0
var _chunks := {}
var _since_draw := 0.0


func _enter_tree() -> void:
	bar = HBoxContainer.new()
	var label := Label.new()
	label.text = "Sculpt"
	bar.add_child(label)
	mode_pick = OptionButton.new()
	for m in Sculpt.MODES:
		mode_pick.add_item(m)
	mode_pick.tooltip_text = "Brush (left mouse paints; Shift swaps Raise/Lower and Walkable/Blocked)"
	mode_pick.item_selected.connect(func(_i): _update_brush())
	bar.add_child(mode_pick)
	size_box = _spin(bar, "Size", 2, 80, 12, 1, "Brush radius in metres ([ and ])")
	strength_box = _spin(bar, "Strength", 0.05, 1, 0.5, 0.05, "How fast the brush works")
	surface_pick = OptionButton.new()
	for i in SURFACES.size():
		surface_pick.add_item(SURFACES[i], i + 1)
	surface_pick.tooltip_text = "Ground to paint"
	bar.add_child(surface_pick)
	bar.visible = false
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, bar)
	set_process(false)


func _exit_tree() -> void:
	if bar:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, bar)
		bar.queue_free()


static func _spin(parent: Control, label: String, lo: float, hi: float, value: float, step: float, tip: String) -> SpinBox:
	var l := Label.new()
	l.text = label
	parent.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.tooltip_text = tip
	parent.add_child(s)
	return s


func _handles(object: Object) -> bool:
	return object is Node3D and object.get_script() == WorldEditor


func _edit(object: Object) -> void:
	editor = object as Node3D
	if editor:
		if sculpt == null:
			sculpt = Sculpt.new()
		editor.sculpt = sculpt
	elif _painting:
		_end_stroke()


func _make_visible(visible: bool) -> void:
	bar.visible = visible
	if not visible and editor:
		editor.show_brush(Vector3.ZERO, 0)


func _mode() -> int:
	var m := mode_pick.selected
	if _shift:
		m = {Sculpt.RAISE: Sculpt.LOWER, Sculpt.LOWER: Sculpt.RAISE, Sculpt.OPEN: Sculpt.BLOCK, Sculpt.BLOCK: Sculpt.OPEN}.get(m, m)
	return m


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if editor == null or not is_instance_valid(editor) or mode_pick.selected == Sculpt.OFF:
		return AFTER_GUI_INPUT_PASS
	_camera = camera
	if event is InputEventKey and event.pressed and event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
		size_box.value *= 0.8 if event.keycode == KEY_BRACKETLEFT else 1.25
		_update_brush()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouse:
		_mouse = event.position
		_shift = event.shift_pressed
		_update_brush()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var hit = _hit()
			if hit == null:
				return AFTER_GUI_INPUT_PASS
			_target = hit.y
			_painting = true
			sculpt.begin_stroke()
			_since_draw = 1.0
			set_process(true)
		elif _painting:
			_end_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _painting:
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _hit():
	if _camera == null:
		return null
	return Sculpt.ray_hit(_camera.project_ray_origin(_mouse), _camera.project_ray_normal(_mouse))


func _update_brush() -> void:
	if editor == null or not is_instance_valid(editor):
		return
	var hit = _hit() if mode_pick.selected != Sculpt.OFF else null
	if hit == null:
		editor.show_brush(Vector3.ZERO, 0)
		return
	editor.ensure_ground(hit)
	var m := _mode()
	var col := Color(1, 0.85, 0.3)
	if m in [Sculpt.LOWER, Sculpt.BLOCK]:
		col = Color(1, 0.4, 0.3)
	elif m == Sculpt.OPEN:
		col = Color(0.5, 1, 0.5)
	editor.show_brush(hit, size_box.value, col)


## While the button is down the brush keeps working; the ground under it is
## drawn again about ten times a second.
func _process(delta: float) -> void:
	if not _painting or editor == null or not is_instance_valid(editor):
		set_process(false)
		return
	var hit = _hit()
	if hit != null:
		var chunks: Dictionary = sculpt.apply(_mode(), hit.x, hit.z, size_box.value, strength_box.value, minf(delta, 0.1), _target, surface_pick.get_selected_id())
		_chunks.merge(chunks)
	_since_draw += delta
	if _since_draw > 0.1 and _chunks.size():
		editor.redraw(_chunks)
		_chunks = {}
		_since_draw = 0.0
		_update_brush()


func _end_stroke() -> void:
	_painting = false
	set_process(false)
	if _chunks.size() and is_instance_valid(editor):
		editor.redraw(_chunks)
	_chunks = {}
	var states: Array = sculpt.end_stroke()
	if states[0].is_empty():
		return
	var ur := get_undo_redo()
	ur.create_action("Sculpt: " + Sculpt.MODES[mode_pick.selected], UndoRedo.MERGE_DISABLE, editor)
	ur.add_do_method(self, "_restore", states[1])
	ur.add_undo_method(self, "_restore", states[0])
	ur.commit_action(false)


func _restore(state: Dictionary) -> void:
	if sculpt == null:
		return
	var chunks: Dictionary = sculpt.restore(state)
	if editor and is_instance_valid(editor):
		editor.redraw(chunks)

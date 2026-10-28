@tool
extends EditorPlugin
## Sculpt brushes for the World editor (addons/shadowfell_data/world_editor.tscn).
## The "World" dock (beside the Scene tree) opens it and holds the brushes:
## pick one and paint with the left mouse button: Raise, Lower, Smooth, Flatten (to the height where
## the stroke began), Walkable / Blocked (where players can go) and Paint
## ground (its surface). Shift swaps Raise/Lower and Walkable/Blocked;
## [ and ] change the size. Ctrl+Z undoes a stroke; Ctrl+S saves.

const Sculpt := preload("sculpt.gd")
const WorldEditor := preload("res://addons/shadowfell_data/world_editor.gd")
const WORLD_SCENE := "res://addons/shadowfell_data/world_editor.tscn"
const PLACE_KINDS := ["NPC", "Enemy", "Item", "Chest", "Prop", "Shrine", "Signpost"]
const PROP_MODELS := ["anvil", "awning", "bone_pile", "camp", "cart", "chest", "cottage", "crate", "crate_broken", "dead_tree", "fence", "forge", "grave0", "grave1", "lamp_post", "palisade", "pine", "rock0", "rock1", "ruin_wall", "shrine", "standing_stone", "watch_post", "waymarker", "well", "wheel"]
const SURFACES := ["Meadow", "Marsh", "Downs", "Blackwood", "Rock", "Moor", "Sand", "Farmland", "Forest", "Snow", "Desert", "Ash", "Swamp", "Jungle", "Haunted"]

var bar: VBoxContainer
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
var kind_pick: OptionButton
var what_pick: OptionButton
var place_button: Button


func _enter_tree() -> void:
	# a "World" dock beside the Scene tree, always there
	bar = VBoxContainer.new()
	bar.name = "World"
	var open := Button.new()
	open.text = "Open the world (sculpt and place)"
	open.tooltip_text = "Opens world_editor.tscn in the 3D view with everything from world.json on the real ground"
	open.pressed.connect(_open_world)
	bar.add_child(open)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 200
	help.text = "Placing: pick what under Place, press the Place button, then click the ground (each click places one). Click anything placed to move it with the gizmo; Ctrl+D copies it, Delete removes it. Its other fields are in the Inspector (record).\nSculpting: pick a brush and paint with the left mouse button. Shift swaps Raise/Lower and Walkable/Blocked; [ and ] resize; Ctrl+Z undoes.\nCtrl+S saves both."
	bar.add_child(help)
	var pl := Label.new()
	pl.text = "Place"
	bar.add_child(pl)
	kind_pick = OptionButton.new()
	for k in PLACE_KINDS:
		kind_pick.add_item(k)
	kind_pick.item_selected.connect(func(_i): _fill_what())
	bar.add_child(kind_pick)
	what_pick = OptionButton.new()
	what_pick.fit_to_longest_item = false
	what_pick.tooltip_text = "Which one to place"
	bar.add_child(what_pick)
	place_button = Button.new()
	place_button.text = "Place: click the ground"
	place_button.toggle_mode = true
	place_button.tooltip_text = "While this is down, each left click on the ground places one (Esc stops)"
	place_button.toggled.connect(_on_place_toggled)
	bar.add_child(place_button)
	var label := Label.new()
	label.text = "Brush"
	bar.add_child(label)
	mode_pick = OptionButton.new()
	for m in Sculpt.MODES:
		mode_pick.add_item(m)
	mode_pick.tooltip_text = "Brush (left mouse paints; Shift swaps Raise/Lower and Walkable/Blocked)"
	mode_pick.item_selected.connect(_on_mode)
	bar.add_child(mode_pick)
	var row := GridContainer.new()
	row.columns = 2
	bar.add_child(row)
	size_box = _spin(row, "Size (m)", 2, 80, 12, 1, "Brush radius in metres ([ and ])")
	strength_box = _spin(row, "Strength", 0.05, 1, 0.5, 0.05, "How fast the brush works")
	var sl := Label.new()
	sl.text = "Ground"
	row.add_child(sl)
	surface_pick = OptionButton.new()
	for i in SURFACES.size():
		surface_pick.add_item(SURFACES[i], i + 1)
	surface_pick.tooltip_text = "Ground to paint"
	row.add_child(surface_pick)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, bar)
	set_process(false)


func _exit_tree() -> void:
	if bar:
		remove_control_from_docks(bar)
		bar.queue_free()


func _open_world() -> void:
	EditorInterface.open_scene_from_path(WORLD_SCENE)
	EditorInterface.set_main_screen_editor("3D")
	_select_root.call_deferred()


func _select_root() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root and root.get_script() == WorldEditor:
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(root)


func _on_place_toggled(on: bool) -> void:
	if on:
		mode_pick.select(Sculpt.OFF)
		if what_pick.item_count == 0:
			_fill_what()
		_on_mode(0)
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.get_script() != WorldEditor:
			_open_world()
		else:
			_select_root()
	elif editor and is_instance_valid(editor):
		editor.show_brush(Vector3.ZERO, 0)


## What can be placed of the chosen kind, by name (ids as metadata).
func _fill_what() -> void:
	DB.ensure()
	what_pick.clear()
	var rows := []
	match PLACE_KINDS[kind_pick.selected]:
		"NPC":
			for id in DB.npcs:
				rows.append([str(DB.npcs[id].get("name", id)), id])
		"Enemy":
			for id in DB.enemies:
				rows.append(["%s (%s)" % [DB.enemies[id].get("name", id), id], id])
		"Item":
			for id in DB.items:
				rows.append([str(DB.items[id].get("name", id)), id])
		"Prop":
			for m in PROP_MODELS:
				rows.append([m, m])
		_:
			rows.append(["(one)", ""])
	rows.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	for r in rows:
		what_pick.add_item(r[0])
		what_pick.set_item_metadata(what_pick.item_count - 1, r[1])


## The record a new thing starts from (the save gives it a unique id).
static func _new_record(kind: String, id: String) -> Array:
	match kind:
		"NPC":
			return ["NPCs", {"npc": id, "position": [0, 0], "facing": 0}]
		"Enemy":
			return ["Enemies", {"id": id, "enemy": id, "position": [0, 0]}]
		"Item":
			var it: Dictionary = DB.items.get(id, {})
			return ["Loot", {"id": id, "model": it.get("model", "satchel"), "position": [0, 0], "prompt": "Take the %s" % str(it.get("name", id)).to_lower(), "reward": {"item": id}}]
		"Chest":
			return ["Chests", {"id": "chest", "name": "Chest", "position": [0, 0], "facing": 0, "coins": 5, "items": []}]
		"Prop":
			return ["Props", {"model": id, "position": [0, 0], "rotation": 0}]
		"Shrine":
			return ["Shrines", {"id": "shrine", "position": [0, 0], "rotation": 0, "label": "at a shrine"}]
	return ["Signposts", {"id": "sign", "position": [0, 0], "points": []}]


func _place() -> void:
	var at = _hit()
	if at == null or what_pick.item_count == 0:
		return
	var nr := _new_record(PLACE_KINDS[kind_pick.selected], str(what_pick.get_item_metadata(what_pick.selected)))
	var rec: Dictionary = nr[1]
	rec.position = [String.num(at.x, 2).to_float(), String.num(at.z, 2).to_float()]
	var node: Node3D = editor.make_marker(nr[0], rec)
	if node == null:
		return
	var holder: Node = editor.get_node(NodePath(nr[0]))
	var ur := get_undo_redo()
	ur.create_action("Place " + node.name, UndoRedo.MERGE_DISABLE, editor)
	ur.add_do_method(editor, "attach", node, holder)
	ur.add_do_reference(node)
	ur.add_undo_method(holder, "remove_child", node)
	ur.commit_action()


## Picking a brush selects the world's root node, which the brushes need.
func _on_mode(_i: int) -> void:
	if mode_pick.selected != Sculpt.OFF:
		place_button.set_pressed_no_signal(false)
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.get_script() != WorldEditor:
			_open_world()
		else:
			_select_root()
	_update_brush()


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
	if not visible and editor:
		editor.show_brush(Vector3.ZERO, 0)


func _mode() -> int:
	var m := mode_pick.selected
	if _shift:
		m = {Sculpt.RAISE: Sculpt.LOWER, Sculpt.LOWER: Sculpt.RAISE, Sculpt.OPEN: Sculpt.BLOCK, Sculpt.BLOCK: Sculpt.OPEN}.get(m, m)
	return m


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if editor == null or not is_instance_valid(editor):
		return AFTER_GUI_INPUT_PASS
	_camera = camera
	if place_button.button_pressed:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			place_button.button_pressed = false
			return AFTER_GUI_INPUT_STOP
		if event is InputEventMouse:
			_mouse = event.position
			var at = _hit()
			if at != null:
				editor.ensure_ground(at)
				editor.show_brush(at, 1.5, Color(0.4, 0.8, 1))
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_place()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS
	if mode_pick.selected == Sculpt.OFF:
		return AFTER_GUI_INPUT_PASS
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

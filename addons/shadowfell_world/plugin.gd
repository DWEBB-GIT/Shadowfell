@tool
extends EditorPlugin
## Sculpt brushes for the World editor (addons/shadowfell_data/world_editor.tscn).
## The "World" dock (a tab beside Scene, top left) opens it and holds the brushes:
## pick one and paint with the left mouse button: Raise, Lower, Smooth, Flatten (to the height where
## the stroke began), Walkable / Blocked (where players can go) and Paint
## ground (its surface). Shift swaps Raise/Lower and Walkable/Blocked;
## [ and ] change the size. Ctrl+Z undoes a stroke; Ctrl+S saves.

const Sculpt := preload("sculpt.gd")
const WorldEditor := preload("res://addons/shadowfell_data/world_editor.gd")
const Catalog := preload("catalog.gd")
const PlacementInspector := preload("placement_inspector.gd")
const CoastEditor := preload("coast_editor.gd")
const CoastData := preload("res://game/world/lantern_coast/placement_records.gd")
const CoastKit := preload("res://game/world/lantern_coast/building_kit.gd")
const PathBrush := preload("path_brush.gd")
const PATH_MODES := ["Brush off", "Paint dirt path", "Paint cobbles", "Erase paths"]
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
var map_pick: OptionButton
var asset_search: LineEdit
var asset_category: OptionButton
var scale_min: SpinBox
var scale_max: SpinBox
var random_turn: CheckBox
var scatter_count: SpinBox
var scatter_radius: SpinBox
var snap_size: SpinBox
var collision_radius: SpinBox
var coast_regions: OptionButton
var coast_controls: VBoxContainer
var brush_options: GridContainer
var ground_label: Label
var pick_scenery: Button
var _coast_brush := false
var _brush_settings := {false: Vector2(12.0, .50), true: Vector2(2.0, 1.0)}
var _path_stroke: PathBrush
var turn_box: SpinBox
var finish_pick: OptionButton
var drag_button: Button
var legacy_open_button: Button
var coast_open_button: Button
var colour_button: Button
var _dragging := false
var _drag_start := Vector2.ZERO
var _drag_pointer := Vector2.ZERO
var _catalog: Array = []
var _inspector: EditorInspectorPlugin
const MAPS := ["act1", "new"]

var dock: Control
var _scroll: ScrollContainer


func _enter_tree() -> void:
	set_input_event_forwarding_always_enabled()
	_inspector = PlacementInspector.new()
	_inspector.plugin = self
	add_inspector_plugin(_inspector)
	scene_changed.connect(_scene_changed)
	# a "World" dock beside the Scene tree, always there
	bar = VBoxContainer.new()
	bar.name = "World"
	legacy_open_button = _button("Open Campaign map", _open_world)
	bar.add_child(legacy_open_button)
	# which map: the Act 1 world, or Dan's new map (its ground only, for now)
	if not ProjectSettings.has_setting(Terrain.MAP_SETTING):
		ProjectSettings.set_setting(Terrain.MAP_SETTING, "act1")
	ProjectSettings.set_initial_value(Terrain.MAP_SETTING, "act1")
	ProjectSettings.add_property_info({"name": Terrain.MAP_SETTING, "type": TYPE_STRING, "hint": PROPERTY_HINT_ENUM, "hint_string": ",".join(MAPS)})
	var mrow := HBoxContainer.new()
	var ml := Label.new()
	ml.text = "Map"
	mrow.add_child(ml)
	map_pick = OptionButton.new()
	map_pick.add_item("Act 1 world")
	map_pick.add_item("New map (2026-10-28)")
	map_pick.add_item("Lantern Coast")
	map_pick.select(MAPS.find(Terrain.chosen_map()))
	map_pick.tooltip_text = "Choose the map to edit. Lantern Coast remains a separate world at login."
	map_pick.item_selected.connect(_on_map)
	mrow.add_child(map_pick)
	bar.add_child(mrow)
	coast_open_button = _button("Open Lantern Coast", _open_coast)
	bar.add_child(coast_open_button)
	coast_controls = VBoxContainer.new()
	coast_regions = OptionButton.new()
	coast_regions.fit_to_longest_item = false
	for hub in preload("res://game/world/lantern_coast/atlas.tres").get_meta("hubs"):
		coast_regions.add_item(str(hub.name).get_slice(" · ", 0))
	coast_regions.item_selected.connect(_pick_coast_region)
	var region_row := HBoxContainer.new()
	coast_regions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	region_row.add_child(coast_regions)
	var frame := _button("Select region", func(): _pick_coast_region(coast_regions.selected))
	frame.tooltip_text = "Select the region centre again so you can frame it with F."
	region_row.add_child(frame)
	coast_controls.add_child(region_row)
	var frame_hint := Label.new()
	frame_hint.text = "Hover over the 3D view and press F."
	frame_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	coast_controls.add_child(frame_hint)
	var prop_tools := HBoxContainer.new()
	prop_tools.add_child(_button("Delete selected", _delete_coast_selection))
	var lamp := _button("Lamp post", _pick_lamp)
	lamp.tooltip_text = "Preview and place a working lamp post. Q and E rotate it."
	prop_tools.add_child(lamp)
	coast_controls.add_child(prop_tools)
	pick_scenery = Button.new()
	pick_scenery.text = "Edit existing scenery"
	pick_scenery.toggle_mode = true
	pick_scenery.tooltip_text = "Click a generated tree, rock, plant or fixture to turn it into an editable placement."
	pick_scenery.toggled.connect(_on_pick_scenery)
	coast_controls.add_child(pick_scenery)
	bar.add_child(coast_controls)
	coast_controls.hide()
	colour_button = _button("New colour zone at the view centre", _new_colour_zone)
	bar.add_child(colour_button)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 200
	help.text = "Move over the ground to preview. Q / E turns it, click places it, Esc exits. Ctrl+S saves."
	kind_pick = OptionButton.new()
	for k in PLACE_KINDS:
		kind_pick.add_item(k)
	kind_pick.item_selected.connect(func(_i): _fill_what())
	bar.add_child(kind_pick)
	asset_search = LineEdit.new()
	asset_search.placeholder_text = "Find a tree, grass, NPC…"
	asset_search.text_changed.connect(func(_text): _fill_what())
	bar.add_child(asset_search)
	asset_category = OptionButton.new()
	for category in ["All assets", "Trees", "Grass", "Plants", "Rocks", "Buildings", "Props", "Characters", "Items"]:
		asset_category.add_item(category)
	asset_category.item_selected.connect(func(_i): _fill_what())
	bar.add_child(asset_category)
	what_pick = OptionButton.new()
	what_pick.fit_to_longest_item = false
	what_pick.tooltip_text = "Which one to place"
	what_pick.item_selected.connect(func(_i): _update_asset_controls())
	bar.add_child(what_pick)
	var placement_row := HBoxContainer.new()
	bar.add_child(placement_row)
	drag_button = Button.new()
	drag_button.text = "Drag to place"
	drag_button.tooltip_text = "Drag the selected asset, NPC or enemy onto the terrain and release to place it."
	drag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag_button.gui_input.connect(_drag_input)
	placement_row.add_child(drag_button)
	bar.add_child(_button("Refresh asset library", func():
		_catalog = Catalog.models()
		DB.ready = false
		_fill_what()))
	bar.add_child(_button("Choose a project scene…", _choose_scene))
	var options := GridContainer.new()
	options.columns = 2
	bar.add_child(options)
	scale_min = _spin(options, "Scale min", 0.01, 100, 1, 0.01, "Random uniform scale: minimum")
	scale_max = _spin(options, "Scale max", 0.01, 100, 1, 0.01, "Random uniform scale: maximum")
	turn_box = _spin(options, "Yaw", -360, 360, 0, 5, "Turn the preview in degrees. Q and E turn 15 degrees.")
	snap_size = _spin(options, "Grid (m)", 0, 100, 0, 0.25, "Zero places freely; otherwise snap X/Z to this grid")
	scatter_count = _spin(options, "Props per click", 1, 100, 1, 1, "Props only: scatter several instances in one undoable placement")
	scatter_radius = _spin(options, "Scatter radius", 0, 80, 8, 1, "Props only: scatter radius in metres; only walkable land is used")
	collision_radius = _spin(options, "Prop collider", 0, 20, 0, 0.1, "Circular footprint before scaling; zero for grass and decorative plants")
	random_turn = CheckBox.new()
	random_turn.text = "Random prop rotation"
	bar.add_child(random_turn)
	finish_pick = OptionButton.new()
	for finish in CoastKit.FINISHES:
		finish_pick.add_item(finish)
	finish_pick.tooltip_text = "Change the compatible Mythkeep kit materials"
	bar.add_child(finish_pick)
	place_button = Button.new()
	place_button.text = "Place with preview"
	place_button.toggle_mode = true
	place_button.tooltip_text = "While this is down, each left click on the ground places one (Esc stops)"
	place_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_button.toggled.connect(_on_place_toggled)
	placement_row.add_child(place_button)
	placement_row.move_child(place_button, 0)
	bar.add_child(help)
	bar.move_child(help, placement_row.get_index() + 1)
	var brush_row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Brush"
	brush_row.add_child(label)
	mode_pick = OptionButton.new()
	mode_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_pick.item_selected.connect(_on_mode)
	brush_row.add_child(mode_pick)
	bar.add_child(brush_row)
	bar.move_child(brush_row, colour_button.get_index() + 1)
	brush_options = GridContainer.new()
	brush_options.columns = 2
	bar.add_child(brush_options)
	bar.move_child(brush_options, brush_row.get_index() + 1)
	size_box = _spin(brush_options, "Radius (m)", 2, 80, 12, 1, "Brush radius in metres ([ and ])")
	strength_box = _spin(brush_options, "Strength (%)", 5, 100, 50, 1, "Set how strongly the brush changes the surface")
	ground_label = Label.new()
	ground_label.text = "Ground"
	brush_options.add_child(ground_label)
	surface_pick = OptionButton.new()
	for i in SURFACES.size():
		surface_pick.add_item(SURFACES[i], i + 1)
	surface_pick.tooltip_text = "Ground to paint"
	brush_options.add_child(surface_pick)
	_configure_brush(false)
	_add_dock()
	set_process(false)
	_catalog = Catalog.models()
	_fill_what()
	_scene_changed(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if _is_coast():
		_finish_path_stroke()
	if _painting:
		_end_stroke()
	if _inspector:
		remove_inspector_plugin(_inspector)
	if bar:
		if dock:
			call("remove_dock", dock)
			dock.queue_free()
		else:
			remove_control_from_docks(_scroll)
			_scroll.queue_free()


# Godot 4.6+ docks are EditorDock nodes added with add_dock (the old
# add_control_to_dock no longer shows anything); older editors use the old call
func _add_dock() -> void:
	_scroll = ScrollContainer.new()
	_scroll.name = "World"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(bar)
	if ClassDB.class_exists("EditorDock") and has_method("add_dock"):
		dock = ClassDB.instantiate("EditorDock")
		dock.name = "World"
		dock.set("title", "World")
		dock.set("layout_key", "shadowfell_world")
		dock.set("default_slot", DOCK_SLOT_LEFT_UR)
		_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dock.add_child(_scroll)
		call("add_dock", dock)
	else:
		add_control_to_dock(DOCK_SLOT_LEFT_UL, _scroll)


func _on_map(i: int) -> void:
	if i == MAPS.size():
		_open_coast()
		return
	var data_screen := EditorInterface.get_editor_main_screen().get_node_or_null("GameData")
	if data_screen and not data_screen.s.dirty.is_empty():
		push_warning("World: save or revert your Game Data changes before switching maps")
		map_pick.select(MAPS.find(Terrain.chosen_map()))
		return
	var current_root := EditorInterface.get_edited_scene_root()
	if (sculpt and sculpt.dirty) or (current_root and current_root.get_script() == WorldEditor and current_root.has_unsaved_changes()):
		push_warning("World: save (Ctrl+S) your placements and terrain before switching maps")
		map_pick.select(MAPS.find(Terrain.chosen_map()))
		return
	ProjectSettings.set_setting(Terrain.MAP_SETTING, MAPS[i])
	ProjectSettings.save()
	Terrain.use_map(MAPS[i])
	DB.ready = false
	sculpt = null # the brushes' layer belongs to the map
	var root := EditorInterface.get_edited_scene_root()
	if root and root.get_script() == WorldEditor:
		get_undo_redo().clear_history(get_undo_redo().get_object_history_id(root))
		root.rebuild()
		sculpt = Sculpt.new()
		root.sculpt = sculpt
	if data_screen:
		data_screen.revert()
	print("World: now on the %s map" % ("new" if MAPS[i] == "new" else "Act 1"))
	if root and root.get_script() == CoastEditor:
		_open_world()


func _scene_changed(root: Node) -> void:
	if _painting:
		_end_stroke()
	if _is_coast():
		_set_path_mode(0)
		editor.hide_preview()
	var was_coast := _is_coast()
	_dragging = false
	place_button.set_pressed_no_signal(false)
	editor = root as Node3D if root and root.get_script() in [WorldEditor, CoastEditor] else null
	var coast := _is_coast()
	pick_scenery.set_pressed_no_signal(false)
	coast_controls.visible = coast
	legacy_open_button.visible = not coast
	coast_open_button.visible = not coast
	colour_button.visible = not coast
	set_process(coast)
	_configure_brush(coast)
	for index in PLACE_KINDS.size():
		kind_pick.set_item_disabled(index, coast and PLACE_KINDS[index] not in ["Prop", "NPC", "Enemy"])
	if coast:
		map_pick.select(MAPS.size())
		if not was_coast or kind_pick.selected < 0 or kind_pick.is_item_disabled(kind_pick.selected):
			kind_pick.select(PLACE_KINDS.find("Prop"))
	elif editor:
		map_pick.select(MAPS.find(Terrain.chosen_map()))
		if sculpt == null:
			sculpt = Sculpt.new()
		editor.sculpt = sculpt
	_fill_what()


func _is_coast() -> bool:
	return is_instance_valid(editor) and editor.get_script() == CoastEditor


func _open_coast() -> void:
	map_pick.select(MAPS.size())
	if dock and dock.has_method("make_visible"):
		dock.call("make_visible")
	EditorInterface.open_scene_from_path(CoastData.PATH)
	EditorInterface.set_main_screen_editor("3D")
	_pick_coast_region.call_deferred(coast_regions.selected)


func _pick_coast_region(index: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.get_script() != CoastEditor:
		return
	var anchor: Node3D = root.load_region(index)
	if anchor:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(anchor)


static func _button(label: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.pressed.connect(action)
	return b


func _choose_scene() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.filters = PackedStringArray(["*.glb,*.gltf,*.tscn ; 3D scenes and models"])
	dialog.file_selected.connect(func(path: String):
		_catalog.append([path.get_file().get_basename(), path])
		kind_pick.select(PLACE_KINDS.find("Prop"))
		asset_category.select(0)
		asset_search.clear()
		_fill_what()
		for index in what_pick.item_count:
			if what_pick.get_item_metadata(index) == path:
				what_pick.select(index)
		_update_asset_controls()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	bar.add_child(dialog)
	dialog.popup_centered_ratio(0.7)


func _open_world() -> void:
	if map_pick.selected == MAPS.size():
		_open_coast()
		return
	if dock and dock.has_method("make_visible"):
		dock.call("make_visible")
	EditorInterface.open_scene_from_path(WORLD_SCENE)
	EditorInterface.set_main_screen_editor("3D")
	_select_root.call_deferred()


func _select_root() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root and root.get_script() in [WorldEditor, CoastEditor]:
		var sel := EditorInterface.get_selection()
		sel.clear()
		sel.add_node(root)


func _on_place_toggled(on: bool) -> void:
	if on:
		if _is_coast():
			_set_path_mode(0)
			pick_scenery.set_pressed_no_signal(false)
		mode_pick.select(Sculpt.OFF)
		if what_pick.item_count == 0:
			_fill_what()
		_on_mode(0)
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.get_script() not in [WorldEditor, CoastEditor]:
			_open_world()
		elif not _is_coast():
			_select_root()
	elif is_instance_valid(editor):
		if _is_coast():
			editor.hide_preview()
		else:
			editor.show_brush(Vector3.ZERO, 0)


func _pick_lamp() -> void:
	_set_path_mode(0)
	kind_pick.select(PLACE_KINDS.find("Prop"))
	asset_category.select(0)
	asset_search.text = "lamp_post"
	_fill_what()
	if what_pick.selected >= 0:
		place_button.button_pressed = true


## What can be placed of the chosen kind, by name (ids as metadata).
func _fill_what() -> void:
	DB.ensure()
	what_pick.clear()
	var rows := []
	match PLACE_KINDS[kind_pick.selected]:
		"NPC":
			for id in DB.npcs:
				rows.append([str(DB.npcs[id].get("name", id)), id])
			if _is_coast() and not DB.npcs.has(CoastData.ANGLER):
				rows.append([CoastData.ANGLER_DEF.name, CoastData.ANGLER])
		"Enemy":
			for id in DB.enemies:
				rows.append(["%s (%s)" % [DB.enemies[id].get("name", id), id], id])
		"Item":
			for id in DB.items:
				rows.append([str(DB.items[id].get("name", id)), id])
		"Prop":
			rows.append_array(_catalog)
		_:
			rows.append(["(one)", ""])
	asset_category.disabled = PLACE_KINDS[kind_pick.selected] != "Prop"
	rows.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	for r in rows:
		if not asset_category.disabled and asset_category.selected > 0:
			var category := asset_category.get_item_text(asset_category.selected).to_lower()
			if not Assets.model_path(str(r[1])).contains("/" + category + "/"):
				continue
		if asset_search.text != "" and not (str(r[0]) + " " + str(r[1])).to_lower().contains(asset_search.text.to_lower()):
			continue
		what_pick.add_item(r[0])
		what_pick.set_item_metadata(what_pick.item_count - 1, r[1])
	_update_asset_controls()


func _selected_model_path() -> String:
	if kind_pick.selected < 0 or PLACE_KINDS[kind_pick.selected] != "Prop" or what_pick.selected < 0:
		return ""
	return Assets.model_path(str(what_pick.get_item_metadata(what_pick.selected)))


func _drag_input(event: InputEvent) -> void:
	if not _is_coast() or drag_button.disabled or not event is InputEventMouse:
		return
	_drag_pointer = drag_button.get_screen_transform() * event.position
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_set_path_mode(0)
			pick_scenery.set_pressed_no_signal(false)
			place_button.button_pressed = false
			_drag_start = _drag_pointer
			_dragging = true
		else:
			_end_drag()


func _end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	if not _is_coast():
		return
	if _drag_pointer.distance_to(_drag_start) >= 8.0 and _drag_target():
		_place()
	editor.hide_preview()


func _drag_target() -> bool:
	for index in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(index)
		if viewport == null:
			continue
		var area := viewport.get_parent() as SubViewportContainer
		if area == null or not area.is_visible_in_tree() or area.size.x <= 0 or area.size.y <= 0:
			continue
		var pointer := area.get_screen_transform().affine_inverse() * _drag_pointer
		if not Rect2(Vector2.ZERO, area.size).has_point(pointer):
			continue
		_camera = viewport.get_camera_3d()
		_mouse = pointer * Vector2(viewport.size) / area.size
		return is_instance_valid(_camera)
	return false


func _shortcut_input(event: InputEvent) -> void:
	if not _dragging or not _is_coast() or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_ESCAPE:
		_dragging = false
		editor.hide_preview()
	elif event.keycode in [KEY_Q, KEY_E]:
		_turn_preview(event.keycode)
	else:
		return
	get_viewport().set_input_as_handled()


func _turn_preview(key: Key) -> void:
	turn_box.value = wrapf(turn_box.value + (15 if key == KEY_E else -15), -180, 180)
	_show_coast_preview()


func _update_asset_controls() -> void:
	var path := _selected_model_path()
	drag_button.visible = _is_coast()
	drag_button.disabled = what_pick.selected < 0
	finish_pick.visible = _is_coast() and not CoastKit.key(path).is_empty()


func _delete_coast_selection() -> void:
	if not _is_coast():
		return
	var removable := []
	for node in EditorInterface.get_selection().get_selected_nodes():
		var parent := node.get_parent()
		if node is Node3D and parent and parent.get_parent() == editor and CoastData.GROUPS.has(str(parent.name)):
			removable.append([node, parent])
		elif node is Node3D and parent and (parent == editor or parent.get_parent() == editor) and not node.scene_file_path.is_empty():
			removable.append([node, parent])
	if removable.is_empty():
		return
	var undo := get_undo_redo()
	undo.create_action("Delete Coast placements", UndoRedo.MERGE_DISABLE, editor)
	for entry in removable:
		undo.add_do_method(entry[1], "remove_child", entry[0])
		undo.add_undo_method(editor, "attach", entry[0], entry[1])
		undo.add_undo_reference(entry[0])
	undo.commit_action()


func _on_pick_scenery(active: bool) -> void:
	if active:
		_set_path_mode(0)
		place_button.button_pressed = false
		_dragging = false


func _scenery_input(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		pick_scenery.button_pressed = false
		return AFTER_GUI_INPUT_STOP
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return AFTER_GUI_INPUT_PASS
	var hit: Dictionary = editor.find_scenery(_camera.project_ray_origin(event.position), _camera.project_ray_normal(event.position))
	if hit.is_empty():
		return AFTER_GUI_INPUT_PASS
	var marker: Node3D = editor.make_scenery_marker(hit)
	if marker == null:
		return AFTER_GUI_INPUT_PASS
	var holder := editor.get_node("Props")
	var undo := get_undo_redo()
	undo.create_action("Make scenery editable", UndoRedo.MERGE_DISABLE, editor)
	undo.add_do_method(editor, "set_scenery_hidden", hit.id, marker.position, true)
	undo.add_do_method(editor, "attach", marker, holder)
	undo.add_do_reference(marker)
	undo.add_undo_method(holder, "remove_child", marker)
	undo.add_undo_method(editor, "set_scenery_hidden", hit.id, marker.position, false)
	undo.commit_action()
	pick_scenery.button_pressed = false
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(marker)
	EditorInterface.edit_node(marker)
	return AFTER_GUI_INPUT_STOP


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


## A colour zone (warm fields, violet graves...) where the 3D view looks,
## selected so its colours, fog and light are in the Inspector.
func _new_colour_zone() -> void:
	if _is_coast():
		push_warning("Lantern Coast's atmosphere uses its regional grade data.")
		return
	if editor == null:
		push_warning("Open the world first (the button above), then add a colour zone.")
		return
	var cam := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	var at := cam.global_position
	var dir := -cam.global_transform.basis.z
	if dir.y < -0.05:
		at += dir * ((at.y - Terrain.height_at(at.x, at.z)) / -dir.y)
	var holder: Node = editor.get_node_or_null("Colour zones")
	var node: Node3D = editor.new_grade_zone(at)
	if node == null or holder == null:
		return
	var ur := get_undo_redo()
	ur.create_action("New colour zone", UndoRedo.MERGE_DISABLE, editor)
	ur.add_do_method(editor, "attach", node, holder)
	ur.add_do_reference(node)
	ur.add_undo_method(holder, "remove_child", node)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)


func _place() -> void:
	var at = _hit()
	if at == null or what_pick.selected < 0:
		return
	var kind: String = PLACE_KINDS[kind_pick.selected]
	if _is_coast() and kind not in ["Prop", "NPC", "Enemy"]:
		return
	var id := str(what_pick.get_item_metadata(what_pick.selected))
	var count := int(scatter_count.value) if kind == "Prop" else 1
	var ur := get_undo_redo()
	ur.create_action("Place " + kind, UndoRedo.MERGE_DISABLE, editor)
	for index in count:
		var point: Vector3 = at
		if count > 1:
			var angle := randf() * TAU
			var distance := sqrt(randf()) * scatter_radius.value
			point += Vector3(sin(angle), 0, cos(angle)) * distance
		if snap_size.value > 0:
			point.x = snappedf(point.x, snap_size.value)
			point.z = snappedf(point.z, snap_size.value)
		if count > 1 and not (_is_coast() or Terrain.walkable(point.x, point.z)):
			continue
		var nr := _new_record(kind, id)
		var rec: Dictionary = nr[1]
		if _is_coast() and editor.elevation(point.x, point.z) <= .12:
			continue
		rec.position = [snappedf(point.x, 0.01), snappedf(point.z, 0.01)]
		if kind == "Prop":
			rec.scale = scale_min.value
			if not _is_coast() or index > 0:
				rec.scale = randf_range(minf(scale_min.value, scale_max.value), maxf(scale_min.value, scale_max.value))
			rec.rotation = randf_range(-180, 180) if random_turn.button_pressed and index > 0 else turn_box.value
			if collision_radius.value > 0:
				rec.collider = collision_radius.value
			if _is_coast() and finish_pick.visible:
				rec.finish = finish_pick.get_item_text(finish_pick.selected)
		elif kind == "NPC":
			rec.facing = turn_box.value
		elif kind == "Enemy" and _is_coast():
			rec.id = "lc_edit_%x_%x" % [Time.get_ticks_usec(), randi()]
		var node: Node3D = editor.make_marker(nr[0], rec)
		if node == null:
			continue
		var holder: Node = editor.get_node(NodePath(nr[0]))
		ur.add_do_method(editor, "attach", node, holder)
		ur.add_do_reference(node)
		ur.add_undo_method(holder, "remove_child", node)
		editor.ensure_ground(node.position, 32)
	ur.commit_action()


## Picking a brush selects the world's root node, which the brushes need.
func _on_mode(_i: int) -> void:
	if _is_coast():
		_set_path_mode(_i)
		return
	if mode_pick.selected != Sculpt.OFF:
		place_button.set_pressed_no_signal(false)
		var root := EditorInterface.get_edited_scene_root()
		if root == null or root.get_script() != WorldEditor:
			_open_world()
		else:
			_select_root()
	_update_brush()


func _configure_brush(coast: bool) -> void:
	if mode_pick.item_count > 0:
		_brush_settings[_coast_brush] = Vector2(size_box.value, strength_box.value / 100.0)
	_coast_brush = coast
	mode_pick.clear()
	for label in (PATH_MODES if coast else Sculpt.MODES):
		mode_pick.add_item(label)
	mode_pick.select(0)
	mode_pick.tooltip_text = "Drag over the ground. [ and ] resize the brush."
	size_box.min_value = .5 if coast else 2.0
	size_box.max_value = 13.0 if coast else 80.0
	size_box.step = .25 if coast else 1.0
	size_box.value = _brush_settings[coast].x
	strength_box.value = _brush_settings[coast].y * 100.0
	ground_label.visible = not coast
	surface_pick.visible = not coast
	brush_options.visible = not coast


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
	return object is Node3D and (object.get_script() in [WorldEditor, CoastEditor]
		or object.has_meta("record") or _is_coast())


func _get_unsaved_status(for_scene: String) -> String:
	if not is_inside_tree():
		return ""
	var root := EditorInterface.get_edited_scene_root()
	if root and root.get_script() == WorldEditor and (for_scene == "" or for_scene == root.scene_file_path) and root.has_unsaved_changes():
		return "Shadowfell world placements or sculpted terrain have unsaved changes."
	return ""


func _edit(object: Object) -> void:
	# Godot clears selection while the edited scene is being removed. There
	# is no scene to resolve at that point; finish the stroke and release it.
	if object == null or not is_inside_tree():
		if _painting and is_inside_tree():
			_end_stroke()
		if not _is_coast():
			editor = null
		return
	var root := EditorInterface.get_edited_scene_root()
	editor = root as Node3D if root and root.get_script() in [WorldEditor, CoastEditor] else null
	if editor and not _is_coast():
		if sculpt == null:
			sculpt = Sculpt.new()
		editor.sculpt = sculpt
	elif _painting:
		_end_stroke()


func _make_visible(visible: bool) -> void:
	if not visible and editor:
		if _painting:
			_end_stroke()
		if _is_coast():
			_finish_path_stroke()
			editor.path_cursor(null, 0.0, false)
			editor.hide_preview()
		else:
			editor.show_brush(Vector3.ZERO, 0)


func _mode() -> int:
	var m := mode_pick.selected
	if _shift:
		m = {Sculpt.RAISE: Sculpt.LOWER, Sculpt.LOWER: Sculpt.RAISE, Sculpt.OPEN: Sculpt.BLOCK, Sculpt.BLOCK: Sculpt.OPEN}.get(m, m)
	return m


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if editor == null or not is_instance_valid(editor):
		return AFTER_GUI_INPUT_PASS
	if event is InputEventMouse and event.alt_pressed:
		if _is_coast():
			_finish_path_stroke()
			editor.path_cursor(null, 0.0, false)
		if _painting:
			_end_stroke()
		return AFTER_GUI_INPUT_PASS
	_camera = camera
	if place_button.button_pressed:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			place_button.button_pressed = false
			return AFTER_GUI_INPUT_STOP
		if event is InputEventKey and event.pressed and event.keycode in [KEY_Q, KEY_E]:
			_turn_preview(event.keycode)
			return AFTER_GUI_INPUT_STOP
		if event is InputEventMouse:
			_mouse = event.position
			var at = _hit()
			if _is_coast():
				_show_coast_preview()
			elif at != null:
				editor.ensure_ground(at)
				editor.show_brush(at, 1.5, Color(0.4, 0.8, 1))
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_place()
			return AFTER_GUI_INPUT_STOP
		return AFTER_GUI_INPUT_PASS
	if _is_coast():
		if pick_scenery.button_pressed:
			return _scenery_input(event)
		return _path_input(event) if mode_pick.selected > 0 else AFTER_GUI_INPUT_PASS
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
			editor.capture_height_offsets()
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
	if _is_coast():
		return editor.ray_hit(_camera.project_ray_origin(_mouse), _camera.project_ray_normal(_mouse))
	var point = Sculpt.ray_hit(_camera.project_ray_origin(_mouse), _camera.project_ray_normal(_mouse))
	return point if point != null and Terrain.map_rect().has_point(Vector2(point.x, point.z)) else null


func _update_brush() -> void:
	if editor == null or not is_instance_valid(editor):
		return
	if _is_coast():
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
	if _is_coast():
		if _dragging:
			if _drag_target():
				_show_coast_preview()
			else:
				editor.hide_preview()
		var view := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
		if view:
			editor.editor_view(view, delta)
		return
	if not _painting or editor == null or not is_instance_valid(editor):
		set_process(false)
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_stroke()
		return
	var hit = _hit()
	if hit != null:
		var chunks: Dictionary = sculpt.apply(_mode(), hit.x, hit.z, size_box.value, strength_box.value / 100.0, minf(delta, 0.1), _target, surface_pick.get_selected_id())
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


func _set_path_mode(mode: int) -> void:
	_finish_path_stroke()
	mode_pick.select(mode)
	brush_options.visible = mode > 0
	if mode > 0:
		_dragging = false
		pick_scenery.set_pressed_no_signal(false)
		place_button.button_pressed = false
	elif _is_coast():
		editor.path_cursor(null, 0.0, false)


func _path_input(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_set_path_mode(0)
			return AFTER_GUI_INPUT_STOP
		if event.keycode in [KEY_BRACKETLEFT, KEY_BRACKETRIGHT]:
			size_box.value *= .8 if event.keycode == KEY_BRACKETLEFT else 1.25
			return AFTER_GUI_INPUT_STOP
	if not event is InputEventMouse:
		return AFTER_GUI_INPUT_PASS
	_mouse = event.position
	var at = _hit()
	var mode := mode_pick.selected
	var radius := size_box.value
	editor.path_cursor(at, radius, mode == 3)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and at != null:
			_path_stroke = PathBrush.new(editor.preview.land, mode, radius * 2.0, Vector2(at.x, at.z), strength_box.value / 100.0)
			_path_stroke.preview()
		elif not event.pressed:
			if _path_stroke != null and at != null:
				_path_stroke.move_to(Vector2(at.x, at.z))
			_finish_path_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion and _path_stroke != null:
		if at != null:
			_path_stroke.move_to(Vector2(at.x, at.z))
			_path_stroke.preview()
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
			_finish_path_stroke()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _finish_path_stroke() -> void:
	if _path_stroke == null:
		return
	var stroke := _path_stroke
	_path_stroke = null
	if not _is_coast():
		return
	var states := stroke.states(editor.get_meta(CoastData.PAINT_META, {}))
	if states[1].is_empty():
		return
	var undo := get_undo_redo()
	undo.create_action(PATH_MODES[mode_pick.selected], UndoRedo.MERGE_DISABLE, editor)
	undo.add_do_method(editor, "apply_path_state", states[1])
	undo.add_undo_method(editor, "apply_path_state", states[0])
	undo.commit_action()


func _show_coast_preview() -> void:
	if not _is_coast() or what_pick.selected < 0:
		return
	var at = _hit()
	var kind: String = PLACE_KINDS[kind_pick.selected]
	if at == null or kind not in ["Prop", "NPC", "Enemy"]:
		editor.hide_preview()
		return
	if snap_size.value > 0:
		at.x = snappedf(at.x, snap_size.value)
		at.z = snappedf(at.z, snap_size.value)
		at.y = editor.elevation(at.x, at.z)
	var placement := _new_record(kind, str(what_pick.get_item_metadata(what_pick.selected)))
	if finish_pick.visible:
		placement[1].finish = finish_pick.get_item_text(finish_pick.selected)
	editor.show_preview(placement[0], placement[1], at, turn_box.value,
		scale_min.value if kind == "Prop" else 1.0)


func _restore(state: Dictionary) -> void:
	if sculpt == null:
		return
	var chunks: Dictionary = sculpt.restore(state)
	if editor and is_instance_valid(editor):
		editor.redraw(chunks)

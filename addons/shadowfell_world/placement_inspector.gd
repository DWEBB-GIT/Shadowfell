@tool
extends EditorInspectorPlugin
## Friendly controls for placed records; metadata remains available for advanced fields.
const UI := preload("res://addons/shadowfell_data/ui.gd")
var plugin: EditorPlugin


func _can_handle(object: Object) -> bool:
	return object is Node3D and object.has_meta("record")


func _parse_begin(object: Object) -> void:
	var node := object as Node3D
	var record: Dictionary = node.get_meta("record")
	var box := VBoxContainer.new()
	UI.heading(box, "Shadowfell placement")
	var category := str(node.get_parent().name) if node.get_parent() else ""
	if category == "Houses":
		UI.note(box, "Move and turn with the 3D gizmos. Set the width and depth below. Ctrl+D copies a house; save the world to apply changes.")
	elif category in ["Buildings", "Ponds", "Puzzles"]:
		UI.note(box, "Move with the 3D gizmo. Ctrl+D copies this placement. Save the world scene to apply changes.")
	else:
		UI.note(box, "Move, rotate and scale with the 3D gizmos. Save the world scene to apply changes to the game.")
	var grid := UI.grid(box)
	if category == "Puzzles":
		UI.row(grid, "Name", UI.line(str(record.get("name", "")), func(value): _change(node, "name", value)))
		UI.row(grid, "Instruction", UI.line(str(record.get("instruction", "")), func(value): _change(node, "instruction", value)))
		var answer := PackedStringArray()
		for value in record.get("answer", []):
			answer.append(str(int(value) + 1))
		UI.row(grid, "Answer (1-based)", UI.line(", ".join(answer), func(value): _puzzle_answer(node, value)), "Dials: state numbers for each control. Sequence: control numbers in order. States and controls are in Metadata > record.")
	if category == "Houses" and record.has("size"):
		UI.row(grid, "House width", UI.spin(record.size[0], 2, 100, 0.5, func(value): _house_size(node, 0, value), " m"))
		UI.row(grid, "House depth", UI.spin(record.size[1], 2, 100, 0.5, func(value): _house_size(node, 1, value), " m"))
	if category == "Ponds" and record.has("radius") and not record.has("rx"):
		UI.row(grid, "Pond radius", UI.spin(record.radius, 2, 100, 0.5, func(value): _change(node, "radius", value), " m"))
	if record.has("id"):
		UI.row(grid, "Spawn ID", UI.line(str(record.id), func(value):
			if not value.strip_edges().is_empty():
				_change(node, "id", value.strip_edges())), "Keep existing IDs: quests and saved games may refer to them.")
	for key in ["enemy", "npc"]:
		if record.has(key):
			var choices := []
			var definitions: Dictionary = DB.enemies if key == "enemy" else DB.npcs
			for id in definitions:
				choices.append([id, "%s (%s)" % [definitions[id].get("name", id), id]])
			UI.row(grid, "Definition", UI.choice(choices, record[key], func(value): _change(node, key, value)))
	if str(node.get_parent().name) == "Props":
		UI.row(grid, "Model / scene", UI.line(str(record.get("model", "")), func(value):
			if Assets.has(value):
				_change(node, "model", value)), "A model ID or res:// path to a glTF or a Godot scene.")
		UI.row(grid, "Height offset", UI.spin(record.get("heightOffset", 0), -1000, 1000, 0.05, func(value): _change(node, "heightOffset", value), " m"))
		var tint := ColorPickerButton.new()
		tint.color = Color(record.get("tint", "ffffff"))
		tint.edit_alpha = false
		tint.color_changed.connect(func(value: Color): _change(node, "tint", value.to_html(false)))
		UI.row(grid, "Colour tint", tint, "Multiplies this instance's materials. Source models keep their original materials.")
		var collider = record.get("collider", 0)
		if collider is float or collider is int:
			UI.row(grid, "Collision radius", UI.spin(collider, 0, 100, 0.1, func(value): _change(node, "collider", value), " m"), "Before scaling; zero lets you walk through grass and plants.")
		else:
			UI.note(box, "This prop uses compound collision. Edit it under Metadata > record.")
	UI.note(box, "More settings: Metadata > record. NPC dialogue, quests and enemy definitions: Game Data.")
	add_custom_control(box)


func _puzzle_answer(node: Node3D, text: String) -> void:
	var record: Dictionary = node.get_meta("record")
	var values := []
	var limit: int = record.get("states", []).size() if record.kind == "dials" else record.nodes.size()
	for part in text.split(","):
		if not part.strip_edges().is_valid_int():
			return
		var value := int(part.strip_edges()) - 1
		if value < 0 or value >= limit:
			return
		values.append(value)
	if values.is_empty() or values.size() > 32 or (record.kind == "dials" and values.size() != record.nodes.size()):
		return
	_change(node, "answer", values)


func _house_size(node: Node3D, axis: int, value: float) -> void:
	var dimensions: Array = node.get_meta("record").size.duplicate()
	dimensions[axis] = value
	_change(node, "size", dimensions)


func _change(node: Node3D, key: String, value) -> void:
	var before: Dictionary = node.get_meta("record").duplicate(true)
	var after := before.duplicate(true)
	after[key] = value
	var undo := plugin.get_undo_redo()
	undo.create_action("Placement: " + key, UndoRedo.MERGE_ENDS, node)
	undo.add_do_method(self, "_apply_record", node, after)
	undo.add_undo_method(self, "_apply_record", node, before)
	undo.commit_action()


func _apply_record(node: Node3D, record: Dictionary) -> void:
	if not is_instance_valid(node):
		return
	var old_height: float = node.get_meta("record", {}).get("heightOffset", 0.0)
	node.set_meta("record", record.duplicate(true))
	if str(node.get_parent().name) == "Props" and not is_equal_approx(old_height, float(record.get("heightOffset", 0.0))):
		node.position.y = Terrain.height_at(node.position.x, node.position.z) + record.get("heightOffset", 0.0)
	var world := node.get_parent().get_parent()
	if world.has_method("refresh_marker"):
		world.refresh_marker(node)

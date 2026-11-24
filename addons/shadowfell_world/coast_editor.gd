@tool
extends Node3D
## The saved scene owns placements, region anchors, and sparse path paint.

const SURVEY := preload("res://game/world/lantern_coast/lantern_coast.tscn")
const DATA := preload("res://game/world/lantern_coast/placement_records.gd")
const KIT := preload("res://game/world/lantern_coast/building_kit.gd")
const BOUNDS := Rect2(-960, -544, 1920, 1120)

var preview: Node3D
var focus := Vector3.ZERO
var ghost: Node3D
var _path_ring: MeshInstance3D
var _ghost_key := ""
var _timer := 0.0


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	DB.ensure()
	preview = SURVEY.instantiate() as Node3D
	preview.name = "Coast preview"
	preview.editor_placement_mode = true
	preview.editor_path_paint = get_meta(DATA.PAINT_META, {})
	preview.hidden_scenery = get_meta(DATA.SCENERY_META, {}).duplicate()
	add_child(preview, false, Node.INTERNAL_MODE_BACK)
	load_region(0)


func load_region(index: int) -> Node3D:
	if not is_instance_valid(preview):
		return null
	var anchor := get_node("Regions").get_child(index) as Node3D
	focus = anchor.position
	ensure_ground(focus, 64)
	_update_actors()
	return anchor


func editor_view(camera: Camera3D, delta: float) -> void:
	_timer += delta
	if _timer < .12 or not is_instance_valid(preview):
		return
	_timer = 0.0
	var aim = ray_hit(camera.global_position, -camera.global_basis.z)
	if aim != null and Vector2(aim.x - focus.x, aim.z - focus.z).length() < 210.0:
		focus = aim
		preview.editor_stream(focus, false)
		_update_actors()


func ensure_ground(at: Vector3, _radius := 0.0) -> void:
	if is_instance_valid(preview):
		preview.editor_stream(at, true)


func elevation(x: float, z: float) -> float:
	return preview.land.floor_height(Vector2(x, z)) if is_instance_valid(preview) and preview.land else 0.0


func apply_path_state(changes: Dictionary) -> void:
	var current: Dictionary = get_meta(DATA.PAINT_META, {}).duplicate()
	for key in changes:
		if changes[key].is_empty():
			current.erase(key)
		else:
			current[key] = changes[key]
	if current.is_empty():
		if has_meta(DATA.PAINT_META):
			remove_meta(DATA.PAINT_META)
	else:
		set_meta(DATA.PAINT_META, current)
	preview.land.apply_path_tiles(changes)


func path_cursor(at, radius: float, erase: bool) -> void:
	if at == null:
		if is_instance_valid(_path_ring):
			_path_ring.hide()
		return
	if not is_instance_valid(_path_ring):
		_path_ring = MeshInstance3D.new()
		_path_ring.mesh = ImmediateMesh.new()
		_path_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		_path_ring.material_override = material
		add_child(_path_ring, false, Node.INTERNAL_MODE_BACK)
	var mesh := _path_ring.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var tint := Color("f27b68") if erase else Color("f8e597")
	for i in 49:
		var point := Vector2(at.x, at.z) + Vector2.from_angle(TAU * i / 48.0) * radius
		mesh.surface_set_color(tint)
		mesh.surface_add_vertex(Vector3(point.x, elevation(point.x, point.y) + .14, point.y))
	mesh.surface_end()
	_path_ring.show()


## Intersect the height field using the same sampling as the game. Editor
## picks ignore translucent water and generated foreground decorations.
func ray_hit(origin: Vector3, direction: Vector3):
	if not is_instance_valid(preview) or direction.y > -.015:
		return null
	var previous := 0.0
	var distance := 0.0
	while distance < 2400.0:
		var point := origin + direction * distance
		if BOUNDS.has_point(Vector2(point.x, point.z)) and point.y <= elevation(point.x, point.z):
			var low := previous
			var high := distance
			for i in 12:
				var middle := (low + high) * .5
				var q := origin + direction * middle
				if q.y <= elevation(q.x, q.z):
					high = middle
				else:
					low = middle
			point = origin + direction * high
			if elevation(point.x, point.z) > .12:
				return point
			return null
		previous = distance
		distance += clampf(distance * .012, .60, 5)
	return null


func make_marker(group: String, source: Dictionary) -> Node3D:
	if not DATA.GROUPS.has(group):
		return null
	var node := Node3D.new()
	var model: String = DATA.model_for(group, source)
	var label := str(source.get("label", source.get("npc", source.get("enemy", model.get_file().get_basename()))))
	if source.get("npc") == DATA.ANGLER:
		label = DATA.ANGLER_DEF.name
	node.name = label.replace("_", " ").capitalize().validate_node_name()
	node.set_meta("record", source.duplicate(true))
	var x := float(source.position[0])
	var z := float(source.position[1])
	node.position = Vector3(x, elevation(x, z) + World.height_offset(source), z)
	node.rotation_degrees.y = source.get("rotation", source.get("facing", 0.0))
	node.scale = Vector3.ONE * float(source.get("scale", 1.0))
	return node


func find_scenery(origin: Vector3, direction: Vector3) -> Dictionary:
	var at = ray_hit(origin, direction)
	var end: Vector3 = (at + direction * .20) if at != null else origin + direction * 256.0
	var natural: Dictionary = preview.dressing_stream.pick_generated_prop(origin, end)
	var landmark: Dictionary = preview.pick_landmark(origin, end)
	return natural if natural.get("distance", INF) < landmark.get("distance", INF) else landmark


func make_scenery_marker(hit: Dictionary) -> Node3D:
	if hit.has("record"):
		var record: Dictionary = hit.record.duplicate()
		record.collider = float(record.get("collider", 0.0)) / maxf(.001, record.scale)
		record.erase("scenery_id")
		return make_marker("Props", record)
	var piece: Node3D = hit.piece
	var node := Node3D.new()
	node.name = piece.name
	node.transform = piece.global_transform
	var copy := piece.duplicate(Node.DUPLICATE_GROUPS) as Node3D
	copy.transform = Transform3D.IDENTITY
	copy.remove_meta("scenery_id")
	copy.remove_meta("editable_landmark")
	_own_children(copy, copy)
	var packed := PackedScene.new()
	var result := packed.pack(copy)
	copy.free()
	if result != OK:
		node.free()
		return null
	node.set_meta("record", {"legacy_scene": packed, "label": str(piece.name)})
	return node


static func _own_children(node: Node, root: Node) -> void:
	for child in node.get_children():
		child.owner = root
		_own_children(child, root)


func set_scenery_hidden(id: String, at: Vector3, hidden: bool) -> void:
	var current: Dictionary = preview.hidden_scenery
	if hidden:
		current[id] = true
	else:
		current.erase(id)
	if current.is_empty():
		if has_meta(DATA.SCENERY_META):
			remove_meta(DATA.SCENERY_META)
	else:
		set_meta(DATA.SCENERY_META, current.duplicate())
	preview.hidden_scenery_changed(at)


func attach(node: Node3D, holder: Node) -> void:
	holder.add_child(node, true)
	node.owner = self
	refresh_marker(node)


func refresh_marker(node: Node3D) -> void:
	for child in node.get_children(true):
		if child.name == &"Placement visual":
			node.remove_child(child)
			child.queue_free()
	if not node.has_meta("record") or not node.get_parent():
		return
	var record: Dictionary = node.get_meta("record")
	var visual := _visual(str(node.get_parent().name), record)
	visual.name = "Placement visual"
	node.add_child(visual, false, Node.INTERNAL_MODE_BACK)


func _visual(group: String, record: Dictionary) -> Node3D:
	if record.get("legacy_scene") is PackedScene:
		return record.legacy_scene.instantiate() as Node3D
	var model: String = DATA.model_for(group, record)
	var buildings := preload("res://game/world/lantern_coast/settlement_building.gd")
	if group == "Props" and buildings.supported(record):
		return buildings.preview(record)
	var visual := Assets.instance(model) if not model.is_empty() else Node3D.new()
	KIT.finish(visual, str(record.get("finish", "")))
	if record.has("tint"):
		Assets.tint_instance(visual, Color(record.tint))
	if model.contains("/environment/nature/"):
		Assets.use_cutaway(visual, int(record.get("snow_cover", 0)))
	if group in ["NPCs", "Enemies"]:
		var label := Label3D.new()
		var defs: Dictionary = DB.npcs if group == "NPCs" else DB.enemies
		var id := str(record.get("npc", record.get("enemy", "")))
		label.text = str((DATA.ANGLER_DEF if id == DATA.ANGLER else defs.get(id, {})).get("name", id))
		label.font_size = 30
		label.pixel_size = .009
		label.position.y = 2.25
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("f7dc92") if group == "NPCs" else Color("eba196")
		visual.add_child(label)
	return visual


func _update_actors() -> void:
	for group in DATA.GROUPS:
		for node: Node3D in get_node(group).get_children():
			if not node.has_meta("record"):
				continue # Native drag already has a mesh.
			var shown := node.get_node_or_null("Placement visual")
			if node.position.distance_squared_to(focus) <= 138.0 * 138.0:
				if shown == null:
					refresh_marker(node)
			elif shown != null:
				node.remove_child(shown)
				shown.queue_free()


func show_preview(group: String, record: Dictionary, at: Vector3, yaw: float, size: float) -> void:
	var key := var_to_str([group, DATA.model_for(group, record), record.get("finish", "")])
	if key != _ghost_key or not is_instance_valid(ghost):
		hide_preview()
		ghost = _visual(group, record)
		ghost.name = "Placement preview"
		var parts := ghost.find_children("*", "GeometryInstance3D", true, false)
		if ghost is GeometryInstance3D:
			parts.push_front(ghost)
		for part: GeometryInstance3D in parts:
			part.transparency = .28
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ghost, false, Node.INTERNAL_MODE_BACK)
		_ghost_key = key
	ghost.position = at
	ghost.rotation_degrees.y = yaw
	ghost.scale = Vector3.ONE * size
	ghost.show()


func hide_preview() -> void:
	if is_instance_valid(ghost):
		remove_child(ghost)
		ghost.queue_free()
	ghost = null
	_ghost_key = ""

@tool
extends Node3D
## Playable survey of the Lantern Coast. Uses independent scenes and no save data.

const ATLAS := preload("atlas.tres")
const LAND := preload("land.gd")
const WALKER := preload("walker.gd")
const LANDMARKS := preload("landmarks.gd")
const WATER := preload("water.gdshader")
const CASCADE := preload("cascade.gdshader")
const DRESSING := preload("coast_dressing.gd")
const PLACEMENTS := preload("placement_records.gd")
const KIT := preload("building_kit.gd")
const BUILDINGS := preload("settlement_building.gd")
const FERRY_DOCKS := preload("ferry_docks.gd")

@export_enum("Oatwick", "Bellharbor", "Gloamwood", "Flintcut", "Reedmire",
	"Ironstep Pass", "Ashcourt Downs", "Tidemark Coast", "Redgate", "Redwash",
	"Cinder March", "Whitehorn", "Saltglass Basin", "Starfall Isles", "Crown of Ash")
var editor_preview := 0:
	set(value):
		editor_preview = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_editor.call_deferred()

@export var editor_focus_offset := Vector2.ZERO:
	set(value):
		editor_focus_offset = value
		if Engine.is_editor_hint() and is_node_ready():
			_refresh_editor.call_deferred()

var embedded_surface
var editor_placement_mode := false
var editor_path_paint: Dictionary
var hidden_scenery: Dictionary
var land: Node3D
var walker: CharacterBody3D
var hubs: Array = ATLAS.get_meta("hubs")
var routes: Array = ATLAS.get_meta("routes")
var bridges: Array = ATLAS.get_meta("bridges")
var overlooks: Array = ATLAS.get_meta("overlooks")
var footpaths: Array = ATLAS.get_meta("footpaths", [])
var dressing_stream: WorldStream
var scenery_sites: Array = []
var atmosphere: Atmosphere
var _scenery := {}
var _zone: Label
var _hint: Label
var _picker: OptionButton
var _last_safe := Vector3.ZERO
var _time := 0.0
var _authored_lamps: Array[Vector3] = []
var _placed_lamps: Array[Dictionary] = []
var _authored_lamps_added := false
var _indoor_blend := 0.0


func _ready() -> void:
	if not editor_placement_mode:
		hidden_scenery = PLACEMENTS.read_hidden_scenery()
	scenery_sites = hubs.duplicate()
	for trail in footpaths:
		var angle := 45.0 if trail.id in ["iron_shelf", "west_snowfields", "whitehorn_cirque",
			"dry_wells", "sailcloth_dunes", "veilwood"] else 0.0
		scenery_sites.append({"id": trail.id, "name": trail.name, "point": trail.at, "yaw": angle})
		if trail.has("trailhead"):
			var direction := _point(trail.points[0]).direction_to(_point(trail.points[1]))
			scenery_sites.append({"id": trail.id + "_trailhead", "name": trail.trailhead.label,
				"point": trail.trailhead.post, "yaw": rad_to_deg(atan2(-direction.y, direction.x)),
				"trail_sign": trail.trailhead.label})
	scenery_sites.append_array([
		{"id": "quarry_gate", "name": "Quarry Cut", "point": [-433.0, -174.5], "yaw": 90.0},
		{"id": "iron_gate", "name": "Ironstep Gate", "point": [-66.0, -42.0], "yaw": 45.0},
	])
	for bridge in bridges:
		if bridge.name == "Lantern Bridge":
			var axis := _point(bridge.a).direction_to(_point(bridge.b))
			var arch := _point(bridge.a) - axis * 2.0
			scenery_sites.append({"id": "lantern_bridge", "name": bridge.name,
				"point": [arch.x, arch.y], "yaw": rad_to_deg(atan2(axis.x, axis.y))})
	for fixture in ATLAS.get_meta("fixtures", []):
		var site: Dictionary = fixture.duplicate()
		site.name = str(site.id).replace("_", " ") + " lantern"
		scenery_sites.append(site)
	for passage in ATLAS.get_meta("ridge_passages", []):
		var site: Dictionary = passage.duplicate()
		site.name = "Stonecutters' Passage"
		scenery_sites.append(site)
	for i in overlooks.size():
		scenery_sites.append({"id": "reed_lookout" if i == 0 else "salt_lookout",
			"name": overlooks[i].name, "point": overlooks[i].position})
	_build_water()
	for pier in ATLAS.get_meta("piers", []) + FERRY_DOCKS.PIERS:
		add_child(LANDMARKS.pier(pier))
	if embedded_surface != null:
		land = embedded_surface.land
		add_child(land)
		_build_dressing()
		return
	if Engine.is_editor_hint():
		_refresh_editor()
		return
	_new_land()
	_build_dressing()
	var spawn := hub_spawn("oat")
	land.stream_near(spawn, true)
	walker = WALKER.new()
	walker.name = "Surveyor"
	walker.position = spawn
	add_child(walker)
	_last_safe = spawn
	_build_ui()
	_stream_scenery(spawn)


func stream_for_player(focus: Vector3, immediate := false) -> void:
	land.stream_near(focus, immediate)
	if dressing_stream != null:
		dressing_stream.update(focus)
	_stream_scenery(focus)
	if atmosphere != null and not _authored_lamps_added:
		for marker in _authored_lamps:
			atmosphere.add_coast_lamp(marker, "amber")
		for lamp in _placed_lamps:
			atmosphere.add_coast_lamp(lamp.position, lamp.style)
		_authored_lamps_added = true
	_stream_buildings(focus)


func _build_dressing() -> void:
	# The game world's prop streamer uses the same terrain height function.
	dressing_stream = WorldStream.new(self)
	dressing_stream.gentle = true
	if Engine.is_editor_hint():
		dressing_stream.hidden_props = hidden_scenery
	for prop in DRESSING.props(land, scenery_sites):
		if embedded_surface != null and embedded_surface.clear_for_building(Vector2(prop.position[0], prop.position[1]), 1.4):
			continue
		var id: String = PLACEMENTS.dressing_id(prop)
		if Engine.is_editor_hint():
			prop.scenery_id = id
		elif hidden_scenery.has(id):
			continue
		if Engine.is_editor_hint() or embedded_surface == null:
			prop.worldY = land.floor_height(Vector2(prop.position[0], prop.position[1])) + World.height_offset(prop)
		dressing_stream.add_prop(prop)
		if embedded_surface != null and prop.collider > 0.0:
			embedded_surface.register_tree(Vector2(prop.position[0], prop.position[1]), prop.collider)
	if Engine.is_editor_hint():
		return
	var records := PLACEMENTS.read()
	var edits: Array = Layout.props if embedded_surface != null else records.Props
	for prop: Dictionary in edits:
		if embedded_surface != null and BUILDINGS.supported(prop):
			continue
		dressing_stream.add_prop(prop)
		if embedded_surface != null:
			_register_placed_prop(prop)
	for prop in records.Landmarks:
		var piece: Node3D = prop.legacy_scene.instantiate()
		World.place(piece, prop)
		add_child(piece, true)
		if embedded_surface != null:
			embedded_surface.register_landmark(prop.editor_id, piece)
		for marker in piece.find_children("*", "Marker3D", true, false):
			if marker.is_in_group("coast_lamp"):
				_placed_lamps.append({"position": marker.global_position, "style": marker.get_meta("light_style", "amber")})
	if embedded_surface != null:
		for site in embedded_surface.buildings:
			for side in [-1.0, 1.0]:
				var lantern := BUILDINGS.to_world(site, Vector2(side * (site.size.w * 0.5 + 0.55), site.size.y * 0.5 + 0.55))
				_authored_lamps.append(Vector3(lantern.x, site.floor + 2.74, lantern.y))
			_authored_lamps.append(Vector3(site.center.x, site.floor + 1.8, site.center.y))


func _stream_buildings(focus: Vector3) -> void:
	if embedded_surface == null:
		return
	var point := Vector2(focus.x, focus.z)
	for site in embedded_surface.buildings:
		var distance: float = point.distance_squared_to(site.center)
		if distance <= 85.0 * 85.0 and not is_instance_valid(site.visual):
			site.visual = BUILDINGS.instantiate_site(site)
			add_child(site.visual)
		elif distance > 105.0 * 105.0 and is_instance_valid(site.visual):
			site.visual.queue_free()
			site.visual = null
			site.erase("fade")
			site.inside = 0.0


func update_buildings(player: Vector3, camera: Vector3, dt: float):
	if embedded_surface == null:
		return null
	var point := Vector2(player.x, player.z)
	var view := Vector2(camera.x, camera.z)
	var current = null
	for site in embedded_surface.buildings:
		if not is_instance_valid(site.visual):
			continue
		var inside := BUILDINGS.inside(site, point) and absf(player.y - site.floor) < 3.0
		if inside:
			current = site
		var p := BUILDINGS.local(site, point)
		var blocks_view := not inside and _occludes_near_wall(site, p, player, camera)
		var angle := BUILDINGS.local(site, view) - p
		var cut := inside or blocks_view
		World.fade_building_part(site.fade.Roof, 0.0 if cut else 1.0, dt)
		for wall in ["Street", "Rear", "East", "West"]:
			var faces_camera: bool
			match wall:
				"Street": faces_camera = angle.y >= 0.0
				"Rear": faces_camera = angle.y < 0.0
				"East": faces_camera = angle.x >= 0.0
				"West": faces_camera = angle.x < 0.0
			World.fade_building_part(site.fade[wall], 0.15 if cut and faces_camera else 1.0, dt)
		var blend := 1.0 - exp(-8.0 * dt) if dt > 0.0 else 1.0
		site.inside = lerpf(site.inside, 1.0 if inside else 0.0, blend)
	var k := 1.0 - exp(-8.0 * dt) if dt > 0.0 else 1.0
	_indoor_blend = lerpf(_indoor_blend, 0.0 if current == null else 1.0, k)
	return current


func _occludes_near_wall(site: Dictionary, p: Vector2, player: Vector3, camera: Vector3) -> bool:
	var footprint: Rect2 = site.floor_area
	if not footprint.grow(3.0).has_point(p) or camera.y <= player.y + 0.5:
		return false
	var direction := Vector2(camera.x - player.x, camera.z - player.z).rotated(site.yaw)
	var limit := minf(8.0, direction.length() * (site.size.z + 1.4) / (camera.y - player.y))
	for n in range(1, 7):
		if footprint.has_point(p + direction.normalized() * limit * float(n) / 6.0):
			return true
	return false


func roof_over(point: Vector2) -> bool:
	if embedded_surface != null:
		var site: Dictionary = embedded_surface.building_at(point)
		return not site.is_empty() and site.inside < 0.5
	return false


func _register_placed_prop(prop: Dictionary) -> void:
	var key := KIT.key(str(prop.model))
	var pose := WorldStream.placed(prop, Transform3D.IDENTITY)
	for point: Vector3 in KIT.LIGHTS.get(key, []):
		_authored_lamps.append(pose * point)
	if prop.get("noCollision", false):
		return
	var radius = prop.get("collider", KIT.CYLINDERS.get(key, World.model_collider(str(prop.model))))
	if radius is float or radius is int:
		if radius > 0.0:
			var size := maxf(pose.basis.x.length(), pose.basis.z.length())
			embedded_surface.register_tree(Vector2(pose.origin.x, pose.origin.z), radius * size)
	else:
		for box: Array in KIT.BOXES.get(key, []):
			embedded_surface.register_prop_box(pose, box)


func _new_land() -> void:
	land = LAND.new()
	land.name = "StreamedTerrain"
	land.editor_placement_collision = editor_placement_mode
	land.configure(ATLAS.get_meta("regions"), editor_path_paint if editor_placement_mode else PLACEMENTS.read_path_paint())
	add_child(land)


func _refresh_editor() -> void:
	if is_instance_valid(land):
		remove_child(land)
		land.queue_free()
	for marker in _scenery.values():
		marker.queue_free()
	_scenery.clear()
	_new_land()
	var point := _point(hubs[editor_preview].point) + editor_focus_offset
	var focus := Vector3(point.x, 0.0, point.y)
	land.stream_near(focus, true)
	_stream_scenery(focus)


func editor_stream(focus: Vector3, immediate: bool) -> void:
	if dressing_stream == null:
		_build_dressing()
	land.stream_near(focus, immediate)
	dressing_stream.update(focus, false, 4.0)
	_stream_scenery(focus)


func hidden_scenery_changed(at: Vector3) -> void:
	if dressing_stream != null:
		dressing_stream.rebuild_prop_cell(at)
	for id in _scenery:
		_apply_landmark_edits(id, _scenery[id])


func _apply_landmark_edits(id: String, landmark: Node3D) -> void:
	for piece: Node3D in landmark.get_children():
		if not piece.has_meta("editable_landmark"):
			continue
		var scenery_id := "landmark:" + id + "/" + str(piece.name)
		piece.set_meta("scenery_id", scenery_id)
		var hidden := hidden_scenery.has(scenery_id)
		if Engine.is_editor_hint():
			piece.visible = not hidden
		elif hidden:
			landmark.remove_child(piece)
			piece.queue_free()


func pick_landmark(origin: Vector3, end: Vector3) -> Dictionary:
	var best := origin.distance_squared_to(end)
	var hit := {}
	for landmark: Node3D in _scenery.values():
		for piece: Node3D in landmark.get_children():
			if not piece.has_meta("scenery_id") or not piece.visible:
				continue
			for model: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
				if model.mesh == null:
					continue
				var distance := WorldStream.mesh_hit_squared(model.mesh, model.global_transform, origin, end)
				if distance < best:
					best = distance
					hit = {"id": piece.get_meta("scenery_id"), "piece": piece, "distance": distance}
	return hit


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(3100, 2300)
	var sea := _water_mesh("Sea", plane, WATER, Vector3.UP * 0.11)
	sea.sorting_offset = -12.0
	var sea_material: ShaderMaterial = sea.material_override
	sea_material.set_shader_parameter("water_field", load("res://game/world/lantern_coast/water_field.png"))
	var bounds: Array = ATLAS.get_meta("terrain_bounds", [-960, -544, 960, 576])
	# The bake includes two shared height samples at each edge.
	sea_material.set_shader_parameter("field_bounds", Vector4(bounds[0] - 5.0, bounds[1] - 5.0,
		bounds[2] - bounds[0] + 10.0, bounds[3] - bounds[1] + 10.0))
	for spot in ATLAS.get_meta("fishing", []):
		if spot.id == "lc_pirate_cove":
			sea_material.set_shader_parameter("sandy_bay", _point(spot.position))
	for spring in ATLAS.get_meta("springs", []):
		var surface := WaterAndDark.flat_ring(0.0, 1.12, 28)
		var pool := _water_mesh("Spring", surface, WATER,
			Vector3(spring.point[0], spring.level, spring.point[1]))
		pool.material_override.set_shader_parameter("raised_pool", true)
		pool.sorting_offset = -2.0
		pool.scale = Vector3(spring.size[0], 1.0, spring.size[1])
	for fall in ATLAS.get_meta("falls", []):
		_build_cascade(fall)


func _water_mesh(label: String, mesh: Mesh, shader: Shader, at: Vector3) -> MeshInstance3D:
	var material := ShaderMaterial.new()
	material.shader = shader
	if shader == WATER:
		material.set_shader_parameter("ripple_detail", load("res://game/world/lantern_coast/terrain_accents.png"))
	var surface := MeshInstance3D.new()
	surface.name = label
	surface.mesh = mesh
	surface.material_override = material
	surface.position = at
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(surface)
	return surface


func _build_cascade(fall: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array = fall.points
	var sections: Array[Vector3] = []
	for p in points:
		sections.append(Vector3(p[0], p[2] + 0.045, p[1]))
	var sides: Array[Vector3] = []
	for i in sections.size():
		var axis := sections[mini(i + 1, sections.size() - 1)] - sections[maxi(i - 1, 0)]
		var width: float = fall.half * (0.82 if i < sections.size() - 1 else 0.62)
		sides.append(Vector3(-axis.z, 0, axis.x).normalized() * width)
	var length := 0.0
	for i in range(1, sections.size()):
		var a := sections[i - 1]
		var b := sections[i]
		var next := length + a.distance_to(b)
		var vertices := [a-sides[i - 1], a+sides[i - 1], b-sides[i], b+sides[i]]
		var uvs := [Vector2(0, length), Vector2(1, length), Vector2(0, next), Vector2(1, next)]
		for j in [0, 1, 2, 1, 3, 2]:
			st.set_uv(uvs[j])
			st.add_vertex(vertices[j])
		length = next
	st.index()
	st.generate_normals()
	var cascade := _water_mesh("BrackenFalls", st.commit(), CASCADE, Vector3.ZERO)
	cascade.material_override.set_shader_parameter("run_length", length)


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(walker):
		return
	_time += delta
	if _time < 0.075:
		return
	_time = 0.0
	var p := walker.global_position
	land.stream_near(p)
	_stream_scenery(p)
	_update_ui(p)


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(walker):
		return
	if walker.position.y < 0.10:
		# The survey has no swimming. The last dry footing stays loaded.
		walker.warp_to(_last_safe + Vector3.UP * 0.15)
	elif walker.is_on_floor() and walker.position.y > 0.65:
		_last_safe = walker.position


func _stream_scenery(focus: Vector3) -> void:
	var centre := Vector2(focus.x, focus.z)
	for hub in scenery_sites:
		var id: String = hub.id
		var p := _point(hub.point)
		var distance := p.distance_to(centre)
		if distance <= 96.0 and not _scenery.has(id):
			var landmark: Node3D
			if hub.has("length"):
				landmark = LANDMARKS.ridge_passage(hub.length, hub.clear_width)
			elif hub.has("trail_sign"):
				landmark = LANDMARKS.trail_sign(hub.trail_sign)
			elif hub.has("light"):
				landmark = LANDMARKS.route_lamp(hub.light)
			else:
				landmark = LANDMARKS.build(id, embedded_surface != null or editor_placement_mode)
			landmark.name = str(hub.name).split(" · ")[0].to_pascal_case()
			landmark.position = Vector3(p.x, land.floor_height(p), p.y)
			landmark.rotation_degrees.y = hub.get("yaw", 0.0)
			LANDMARKS.ground_detail(landmark, id, land)
			_apply_landmark_edits(id, landmark)
			add_child(landmark)
			_scenery[id] = landmark
			if embedded_surface != null:
				embedded_surface.register_landmark(id, landmark)
				if atmosphere != null:
					for marker in landmark.find_children("*", "Marker3D", true, false):
						if marker.is_in_group("coast_lamp"):
							atmosphere.add_coast_lamp(marker.global_position, marker.get_meta("light_style", "amber"))
		elif distance > 128.0 and _scenery.has(id):
			_scenery[id].queue_free()
			_scenery.erase(id)
	for lookout in overlooks:
		var id: String = lookout.name
		var p := _point(lookout.position)
		var distance := p.distance_to(centre)
		if distance <= 96.0 and not _scenery.has(id):
			var sign := Label3D.new()
			sign.name = id.to_pascal_case()
			sign.text = id
			sign.font_size = 42
			sign.pixel_size = 0.008
			sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			sign.modulate = Color("ffe5ab")
			sign.position = Vector3(p.x, land.floor_height(p) + 2.1, p.y)
			add_child(sign)
			_scenery[id] = sign
		elif distance > 128.0 and _scenery.has(id):
			_scenery[id].queue_free()
			_scenery.erase(id)


func hub_spawn(id: String) -> Vector3:
	for hub in hubs:
		if hub.id == id:
			var p := _point(hub.point)
			return Vector3(p.x, land.floor_height(p) + 0.08, p.y)
	return Vector3.ZERO


func relocate(p: Vector3) -> void:
	land.stream_near(p, true)
	if dressing_stream != null:
		dressing_stream.update(p)
	_stream_scenery(p)
	walker.warp_to(p)
	_last_safe = p


func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


func _nearest_hub(p: Vector3) -> Dictionary:
	var best: Dictionary = hubs[0]
	var distance := INF
	for hub in hubs:
		var d := Vector2(p.x, p.z).distance_squared_to(_point(hub.point))
		if d < distance:
			distance = d
			best = hub
	return best


func _ferry_here(p: Vector3) -> String:
	var hub := _nearest_hub(p)
	if Vector2(p.x, p.z).distance_to(_point(hub.point)) > 20.0:
		return ""
	if hub.id == "tide" or hub.id == "salt":
		return "star"
	if hub.id == "star":
		return "salt"
	return ""


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(walker):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			var destination := _ferry_here(walker.position)
			if not destination.is_empty():
				relocate(hub_spawn(destination))
				get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F and _ferry_here(walker.position) == "salt":
			relocate(hub_spawn("tide"))
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R:
			relocate(hub_spawn(str(_nearest_hub(walker.position).id)))
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var border := MarginContainer.new()
	border.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "top", "right"]:
		border.add_theme_constant_override("margin_" + side, 22)
	ui.add_child(border)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(row)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_zone = Label.new()
	_zone.add_theme_font_size_override("font_size", 24)
	_zone.add_theme_color_override("font_color", Color("fff0cc"))
	_zone.add_theme_constant_override("outline_size", 6)
	words.add_child(_zone)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color("e0dccb"))
	_hint.add_theme_constant_override("outline_size", 5)
	words.add_child(_hint)
	var preview_note := Label.new()
	preview_note.text = "Terrain preview. Press F5 and choose Lantern Coast for combat and quests."
	preview_note.add_theme_color_override("font_color", Color("bdc7ce"))
	preview_note.add_theme_constant_override("outline_size", 5)
	words.add_child(preview_note)
	_picker = OptionButton.new()
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_picker.add_item("Survey a region")
	for hub in hubs:
		_picker.add_item(hub.name)
	for lookout in overlooks:
		_picker.add_item(lookout.name)
	_picker.item_selected.connect(func(index: int):
		if index > 0 and index <= hubs.size():
			relocate(hub_spawn(hubs[index - 1].id))
		elif index > hubs.size():
			var p := _point(overlooks[index - hubs.size() - 1].position)
			relocate(Vector3(p.x, land.floor_height(p) + 0.08, p.y))
		_picker.select(0))
	row.add_child(_picker)
	_update_ui(walker.position)


func _update_ui(p: Vector3) -> void:
	_zone.text = _nearest_hub(p).name
	var ferry := _ferry_here(p)
	if ferry == "salt":
		_hint.text = "E  Ferry to Saltglass   ·   F  Ferry to Tidemark"
	elif not ferry.is_empty():
		_hint.text = "E  Take the ferry   ·   WASD  Walk   ·   Space  Jump"
	else:
		_hint.text = "WASD  Walk   ·   Space  Jump   ·   R  Return to nearby hub"

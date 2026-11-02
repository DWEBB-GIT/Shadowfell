@tool
extends Node3D
## The World editor: open world_editor.tscn and the world from data/world/world.json
## and data/world/scenery.json is laid out in the 3D view, on the real terrain.
## Move and turn things with the usual gizmos, Ctrl+D to place another,
## Delete to remove one, then save the scene (Ctrl+S): positions, turns and
## scales are written back to the JSON files, which both builds read. The
## scene file itself stays empty; the data files are the world.
##
## Height is not saved: everything stands on the ground, as in the game.
##
## Open it from the "World" dock (beside the Scene tree), which also holds the brushes to sculpt
## the ground (the World tools plugin, addons/shadowfell_world); Ctrl+S then
## also saves the sculpted ground.

const IO := preload("json_io.gd")

const WORLD := "res://data/world/world.json"
const SCENERY := "res://data/world/scenery.json"

## Each group: the file and list it edits, the key its turn is saved under
## (degrees, or radians for trees), whether it keeps a scale, and its label.
const GROUPS := [
	{"name": "Chests", "file": "world", "list": "chests", "turn": "facing"},
	{"name": "Props", "file": "scenery", "list": "props", "turn": "rotation", "scale": "scale"},
	{"name": "Loot", "file": "world", "list": "placedLoot", "scale": "scale"},
	{"name": "NPCs", "file": "world", "list": "npcSpawns", "turn": "facing"},
	{"name": "Enemies", "file": "world", "list": "enemySpawns"},
	{"name": "Shrines", "file": "world", "list": "shrines", "turn": "rotation"},
	{"name": "Signposts", "file": "world", "list": "signposts"},
	{"name": "Houses", "file": "world", "list": "houses", "turn": "rotation"},
	{"name": "Buildings", "file": "world", "list": "buildings"},
	{"name": "Ponds", "file": "world", "list": "water"},
	{"name": "Puzzles", "file": "world", "list": "puzzles"},
]

var _files := {}
var _owned: Array[Node] = []
var _ground: Node3D
var _chunks := {} ## Vector2i -> the ground chunk drawn there
var _ground_mat: Material
var _brush: MeshInstance3D
var sculpt: RefCounted ## addons/shadowfell_world/sculpt.gd, made by the World tools plugin
var _paths := {}
var _baseline := {}
var _map := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild()


## Lay the world out again from the data files (also after a save, so what
## you see is what was written).
func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	DB.ready = false
	DB.ensure()
	_map = Terrain.chosen_map()
	_paths = {"world": Terrain.dir + "spawns.json" if Terrain.is_new_map() else WORLD,
		"scenery": Terrain.dir + "scenery.json" if Terrain.is_new_map() else SCENERY}
	_files = {}
	for file in _paths:
		_files[file] = IO.load_file(_paths[file]) if FileAccess.file_exists(_paths[file]) else {}
	if _files.world == null or _files.scenery == null:
		push_error("World editor: cannot read the data files")
		return
	_baseline = _files.duplicate(true)
	_ground = Node3D.new()
	_ground.name = "Terrain"
	add_child(_ground) # not owned: it cannot be picked or saved
	_chunks.clear()
	_ground_mat = Land.ground_material()
	var start: Array = DB.world.playerStart.position
	ensure_ground(Vector3(start[0], 0, start[1]))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	add_child(sun)
	for g in GROUPS:
		var holder := Node3D.new()
		holder.name = g.name
		add_child(holder)
		_own(holder)
		var list: Array = _files[g.file].get(g.list, [])
		for i in list.size():
			holder.add_child(_marker(g, list[i], i))
			_own(holder.get_child(-1))
			ensure_ground(holder.get_child(-1).position, 32.0)
	if Terrain.is_new_map():
		_add_sea()


## The new map (Dan, 2026-10-28): just its ground, all of it, to sculpt.
## Nothing from world.json is on it, and saving writes only the ground.
func _add_sea() -> void:
	var b: Dictionary = DB.world.bounds
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(b.maxX - b.minX + 800, b.maxZ - b.minZ + 800)
	sea.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.35, 0.6, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sea.material_override = mat
	sea.position = Vector3((b.minX + b.maxX) / 2, DB.water.get("sea", 0.0), (b.minZ + b.maxZ) / 2)
	add_child(sea)


func _draw_chunk(k: Vector2i) -> void:
	if _chunks.has(k) and is_instance_valid(_chunks[k]):
		_chunks[k].free()
	var g := Land.chunk_ground(k, _ground_mat)
	_ground.add_child(g)
	_chunks[k] = g


## Draw the ground within `radius` of a point too (sculpting far from
## anything placed).
func ensure_ground(at: Vector3, radius := 160.0) -> void:
	if _ground == null:
		return
	for i in range(floori((at.x - radius) / Land.CHUNK), floori((at.x + radius) / Land.CHUNK) + 1):
		for j in range(floori((at.z - radius) / Land.CHUNK), floori((at.z + radius) / Land.CHUNK) + 1):
			if not _chunks.has(Vector2i(i, j)):
				_draw_chunk(Vector2i(i, j))


## Draw these chunks again (after a brush stroke), and stand what is placed
## on them back on the ground.
func redraw(chunks: Dictionary) -> void:
	if _ground == null:
		return
	for k in chunks:
		if _chunks.has(k):
			_draw_chunk(k)
	for g in GROUPS:
		var holder := get_node_or_null(NodePath(g.name))
		if holder == null:
			continue
		for n in holder.get_children():
			if n is Node3D and chunks.has(Vector2i(floori(n.position.x / Land.CHUNK), floori(n.position.z / Land.CHUNK))):
				var record: Dictionary = n.get_meta("record", {})
				n.position.y = Terrain.water_level(record) if g.list == "water" else Terrain.height_at(n.position.x, n.position.z) + float(record.get("heightOffset", 0.0))


func capture_height_offsets() -> void:
	var props := get_node_or_null("Props")
	if props == null:
		return
	for node in props.get_children():
		if node is Node3D and node.has_meta("record"):
			var record: Dictionary = node.get_meta("record").duplicate(true)
			var offset := snappedf(node.position.y - Terrain.height_at(node.position.x, node.position.z), 0.01)
			if not is_zero_approx(offset) or record.has("heightOffset"):
				record.heightOffset = offset
				node.set_meta("record", record)


## The brush's ring on the ground, or hidden with `radius` 0.
func show_brush(at: Vector3, radius: float, color := Color(1, 0.85, 0.3)) -> void:
	if _brush == null or not is_instance_valid(_brush):
		_brush = MeshInstance3D.new()
		_brush.name = "Brush"
		_brush.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.vertex_color_use_as_albedo = true
		_brush.material_override = m
		add_child(_brush) # not owned
	_brush.visible = radius > 0
	if radius <= 0:
		return
	var im: ImmediateMesh = _brush.mesh
	im.clear_surfaces()
	for r in [radius, radius * 0.5]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 49:
			var t := TAU * i / 48.0
			var x: float = at.x + cos(t) * r
			var z: float = at.z + sin(t) * r
			im.surface_set_color(color if r == radius else color.darkened(0.3))
			im.surface_add_vertex(Vector3(x, Terrain.height_at(x, z) + 0.3, z))
		im.surface_end()


## A new thing for the group named `group` (NPCs, Enemies, ...) from a
## record, not yet in the scene (the World dock's Place adds it with attach).
func make_marker(group: String, r: Dictionary) -> Node3D:
	for g in GROUPS:
		if g.name == group:
			var holder := get_node_or_null(NodePath(group))
			return _marker(g, r, holder.get_child_count() if holder else 0)
	return null


func attach(n: Node3D, holder: Node) -> void:
	holder.add_child(n, true)
	_own(n)


func _own(n: Node) -> void:
	var root := get_tree().edited_scene_root if is_inside_tree() else null
	n.owner = root if root else self


## One thing in the world: a node holding its model, with the record it came
## from kept as metadata (copied with Ctrl+D).
func _marker(g: Dictionary, r: Dictionary, i: int) -> Node3D:
	var n := Node3D.new()
	n.name = _label(g, r, i)
	n.set_meta("record", r.duplicate(true))
	var x: float = r.x if g.list == "trees" else r.position[0]
	var z: float = r.z if g.list == "trees" else r.position[1]
	n.position = Vector3(x, Terrain.height_at(x, z) + r.get("heightOffset", 0.0), z)
	if g.has("turn"):
		var t: float = r.get(g.turn, 0.0)
		n.rotation.y = t if g.get("radians") else deg_to_rad(t)
	if g.has("scale") and r.has(g.scale):
		n.scale = Vector3.ONE * float(r[g.scale])
	if g.list == "props":
		if r.has("scale3"):
			n.scale = Vector3(r.scale3[0], r.scale3[1], r.scale3[2])
		if r.has("rotation3"):
			n.rotation_degrees = Vector3(r.rotation3[0], r.rotation3[1], r.rotation3[2])
		elif r.get("tilt"):
			n.rotation.z = -deg_to_rad(r.tilt)
	var model := _model(g, r)
	if g.list == "puzzles":
		n.add_child(WorldPuzzles.visual(r))
	elif g.list == "houses":
		var house := Town.house_visual(r)
		var material := ShaderMaterial.new()
		material.shader = SeeThrough.FLAT
		material.set_shader_parameter("albedo", Color.WHITE)
		house.material_override = material
		n.add_child(house)
	elif g.list == "buildings":
		for part in ["shell", "front", "roof"]:
			var piece := Assets.instance(r[part])
			piece.position.y = -0.1
			n.add_child(piece)
	elif g.list == "water":
		n.position.y = Terrain.water_level(r)
		var water := MeshInstance3D.new()
		water.mesh = WaterAndDark.flat_ring(0, 1, 48)
		water.scale = Vector3(r.get("rx", r.radius), 1, r.get("rz", r.radius))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(r.get("color", "#416e78"))
		mat.roughness = 0.3
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		water.material_override = mat
		n.add_child(water)
	if model != "":
		var m := Assets.instance(model)
		if g.list == "trees":
			m.position.y = -0.1
		if g.list != "props" and r.get("tilt"):
			m.rotation.z = -deg_to_rad(r.tilt)
		if r.has("tint"):
			Assets.tint_instance(m, Color(r.tint))
		n.add_child(m)
	return n


## Refresh an Inspector edit without changing its placement or selection.
func refresh_marker(n: Node3D) -> void:
	var fresh := make_marker(str(n.get_parent().name), n.get_meta("record"))
	if fresh == null:
		return
	for child in n.get_children():
		n.remove_child(child)
		child.queue_free()
	for child in fresh.get_children():
		fresh.remove_child(child)
		n.add_child(child)
	fresh.free()


static func _label(g: Dictionary, r: Dictionary, i: int) -> String:
	var what = r.get("id", r.get("npc", r.get("model", "")))
	if str(what).begins_with("res://"):
		what = str(what).get_file().get_basename()
	return ("%s %d" % [what, i + 1]) if g.list in ["props", "trees"] else str(what)


static func _model(g: Dictionary, r: Dictionary) -> String:
	match g.list:
		"chests":
			return "chest"
		"shrines":
			return "shrine"
		"signposts":
			return "signpost"
		"npcSpawns":
			return DB.npcs.get(r.npc, {}).get("model", "")
		"enemySpawns":
			return DB.enemies.get(r.enemy, {}).get("model", "")
	return r.get("model", "")


## Ctrl+S: the scene's children are written to the data files, then left out
## of the .tscn (unowned while it saves).
func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		save_world()
		_owned = []
		for n in find_children("*", "", true, true):
			if n.owner:
				_owned.append(n)
				n.owner = null
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		for n in _owned:
			if is_instance_valid(n):
				n.owner = self
		_owned = []


## The world as it stands in the scene, back into world.json and
## scenery.json. Returns the files written.
func save_world() -> PackedStringArray:
	var saved := PackedStringArray()
	if _map != Terrain.chosen_map():
		_save_error("this scene belongs to another map. Reopen it before saving.")
		return saved
	# Merge unrelated changes; refuse to overwrite another editor's placements.
	var next := _files.duplicate(true)
	for file in _paths:
		var disk = IO.load_file(_paths[file]) if FileAccess.file_exists(_paths[file]) else {}
		if not disk is Dictionary:
			_save_error("cannot read " + str(_paths[file]))
			return saved
		for g in GROUPS:
			if g.file == file and not IO.same(disk.get(g.list, []), _baseline[file].get(g.list, [])):
				_save_error("%s changed on disk. Reopen the world before saving; your scene is still open." % g.list)
				return saved
		next[file] = disk
	if sculpt and sculpt.dirty:
		var err: Error = sculpt.save()
		if err != OK:
			_save_error("cannot save the sculpted ground (%s)" % error_string(err))
			return saved
		else:
			saved.append(Terrain.dir.trim_prefix("res://") + "sculpt.json, world.bin")
	for g in GROUPS:
		var holder := get_node_or_null(NodePath(g.name))
		if holder == null:
			continue
		var out := []
		var ids := {}
		for n in holder.get_children():
			if not n.has_meta("record"):
				continue
			out.append(_record(g, n, ids))
		if not IO.same(out, _baseline[g.file].get(g.list, [])):
			next[g.file][g.list] = out
	for f in next:
		var path: String = _paths[f]
		if IO.same(next[f], _baseline[f]):
			continue
		var err := IO.save_file(path, next[f])
		if err != OK:
			_save_error("cannot write %s (%s)" % [path, error_string(err)])
		else:
			saved.append(path.get_file())
			_files[f] = next[f]
			_baseline[f] = next[f].duplicate(true)
			for g in GROUPS:
				if g.file != f:
					continue
				var holder := get_node_or_null(NodePath(g.name))
				if holder == null:
					continue
				var records: Array = next[f].get(g.list, [])
				var index := 0
				for child in holder.get_children():
					if child.has_meta("record") and index < records.size():
						child.set_meta("record", records[index].duplicate(true))
						index += 1
	if saved.size():
		print("World editor: saved ", ", ".join(saved))
		DB.ready = false
	return saved


func _save_error(message: String) -> void:
	push_error("World editor: " + message)
	if Engine.is_editor_hint():
		_mark_unsaved.call_deferred()


func _mark_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()


func has_unsaved_changes() -> bool:
	if sculpt and sculpt.dirty:
		return true
	for g in GROUPS:
		var holder := get_node_or_null(NodePath(g.name))
		if holder == null:
			continue
		var records := []
		var ids := {}
		for child in holder.get_children():
			if child.has_meta("record"):
				records.append(_record(g, child, ids))
		if not IO.same(records, _baseline.get(g.file, {}).get(g.list, [])):
			return true
	return false


## A node's record with where it now stands; a copy (Ctrl+D) gets an id of
## its own.
static func _record(g: Dictionary, n: Node3D, ids: Dictionary) -> Dictionary:
	var r: Dictionary = n.get_meta("record").duplicate(true)
	# to the centimetre, written as typed (4.6, not 4.6000000000000005)
	var x := String.num(n.position.x, 2).to_float()
	var z := String.num(n.position.z, 2).to_float()
	if g.list == "trees":
		r.x = x
		r.z = z
	else:
		r.position = [x, z]
	if g.has("turn") and not (g.list == "props" and r.has("rotation3")):
		# an unturned thing keeps the number it had (270 stays 270, not -90)
		var was: float = r.get(g.turn, 0.0)
		var t := n.rotation.y
		if absf(angle_difference(was if g.get("radians") else deg_to_rad(was), t)) > 0.0005:
			t = wrapf(t, -PI, PI)
			r[g.turn] = String.num(t, 3).to_float() if g.get("radians") else String.num(rad_to_deg(t), 1).to_float()
	if g.has("scale"):
		var s := String.num(n.scale.x, 2).to_float()
		var expected: float = r.scale3[0] if g.list == "props" and r.has("scale3") else float(r.get(g.scale, 1.0))
		# Preserve authored precision until a gizmo actually changes the scale.
		if not is_equal_approx(n.scale.x, expected):
			r[g.scale] = s
	if g.list == "props":
		var offset := snappedf(n.position.y - Terrain.height_at(x, z), 0.01)
		if not is_zero_approx(offset) or r.has("heightOffset"):
			r.heightOffset = offset
		var expected_scale: Vector3 = Vector3(r.scale3[0], r.scale3[1], r.scale3[2]) if r.has("scale3") else Vector3.ONE * r.get("scale", 1.0)
		if not n.scale.is_equal_approx(expected_scale) and (not n.scale.is_equal_approx(Vector3.ONE * n.scale.x) or r.has("scale3")):
			r.scale3 = [snappedf(n.scale.x, 0.01), snappedf(n.scale.y, 0.01), snappedf(n.scale.z, 0.01)]
		var expected_rotation := Vector3(0, deg_to_rad(r.get("rotation", 0.0)), -deg_to_rad(r.get("tilt", 0.0)))
		if r.has("rotation3"):
			expected_rotation = Vector3(r.rotation3[0], r.rotation3[1], r.rotation3[2]) * PI / 180.0
		var same_rotation := absf(n.quaternion.dot(Quaternion.from_euler(expected_rotation))) > 0.999999
		if not same_rotation:
			r.rotation3 = [snappedf(n.rotation_degrees.x, 0.1), snappedf(n.rotation_degrees.y, 0.1), snappedf(n.rotation_degrees.z, 0.1)]
			r.erase("tilt")
	if r.has("id"):
		var base: String = r.id
		var k := 2
		while ids.has(r.id):
			r.id = "%s_%d" % [base, k]
			k += 1
		ids[r.id] = true
	return r


func _exit_tree() -> void:
	RenderCleanup.detach(self)

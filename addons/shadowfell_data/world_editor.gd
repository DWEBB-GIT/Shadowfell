@tool
extends Node3D
## The World editor: open world_editor.tscn and the world from data/world.json
## and data/scenery.json is laid out in the 3D view, on the real terrain.
## Move and turn things with the usual gizmos, Ctrl+D to place another,
## Delete to remove one, then save the scene (Ctrl+S): positions, turns and
## scales are written back to the JSON files, which both builds read. The
## scene file itself stays empty; the data files are the world.
##
## Height is not saved: everything stands on the ground, as in the game.
##
## Select this root node and pick a brush on the 3D view's toolbar to sculpt
## the ground (the World tools plugin, addons/shadowfell_world); Ctrl+S then
## also saves the sculpted ground.

const IO := preload("json_io.gd")

const WORLD := "res://data/world.json"
const SCENERY := "res://data/scenery.json"

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
]

var _files := {}
var _owned: Array[Node] = []
var _ground: Node3D
var _chunks := {} ## Vector2i -> the ground chunk drawn there
var _ground_mat: Material
var _brush: MeshInstance3D
var sculpt: RefCounted ## addons/shadowfell_world/sculpt.gd, made by the World tools plugin


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
	_files = {"world": IO.load_file(WORLD), "scenery": IO.load_file(SCENERY)}
	if _files.world == null or _files.scenery == null:
		push_error("World editor: cannot read the data files")
		return
	# the ground under everything placed (the whole world is too big to show)
	var lo := Vector2(INF, INF)
	var hi := -lo
	for g in GROUPS:
		for r in _files[g.file].get(g.list, []):
			var p := Vector2(r.position[0], r.position[1])
			lo = lo.min(p)
			hi = hi.max(p)
	_ground = Node3D.new()
	_ground.name = "Terrain"
	add_child(_ground) # not owned: it cannot be picked or saved
	_chunks.clear()
	_ground_mat = Land.ground_material()
	for i in range(floori((lo.x - 40) / Land.CHUNK), floori((hi.x + 40) / Land.CHUNK) + 1):
		for j in range(floori((lo.y - 40) / Land.CHUNK), floori((hi.y + 40) / Land.CHUNK) + 1):
			_draw_chunk(Vector2i(i, j))
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
				n.position.y = Terrain.height_at(n.position.x, n.position.z)


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
			var x := at.x + cos(t) * r
			var z := at.z + sin(t) * r
			im.surface_set_color(color if r == radius else color.darkened(0.3))
			im.surface_add_vertex(Vector3(x, Terrain.height_at(x, z) + 0.3, z))
		im.surface_end()


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
	n.position = Vector3(x, Terrain.height_at(x, z), z)
	if g.has("turn"):
		var t: float = r.get(g.turn, 0.0)
		n.rotation.y = t if g.get("radians") else deg_to_rad(t)
	if g.has("scale") and r.has(g.scale):
		n.scale = Vector3.ONE * float(r[g.scale])
	var model := _model(g, r)
	if model != "":
		var m := Assets.instance(model)
		if g.list == "trees":
			m.position.y = -0.1
		if r.get("tilt"):
			m.rotation.z = -deg_to_rad(r.tilt)
		n.add_child(m)
	return n


static func _label(g: Dictionary, r: Dictionary, i: int) -> String:
	var what = r.get("id", r.get("npc", r.get("model", "")))
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
	if _files.is_empty():
		return []
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
		_files[g.file][g.list] = out
	var saved := PackedStringArray()
	if sculpt and sculpt.dirty:
		var err: Error = sculpt.save()
		if err != OK:
			push_error("World editor: cannot save the sculpted ground (%s)" % error_string(err))
		else:
			saved.append("sculpt.json, world.bin")
	for f in _files:
		var path: String = WORLD if f == "world" else SCENERY
		if IO.to_text(_files[f], false, true) == FileAccess.get_file_as_string(path):
			continue
		var err := IO.save_file(path, _files[f])
		if err != OK:
			push_error("World editor: cannot write %s (%s)" % [path, error_string(err)])
		else:
			saved.append(path.get_file())
	if saved.size():
		print("World editor: saved ", ", ".join(saved))
		DB.ready = false
	return saved


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
	if g.has("turn"):
		# an unturned thing keeps the number it had (270 stays 270, not -90)
		var was: float = r.get(g.turn, 0.0)
		var t := n.rotation.y
		if absf(angle_difference(was if g.get("radians") else deg_to_rad(was), t)) > 0.0005:
			t = wrapf(t, -PI, PI)
			r[g.turn] = String.num(t, 3).to_float() if g.get("radians") else String.num(rad_to_deg(t), 1).to_float()
	if g.has("scale"):
		var s := String.num(n.scale.x, 2).to_float()
		if not is_equal_approx(s, float(r.get(g.scale, 1.0))):
			r[g.scale] = s
	if r.has("id"):
		var base: String = r.id
		var k := 2
		while ids.has(r.id):
			r.id = "%s_%d" % [base, k]
			k += 1
		ids[r.id] = true
	return r

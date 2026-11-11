class_name Highlight
extends RefCounted
## Brightens whatever the mouse is over, and whatever is selected, so drops,
## nodes, bodies and people stand out (Dan, 2026-11-11). A soft additive
## overlay on every mesh of the thing; the old overlay comes back after.

const HOVER := Color(1.0, 0.95, 0.8, 0.22)
const SELECTED := Color(1.0, 0.95, 0.8, 0.14)

var game
var _mat_hover: StandardMaterial3D
var _mat_sel: StandardMaterial3D
var _lit := {} ## Node3D -> material put on it
var _saved := {} ## GeometryInstance3D -> its own overlay


func _init(g) -> void:
	game = g
	_mat_hover = _make(HOVER)
	_mat_sel = _make(SELECTED)


static func _make(c: Color) -> StandardMaterial3D:
	var m := Tex.fx_material(null, c)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## the visible node of a picked thing ({kind, obj}), or null
func visual(pick) -> Node3D:
	var n = _visual(pick)
	return n if is_instance_valid(n) and n.is_inside_tree() else null


func _visual(pick):
	if pick == null or not is_instance_valid(pick.obj) and typeof(pick.obj) == TYPE_OBJECT:
		return null
	var o = pick.obj
	match pick.kind:
		"enemy", "npc", "chest":
			return o.get("group")
		"vein", "herb":
			return o.get("node")
		"loot":
			if o.kind == "item":
				return o.entry.get("group")
			var e = game.enemies.by_id(o.id)
			return e.get("group") if e != null else null
	return null


## call each frame with the hover pick (or null) and the selected enemy
func update(hover, selected) -> void:
	var want := {}
	var s = visual({"kind": "enemy", "obj": selected}) if selected != null else null
	if is_instance_valid(s):
		want[s] = _mat_sel
	var h = visual(hover)
	if is_instance_valid(h):
		want[h] = _mat_hover
	for n in _lit.keys():
		if not is_instance_valid(n):
			_lit.erase(n)
		elif not want.has(n) or want[n] != _lit[n]:
			_unlight(n)
	for n in want:
		if not _lit.has(n):
			_light(n, want[n])


## lit: the thing is drawn unshaded (full brightness, no shadow or night),
## each surface swapped for an unlit copy of its own material; shader
## materials that can't be copied get the bright overlay instead
var _unlit := {} ## original material -> its unlit copy
var _saved_surf := {} ## GeometryInstance3D -> [surface overrides]


func _unlit_of(m: Material) -> Material:
	# browser: every unlit copy is a new shader to compile mid-game (a frame
	# hitch per new thing hovered), so the web keeps the overlay only
	if OS.has_feature("web") or not (m is BaseMaterial3D):
		return null
	if not _unlit.has(m):
		var c: BaseMaterial3D = m.duplicate()
		c.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		c.albedo_color = c.albedo_color.lightened(0.08)
		_unlit[m] = c
	return _unlit[m]


func _light(root: Node3D, mat: Material) -> void:
	_lit[root] = mat
	var full := mat == _mat_hover
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			if not _saved.has(n):
				_saved[n] = n.material_overlay
			var swapped := false
			if full:
				var keep := []
				for i in n.mesh.get_surface_count():
					keep.append(n.get_surface_override_material(i))
					var u = _unlit_of(n.get_active_material(i))
					if u != null:
						n.set_surface_override_material(i, u)
						swapped = true
				_saved_surf[n] = keep
			if not swapped:
				n.material_overlay = mat
		stack.append_array(n.get_children())


func _unlight(root) -> void:
	_lit.erase(root)
	for n in _saved.keys():
		if not is_instance_valid(n):
			_saved.erase(n)
			_saved_surf.erase(n)
		elif is_instance_valid(root) and (n == root or root.is_ancestor_of(n)):
			n.material_overlay = _saved[n]
			_saved.erase(n)
			if _saved_surf.has(n):
				var keep: Array = _saved_surf[n]
				for i in mini(keep.size(), n.mesh.get_surface_count() if n.mesh else 0):
					n.set_surface_override_material(i, keep[i])
				_saved_surf.erase(n)

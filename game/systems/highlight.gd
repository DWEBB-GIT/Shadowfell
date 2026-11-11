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
	if pick == null:
		return null
	var o = pick.obj
	match pick.kind:
		"enemy", "npc":
			return o.get("group")
		"chest":
			return o.get("group")
		"vein", "herb":
			return o.get("node")
		"loot":
			if o.kind == "item":
				return o.entry.get("group")
			var e = game.enemies.by_id(o.id)
			return e.group if e else null
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
		if not want.has(n) or want[n] != _lit[n]:
			_unlight(n)
	for n in want:
		if not _lit.has(n):
			_light(n, want[n])


func _light(root: Node3D, mat: Material) -> void:
	_lit[root] = mat
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is GeometryInstance3D:
			if not _saved.has(n):
				_saved[n] = n.material_overlay
			n.material_overlay = mat
		stack.append_array(n.get_children())


func _unlight(root) -> void:
	_lit.erase(root)
	for n in _saved.keys():
		if not is_instance_valid(n):
			_saved.erase(n)
		elif is_instance_valid(root) and (n == root or root.is_ancestor_of(n)):
			n.material_overlay = _saved[n]
			_saved.erase(n)

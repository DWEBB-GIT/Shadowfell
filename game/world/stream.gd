class_name WorldStream
extends RefCounted
## The world in 32 m cells, drawn only near the camera (foundations step 2,
## Dan 2026-11-03: a browser game needs a light scene).
##
## What the world IS never depends on what is drawn. Colliders, examine
## points, enemies, herb patches and veins all exist as data for the whole
## world, which is what a multiplayer server would simulate. This class only
## decides which of their views are in the scene tree:
## - placed props (Layout.props) are kept per cell as data. When a cell comes
##   within RADIUS of the camera's focus its props are built as one MultiMesh
##   per mesh part per cell (one draw for every fence post of a kind in it),
##   and freed again past KEEP. Props that cannot be batched (lamps and
##   torches, anything with lights, skeletons or animation) are instanced as
##   nodes in the same cell node.
## - other views (a herb patch, a vein, a chest) are parked out of the scene
##   tree until their cell loads; their systems keep the node and may change
##   it while it is parked (visible, colours), which costs nothing.
## Enemies move, so Enemies attaches their bodies by distance itself
## (VIEW_IN / VIEW_OUT); their AI runs whether they are drawn or not.

const CHUNK := 32.0
const RADIUS := 100.0 ## cells within this of the focus are loaded (the view reaches ~70 m)
const KEEP := 132.0 ## loaded cells further than this are unloaded
const BUDGET_MS := 2.0 ## cell loading per frame, once playing (sliced, so it holds)
const VIEW_IN := 110.0 ## an enemy's body joins the scene within this of the player
const VIEW_OUT := 140.0 ## and leaves it past this (unless it is fighting)

var root: Node3D
var cells := {} ## Vector2i -> {props: Array, views: Array of [node, parent], node: Node3D}
var loaded := {} ## Vector2i -> true
var gentle := false ## a loading screen is up: build a slice each frame, never all at once
var focus := Vector3.ZERO
var _view_key := {} ## node instance id -> its cell
var _jobs := {} ## Vector2i -> a cell whose props are being built (_start_props)


func _init(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Streamed"
	parent.add_child(root)


static func key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / CHUNK), floori(z / CHUNK))


static func cell_distance(k: Vector2i, at: Vector3) -> float:
	var cx := clampf(at.x, k.x * CHUNK, (k.x + 1) * CHUNK)
	var cz := clampf(at.z, k.y * CHUNK, (k.y + 1) * CHUNK)
	return Vector2(at.x - cx, at.z - cz).length()


func _cell(k: Vector2i) -> Dictionary:
	if not cells.has(k):
		cells[k] = {"props": [], "views": [], "node": null}
	return cells[k]


func is_loaded(x: float, z: float) -> bool:
	return loaded.has(key(x, z))


## every cell overlapping this rectangle is loaded (the minimap waits for
## this before it photographs an area, so its still has the props on it)
func covers(x0: float, z0: float, x1: float, z1: float) -> bool:
	var a := key(x0, z0)
	var b := key(x1 - 0.01, z1 - 0.01)
	for i in range(a.x, b.x + 1):
		for j in range(a.y, b.y + 1):
			if not loaded.has(Vector2i(i, j)):
				return false
	return true


# ------------------------------------------------------------ registering
## A placed prop (Layout.props entry): drawn with its cell.
func add_prop(p: Dictionary) -> void:
	_cell(key(p.position[0], p.position[1])).props.append(p)


## A node that stands still at x/z: in `parent` while its cell is loaded,
## out of the tree otherwise.
func add_view(node: Node3D, parent: Node, x: float, z: float) -> void:
	var k := key(x, z)
	_cell(k).views.append([node, parent])
	_view_key[node.get_instance_id()] = k
	if loaded.has(k) and node.get_parent() == null:
		parent.add_child(node)


## Forget a view (before freeing it, or when it moves for good).
func remove_view(node: Node3D) -> void:
	var id := node.get_instance_id()
	if not _view_key.has(id):
		return
	var c: Dictionary = cells[_view_key[id]]
	_view_key.erase(id)
	for i in c.views.size():
		if c.views[i][0] == node:
			c.views.remove_at(i)
			break


# ------------------------------------------------------------ streaming
func update(at: Vector3, all := false, budget_ms := BUDGET_MS) -> void:
	focus = at
	var c := key(at.x, at.z)
	# arriving somewhere new (loading in, a portal, a boat): load it all now,
	# unless a loading screen is up and loads it a little each frame
	all = all or (not gentle and not loaded.has(c))
	var want := _wanted(at)
	# a cell's props are built a slice at a time (a town cell holds ~1,000)
	var deadline := INF if all else Time.get_ticks_usec() + budget_ms * 1000.0
	for w in want:
		if not _load(w[1], deadline) or Time.get_ticks_usec() > deadline:
			break
	for k in loaded.keys():
		if cell_distance(k, at) > KEEP:
			_unload(k)
	for k in _jobs.keys():
		if cell_distance(k, at) > KEEP:
			_jobs[k].node.free()
			_jobs.erase(k)


## cells within reach of `at` not loaded yet
func missing(at: Vector3) -> int:
	return _wanted(at).size()


func _wanted(at: Vector3) -> Array:
	var c := key(at.x, at.z)
	var reach := int(ceil(RADIUS / CHUNK)) + 1
	var want := []
	for i in range(c.x - reach, c.x + reach + 1):
		for j in range(c.y - reach, c.y + reach + 1):
			var k := Vector2i(i, j)
			if loaded.has(k):
				continue
			var d := cell_distance(k, at)
			if d <= RADIUS:
				want.append([d, k])
	want.sort_custom(func(a, b): return a[0] < b[0])
	return want


## load a cell, or work on it until the deadline (usec): true when loaded
func _load(k: Vector2i, deadline := INF) -> bool:
	var c = cells.get(k)
	if c != null and not c.props.is_empty() and c.node == null:
		if not _jobs.has(k):
			_jobs[k] = _start_props(k)
		if not _step_props(_jobs[k], c.props, deadline):
			return false
		c.node = _finish_props(_jobs[k])
		_jobs.erase(k)
	loaded[k] = true
	if c == null:
		return true
	for v in c.views:
		if is_instance_valid(v[0]) and v[0].get_parent() == null:
			v[1].add_child(v[0])
	return true


func _unload(k: Vector2i) -> void:
	loaded.erase(k)
	var c = cells.get(k)
	if c == null:
		return
	if c.node != null:
		c.node.queue_free()
		c.node = null
	for v in c.views:
		if is_instance_valid(v[0]) and v[0].get_parent() != null:
			v[0].get_parent().remove_child(v[0])


## what is in the scene now, for the F3 readout and checks
func stats() -> Dictionary:
	var out := {"cells": loaded.size(), "batches": 0, "batched": 0, "nodes": 0, "views": 0}
	for k in loaded:
		var c = cells.get(k)
		if c == null:
			continue
		out.views += c.views.size()
		if c.node == null:
			continue
		for n in c.node.get_children():
			if n is MultiMeshInstance3D:
				out.batches += 1
				out.batched += (n as MultiMeshInstance3D).multimesh.instance_count
			else:
				out.nodes += 1
	return out


# ------------------------------------------------------------ batching
func _start_props(k: Vector2i) -> Dictionary:
	var node := Node3D.new()
	node.name = "Props_%d_%d" % [k.x, k.y]
	return {"node": node, "i": 0, "groups": {}, "order": []}


## sort a cell's props into batches (kit id # part -> transforms) and make
## the ones that stay nodes, until done (true) or the deadline passes
func _step_props(job: Dictionary, props: Array, deadline: float) -> bool:
	var node: Node3D = job.node
	var groups: Dictionary = job.groups
	while job.i < props.size():
		var p: Dictionary = props[job.i]
		job.i += 1
		var kt := kit(p)
		if not kt.batch:
			var obj := World.prop_instance(p)
			World.budget_prop(obj, str(p.model))
			node.add_child(obj)
		else:
			var xf := placed(p, kt.base)
			for i in kt.parts.size():
				var gid: String = kt.id + "#" + str(i)
				if not groups.has(gid):
					groups[gid] = {"part": kt.parts[i], "xfs": []}
					job.order.append(gid)
				groups[gid].xfs.append(xf * kt.parts[i].xf)
		if job.i % 16 == 0 and Time.get_ticks_usec() > deadline:
			return job.i >= props.size()
	return true


func _finish_props(job: Dictionary) -> Node3D:
	var node: Node3D = job.node
	for gid in job.order:
		var g: Dictionary = job.groups[gid]
		var part: Dictionary = g.part
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = g.xfs.size()
		for i in g.xfs.size():
			mm.set_instance_transform(i, g.xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Batch"
		mmi.multimesh = mm
		mmi.cast_shadow = part.shadow
		mmi.visibility_range_end = batch_range(part.range, mm.get_aabb())
		mmi.layers = part.layers
		if part.mat != null:
			mmi.material_override = part.mat
		node.add_child(mmi)
	root.add_child(node)
	return node


## A visibility range is measured to the middle of what is drawn, and a
## batch spreads over its whole cell: as is, every tree in a cell (and its
## leaves apart from its trunks, whose middles sit lower) popped in at once
## well inside the view (Dan 2026-11-12). Push it out by the batch's reach
## so nothing in it is cut nearer than the model's own range.
static func batch_range(model_range: float, aabb: AABB) -> float:
	if model_range <= 0.0:
		return model_range
	return model_range + aabb.size.length() * 0.5


## One model (with its tint) taken apart once: its meshes with their final
## materials (tinted, see-through for the nature pack, ground cover without
## shadows) and where each sits in the model. `batch` is false for models
## that must stay nodes.
static var _kits := {}

static func kit(p: Dictionary) -> Dictionary:
	var model := str(p.model)
	var tint := str(p.get("tint", ""))
	var id := model + "|" + tint
	if _kits.has(id):
		return _kits[id]
	var obj := Assets.instance(model)
	if tint != "":
		Assets.tint_instance(obj, Color(tint))
	if model.contains("/environment/nature/"):
		Assets.use_cutaway(obj)
	World.budget_prop(obj, model)
	var batch := not World.is_light_fixture(model)
	var parts := []
	var stack := [[obj, Transform3D.IDENTITY]]
	while stack:
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n.get_class() != "Node3D" and n.get_class() != "MeshInstance3D":
			batch = false
		if n is MeshInstance3D and (n as MeshInstance3D).visible and (n as MeshInstance3D).mesh != null:
			var part := _part(n, xf)
			if part.is_empty():
				batch = false
			else:
				parts.append(part)
		for ch in n.get_children():
			if ch is Node3D:
				stack.append([ch, xf * (ch as Node3D).transform])
			else:
				batch = false
	var out := {"id": id, "base": obj.transform, "parts": parts, "batch": batch and not parts.is_empty()}
	obj.free()
	_kits[id] = out
	return out


static func _part(mi: MeshInstance3D, xf: Transform3D) -> Dictionary:
	if mi.skin != null:
		return {}
	var mesh: Mesh = mi.mesh
	var n := mesh.get_surface_count()
	var overridden := false
	for i in n:
		if mi.get_surface_override_material(i) != null:
			overridden = true
	var out_mesh := mesh
	var mat: Material = mi.material_override
	if mat == null and overridden:
		if mesh is ArrayMesh:
			# a private copy of the mesh carrying this model's materials
			out_mesh = mesh.duplicate()
			for i in n:
				out_mesh.surface_set_material(i, mi.get_active_material(i))
		elif n == 1:
			mat = mi.get_active_material(0)
		else:
			return {}
	return {"mesh": out_mesh, "xf": xf, "mat": mat, "shadow": mi.cast_shadow, "range": mi.visibility_range_end, "layers": mi.layers}


static var _scratch: Node3D

## where a prop stands: the same transform World.prop_instance gives its node
static func placed(p: Dictionary, base: Transform3D) -> Transform3D:
	if _scratch == null:
		_scratch = Node3D.new()
	_scratch.transform = base
	World.place(_scratch, p)
	return _scratch.transform


## how high a placed prop stands above the ground under it, without making it
static func prop_height(p: Dictionary) -> float:
	var kt := kit(p)
	var xf := placed(p, kt.base)
	var top := -INF
	for part in kt.parts:
		top = maxf(top, (xf * part.xf * (part.mesh as Mesh).get_aabb()).end.y)
	return top - Terrain.height_at(p.position[0], p.position[1]) if top > -INF else INF

class_name Assets
extends RefCounted
## The models in assets/models (made in Blender, exported as .glb). A model
## with no .glb yet shows as a grey box so it is easy to spot.

const MODELS := "res://assets/models/%s.glb"

static var _cache := {}
static var _shared := {}


## One shared material per Blender material name, as the browser build does:
## M_Base is lit and painted by vertex colour, M_Glow ignores light.
static func shared_material(name: String) -> StandardMaterial3D:
	if _shared.is_empty():
		var base := StandardMaterial3D.new()
		base.vertex_color_use_as_albedo = true
		base.roughness = 1.0
		_shared.M_Base = base
		var glow := StandardMaterial3D.new()
		glow.vertex_color_use_as_albedo = true
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_shared.M_Glow = glow
	return _shared.get(name, _shared.M_Base)


## glTF vertex colours are linear; the GL Compatibility renderer reads
## vertex colours as sRGB, so each mesh is converted once.
static var _converted := {}


static func _srgb_mesh(mesh: Mesh) -> Mesh:
	if _converted.has(mesh):
		return _converted[mesh]
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var cols = arrays[Mesh.ARRAY_COLOR]
		if cols is PackedColorArray:
			for j in cols.size():
				cols[j] = cols[j].linear_to_srgb()
			arrays[Mesh.ARRAY_COLOR] = cols
		out.add_surface_from_arrays(mesh.surface_get_primitive_type(i), arrays)
		out.surface_set_material(i, mesh.surface_get_material(i))
	_converted[mesh] = out
	return out


## Imported models keep their own textured materials (named "T_...", see
## assets/blender/import_models.py).
static func _textured(mesh: Mesh) -> bool:
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m and m.resource_name.begins_with("T_"):
			return true
	return false


static func _adopt_shared_materials(root: Node) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or _textured(mi.mesh):
			continue
		mi.mesh = _srgb_mesh(mi.mesh)
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, shared_material(m.resource_name if m else ""))


static func has(name: String) -> bool:
	return ResourceLoader.exists(MODELS % name)


static func instance(name: String) -> Node3D:
	if not _cache.has(name):
		_cache[name] = load(MODELS % name) if has(name) else null
	var scene: PackedScene = _cache[name]
	if scene:
		var n := scene.instantiate() as Node3D
		n.name = name
		_adopt_shared_materials(n)
		return n
	var holder := Node3D.new()
	holder.name = name
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 1.2, 0.8)
	box.mesh = mesh
	box.position.y = 0.6
	holder.add_child(box)
	return holder

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
		if RenderingServer.get_current_rendering_method() == "gl_compatibility":
			mi.mesh = _srgb_mesh(mi.mesh)
		for i in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, shared_material(m.resource_name if m else ""))


static func has(name: String) -> bool:
	return ResourceLoader.exists(model_path(name))


## Existing model ids still work; scenery may also use a project scene or glTF.
static func model_path(name: String) -> String:
	if name.begins_with("res://"):
		return name
	if _paths.is_empty():
		_load_paths()
	if _paths.has(name):
		return _paths[name]
	var native := "res://assets/models/%s.tscn" % name
	return native if ResourceLoader.exists(native) else MODELS % name


static func instance(name: String) -> Node3D:
	if not _cache.has(name):
		_cache[name] = load(model_path(name)) if has(name) else null
	var scene: PackedScene = _cache[name]
	if scene:
		var n := scene.instantiate() as Node3D
		n.name = name.get_file().get_basename()
		# Pack scenes keep their authored textures and materials.
		if not name.begins_with("res://") and model_path(name).ends_with(".glb"):
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


## Tint an instance with private materials, leaving the source pack untouched.
static func tint_instance(root: Node3D, tint: Color) -> void:
	if tint.is_equal_approx(Color.WHITE):
		return
	# Keep materials on the parent until its meshes are destroyed. Otherwise
	# Godot 4.7 can release an override before removing its renderer dependency.
	var materials: Array = root.get_meta("_shadowfell_tint_materials", [])
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var original := mi.get_active_material(i)
			if original is BaseMaterial3D:
				var material: BaseMaterial3D = original.duplicate()
				material.albedo_color *= tint
				materials.append(material)
				mi.set_surface_override_material(i, material)
	root.set_meta("_shadowfell_tint_materials", materials)


## The see-through circle for a textured pack model (nature trees, rocks,
## plants): each surface gets a nature_cutaway material built once per source
## material, so every copy of a tree shares the same few materials.
const NATURE_CUTAWAY := preload("res://game/render/nature_cutaway.gdshader")
static var _cutaway_for := {}

static func use_cutaway(root: Node3D) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mi: MeshInstance3D in meshes:
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var original := mi.get_active_material(i)
			if original is BaseMaterial3D:
				mi.set_surface_override_material(i, cutaway_material(original))


static func cutaway_material(src: BaseMaterial3D) -> ShaderMaterial:
	if _cutaway_for.has(src):
		return _cutaway_for[src]
	var m := ShaderMaterial.new()
	m.shader = NATURE_CUTAWAY
	m.set_shader_parameter("albedo", src.albedo_color)
	if src.albedo_texture:
		m.set_shader_parameter("albedo_tex", src.albedo_texture)
		m.set_shader_parameter("use_albedo_tex", true)
	if src.normal_enabled and src.normal_texture:
		m.set_shader_parameter("normal_tex", src.normal_texture)
		m.set_shader_parameter("use_normal_tex", true)
		m.set_shader_parameter("normal_scale", src.normal_scale)
	if src.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		m.set_shader_parameter("alpha_scissor", src.alpha_scissor_threshold)
	m.set_shader_parameter("roughness", src.roughness)
	_cutaway_for[src] = m
	return m


static var _paths := {}
static func _load_paths() -> void:
	var path := "res://assets/model_library.json"
	if FileAccess.file_exists(path):
		var data = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			_paths = data.get("models", {})

static func model_ids() -> Array:
	if _paths.is_empty():
		_load_paths()
	var ids := _paths.keys()
	ids.sort()
	return ids

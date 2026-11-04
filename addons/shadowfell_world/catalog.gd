@tool
extends RefCounted
## Project scene paths rather than copied pack files. Source art stays editable.
const ROOTS := ["res://assets/models", "res://assets/environment"]


static func models() -> Array:
	var out := []
	for dir in ROOTS:
		_scan(dir, out)
	out.sort_custom(func(a, b): return a[0].naturalnocasecmp_to(b[0]) < 0)
	return out


static func _scan(dir: String, out: Array) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		if file.get_extension().to_lower() in ["glb", "gltf", "tscn"]:
			var path := dir.path_join(file)
			var key := file.get_basename()
			var id := key if Assets.model_path(key) == path else path
			out.append(["%s  ·  %s" % [file.get_basename().replace("_", " "), dir.trim_prefix("res://")], id])
	for child in DirAccess.get_directories_at(dir):
		if not child.begins_with("."):
			_scan(dir.path_join(child), out)

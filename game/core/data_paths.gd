class_name DataPaths
extends RefCounted
## Logical file names stay stable while authoring files live in clear folders.
static func entries(root := "res://data") -> Dictionary:
	var manifest := root.path_join("catalogue.json")
	if FileAccess.file_exists(manifest):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		if parsed is Dictionary:
			return parsed.get("files", {})
	var out := {}
	for file in DirAccess.get_files_at(root):
		if file.ends_with(".json"):
			out[file.get_basename()] = file
	return out

static func path_for(name: String, root := "res://data") -> String:
	return root.path_join(str(entries(root).get(name, name + ".json")))

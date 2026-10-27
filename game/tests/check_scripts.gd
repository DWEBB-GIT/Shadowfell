extends SceneTree
## Loads every script under res://game so parse errors show up at once:
## godot --headless --path . --script res://game/tests/check_scripts.gd


func _initialize() -> void:
	var bad := 0
	for path in _scripts("res://game") + _scripts("res://addons"):
		var s = load(path)
		if s == null or (s is GDScript and not s.can_instantiate() and not path.ends_with("check_scripts.gd")):
			print("FAILED: ", path)
			bad += 1
	print("checked scripts, %d failed" % bad)
	quit(1 if bad else 0)


func _scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out

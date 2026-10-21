class_name Store
extends RefCounted
## A small key/value store standing in for the browser's localStorage: each
## key is one text file under user://store. On a web export user:// lives in
## the browser's IndexedDB, so saves persist there too.

static var dir := "user://store" ## tests point this elsewhere


static func _path(key: String) -> String:
	return "%s/%s.json" % [dir, key.replace("/", "_")]


static func get_item(key: String):
	var p := _path(key)
	if not FileAccess.file_exists(p):
		return null
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text() if f else null


static func set_item(key: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_path(key), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	return true


static func remove_item(key: String) -> void:
	var p := _path(key)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

extends SceneTree
const DataStore := preload("res://addons/shadowfell_data/store.gd")
const IO := preload("res://addons/shadowfell_data/json_io.gd")
var failures := 0
func _initialize() -> void:
	var folder := "user://organised_data_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(folder)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("res://data/catalogue.json"),ProjectSettings.globalize_path(folder+"/catalogue.json"))
	for key in DataPaths.entries():
		var destination := DataPaths.path_for(key,folder)
		DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(DataPaths.path_for(key)),ProjectSettings.globalize_path(destination))
	var s := DataStore.new()
	s.data_dir = folder
	s.load_all()
	check(s.files.size() == 16 and s.quests.size() == 174,"editor loads the organised content tables")
	check(s.save_all().is_empty(),"opening organised data does not write files")
	s.quests[0].name += " Fixture only."
	s.touch("quests")
	check(s.save_all().size() == 1,"editing a quest saves one content table")
	check(IO.load_file(folder+"/quests/quests.json").quests[0].name.ends_with("Fixture only."),"quest edits reach the quests folder")
	check(not FileAccess.file_exists(folder+"/quests.json"),"saving does not recreate flat duplicate data")
	check(s.save_all().is_empty(),"a second save leaves the files alone")
	print("organised_data_check: %d failed" % failures)
	quit(1 if failures else 0)
func check(ok: bool,message: String) -> void:
	print("ok: " if ok else "FAIL: ",message)
	if not ok:failures+=1

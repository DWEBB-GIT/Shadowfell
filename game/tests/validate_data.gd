extends SceneTree
## The data gate: every data file loads, and the Game Data editor's checks
## (addons/shadowfell_data/checks.gd: shapes, ids and the links between
## files) all pass. Fast, no world is built. Runs on every push to main
## before the web export, so broken content never ships:
##   godot --headless --path . --script res://game/tests/validate_data.gd
## Exits 1 and lists each problem if anything is wrong.

const DataStore := preload("res://addons/shadowfell_data/store.gd")
const Checks := preload("res://addons/shadowfell_data/checks.gd")


func _initialize() -> void:
	var problems := PackedStringArray()
	var data = load("res://game/autoload/game_data.gd").new()
	for p in data.problems:
		problems.append("load: " + str(p))
	var s := DataStore.new()
	s.load_all()
	problems.append_array(Checks.run(s))
	problems.append_array(SaveManager.rename_problems())
	for p in problems:
		printerr("DATA  " + p)
	print("validate_data: %d problem(s)" % problems.size())
	quit(1 if not problems.is_empty() else 0)

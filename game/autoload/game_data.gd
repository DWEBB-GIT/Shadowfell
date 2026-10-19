extends Node
## Every content file in res://data, loaded once at start. These are the same
## JSON files the browser build and the quest editor use, so a change to them
## shows up everywhere.
##
## Records live in tables by their list name: GameData.get_record("items", "dirk"),
## GameData.table("enemySpawns"). Whole files are in GameData.files["world"].

const DATA_DIR := "res://data"

## file name without .json -> the parsed file
var files: Dictionary = {}
## list name (items, npcs, quests, enemySpawns...) -> { id: record }
var tables: Dictionary = {}
## problems found while loading (bad JSON, repeated ids)
var problems: PackedStringArray = []


func _init() -> void:
	load_all()


func load_all() -> void:
	files.clear()
	tables.clear()
	problems.clear()
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		problems.append("cannot open %s" % DATA_DIR)
		return
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [DATA_DIR, file_name])
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			problems.append("%s: not valid JSON" % file_name)
			continue
		files[file_name.get_basename()] = parsed
		_index(file_name, parsed)


# Any list of records with ids becomes a table under its key, so a new list in
# a data file needs no code here.
func _index(file_name: String, parsed: Dictionary) -> void:
	for key in parsed:
		var list = parsed[key]
		if typeof(list) != TYPE_ARRAY or list.is_empty() or typeof(list[0]) != TYPE_DICTIONARY or not list[0].has("id"):
			continue
		var by_id: Dictionary = tables.get(key, {})
		for record in list:
			var id = record.get("id")
			if by_id.has(id):
				problems.append("%s %s: id %s is repeated" % [file_name, key, id])
			by_id[id] = record
		tables[key] = by_id


func table(name: String) -> Dictionary:
	return tables.get(name, {})


func get_record(table_name: String, id: String) -> Dictionary:
	return table(table_name).get(id, {})


## A section of a file that is not a list of records, e.g. section("world", "bounds").
func section(file: String, key: String, fallback = null):
	return files.get(file, {}).get(key, fallback)

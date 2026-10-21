class_name Roster
extends RefCounted
## The character roster (src/systems/characters.js): who has been made, which
## class each is, and where each one's save lives. One save key per
## character; the roster itself is a small list under its own key. The first
## character takes the original save key.

const ROSTER_KEY := "shadowfall.characters"

var list: Array = []
var last = null


static func tidy_name(raw) -> String:
	var s := str(raw if raw != null else "").strip_edges()
	var re := RegEx.create_from_string("\\s+")
	s = re.sub(s, " ", true)
	var words := []
	for w in s.split(" "):
		words.append(w.substr(0, 1).to_upper() + w.substr(1).to_lower() if w != "" else w)
	return " ".join(words)


static func _name_ok(name: String) -> bool:
	var re := RegEx.create_from_string("^[A-Z][a-z]{1,11}( [A-Z][a-z]{1,11})?$")
	return re.search(name) != null


var max: int:
	get:
		return int(DB.text.title.maxCharacters)

var full: bool:
	get:
		return list.size() >= max


## Read the roster. Returns { legacyUnreadable } when an old save sits under
## the original key but could not be adopted.
func load_roster(read_save: Callable) -> Dictionary:
	var text = Store.get_item(ROSTER_KEY)
	var data = JSON.parse_string(text) if text != null else null
	var ok: bool = typeof(data) == TYPE_DICTIONARY and typeof(data.get("list")) == TYPE_ARRAY and data.list.all(func(c): return typeof(c) == TYPE_DICTIONARY and typeof(c.get("id")) == TYPE_STRING and typeof(c.get("name")) == TYPE_STRING and typeof(c.get("key")) == TYPE_STRING)
	list = data.list if ok else []
	last = data.get("last") if ok and by_id(data.get("last", "")) != null else (list[0].id if not list.is_empty() else null)
	# adopt a save made before the roster existed
	var legacy_unreadable := false
	if not list.any(func(c): return c.key == SaveManager.SAVE_KEY) and Store.get_item(SaveManager.SAVE_KEY) != null:
		if read_save.call(SaveManager.SAVE_KEY).status == "ok":
			var c := {"id": _new_id(), "name": "Warden", "classId": "warden", "key": SaveManager.SAVE_KEY, "createdAt": Time.get_unix_time_from_system() * 1000, "lastPlayed": Time.get_unix_time_from_system() * 1000}
			list.push_front(c)
			last = c.id
			_write()
		else:
			legacy_unreadable = true
	return {"legacyUnreadable": legacy_unreadable}


func by_id(id):
	for c in list:
		if c.id == id:
			return c
	return null


## "" when the name is fine, otherwise why not
func name_problem(raw) -> String:
	var name := tidy_name(raw)
	if name == "":
		return "Your character needs a name."
	if not _name_ok(name):
		return "Use letters only: one or two words of 2 to 12 letters."
	if list.any(func(c): return c.name.to_lower() == name.to_lower()):
		return "There is already a character called %s." % name
	return ""


func random_name() -> String:
	var names: Dictionary = DB.text.title.names
	for i in 40:
		var name := "%s %s" % [names.first[randi() % names.first.size()], names.last[randi() % names.last.size()]]
		if name_problem(name) == "":
			return name
	return ""


func create(raw_name, class_id: String) -> Dictionary:
	var name := tidy_name(raw_name)
	var problem := "You can keep %d characters. Delete one to make room." % max if full else name_problem(name)
	if problem != "":
		return {"ok": false, "reason": problem}
	var id := _new_id()
	# the original key is free: the first character (or one after it was deleted) takes it
	var taken: bool = list.any(func(c): return c.key == SaveManager.SAVE_KEY) or Store.get_item(SaveManager.SAVE_KEY) != null
	var key := "%s.%s" % [SaveManager.SAVE_KEY, id] if taken else SaveManager.SAVE_KEY
	var now := Time.get_unix_time_from_system() * 1000
	var c := {"id": id, "name": name, "classId": class_id, "key": key, "createdAt": now, "lastPlayed": now}
	list.append(c)
	last = id
	if not _write():
		list.pop_back()
		return {"ok": false, "reason": "Storage is full or disabled, so no character can be made."}
	return {"ok": true, "character": c}


## Deleting removes the character's save for good.
func remove(id: String) -> bool:
	var c = by_id(id)
	if c == null:
		return false
	list.erase(c)
	Store.remove_item(c.key)
	if last == id:
		last = list[0].id if not list.is_empty() else null
	_write()
	return true


func touch(id: String) -> void:
	var c = by_id(id)
	if c == null:
		return
	c.lastPlayed = Time.get_unix_time_from_system() * 1000
	last = id
	_write()


func _new_id() -> String:
	var n := list.size() + 1
	while list.any(func(c): return c.id == "c%d" % n):
		n += 1
	return "c%d" % n


func _write() -> bool:
	return Store.set_item(ROSTER_KEY, JSON.stringify({"version": 1, "last": last, "list": list}))

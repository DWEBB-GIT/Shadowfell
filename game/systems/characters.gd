class_name Roster
extends RefCounted
## The character roster (src/systems/characters.js): who has been made, which
## class each is, and where each one's save lives. One save key per
## character; the roster itself is a small list under its own key. The first
## character takes the original save key.

const ROSTER_KEY := "shadowfall.characters"

var deleted: Array = []
var list: Array = []
var last = null


## Names are one word of 2 to 12 letters, first letter capital, the rest
## small (Dan, 2026-11-04). Anything else typed is dropped here, so the name
## box and create() agree on what the name will be.
const NAME_MIN := 2
const NAME_MAX := 12

static var _blocked = null


static func tidy_name(raw) -> String:
	var s := str(raw if raw != null else "")
	var re := RegEx.create_from_string("[^A-Za-z]")
	s = re.sub(s, "", true)
	return s.substr(0, 1).to_upper() + s.substr(1).to_lower()


static func _name_ok(name: String) -> bool:
	var re := RegEx.create_from_string("^[A-Z][a-z]{%d,%d}$" % [NAME_MIN - 1, NAME_MAX - 1])
	return re.search(name) != null


## Swear words and slurs (data/meta/blocked_names.json): `words` are refused
## when the whole name is that word or that word plus a short ending (s, es,
## er, ers, y, ie...), `contains` are refused anywhere inside the name.
## Kept apart so ordinary names that happen to hold a short bad word
## (Scunthorpe, Cassandra) still pass.
static func blocked_words() -> Dictionary:
	if _blocked == null:
		var path := DataPaths.path_for("blocked_names")
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		_blocked = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	return _blocked


static func is_offensive(raw) -> bool:
	var n := str(raw).to_lower()
	var re := RegEx.create_from_string("[^a-z]")
	n = re.sub(n, "", true)
	if n == "":
		return false
	var b := blocked_words()
	for w in b.get("contains", []):
		if n.contains(str(w)):
			return true
	for w in b.get("words", []):
		var word := str(w)
		if n == word:
			return true
		if n.begins_with(word) and n.substr(word.length()) in ["s", "es", "er", "ers", "y", "ie", "ies", "ed", "ing", "z", "a", "o"]:
			return true
	return false


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
	deleted = data.get("deleted", []) if ok else []
	deleted = deleted.filter(func(c): return c is Dictionary and c.has_all(["id","name","key","classId","deletedAt"]))
	for c in deleted.duplicate():
		if Time.get_unix_time_from_system()-float(c.deletedAt)>30*86400:
			Store.remove_item(c.key)
			deleted.erase(c)
	last = data.get("last") if ok and by_id(data.get("last", "")) != null else (list[0].id if not list.is_empty() else null)
	# adopt a save made before the roster existed
	var legacy_unreadable := false
	if not (list+deleted).any(func(c): return c.key == SaveManager.SAVE_KEY) and Store.get_item(SaveManager.SAVE_KEY) != null:
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
		return "Use one word of %d to %d letters, with no spaces or symbols." % [NAME_MIN, NAME_MAX]
	if is_offensive(name):
		return "That name is not allowed. Please choose another."
	if deleted.any(func(c): return c.name.to_lower()==name.to_lower()):
		return "A recently deleted character has that name. Restore them or choose another name."
	if list.any(func(c): return c.name.to_lower() == name.to_lower()):
		return "There is already a character called %s." % name
	return ""


func random_name() -> String:
	var names: Dictionary = DB.text.title.names
	for i in 40:
		var name: String = names.first[randi() % names.first.size()]
		if name_problem(name) == "":
			return name
	return ""


func create(raw_name, class_id: String, appearance = null) -> Dictionary:
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
	c.appearance = ForgeCharacter.clean(appearance)
	list.append(c)
	last = id
	if not _write():
		list.pop_back()
		return {"ok": false, "reason": "Storage is full or disabled, so no character can be made."}
	return {"ok": true, "character": c}


## Deletion frees a slot and retains the save for thirty days.
func remove(id: String) -> bool:
	var c = by_id(id)
	if c == null:
		return false
	var before: Array=list.duplicate(true)
	var previous=last
	list.erase(c)
	c=c.duplicate(true)
	c.deletedAt=Time.get_unix_time_from_system()
	deleted.append(c)
	if last == id:
		last = list[0].id if not list.is_empty() else null
	if not _write():
		list=before
		last=previous
		deleted.erase(c)
		return false
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
	while (list+deleted).any(func(c): return c.id == "c%d" % n):
		n += 1
	return "c%d" % n


func _write() -> bool:
	return Store.set_item(ROSTER_KEY, JSON.stringify({"version": 1, "last": last, "list": list, "deleted": deleted}))


func restore(id: String) -> Dictionary:
	if full:
		return {"ok":false,"reason":"All ten slots are occupied. Free a slot before restoring a character."}
	for c in deleted:
		if c.id!=id:
			continue
		deleted.erase(c)
		list.append(c)
		if not _write():
			list.erase(c)
			deleted.append(c)
			return {"ok":false,"reason":"Storage could not be updated. Your character has been kept."}
		return {"ok":true}
	return {"ok":false,"reason":"That character is no longer available to restore."}

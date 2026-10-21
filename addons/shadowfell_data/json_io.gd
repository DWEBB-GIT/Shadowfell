@tool
extends RefCounted
## Reads and writes the data/*.json files exactly as the browser tools do, so
## a save from the Godot editor only changes the lines that really changed.
##
## Godot reads every JSON number as a float; whole numbers are written back
## without a ".0", as JavaScript writes them.
##
## Two layouts are in use:
##  - plain: JSON.stringify(data, null, 2), most files;
##  - compact: quests.json, where short leaf objects and lists sit on one line
##    (the quest editor's pretty(), tools/quest-editor/editor.js).

const COMPACT_FILES := ["quests.json"]
## world.json and scenery.json: plain, but a list of plain values sits on
## one line ([x, z], [0, 0, 1.3]), as they are written by hand
const SHORT_LIST_FILES := ["world.json", "scenery.json"]


static func load_file(path: String):
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return null
	return JSON.parse_string(text)


static func save_file(path: String, data) -> Error:
	var text := to_text(data, path.get_file() in COMPACT_FILES, path.get_file() in SHORT_LIST_FILES)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(text)
	f.close()
	return OK


static func to_text(data, compact := false, short_lists := false) -> String:
	return (_pretty(data, "") if compact else _plain(data, "", short_lists)) + "\n"


# ------------------------------------------------------------------ plain
static func _plain(v, indent: String, short_lists := false) -> String:
	var inner := indent + "  "
	if v is Array:
		if v.is_empty():
			return "[]"
		if short_lists and _depth(v) == 1:
			return _inline(v)
		var parts := PackedStringArray()
		for x in v:
			parts.append(inner + _plain(x, inner, short_lists))
		return "[\n" + ",\n".join(parts) + "\n" + indent + "]"
	if v is Dictionary:
		if v.is_empty():
			return "{}"
		var parts := PackedStringArray()
		for k in v:
			parts.append(inner + _scalar(str(k)) + ": " + _plain(v[k], inner, short_lists))
		return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
	return _scalar(v)


# ------------------------------------------------------------------ compact
static func _depth(v) -> int:
	if v is Array or v is Dictionary:
		var m := 0
		for x in (v if v is Array else v.values()):
			m = maxi(m, _depth(x))
		return 1 + m
	return 0


static func _inline(v) -> String:
	if v is Array:
		var parts := PackedStringArray()
		for x in v:
			parts.append(_inline(x))
		return "[" + ", ".join(parts) + "]"
	if v is Dictionary:
		var parts := PackedStringArray()
		for k in v:
			parts.append(_scalar(str(k)) + ": " + _inline(v[k]))
		return "{ " + ", ".join(parts) + " }"
	return _scalar(v)


static func _pretty(v, indent: String) -> String:
	var inner := indent + "  "
	if v is Array or v is Dictionary:
		if v.is_empty():
			return "[]" if v is Array else "{}"
		var leaf := _depth(v) <= 1 or (v is Array and _depth(v) <= 2)
		var one := _inline(v)
		if leaf and one.length() + indent.length() < 90 and not one.contains("\\n"):
			return one
		var parts := PackedStringArray()
		if v is Array:
			for x in v:
				parts.append(inner + _pretty(x, inner))
			return "[\n" + ",\n".join(parts) + "\n" + indent + "]"
		for k in v:
			parts.append(inner + _scalar(str(k)) + ": " + _pretty(v[k], inner))
		return "{\n" + ",\n".join(parts) + "\n" + indent + "}"
	return _scalar(v)


# ------------------------------------------------------------------ values
static func _scalar(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return number(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return _quote(str(v))
	return _quote(str(v))


## A number as JavaScript prints it: 3, 0.45, 2.2
static func number(x: float) -> String:
	if is_nan(x) or is_inf(x):
		return "null"
	if x == floorf(x) and absf(x) < 1e15:
		return str(int(x))
	# the shortest text that reads back as the same number
	for digits in range(1, 18):
		var s := String.num(x, digits)
		if s.to_float() == x:
			return s
	return str(x)


static func _quote(s: String) -> String:
	var out := "\""
	for i in s.length():
		var c := s.unicode_at(i)
		match c:
			0x22:
				out += "\\\""
			0x5C:
				out += "\\\\"
			0x0A:
				out += "\\n"
			0x0D:
				out += "\\r"
			0x09:
				out += "\\t"
			0x08:
				out += "\\b"
			0x0C:
				out += "\\f"
			_:
				if c < 0x20:
					out += "\\u%04x" % c
				else:
					out += char(c)
	return out + "\""

class_name Settings
extends RefCounted
## Player preferences (the Settings window, O; src/systems/settings.js).
## Kept apart from the save, so they hold across characters. A setting is a
## checkbox, or a slider when it has `min` and `max` (volumes, in percent).

const KEY := "shadowfall.settings"
const SETTINGS := [
	{"id": "names", "label": "Show names over characters", "default": true},
	{"id": "playerName", "label": "Show your own name over your character", "default": true},
	{"id": "lootNames", "label": "Show names of items on the ground", "default": true},
	{"id": "clickToMove", "label": "Click to move (right click; left click with mouse aim)", "default": false},
	{"id": "classicControls", "label": "Classic controls (left click selects, right click attacks, spells on 1-4 Q E)", "group": "Controls and camera", "default": false},
	{"id": "tankControls", "label": "Keyboard turning (A and D turn you on the spot, W walks forward, S backs up slowly)", "group": "Controls and camera", "default": false},
	{"id": "classicCamera", "label": "Classic camera (one lower angle at every zoom)", "group": "Controls and camera", "default": false},
	{"id": "volMaster", "label": "Master volume", "group": "Sound", "default": 70, "min": 0, "max": 100},
	{"id": "volEffects", "label": "Effects", "group": "Sound", "default": 100, "min": 0, "max": 100},
	{"id": "volAmbience", "label": "Ambience (forest, town, birds, bells)", "group": "Sound", "default": 100, "min": 0, "max": 100},
	{"id": "volMusic", "label": "Music", "group": "Sound", "default": 60, "min": 0, "max": 100},
]

var game
var values := {}


static func _def(id: String):
	for s in SETTINGS:
		if s.id == id:
			return s
	return null


## a stored value made safe: the right type, and inside a slider's range
static func _clean(s: Dictionary, v):
	if s.has("min"):
		return clampi(U.jround(v), s.min, s.max) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(v) else s.default
	return v if typeof(v) == TYPE_BOOL else s.default


func _init(g) -> void:
	game = g
	for s in SETTINGS:
		values[s.id] = s.default
	var text = Store.get_item(KEY)
	var saved = JSON.parse_string(text) if text != null else null
	if typeof(saved) == TYPE_DICTIONARY:
		for s in SETTINGS:
			if saved.has(s.id):
				values[s.id] = _clean(s, saved[s.id])


func get_value(id: String):
	return values.get(id)


func set_value(id: String, v) -> void:
	var s = _def(id)
	if s == null:
		return
	var value = _clean(s, float(v) if s.has("min") else bool(v))
	values[id] = value
	Store.set_item(KEY, JSON.stringify(values))
	game.events.emit("settingsChanged", {"id": id, "value": value})

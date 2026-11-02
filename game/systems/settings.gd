class_name Settings
extends RefCounted
## Player preferences (the Settings window, O; src/systems/settings.js).
## Kept apart from the save, so they hold across characters. A setting is a
## checkbox, a slider when it has `min` and `max` (volumes, in percent), or
## a drop-down when it is a `choice` (its options come from the game).

const KEY := "shadowfall.settings"
## `tab`: the page of the Settings window it sits on (TABS); `group`: a
## heading on that page.
const TABS := [["controls", "Controls"], ["keys", "Key binding"], ["audio", "Audio"], ["interface", "Interface"]]
const SETTINGS := [
	{"id": "leftInteract", "label": "Interact on left click (talk, attack and use as right click does; right click still works)", "tab": "controls", "default": false},
	{"id": "autoLoot", "label": "Auto loot (walking up to a body you can loot takes what it holds)", "tab": "controls", "default": false},
	{"id": "clickToMove", "label": "Click to move (right click; left click with mouse aim)", "tab": "controls", "default": false},
	{"id": "targetLock", "label": "Target lock (with nothing selected, abilities lock on to the enemy you face)", "tab": "controls", "default": true},
	{"id": "classicControls", "label": "Classic controls (left click selects, right click attacks, spells on 1-4 Q E)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "tankControls", "label": "Keyboard turning (A and D turn you on the spot, W walks forward, S backs up slowly)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "classicCamera", "label": "Lower camera angle (fixed while zooming)", "tab": "controls", "group": "Scheme and camera", "default": true},
	{"id": "keysPerCharacter", "label": "Character specific (each character keeps its own key bindings)", "tab": "keys", "default": false},
	{"id": "soundOn", "label": "Enable sound", "tab": "audio", "default": true},
	{"id": "outputDevice", "label": "Output device", "tab": "audio", "default": "Default", "choice": true},
	{"id": "volMaster", "label": "Master volume", "tab": "audio", "default": 70, "min": 0, "max": 100},
	{"id": "volMusic", "label": "Music", "tab": "audio", "default": 60, "min": 0, "max": 100},
	{"id": "volEffects", "label": "Effects", "tab": "audio", "default": 100, "min": 0, "max": 100},
	{"id": "volAmbience", "label": "Ambience", "tab": "audio", "default": 100, "min": 0, "max": 100},
	{"id": "names", "label": "Show NPC names", "tab": "interface", "default": true},
	{"id": "playerName", "label": "Show your own name over your character", "tab": "interface", "default": true},
	{"id": "bloodEffects", "label": "Small blood effects on living creatures", "tab": "interface", "default": true},
	{"id": "lootNames", "label": "Show names of items on the ground", "tab": "interface", "default": true},
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
	if s.get("choice"):
		return v if typeof(v) == TYPE_STRING and v != "" else s.default
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
	var value = _clean(s, float(v) if s.has("min") else str(v) if s.get("choice") else bool(v))
	values[id] = value
	Store.set_item(KEY, JSON.stringify(values))
	game.events.emit("settingsChanged", {"id": id, "value": value})

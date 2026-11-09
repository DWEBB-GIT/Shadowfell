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
	{"id": "clickToMove", "label": "Click to move (left click)", "tab": "controls", "default": false},
	{"id": "targetLock", "label": "Target lock (with nothing selected, abilities lock on to the enemy you face)", "tab": "controls", "default": true},
	{"id": "classicControls", "label": "Classic controls (left click selects, right click attacks, spells on 1-4 Q E)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "tankControls", "label": "Keyboard turning (A and D turn you on the spot, W walks forward, S backs up slowly)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "classicCamera", "label": "Lower camera angle (fixed while zooming)", "tab": "controls", "group": "Scheme and camera", "default": false},
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
	{"id": "weaponTrails", "label": "Weapon trails on swings", "tab": "interface", "default": true},
	{"id": "stationNames", "label": "Show names of forges, hearths and other workplaces when you are close", "tab": "interface", "default": true},
	{"id": "lootNames", "label": "Show names of items on the ground", "tab": "interface", "default": true},
	# 0 off, 1 the player only, 2 the player, enemies and NPCs. Each step
	# costs more near lamps (a moving shadow caster redraws the lamp's shadow).
	{"id": "lampShadows", "label": "Shadows from lamps and torches (lower it if the game slows near lights)", "tab": "interface", "group": "Graphics", "default": 1, "webDefault": 0, "min": 0, "max": 2, "names": ["Off", "Player", "Everyone"]},
]

var game
var values := {}


static func _def(id: String):
	for s in SETTINGS:
		if s.id == id:
			return s
	return null


## A setting's starting value; the browser build may start lower
## ("webDefault"), since a browser has less to spare for the same picture.
static func default_of(s: Dictionary):
	return s.webDefault if s.has("webDefault") and OS.has_feature("web") else s.default


## a stored value made safe: the right type, and inside a slider's range
static func _clean(s: Dictionary, v):
	if s.get("choice"):
		return v if typeof(v) == TYPE_STRING and v != "" else default_of(s)
	if s.has("min"):
		if typeof(v) == TYPE_BOOL and s.has("names"):
			return 1 if v else 0
		return clampi(U.jround(v), s.min, s.max) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(v) else default_of(s)
	return v if typeof(v) == TYPE_BOOL else default_of(s)


func _init(g) -> void:
	game = g
	for s in SETTINGS:
		values[s.id] = default_of(s)
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

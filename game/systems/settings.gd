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
	{"id": "combatMove", "label": "Combat move (experiment: in a fight, Space does a Roll, a ~4 m tumble on a 6 s cooldown, or a Hop that leaps you further)", "tab": "controls", "default": "Roll", "choice": true, "options": "COMBAT_MOVES"},
	{"id": "classicControls", "label": "Classic controls (left click selects, right click attacks, spells on 1-4 Q E)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "tankControls", "label": "Keyboard turning (A and D turn you on the spot, W walks forward, S backs up slowly)", "tab": "controls", "group": "Scheme and camera", "default": false},
	{"id": "classicCamera", "label": "Lower camera angle (fixed while zooming)", "tab": "controls", "group": "Scheme and camera", "default": false},
	# Camera tuning (Dan, 2026-11-09): try angles in the game, then lock the
	# chosen numbers into CONFIG.camera. Off, the fixed view is used.
	{"id": "camPreset", "label": "Camera preset (sets the sliders below)", "tab": "controls", "group": "Camera tuning", "default": "Live (now)", "choice": true, "options": "CAMERA_PRESETS"},
	{"id": "camTune", "label": "Tune the camera myself (test: find the view, then send Claude the numbers)", "tab": "controls", "group": "Camera tuning", "default": false},
	{"id": "camPitch", "label": "Angle down", "tab": "controls", "group": "Camera tuning", "default": 42, "min": 15, "max": 80, "unit": "°"},
	{"id": "camYaw", "label": "Turn", "tab": "controls", "group": "Camera tuning", "default": 0, "min": -60, "max": 60, "unit": "°"},
	{"id": "camDistance", "label": "Distance", "tab": "controls", "group": "Camera tuning", "default": 31, "min": 12, "max": 70, "unit": " m"},
	{"id": "camFov", "label": "Lens (field of view)", "tab": "controls", "group": "Camera tuning", "default": 39, "min": 15, "max": 75, "unit": "°"},
	{"id": "camOrtho", "label": "Flat lens (true isometric: nothing shrinks with distance)", "tab": "controls", "group": "Camera tuning", "default": false},
	{"id": "openingCinematic", "label": "Cinematic arrival for new characters", "tab": "controls", "group": "Arrival", "default": true},
	{"id": "reducedOpeningMotion", "label": "Reduced opening motion (simple fade instead of a camera flight)", "tab": "controls", "default": false},
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
	{"id": "classicLight", "label": "Classic bright lighting (high sun, bright shade, richer colour, clear air; gloomy places stay gloomy)", "tab": "interface", "group": "Graphics", "default": false},
	{"id": "lampShadows", "label": "Shadows from lamps and torches (lower it if the game slows near lights)", "tab": "interface", "group": "Graphics", "default": 1, "webDefault": 0, "min": 0, "max": 2, "names": ["Off", "Player", "Everyone"]},
]

## Camera presets to compare (Dan, 2026-11-09): [angle down, turn,
## distance m, lens], before the zoom wheel (default zoom 0.94). Picking
## one turns camera tuning on and sets the four sliders.
## the Combat move setting (Player._update_jump)
const COMBAT_MOVES := ["Roll", "Hop", "Off"]
const CAMERA_PRESETS := {
	"Live (now)": [42, 0, 31, 39],
	"Live, lower angle": [30, 0, 31, 39],
	"Before today": [50, 0, 36, 35],
	"Before today, lower angle": [45, 0, 36, 35],
	"Claude's pick": [45, 0, 25, 30],
	"Claude's pick, wider": [45, 0, 28, 30],
	"Conquer size, paths kept": [45, 0, 16, 30],
	"Conquer (turned 45°, flat)": [30, 45, 28, 20],
	"Diablo 2, paths kept": [35, 0, 42, 25],
	"Diablo 2 (turned 45°)": [35, 45, 42, 25],
	"RuneScape": [30, 30, 16, 55],
	# turned 45° so walls and roads run on screen diagonals, flat lens
	"Classic isometric (turned 45°, flat)": [35, 45, 30, 35, true],
}

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


## a slider's number as shown: volumes in percent, else in its `unit`
static func shown(s: Dictionary, v: int) -> String:
	return "%d%s" % [v, s.get("unit", "%")]


func get_value(id: String):
	return values.get(id)


func set_value(id: String, v) -> void:
	var s = _def(id)
	if s == null:
		return
	var value = _clean(s, float(v) if s.has("min") else str(v) if s.get("choice") else bool(v))
	values[id] = value
	if id == "camPreset" and CAMERA_PRESETS.has(value):
		var c: Array = CAMERA_PRESETS[value]
		values.camTune = true
		values.camPitch = c[0]
		values.camYaw = c[1]
		values.camDistance = c[2]
		values.camFov = c[3]
		values.camOrtho = c.size() > 4 and c[4]
	Store.set_item(KEY, JSON.stringify(values))
	game.events.emit("settingsChanged", {"id": id, "value": value})

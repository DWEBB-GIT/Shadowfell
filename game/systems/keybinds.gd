class_name Keybinds
extends RefCounted
## Key bindings (Settings, O; src/systems/keybinds.js). Every action has one
## or more keys; players can change them in the Settings window, or use Quick
## bind: hover a bar slot and press a key. Movement stays on WASD and the
## arrow keys. A key held with Shift is its own binding, 'Shift+Digit1'.
##
## Each control scheme (Settings: Classic controls) keeps its own bindings,
## so switching back and forth never loses either set. Mouse aim moves the
## last two spell slots off Q and E (WoW hands strafe there) to R and F, and
## the right mouse button also fires spell slot 1.

const KEY := "shadowfall.keys.v2"
const KEY_AIM := "shadowfall.keys.aim"
## mouse aim's defaults, where they differ from the classic ones
const AIM_KEYS := {"bar0": ["Digit1", "MouseRight"], "bar4": ["KeyR"], "bar5": ["KeyF"]}
## mouse buttons: shown on the bar, but never taken by a key press
const MOUSE := ["MouseRight"]
const KEY_ACTIONS := [
	{"id": "bar0", "label": "Spell bar 1", "group": "Spell bar", "keys": ["Digit1"]},
	{"id": "bar1", "label": "Spell bar 2", "group": "Spell bar", "keys": ["Digit2"]},
	{"id": "bar2", "label": "Spell bar 3", "group": "Spell bar", "keys": ["Digit3"]},
	{"id": "bar3", "label": "Spell bar 4", "group": "Spell bar", "keys": ["Digit4"]},
	{"id": "bar4", "label": "Spell bar 5", "group": "Spell bar", "keys": ["KeyQ"]},
	{"id": "bar5", "label": "Spell bar 6", "group": "Spell bar", "keys": ["KeyE"]},
	{"id": "bar6", "label": "Utility 1", "group": "Utility bar", "keys": ["Shift+Digit1"]},
	{"id": "bar7", "label": "Utility 2", "group": "Utility bar", "keys": ["Shift+Digit2"]},
	{"id": "bar8", "label": "Utility 3", "group": "Utility bar", "keys": ["Shift+Digit3"]},
	{"id": "bar9", "label": "Utility 4", "group": "Utility bar", "keys": ["Shift+Digit4"]},
	{"id": "interact", "label": "Interact", "group": "Actions", "keys": ["Space"]},
	{"id": "cycleTarget", "label": "Next target", "group": "Actions", "keys": ["Tab"]},
	{"id": "crime", "label": "Hold to attack townsfolk", "group": "Actions", "keys": ["AltLeft"]},
	{"id": "sheathe", "label": "Sheathe / draw weapons", "group": "Actions", "keys": ["KeyZ"]},
	{"id": "sit", "label": "Sit / stand", "group": "Actions", "keys": ["KeyX"]},
	{"id": "character", "label": "Character", "group": "Menus", "keys": ["KeyC"]},
	{"id": "spellbook", "label": "Spells", "group": "Menus", "keys": ["KeyP"]},
	{"id": "talents", "label": "Talents", "group": "Menus", "keys": ["KeyN"]},
	{"id": "quests", "label": "Quest log", "group": "Menus", "keys": ["KeyL"]},
	{"id": "map", "label": "World map", "group": "Menus", "keys": ["KeyM"]},
	{"id": "settings", "label": "Settings", "group": "Menus", "keys": ["KeyO"]},
	{"id": "bags", "label": "Bags", "group": "Menus", "keys": ["KeyB", "KeyI"]},
	{"id": "skills", "label": "Professions", "group": "Menus", "keys": ["KeyU"]},
	{"id": "save", "label": "Save the game", "group": "Menus", "keys": ["KeyK"]},
]
## keys nobody may take: movement, Escape and the mouse
const RESERVED := ["KeyW", "KeyA", "KeyS", "KeyD", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Escape"]
const NAMES := {"MouseRight": "RMB", "Space": "Space", "Backquote": "`", "Minus": "-", "Equal": "=", "BracketLeft": "[", "BracketRight": "]", "Semicolon": ";", "Quote": "'", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\", "ShiftLeft": "Shift", "ShiftRight": "RShift", "ControlLeft": "Ctrl", "AltLeft": "Alt", "Tab": "Tab", "CapsLock": "Caps", "Enter": "Enter"}

var game
var map := {}
var aim := true ## which scheme the bindings are for


## how a key code reads on a button: Digit1 -> 1, KeyQ -> Q, Shift+Digit1 -> Shift-1
static func key_label(code: String) -> String:
	if code == "":
		return ""
	if code.begins_with("Shift+"):
		return "Shift-" + key_label(code.substr(6))
	if code.begins_with("Digit"):
		return code.substr(5)
	if code.begins_with("Key"):
		return code.substr(3)
	if code.begins_with("Numpad"):
		return "N" + code.substr(6)
	return NAMES.get(code, code)


## The binding a key press makes: Shift held turns Digit1 into Shift+Digit1.
static func combo_of(code: String, shift: bool) -> String:
	return "Shift+" + code if shift and not code.begins_with("Shift") else code


static func _defaults(for_aim: bool) -> Dictionary:
	var m := {}
	for a in KEY_ACTIONS:
		m[a.id] = (AIM_KEYS[a.id] if for_aim and AIM_KEYS.has(a.id) else a.keys).duplicate()
	return m


func _init(g) -> void:
	game = g
	load_scheme(not g.settings.get_value("classicControls"))
	g.events.on("settingsChanged", func(e):
		if e.id == "classicControls":
			load_scheme(not e.value)
			g.events.emit("keysChanged", {}))


## read the bindings of one scheme (defaults, then what the player changed)
func load_scheme(for_aim: bool) -> void:
	aim = for_aim
	map = _defaults(aim)
	var text = Store.get_item(KEY_AIM if aim else KEY)
	var saved = JSON.parse_string(text) if text != null else null
	if typeof(saved) == TYPE_DICTIONARY:
		for a in KEY_ACTIONS:
			var k = saved.get(a.id)
			if typeof(k) == TYPE_ARRAY and k.all(func(x): return typeof(x) == TYPE_STRING):
				map[a.id] = k


func keys(id: String) -> Array:
	return map.get(id, [])


func label(id: String) -> String:
	return " / ".join(keys(id).map(func(k): return key_label(k)))


func is_bound(code: String) -> bool:
	return map.values().any(func(k): return k.has(code))


## is one of this action's keys held down now?
func held(id: String) -> bool:
	for k in keys(id):
		if game.input.is_held(k):
			return true
	return false


## was this action's key pressed this frame? (consumes the press)
func pressed(id: String) -> bool:
	var hit := false
	for k in keys(id):
		if game.input.consume(k):
			hit = true
	return hit


## Bind a key to an action, taking it from anything else that had it.
## Returns false for keys that cannot be bound.
func bind(id: String, code: String) -> bool:
	if RESERVED.has(code.replace("Shift+", "")) or not map.has(id):
		return false
	for k in map:
		map[k] = map[k].filter(func(c): return c != code)
	# a key replaces the slot's key; the mouse button stays with it
	map[id] = [code] + map[id].filter(func(c): return MOUSE.has(c))
	_save()
	return true


func unbind(id: String) -> void:
	if not map.has(id):
		return
	map[id] = []
	_save()


func reset_all() -> void:
	map = _defaults(aim)
	_save()


func _save() -> void:
	Store.set_item(KEY_AIM if aim else KEY, JSON.stringify(map))
	game.events.emit("keysChanged", {})

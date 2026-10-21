class_name Cursors
extends RefCounted
## Mouse cursors drawn from small SVGs (src/ui/cursors.js), so they match
## the browser build: a sword over an enemy, a speech bubble over a
## townsperson, a hand over loot, a hook over the fishing bob. The grey
## ones mean "too far away" (Dan, 2026-10-21: grey the cursor, never swap
## it for a no-entry sign). The hotspot is the tip at the top left.

const HEAD := "<svg xmlns='http://www.w3.org/2000/svg' width='28' height='28' viewBox='0 0 28 28'>"

static var _cache := {}


static func _sword(blade: String, hilt: String) -> String:
	return "<path d='M2 2 L6 2 L19 15 L15 19 L2 6 Z' fill='%s' stroke='#000' stroke-width='1.2'/><path d='M13 21 L21 13 L23 15 L15 23 Z' fill='%s' stroke='#000'/><path d='M18 20 L24 26 L26 24 L20 18 Z' fill='%s' stroke='#000'/>" % [blade, hilt, hilt]


static func _speech(fill: String) -> String:
	return "<path d='M3 3 H25 V18 H12 L6 24 V18 H3 Z' fill='%s' stroke='#000' stroke-width='1.5'/><circle cx='9' cy='10.5' r='1.6'/><circle cx='14' cy='10.5' r='1.6'/><circle cx='19' cy='10.5' r='1.6'/>" % fill


static func _hand(fill: String) -> String:
	return "<path d='M8 13 V5 a2 2 0 0 1 4 0 V12 V4 a2 2 0 0 1 4 0 V12 V5 a2 2 0 0 1 4 0 V13 V8 a2 2 0 0 1 4 0 V17 c0 5 -3 8 -8 8 h-2 c-4 0 -6 -3 -8 -6 l-3 -5 a2 2 0 0 1 3 -2 Z' fill='%s' stroke='#000' stroke-width='1.2'/>" % fill


const HOOK := "<g fill='none' stroke-linecap='round'><path d='M19 6 V18 a6 6 0 0 1 -12 0 V12 L4 15' stroke='#000' stroke-width='4.5'/><path d='M19 6 V18 a6 6 0 0 1 -12 0 V12 L4 15' stroke='#d8dce0' stroke-width='2.2'/><circle cx='19' cy='4' r='2.4' stroke='#000' stroke-width='3.5'/><circle cx='19' cy='4' r='2.4' stroke='#d8dce0' stroke-width='1.6'/></g>"


## [svg body, hotspot] per cursor name
static func _defs() -> Dictionary:
	return {
		"fish": [HOOK, Vector2(7, 11)],
		"attack": [_sword("#e8e8f0", "#c89a3a"), Vector2(2, 2)],
		"talk": [_speech("#f0e4c8"), Vector2(2, 2)],
		"talkFar": [_speech("#7a7a7a"), Vector2(2, 2)],
		"loot": [_hand("#f0d070"), Vector2(2, 2)],
		"lootFar": [_hand("#7a7a7a"), Vector2(2, 2)],
	}


## the texture and hotspot for a cursor ("" for none)
static func get_cursor(id: String) -> Array:
	if not _cache.has(id):
		var d = _defs().get(id)
		if d == null:
			return []
		var img := Image.new()
		if img.load_svg_from_string(HEAD + d[0] + "</svg>", 1.0) != OK:
			_cache[id] = []
		else:
			_cache[id] = [ImageTexture.create_from_image(img), d[1]]
	return _cache[id]


## Show a cursor by name, or the plain arrow for "".
static func show(id: String) -> void:
	var c := get_cursor(id) if id != "" else []
	if c.is_empty():
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	else:
		Input.set_custom_mouse_cursor(c[0], Input.CURSOR_ARROW, c[1])
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)

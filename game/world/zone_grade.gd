class_name ZoneGrade
extends RefCounted
## Per-area colour grading (Dan, 2026-11-02): each colour zone gives the
## place it covers its own mood: a warm tint over fields and towns, a purple
## one over a graveyard, its own fog and light. Zones are circles with a soft
## edge (`feather`), kept per map in <map folder>/grades.json and placed and
## tuned in the World editor (Colour zones). Where zones overlap, the later one
## in the file wins. The game eases between them as the player walks.
##
## Every field is optional except the circle: a zone only changes the groups
## it has (colour always; fog and light only when it carries them), so a zone
## inside the Blackwood keeps the wood's gloom unless it says otherwise.
## Cost: one 256 px colour ramp in the tonemap pass, which runs anyway; no
## extra pass, so it is as cheap on the web build as on desktop.

const FILE := "grades.json"

## The grade fields, by group, and what "no change" is for each.
const COLOUR := ["tint", "shadowTint", "tintStrength", "saturation", "contrast", "brightness"]
const FOG := ["fogColor", "fogNear", "fogFar", "fogAmount", "mist"]
const LIGHT := ["ambientColor", "ambient", "sunlight"]
const COLOR_FIELDS := ["tint", "shadowTint", "fogColor", "ambientColor"]

static var zones: Array = []
static var _loaded_from := ""
static var _stamp := 0


static func path() -> String:
	return Terrain.dir + FILE


## The zones of the current map (read once; `reload` reads them again).
static func list() -> Array:
	if _loaded_from != path():
		reload()
	return zones


static func reload() -> void:
	_loaded_from = path()
	zones = []
	_stamp = _modified()
	if not FileAccess.file_exists(_loaded_from):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(_loaded_from))
	if not data is Dictionary:
		push_warning("Colour zones: cannot read " + _loaded_from)
		return
	for z in data.get("zones", []):
		if z is Dictionary and z.has("position"):
			zones.append(parse(z))


## Run from the Godot editor: true once grades.json was saved since it was
## read, so tuning a zone in the editor shows in the running game.
static func changed_on_disk() -> bool:
	if not OS.has_feature("editor"):
		return false
	return _modified() != _stamp


static func _modified() -> int:
	var p := ProjectSettings.globalize_path(path())
	return FileAccess.get_modified_time(p) if FileAccess.file_exists(path()) else 0


## A zone record with its colours as Colors and numbers as floats.
static func parse(z: Dictionary) -> Dictionary:
	var out := {"name": str(z.get("name", "")), "x": float(z.position[0]), "z": float(z.position[1]),
		"radius": float(z.get("radius", 40.0)), "feather": float(z.get("feather", 25.0)), "grade": {}}
	for k in COLOUR + FOG + LIGHT:
		if z.has(k):
			out.grade[k] = Color(z[k]) if k in COLOR_FIELDS else float(z[k])
	return out


## 1 inside a zone's circle, fading to 0 across its feather.
static func weight(z: Dictionary, x: float, zz: float) -> float:
	var d := Vector2(x - z.x, zz - z.z).length()
	if d <= z.radius:
		return 1.0
	if z.feather <= 0.0:
		return 0.0
	return 1.0 - smoothstep(z.radius, z.radius + z.feather, d)


## The grade at a point: `base` (the world's own air there) with every zone
## covering the point laid over it.
static func target_at(x: float, z: float, base: Dictionary, zone_list: Array) -> Dictionary:
	var out := base.duplicate()
	for zone in zone_list:
		var w := weight(zone, x, z)
		if w > 0.0:
			out = mix(out, zone.grade, w)
	return out


## `a` moved towards `b` by `t` (only the fields `b` has).
static func mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate()
	for k in b:
		if out.has(k):
			out[k] = lerp(out[k], b[k], t)
	return out


## The biggest difference between two grades (0 when they match).
static func distance(a: Dictionary, b: Dictionary) -> float:
	var d := 0.0
	for k in b:
		if not a.has(k):
			return INF
		if b[k] is Color:
			var c: Color = a[k] - b[k]
			d = maxf(d, maxf(absf(c.r), maxf(absf(c.g), absf(c.b))))
		else:
			d = maxf(d, absf(float(a[k]) - float(b[k])) / maxf(1.0, absf(float(b[k]))))
	return d


## The colour part of a grade on an Environment: brightness, contrast and
## saturation, and the tint as a colour ramp (shadows lean to `shadowTint`,
## highlights to `tint`, by `tintStrength`). The ramp is made once and
## repainted in place.
static func apply_colour(env: Environment, g: Dictionary) -> void:
	env.adjustment_enabled = true
	env.adjustment_brightness = g.brightness
	env.adjustment_contrast = g.contrast
	env.adjustment_saturation = g.saturation
	var amount: float = g.tintStrength
	if amount <= 0.002:
		env.adjustment_color_correction = null
		return
	var tex := env.adjustment_color_correction as GradientTexture1D
	if tex == null:
		tex = GradientTexture1D.new()
		tex.width = 256
		tex.gradient = Gradient.new()
		env.adjustment_color_correction = tex
	tex.gradient = ramp(g.shadowTint, g.tint, amount)


## A per-channel curve (Godot reads a 1D colour correction texture one
## channel at a time): grey at full strength becomes the tint, scaled to keep
## its brightness, so a tint shifts hue without darkening the scene.
static func ramp(shadow: Color, high: Color, amount: float) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var colors := PackedColorArray()
	for i in 9:
		var v := i / 8.0
		var t := _unit(shadow).lerp(_unit(high), smoothstep(0.1, 0.9, v))
		var m := Color(1, 1, 1).lerp(t, amount)
		offsets.append(v)
		colors.append(Color(clampf(v * m.r, 0, 1), clampf(v * m.g, 0, 1), clampf(v * m.b, 0, 1)))
	g.offsets = offsets
	g.colors = colors
	return g


## A colour scaled to the brightness of white (so white stays neutral).
static func _unit(c: Color) -> Color:
	var l := maxf(0.05, c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722)
	return Color(c.r / l, c.g / l, c.b / l)

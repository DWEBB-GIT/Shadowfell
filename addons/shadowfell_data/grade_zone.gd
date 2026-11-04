@tool
extends Node3D
## One colour zone in the World editor (see game/world/zone_grade.gd). Move it
## with the gizmo; set its size, colour, fog and light in the Inspector. The
## view tints to the zone while it is selected, so what you set is what you
## see. Ctrl+S writes all zones to the map's grades.json; a game running from
## the editor picks the change up within a second.

const Grade := preload("res://game/world/zone_grade.gd")

@export var zone_name := "":
	set(v):
		zone_name = v
		_changed()
## Full strength inside this many metres.
@export_range(1, 600, 1, "suffix:m") var radius := 40.0:
	set(v):
		radius = v
		_changed()
## Fades out over this many metres past the radius.
@export_range(0, 300, 1, "suffix:m") var feather := 25.0:
	set(v):
		feather = v
		_changed()

@export_group("Colour")
## The colour highlights and midtones lean to (warm gold for fields, violet for graves).
@export var tint := Color("ffd9a0"):
	set(v):
		tint = v
		_changed()
## The colour shadows lean to.
@export var shadow_tint := Color("8a6a5a"):
	set(v):
		shadow_tint = v
		_changed()
## How strongly the tint shows: 0 none, 0.3 clear, 1 heavy.
@export_range(0, 1, 0.01) var tint_strength := 0.25:
	set(v):
		tint_strength = v
		_changed()
@export_range(0, 2, 0.01) var saturation := 0.96:
	set(v):
		saturation = v
		_changed()
@export_range(0.5, 2, 0.01) var contrast := 1.08:
	set(v):
		contrast = v
		_changed()
@export_range(0.5, 1.5, 0.01) var brightness := 1.0:
	set(v):
		brightness = v
		_changed()

@export_group("Fog")
## Off: the zone keeps the fog of the land around it.
@export var change_fog := false:
	set(v):
		change_fog = v
		_changed()
@export var fog_color := Color("9aa7ad"):
	set(v):
		fog_color = v
		_changed()
## Where fog starts and where it is full, in metres from the camera.
@export_range(5, 400, 1, "suffix:m") var fog_start := 60.0:
	set(v):
		fog_start = v
		_changed()
@export_range(10, 500, 1, "suffix:m") var fog_end := 120.0:
	set(v):
		fog_end = v
		_changed()
## How thick the fog gets at its end (1 hides everything past it).
@export_range(0, 1, 0.01) var fog_strength := 1.0:
	set(v):
		fog_strength = v
		_changed()
## Volumetric mist, as a multiple of the usual (desktop only; the web build has none).
@export_range(0, 6, 0.05) var mist := 1.0:
	set(v):
		mist = v
		_changed()

@export_group("Light")
## Off: the zone keeps the light of the land around it.
@export var change_light := false:
	set(v):
		change_light = v
		_changed()
## The colour of the fill light in shade.
@export var ambient_color := Color("71869b"):
	set(v):
		ambient_color = v
		_changed()
## Fill light, as a multiple of the usual.
@export_range(0, 3, 0.01) var ambient := 1.0:
	set(v):
		ambient = v
		_changed()
## Sunlight, as a multiple of the usual.
@export_range(0, 2, 0.01) var sunlight := 1.0:
	set(v):
		sunlight = v
		_changed()

var _ring: MeshInstance3D
var _loading := false


## Fill the fields from a grades.json record.
func load_record(r: Dictionary) -> void:
	_loading = true
	zone_name = str(r.get("name", ""))
	radius = float(r.get("radius", 40.0))
	feather = float(r.get("feather", 25.0))
	var map := {"tint": "tint", "shadowTint": "shadow_tint", "tintStrength": "tint_strength",
		"saturation": "saturation", "contrast": "contrast", "brightness": "brightness",
		"fogColor": "fog_color", "fogNear": "fog_start", "fogFar": "fog_end", "fogAmount": "fog_strength", "mist": "mist",
		"ambientColor": "ambient_color", "ambient": "ambient", "sunlight": "sunlight"}
	for k in map:
		if r.has(k):
			set(map[k], Color(r[k]) if k in Grade.COLOR_FIELDS else float(r[k]))
	change_fog = Grade.FOG.any(func(k): return r.has(k))
	change_light = Grade.LIGHT.any(func(k): return r.has(k))
	_loading = false
	_changed()


## The zone as grades.json keeps it (colours as hex, numbers as typed).
func record() -> Dictionary:
	var r := {"name": zone_name, "position": [snappedf(position.x, 0.1), snappedf(position.z, 0.1)],
		"radius": snappedf(radius, 0.1), "feather": snappedf(feather, 0.1),
		"tint": "#" + tint.to_html(false), "shadowTint": "#" + shadow_tint.to_html(false),
		"tintStrength": snappedf(tint_strength, 0.01), "saturation": snappedf(saturation, 0.01),
		"contrast": snappedf(contrast, 0.01), "brightness": snappedf(brightness, 0.01)}
	if change_fog:
		r.merge({"fogColor": "#" + fog_color.to_html(false), "fogNear": snappedf(fog_start, 0.1),
			"fogFar": snappedf(maxf(fog_end, fog_start + 1), 0.1), "fogAmount": snappedf(fog_strength, 0.01), "mist": snappedf(mist, 0.01)})
	if change_light:
		r.merge({"ambientColor": "#" + ambient_color.to_html(false), "ambient": snappedf(ambient, 0.01), "sunlight": snappedf(sunlight, 0.01)})
	return r


func _changed() -> void:
	if _loading or not is_inside_tree():
		return
	_draw_ring()


func _enter_tree() -> void:
	_draw_ring.call_deferred()


## Two rings on the ground: full strength, and where the fade ends.
func _draw_ring() -> void:
	if not is_inside_tree():
		return
	if _ring == null or not is_instance_valid(_ring):
		for c in get_children():
			if c.name.begins_with("Ring"): # copied along by Ctrl+D
				c.free()
		_ring = MeshInstance3D.new()
		_ring.name = "Ring"
		_ring.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.vertex_color_use_as_albedo = true
		_ring.material_override = m
		_ring.top_level = true
		add_child(_ring) # not owned: drawn, never saved
	var im: ImmediateMesh = _ring.mesh
	im.clear_surfaces()
	var c := tint
	c.a = 1.0
	for r in [radius, radius + feather]:
		if r <= 0:
			continue
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for i in 97:
			var t := TAU * i / 96.0
			var x: float = global_position.x + cos(t) * r
			var z: float = global_position.z + sin(t) * r
			im.surface_set_color(c if r == radius else c.darkened(0.45))
			im.surface_add_vertex(Vector3(x, Terrain.height_at(x, z) + 0.6, z))
		im.surface_end()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_draw_ring()


func _ready() -> void:
	set_notify_transform(true)

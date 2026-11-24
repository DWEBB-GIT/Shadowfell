class_name Atmosphere
extends Node3D
## Local atmosphere and a fixed light budget, shared by every continent region.
const LIGHT_BUDGET := 16
const VOLUME_BUDGET := 8
const SHADOW_BUDGET := 2
const SHADOW_REACH := 16.0
## Desktop volumetric mist, before a colour zone's `mist` multiplier.
const MIST_DENSITY := 0.004
## A shadowed source keeps its shadow until this much further away, so
## walking along a boundary doesn't hand shadows back and forth.
const SHADOW_HOLD := 4.0
var game
var sources: Array = []
var _coast_lamps := {}
## The first SHADOW_BUDGET lamps always have shadows on; the rest never do.
## Switching a light's shadow (or its range) re-renders its shadow map and
## re-pairs everything it lights, which froze the game near lamps, so the
## pool only writes a lamp when the source it shows actually changes.
var lamps: Array[OmniLight3D] = []
var _slot: Array = []
## A shadowless light beside each shadow lamp that lights only moving bodies
## (World.MOVING_LAYER). The shadow lamp itself leaves that layer out, so
## nothing that animates is ever paired with it: in Godot every move or
## skeleton pose of a shadow caster paired with a shadowed light marks its
## shadow map for a full re-render, which was costing frames whenever the
## player, an enemy or an idling NPC stood near a lamp.
var _twins: Array[OmniLight3D] = []
var _everyone := false
var volumes: Array[FogVolume] = []
var wisps: Array = []
var _wait := 0.0
var _time := 0.0
var _volumetric := false
var _window_groups := {}
var _glow: StandardMaterial3D
var _snow: CPUParticles3D
var _dust: CPUParticles3D
var _motes: CPUParticles3D

func _init(g) -> void:
	game = g
	name = "Atmosphere"
	_volumetric = RenderingServer.get_current_rendering_method() == "forward_plus"
	_glow = StandardMaterial3D.new()
	_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow.albedo_color = Color("ffd49a")
	_glow.emission_enabled = true
	_glow.emission = Color("ffb65f")
	_glow.emission_energy_multiplier = 2.2
	_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	var fixtures: Array = Layout.lights.duplicate(true)
	# Lamps placed with the World dock become working lights on the next run.
	for prop in Layout.props:
		var model_id: String = str(prop.get("model", "")).get_file().get_basename()
		if model_id not in ["lamp_post", "torch"]:
			continue
		var at: Array = prop.position
		if fixtures.any(func(l): return Vector2(l.position[0]-at[0], l.position[1]-at[1]).length_squared() < 0.25):
			continue
		var size: float = float(prop.get("scale", 1.0))
		var flame_y := 2.15 if model_id == "lamp_post" else 1.3
		var fixture := {"position": at, "height": flame_y * size, "intensity": 6.0,
			"distance": 8.5, "color": "#ffd198", "flicker": true, "lamp": true}
		if prop.has("worldY"):
			var flame := WorldStream.placed(prop, Transform3D.IDENTITY) * Vector3(0, flame_y, 0)
			fixture.position = [flame.x, flame.z]
			fixture.worldY = flame.y
		fixtures.append(fixture)
	for l in fixtures:
		if l.get("noLight", false):
			continue
		var p: Array = l.position
		var ground := Terrain.height_at(p[0], p[1])
		var y: float = l.worldY if l.has("worldY") else ground + l.get("height", 1.6)
		_source(Vector3(p[0], y, p[1]), Color(l.get("color", "#ffc581")), float(l.get("intensity", 2.0)) * Tex.OMNI_SCALE * 3.0, float(l.get("distance", 8.0)), l.get("flicker", false), "fixture", l.get("shadows", l.get("brazier", false) or l.get("lamp", false)))
		if l.get("lamp", false):
			var glow := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.09
			sphere.height = 0.18
			glow.mesh = sphere
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.layers = World.LIGHT_FIXTURE_LAYER
			glow.material_override = _glow
			var glow_y: float = l.worldY if l.has("worldY") else ground + l.get("height", 2.2)
			glow.position = Vector3(p[0], glow_y, p[1])
			glow.visibility_range_end = 65.0
			add_child(glow)
	for b in Layout.buildings:
		if b.get("light"):
			_source(Vector3(b.position[0] + b.light[0], Terrain.height_at(b.position[0], b.position[1]) + 1.7, b.position[1] + b.light[1]), Color("ffb770"), 2.2, 7.0, true, "hearth")
		_windows(b, true)
	for house in Layout.houses:
		var id: String = house.get("id", "")
		if not ["mausoleum", "crypt", "ruin"].any(func(s): return id.contains(s)):
			_windows(house, false)
	for i in LIGHT_BUDGET:
		var light := OmniLight3D.new()
		light.name = "LocalLight_%02d" % i
		light.shadow_enabled = i < SHADOW_BUDGET
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.shadow_caster_mask = ((1 << 20) - 1) ^ World.LIGHT_FIXTURE_LAYER
		light.shadow_bias = 0.04
		light.shadow_normal_bias = 0.45
		light.shadow_blur = 1.5
		light.shadow_opacity = 0.82
		light.light_specular = 0.8
		light.light_volumetric_fog_energy = 1.4
		light.distance_fade_enabled = true
		light.distance_fade_begin = 48
		light.distance_fade_length = 12
		light.visible = false
		add_child(light)
		lamps.append(light)
		_slot.append(null)
		if i < SHADOW_BUDGET:
			light.light_cull_mask = 0xFFFFF ^ World.MOVING_LAYER
			var twin := OmniLight3D.new()
			twin.name = "LocalLightBodies_%02d" % i
			twin.light_cull_mask = World.MOVING_LAYER
			twin.light_specular = light.light_specular
			twin.light_volumetric_fog_energy = 0.0
			twin.distance_fade_enabled = true
			twin.distance_fade_begin = light.distance_fade_begin
			twin.distance_fade_length = light.distance_fade_length
			twin.visible = false
			add_child(twin)
			_twins.append(twin)
	if _volumetric:
		game.env.volumetric_fog_enabled = true
		game.env.volumetric_fog_density = MIST_DENSITY
		game.env.volumetric_fog_albedo = Color("8c9da5")
		game.env.volumetric_fog_length = 100.0
		game.env.volumetric_fog_detail_spread = 2.0
		game.env.volumetric_fog_temporal_reprojection_enabled = true
		game.env.volumetric_fog_temporal_reprojection_amount = 0.8
		game.env.volumetric_fog_ambient_inject = 0.7
		game.sun.light_volumetric_fog_energy = 0.7
		var noise := FastNoiseLite.new()
		noise.seed = 61101
		noise.frequency = 0.11
		noise.fractal_octaves = 2
		var texture := NoiseTexture3D.new()
		texture.width = 32
		texture.height = 16
		texture.depth = 32
		texture.noise = noise
		for i in VOLUME_BUDGET:
			var fog := FogVolume.new()
			fog.name = "GroundMist_%02d" % i
			fog.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
			fog.size = Vector3(26, 5, 24)
			var mat := FogMaterial.new()
			mat.density = 0.027
			mat.albedo = Color("8aaba8")
			mat.density_texture = texture
			mat.edge_fade = 0.3
			fog.material = mat
			add_child(fog)
			volumes.append(fog)
		# Keep nearby opponents and the player readable through regional haze.
		var clear := FogVolume.new()
		clear.name = "ReadableForeground"
		clear.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		clear.size = Vector3(10, 5, 10)
		var clear_mat := FogMaterial.new()
		clear_mat.density = -0.003
		clear_mat.edge_fade = 0.4
		clear.material = clear_mat
		add_child(clear)
		wisps.append(clear)

func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	for body in get_tree().get_nodes_in_group(World.MOVING_GROUP):
		_mark_moving(body)


## Puts everything drawn under a moving body (its model, gear swapped in
## later, a held torch) on the moving layer.
func _mark_moving(n: Node) -> void:
	if n is VisualInstance3D and not (n.layers & World.LIGHT_FIXTURE_LAYER):
		n.layers = World.MOVING_LAYER
	for c in n.get_children():
		_mark_moving(c)


func _on_node_added(n: Node) -> void:
	if not n is VisualInstance3D:
		return
	var up := n.get_parent()
	while up != null and up is Node3D:
		if up.is_in_group(World.MOVING_GROUP):
			if not (n.layers & World.LIGHT_FIXTURE_LAYER):
				n.layers = World.MOVING_LAYER
			return
		up = up.get_parent()


func _source(p: Vector3, colour: Color, energy: float, radius: float, flicker: bool, kind := "fixture", shadows := false) -> void:
	# Stylised pools retain light across the full nearby tree/prop silhouette.
	# Window and hearth spill stay gentler than exposed outdoor flames.
	var fixture := kind == "fixture"
	var gain := 4.0 if fixture else 1.6
	var reach := clampf(radius * 1.7, 9.0, 16.0) if fixture else minf(radius * 1.3, 10.0)
	sources.append({"at":p, "colour":colour, "energy":energy * gain, "radius":reach,
		"base_energy":energy, "base_radius":radius, "kind":kind,
		"fog":1.4 if fixture else 0.65 if kind == "window" else 0.35,
		"attenuation":0.75 if fixture else 1.0, "shadows":shadows,
		"flicker":flicker, "seed":p.x * 0.1 + p.z * 0.05})

func add_coast_lamp(at: Vector3, style := "amber") -> void:
	var key := Vector3i(at * 10.0)
	if _coast_lamps.has(key):
		return
	_coast_lamps[key] = true
	var colours := {"amber": "ffc58d", "reed": "cfe6a1", "veil": "9bffcf", "grave": "9ddbec"}
	_source(at, Color(colours.get(style, "ffc58d")), 0.72 if style == "amber" else 0.52,
		7.0 if style == "amber" else 5.7, true, "fixture")


func _windows(b: Dictionary, enterable: bool) -> void:
	var group_id: String = b.get("id", "")
	_window_groups[group_id] = []
	var p: Array = b.position
	var size: Array = b.size
	var angle := deg_to_rad(float(b.get("rotation", 0)))
	if size[1] > size[0] and not enterable:
		angle += PI * 0.5
	var length: float = maxf(size[0], size[1]) if not enterable else size[0]
	var span: float = minf(size[0], size[1]) if not enterable else size[1]
	var basis := Basis(Vector3.UP, angle)
	var base := Vector3(p[0], Terrain.height_at(p[0], p[1]), p[1])
	for side in [-1.0, 1.0]:
		for along in [-0.28, 0.28]:
			var window := MeshInstance3D.new()
			window.name = "WarmWindow"
			var box := BoxMesh.new()
			box.size = Vector3(0.67, 0.72, 0.025)
			window.mesh = box
			window.material_override = _glow
			window.transform = Transform3D(basis, base + basis * Vector3(length * along, 1.8, side * (span / 2.0 + 0.105)))
			window.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			window.visibility_range_end = 62
			_window_groups[group_id].append(window)
			add_child(window)
	_source(base + basis * Vector3(0, 1.7, span / 2.0 + 0.7), Color("ffbe7c"), 1.7, 6.0, false, "window")

func _process(dt: float) -> void:
	if not is_instance_valid(game) or not game.player:
		return
	_time += dt
	_wait -= dt
	var focus: Vector3 = game.player.position
	if _wait <= 0:
		_wait = 0.25
		# Windows belong to their walls: hide them with the building cutaway.
		for building in game.world.buildings:
			for window in _window_groups.get(str(building.def.id), []):
				window.visible = building.inside < 0.02
		for house in game.world.see_through.houses:
			for window in _window_groups.get(str(house.mi.name), []):
				window.visible = house.fade > 0.98
		_apply_shadow_level()
		_assign_lamps(focus)
		_update_snow(focus)
		_update_coast_weather(focus)
		if _volumetric:
			var deep := Terrain.gloom(focus.x, focus.z)
			var mist := float(game.grade.get("mist", 1.0))
			var zone_colour: Color = game.grade.get("fogColor", Color("8c9da5"))
			var colour := Color("8c9da5").lerp(Color("72938f"), deep).lerp(zone_colour, 0.58)
			game.env.volumetric_fog_density = lerpf(MIST_DENSITY, 0.007, deep) * mist
			game.env.volumetric_fog_albedo = colour
			for i in volumes.size():
				var a := float(i) * TAU / VOLUME_BUDGET
				var at := focus + Vector3(cos(a) * 18.0, 0, sin(a) * 18.0)
				# Quantised placement reduces temporal swimming while moving.
				at.x = snappedf(at.x, 8)
				at.z = snappedf(at.z, 8)
				at.y = Terrain.height_at(at.x, at.z) + 1.7
				# Written only when they change: setting even the same
				# position or material value re-uploads it.
				if not volumes[i].position.is_equal_approx(at):
					volumes[i].position = at
					volumes[i].visible = at.y > 0.5 and Terrain.water_at(at.x, at.z) == null
				var mat: FogMaterial = volumes[i].material
				var density := lerpf(0.026, 0.046, maxf(deep, 0.3)) * clampf(mist, 0.5, 1.8)
				if not mat.albedo.is_equal_approx(colour) or not is_equal_approx(mat.density, density):
					mat.albedo = colour
					mat.density = density
	for i in lamps.size():
		var light := lamps[i]
		if _slot[i] == null:
			continue
		var s: Dictionary = _slot[i]
		light.light_energy = s.energy * (0.92 + 0.05 * sin(_time * 7 + s.seed) + 0.03 * sin(_time * 13 + s.seed)) if s.flicker else s.energy
		if i < _twins.size():
			_twins[i].light_energy = light.light_energy
	for clear in wisps:
		clear.position = focus + Vector3(0, 2.5, 0)


func _update_snow(focus: Vector3) -> void:
	var snow := float(game.grade.get("snow", 0.0))
	if _snow == null and snow <= 0.07:
		return
	if _snow == null:
		_snow = CPUParticles3D.new()
		_snow.name = "WindblownSnow"
		_snow.amount = 180
		_snow.lifetime = 5.0
		_snow.preprocess = 4.0
		_snow.local_coords = false
		_snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_snow.emission_box_extents = Vector3(18, 5, 18)
		_snow.direction = Vector3(0.65, -1.0, 0.25)
		_snow.spread = 24.0
		_snow.gravity = Vector3(0.35, -0.19, 0.19)
		_snow.initial_velocity_min = 1.1
		_snow.initial_velocity_max = 3.0
		_snow.scale_amount_min = 0.45
		_snow.scale_amount_max = 1.30
		_snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var fleck := QuadMesh.new()
		fleck.size = Vector2(0.095, 0.095)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.84, 0.92, 1.0, 0.60)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var feather := Gradient.new()
		feather.set_color(0, Color.WHITE)
		feather.set_color(1, Color(1, 1, 1, 0))
		var mask := GradientTexture2D.new()
		mask.width = 24
		mask.height = 24
		mask.fill = GradientTexture2D.FILL_RADIAL
		mask.fill_from = Vector2(0.5, 0.5)
		mask.fill_to = Vector2(1.0, 0.5)
		mask.gradient = feather
		mat.albedo_texture = mask
		_snow.material_override = mat
		_snow.mesh = fleck
		add_child(_snow)
	_snow.visible = snow > 0.07
	_snow.emitting = _snow.visible
	if not _snow.emitting:
		return
	_snow.position = focus + Vector3(-2, 7, -1)
	var colour: Color = _snow.material_override.albedo_color
	colour.a = clampf(snow, 0.0, 1.0) * 0.70
	_snow.material_override.albedo_color = colour


func _update_coast_weather(focus: Vector3) -> void:
	var dust := float(game.grade.get("dust", 0.0))
	var motes := float(game.grade.get("motes", 0.0))
	if _dust == null and dust > 0.07:
		_dust = _weather_flecks("WindblownDust", 56, Color("e9c497"), Vector2(0.28, 0.08))
		_dust.emission_box_extents = Vector3(19, 1.5, 17)
		_dust.direction = Vector3(1, 0.02, -0.45)
		_dust.initial_velocity_min = 2.2
		_dust.initial_velocity_max = 5.1
	if _motes == null and motes > 0.07:
		_motes = _weather_flecks("ForestMotes", 38, Color("d5ffb5"), Vector2(0.14, 0.14))
		_motes.emission_box_extents = Vector3(14, 2.0, 13)
		_motes.direction = Vector3(0.28, 0.94, -0.2)
		_motes.initial_velocity_min = 0.12
		_motes.initial_velocity_max = 0.42
	_weather_strength(_dust, focus + Vector3(-6, 1.65, 2), dust, 0.45)
	_weather_strength(_motes, focus + Vector3(0, 2.2, 0), motes, 0.73)


func _weather_flecks(label: String, amount: int, tint: Color, size: Vector2) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.name = label
	emitter.amount = amount
	emitter.lifetime = 5.0
	emitter.preprocess = 3.0
	emitter.gravity = Vector3.ZERO
	emitter.spread = 15.0
	emitter.scale_amount_min = 0.40
	emitter.scale_amount_max = 1.40
	emitter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var feather := Gradient.new()
	feather.set_color(0, Color.WHITE)
	feather.set_color(1, Color(1, 1, 1, 0))
	var mask := GradientTexture2D.new()
	mask.width = 24
	mask.height = 24
	mask.fill = GradientTexture2D.FILL_RADIAL
	mask.fill_from = Vector2(0.5, 0.5)
	mask.fill_to = Vector2(1.0, 0.5)
	mask.gradient = feather
	mat.albedo_texture = mask
	emitter.material_override = mat
	emitter.mesh = quad
	add_child(emitter)
	return emitter


func _weather_strength(emitter: CPUParticles3D, at: Vector3, strength: float, opacity: float) -> void:
	if emitter == null:
		return
	emitter.visible = strength > 0.07
	emitter.emitting = emitter.visible
	if emitter.visible:
		emitter.position = at
		var tint: Color = emitter.material_override.albedo_color
		tint.a = clampf(strength, 0.0, 1.0) * opacity
		emitter.material_override.albedo_color = tint


## Nearest sources to the pool: shadowed fixtures within reach to the shadow
## lamps, the rest to plain ones. A source already on a lamp stays there.
func _assign_lamps(focus: Vector3) -> void:
	var nearby: Array = sources.filter(func(s): return s.at.distance_squared_to(focus) < 55.0 * 55.0)
	nearby.sort_custom(func(a,b): return a.at.distance_squared_to(focus) < b.at.distance_squared_to(focus))
	var shadowed: Array = []
	if _shadows_wanted():
		for s in nearby:
			if shadowed.size() >= SHADOW_BUDGET:
				break
			var reach := SHADOW_REACH + (SHADOW_HOLD if _slot.slice(0, SHADOW_BUDGET).any(func(o): return is_same(o, s)) else 0.0)
			if s.shadows and s.at.distance_squared_to(focus) < reach * reach:
				shadowed.append(s)
	var plain: Array = nearby.filter(func(s): return not shadowed.any(func(o): return is_same(o, s))).slice(0, LIGHT_BUDGET - SHADOW_BUDGET)
	_fill(range(SHADOW_BUDGET), shadowed)
	_fill(range(SHADOW_BUDGET, LIGHT_BUDGET), plain)


func _shadows_wanted() -> bool:
	return _shadow_level() > 0


## Settings "lampShadows": 0 off, 1 the player only, 2 everyone.
func _shadow_level() -> int:
	return 1 if game.settings == null else int(game.settings.get_value("lampShadows"))


## On "Everyone" the shadow lamps light (and are shadowed by) moving bodies
## themselves and the twins rest. Written only when the setting changes.
func _apply_shadow_level() -> void:
	var everyone := _shadow_level() >= 2
	if everyone == _everyone:
		return
	_everyone = everyone
	for i in _twins.size():
		lamps[i].light_cull_mask = 0xFFFFF if everyone else 0xFFFFF ^ World.MOVING_LAYER
		_twins[i].visible = not everyone and _slot[i] != null


func _fill(slots: Array, wanted: Array) -> void:
	var free: Array = []
	var placed: Array = []
	for i in slots:
		if _slot[i] != null and wanted.any(func(s): return is_same(s, _slot[i])):
			placed.append(_slot[i])
		else:
			free.append(i)
	for s in wanted:
		if placed.any(func(o): return is_same(o, s)):
			continue
		var i: int = free.pop_front()
		_slot[i] = s
		var light := lamps[i]
		light.position = s.at
		light.light_color = s.colour
		light.omni_range = s.radius
		light.omni_attenuation = s.attenuation
		light.light_volumetric_fog_energy = s.fog
		light.light_energy = s.energy
		light.visible = true
		if i < _twins.size():
			var twin := _twins[i]
			twin.position = s.at
			twin.light_color = s.colour
			twin.omni_range = s.radius
			twin.omni_attenuation = s.attenuation
			twin.light_energy = s.energy
			twin.visible = not _everyone
	for i in free:
		_slot[i] = null
		lamps[i].visible = false
		if i < _twins.size():
			_twins[i].visible = false

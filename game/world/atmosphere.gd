class_name Atmosphere
extends Node3D
## Local atmosphere and a fixed light budget, shared by every continent region.
const LIGHT_BUDGET := 16
const VOLUME_BUDGET := 8
const SHADOW_BUDGET := 2
const SHADOW_REACH := 16.0
var game
var sources: Array = []
var lamps: Array[OmniLight3D] = []
var volumes: Array[FogVolume] = []
var wisps: Array = []
var shafts: Array[Node3D] = []
var _wait := 0.0
var _time := 0.0
var _volumetric := false
var _window_groups := {}
var _glow: StandardMaterial3D

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
		fixtures.append({"position":at, "height":(2.15 if model_id=="lamp_post" else 1.3)*size, "intensity":6.0, "distance":8.5, "color":"#ffd198", "flicker":true, "lamp":true})
	for l in fixtures:
		if l.get("noLight", false):
			continue
		var p: Array = l.position
		_source(Vector3(p[0], Terrain.height_at(p[0], p[1]) + l.get("height", 1.6), p[1]), Color(l.get("color", "#ffc581")), float(l.get("intensity", 2.0)) * Tex.OMNI_SCALE * 3.0, float(l.get("distance", 8.0)), l.get("flicker", false), "fixture", l.get("shadows", l.get("brazier", false) or l.get("lamp", false)))
		if l.get("lamp", false):
			var glow := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.09
			sphere.height = 0.18
			glow.mesh = sphere
			glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			glow.layers = World.LIGHT_FIXTURE_LAYER
			glow.material_override = _glow
			glow.position = Vector3(p[0], Terrain.height_at(p[0], p[1]) + l.get("height", 2.2), p[1])
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
		light.shadow_enabled = false
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
	if _volumetric:
		game.env.volumetric_fog_enabled = true
		game.env.volumetric_fog_density = 0.004
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
	_build_shafts()

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

func _build_shafts() -> void:
	# Authored tree groups on the new map do not use procedural chunk trees.
	# Sparse art-directed ribbons reinforce real volumetric sun scattering.
	for p in [[-445,-330],[-568,-298],[-400,-187],[-530,-78],[522,-414],[401,-551]]:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://game/render/light_shaft.gdshader")
		mat.set_shader_parameter("uAxis", World.SHAFT_AXIS.normalized())
		mat.set_shader_parameter("uLength", 16.0)
		mat.set_shader_parameter("uWidth", 1.6)
		mat.set_shader_parameter("uFadeNear", 38.0)
		mat.set_shader_parameter("uFadeFar", 60.0)
		mat.set_shader_parameter("uColor", Color(0.95, 0.83, 0.54, 0.10 if _volumetric else 0.17))
		var shaft := Tex.sprite(mat)
		shaft.position = Vector3(p[0], Terrain.height_at(p[0], p[1]), p[1]) - World.SHAFT_AXIS.normalized() * 15.0
		shaft.custom_aabb = AABB(Vector3(-6,-20,-6), Vector3(22,24,20))
		shaft.visibility_range_end = 65
		add_child(shaft)
		shafts.append(shaft)

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
		var nearby: Array = sources.filter(func(s): return s.at.distance_squared_to(focus) < 55.0 * 55.0)
		nearby.sort_custom(func(a,b): return a.at.distance_squared_to(focus) < b.at.distance_squared_to(focus))
		var shadow_count := 0
		for i in LIGHT_BUDGET:
			lamps[i].visible = i < nearby.size()
			if i < nearby.size():
				var s: Dictionary = nearby[i]
				lamps[i].position = s.at
				lamps[i].light_color = s.colour
				lamps[i].omni_range = s.radius
				lamps[i].omni_attenuation = s.attenuation
				lamps[i].light_volumetric_fog_energy = s.fog
				var casts: bool = s.shadows and shadow_count < SHADOW_BUDGET and s.at.distance_squared_to(focus) < SHADOW_REACH * SHADOW_REACH
				lamps[i].shadow_enabled = casts
				if casts:
					shadow_count += 1
				lamps[i].set_meta("source", s)
			else:
				lamps[i].shadow_enabled = false
		if _volumetric:
			var deep := Terrain.gloom(focus.x, focus.z)
			var colour := Color("8c9da5").lerp(Color("72938f"), deep)
			game.env.volumetric_fog_density = lerpf(0.004, 0.007, deep)
			game.env.volumetric_fog_albedo = colour
			for i in volumes.size():
				var a := float(i) * TAU / VOLUME_BUDGET
				var at := focus + Vector3(cos(a) * 18.0, 0, sin(a) * 18.0)
				# Quantised placement reduces temporal swimming while moving.
				at.x = snappedf(at.x, 8)
				at.z = snappedf(at.z, 8)
				at.y = Terrain.height_at(at.x, at.z) + 1.7
				volumes[i].position = at
				volumes[i].visible = at.y > 0.5 and Terrain.water_at(at.x, at.z) == null
				var mat: FogMaterial = volumes[i].material
				mat.albedo = colour
				mat.density = lerpf(0.026, 0.046, maxf(deep, 0.3))
	for light in lamps:
		if not light.visible:
			continue
		var s: Dictionary = light.get_meta("source")
		light.light_energy = s.energy * (0.92 + 0.05 * sin(_time * 7 + s.seed) + 0.03 * sin(_time * 13 + s.seed)) if s.flicker else s.energy
	for clear in wisps:
		clear.position = focus + Vector3(0, 2.5, 0)

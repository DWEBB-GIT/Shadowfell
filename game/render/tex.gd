class_name Tex
extends RefCounted
## Small generated textures for effects (src/render/textures.js): a glint,
## a ring, a soft blob shadow and ground mist. Made once and shared.

static var _cache := {}


static func _radial(stops: Array, size := 64) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(stops.map(func(s): return s[0]))
	g.colors = PackedColorArray(stops.map(func(s): return s[1]))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


static func glint() -> Texture2D:
	if not _cache.has("glint"):
		_cache.glint = _radial([[0.0, Color8(255, 236, 190, 255)], [0.25, Color8(255, 214, 150, 128)], [1.0, Color8(255, 200, 120, 0)]], 32)
	return _cache.glint


static func ring() -> Texture2D:
	if not _cache.has("ring"):
		_cache.ring = _radial([[0.0, Color(1, 1, 1, 0)], [0.56, Color(1, 1, 1, 0)], [0.868, Color8(255, 240, 210, 230)], [1.0, Color8(255, 240, 210, 0)]], 64)
	return _cache.ring


static func blob() -> Texture2D:
	if not _cache.has("blob"):
		_cache.blob = _radial([[0.0, Color(0, 0, 0, 0.55)], [1.0, Color(0, 0, 0, 0)]], 32)
	return _cache.blob


## the ground's hand-painted grain: grey specks, multiplied over the terrain colours
static func ground_detail() -> Texture2D:
	if _cache.has("ground"):
		return _cache.ground
	var rand := U.Seeded.new(7)
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color8(0xd8, 0xd8, 0xd8))
	for i in 900:
		var v := int(floor(170 + rand.next() * 85))
		var w := 1 + int(floor(rand.next() * 2))
		var x := int(floor(rand.next() * s))
		var y := int(floor(rand.next() * s))
		var h := w + int(floor(rand.next() * 2))
		img.fill_rect(Rect2i(x, y, w, h).intersection(Rect2i(0, 0, s, s)), Color8(v, v, v))
	img.generate_mipmaps() # sampled with mipmaps; without them GL samples black
	_cache.ground = ImageTexture.create_from_image(img)
	return _cache.ground


## soft cloudy blotches for ground mist, painted with the same seed as the browser build
static func mist() -> Texture2D:
	if _cache.has("mist"):
		return _cache.mist
	var rand := U.Seeded.new(7)
	# the ground detail texture draws first from the same stream (900 specks, 4-5 draws each)
	for i in 900:
		rand.next(); rand.next(); rand.next(); rand.next(); rand.next()
	var s := 128
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var acc := PackedFloat32Array()
	acc.resize(s * s)
	for i in 26:
		var x := s * (0.32 + rand.next() * 0.36)
		var y := s * (0.32 + rand.next() * 0.36)
		var r := s * (0.1 + rand.next() * 0.17)
		for py in s:
			for px in s:
				var d := Vector2(px + 0.5 - x, py + 0.5 - y).length()
				if d < r:
					var a := 0.22 * (1 - d / r)
					var j := py * s + px
					acc[j] = acc[j] + a * (1 - acc[j])
	for py in s:
		for px in s:
			img.set_pixel(px, py, Color(1, 1, 1, acc[py * s + px]))
	img.generate_mipmaps()
	_cache.mist = ImageTexture.create_from_image(img)
	return _cache.mist


## An unshaded material for effects: additive or plain alpha, optionally a billboard.
static func fx_material(tex: Texture2D, colour: Color, additive := true, billboard := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = tex
	m.albedo_color = colour
	if billboard:
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return m


## A flat quad lying on the ground (size 1 x 1), like a rotated PlaneGeometry.
static func ground_quad(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not _cache.has("plane"):
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		_cache.plane = q
	mi.mesh = _cache.plane # shared: a new mesh per spark was uploaded each time
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A camera-facing quad (a three.js Sprite).
static func sprite(mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if not _cache.has("quad"):
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		_cache.quad = q
	mi.mesh = _cache.quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A three.js PointLight(colour, intensity, distance, decay) as an OmniLight3D.
## three.js divides a light by pi in its Lambert term and Godot does not, so
## a Godot energy is a three.js intensity times LIGHT_SCALE. The falloff
## (inverse power of distance, windowed at the range) is the same in both.
const LIGHT_SCALE := 1.0 / PI
## Godot also multiplies omni lights by pi (power to intensity), so a lamp
## takes another 1/pi.
const OMNI_SCALE := LIGHT_SCALE / PI


static func point_light(colour: Color, intensity: float, distance: float, decay := 2.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = colour
	l.light_energy = intensity * OMNI_SCALE
	l.omni_range = distance
	l.omni_attenuation = decay
	l.shadow_enabled = false
	# lights past the fog cost per-pixel work for nothing: fade them out
	l.distance_fade_enabled = true
	l.distance_fade_begin = 40.0
	l.distance_fade_length = 10.0
	return l

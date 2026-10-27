class_name Icons
extends Node
## Every picture the HUD shows (src/ui/icons.js, src/ui/portraits.js):
##  - item icons, rendered from the same Blender models used in the world, so
##    an item always looks like what you dropped;
##  - Dan's spell icons (assets/icons/spells), else the painted glyphs (Glyphs);
##  - target-frame portraits, head and shoulders, made the first time a model
##    is targeted.
## Each is drawn once by its own small viewport and then kept as a texture.

const ITEM_SIZE := 64
const GLYPH_SIZE := 64
const PORTRAIT_SIZE := 96

const SPRITES := "res://assets/icons/%s.png"
const SPELLS := "res://assets/icons/spells/%s.png"
const PROFESSIONS := "res://assets/icons/professions/%s.png"

var items := {} ## model -> Texture2D
var _sprites := {} ## sprite -> Texture2D, or null if the file is missing
var abilities := {} ## ability id -> Texture2D
var _portraits := {} ## model -> Texture2D


func _init() -> void:
	name = "Icons"
	_item_icons()
	for id in Glyphs.ids():
		abilities[id] = _glyph(id)
	# Dan's painted icons (assets/icons/spells/<ability id>.png) win over the glyphs
	for id in DB.abilities:
		var path := SPELLS % id
		if ResourceLoader.exists(path):
			abilities[id] = load(path)


# ------------------------------------------------------------------ items
func _item_icons() -> void:
	var models := {}
	var weapons := {}
	for def in DB.items.values():
		var m = def.get("model")
		if m == null:
			continue
		models[m] = true
		if def.get("kind") == "weapon":
			weapons[m] = true
	for m in models:
		var obj := Assets.instance(m)
		obj.rotation_order = EULER_ORDER_XYZ
		# long items (swords) are shown diagonally, the classic RPG way
		if weapons.has(m):
			obj.rotation = Vector3(0, 0, -PI / 4)
		elif m == "kite_shield" or m == "iron_shield":
			obj.rotation = Vector3(0.15, 0.35, 0)
		else:
			obj.rotation = Vector3(0.5, -0.6, 0)
		items[m] = _snapshot(obj, ITEM_SIZE, Color("f0e8d8"), 3.4, Color("fff0d8"), 3.0, Vector3(2, 3, 4), func(cam: Camera3D, box: AABB):
			# frame the model's largest side, so flat and long items both fill the tile
			var c := box.get_center()
			var radius := maxf(box.size.x, maxf(box.size.y, box.size.z)) / 2
			var dist := radius / tan(deg_to_rad(cam.fov) / 2) * 0.78 + box.size.z / 2
			cam.transform = Transform3D(Basis(), Vector3(c.x, c.y, c.z + dist)))


## A model on its own in a small world: flat light from above (three.js's
## hemisphere light, as in the game) and a key light, drawn once.
func _snapshot(obj: Node3D, size: int, ambient: Color, ambient_k: float, key: Color, key_k: float, key_at: Vector3, frame: Callable) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient
	env.ambient_light_energy = ambient_k * Tex.LIGHT_SCALE
	env.ambient_light_sky_contribution = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var cam := Camera3D.new()
	cam.fov = 30
	cam.near = 0.01
	cam.far = 50
	cam.environment = env
	var light := DirectionalLight3D.new()
	light.light_color = key
	light.light_energy = key_k * Tex.LIGHT_SCALE * Game.SUN_MATCH
	light.transform = Transform3D(Basis(), key_at).looking_at(Vector3.ZERO, Vector3.UP)
	vp.add_child(light)
	vp.add_child(obj)
	vp.add_child(cam)
	frame.call(cam, bounds(obj))
	add_child(vp)
	return vp.get_texture()


## The box around a model's meshes, in the model's parent space.
static func bounds(node: Node3D, under: Node3D = null) -> AABB:
	var out := [null]
	var xf := Transform3D.IDENTITY
	if under != null:
		# the transform from `under` (the model) down to `node`
		var n: Node = node.get_parent()
		while n != null and n != under:
			if n is Node3D:
				xf = n.transform * xf
			n = n.get_parent()
		xf = under.transform * xf
	_bounds(node, xf, out)
	return out[0] if out[0] != null else AABB(Vector3(-0.5, 0, -0.5), Vector3.ONE)


static func _bounds(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var b: AABB = xf * n.mesh.get_aabb()
		out[0] = b if out[0] == null else out[0].merge(b)
	for c in n.get_children():
		_bounds(c, xf, out)


# ------------------------------------------------------------------ glyphs
func _glyph(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(GLYPH_SIZE, GLYPH_SIZE)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var c := Control.new()
	c.size = Vector2(GLYPH_SIZE, GLYPH_SIZE)
	c.draw.connect(func(): Glyphs.paint(Canvas2D.new(c), id, GLYPH_SIZE))
	vp.add_child(c)
	add_child(vp)
	return vp.get_texture()


## the icon for an aura: its own, else its spell's, else the cooking pot
func aura(a: Dictionary) -> Texture2D:
	return abilities.get(a.get("icon", a.get("id", "")), abilities.get(a.get("id", ""), abilities.get("cook")))


## a profession's icon (Dan's, assets/icons/professions/<skill id>.png),
## Camping's tent spell, or null
func profession(id: String) -> Texture2D:
	var path := PROFESSIONS % id
	if ResourceLoader.exists(path):
		return load(path)
	return abilities.get("setCamp") if id == "camping" else null


## an item's icon (its model's), or null for a lettered tile
func item(id) -> Texture2D:
	if id == null:
		return null
	var def := Items.get_def(id)
	if def.is_empty():
		return null
	# a painted sprite (assets/icons) wins over the picture of its model
	var sprite = def.get("sprite")
	if sprite:
		if not _sprites.has(sprite):
			var path := SPRITES % sprite
			_sprites[sprite] = load(path) if ResourceLoader.exists(path) else null
		if _sprites[sprite]:
			return _sprites[sprite]
	return items.get(def.get("model", ""))


# ------------------------------------------------------------------ portraits
## Target-frame portraits, WoW style: a head-and-shoulders picture of each
## model, made the first time it is asked for.
func portrait(model_id: String) -> Texture2D:
	if _portraits.has(model_id):
		return _portraits[model_id]
	var tex := _head_shot(Assets.instance(model_id))
	_portraits[model_id] = tex
	return tex


var _player_shot: SubViewport ## the player's own portrait, made again as their gear changes


## The player frame's portrait: the player's own model as it looks now,
## gear and all (a copy, so the picture holds still)
func player_portrait(model: Node3D) -> Texture2D:
	if _player_shot:
		_player_shot.queue_free()
	var copy := model.duplicate() as Node3D
	copy.visible = true
	copy.transform = Transform3D()
	var tex := _head_shot(copy)
	_player_shot = copy.get_parent() as SubViewport
	return tex


func _head_shot(model: Node3D) -> Texture2D:
	return _snapshot(model, PORTRAIT_SIZE, Color.WHITE, 2.4, Color("ffe0c0"), 3.2, Vector3(1.5, 2, 3), func(cam: Camera3D, box: AABB):
		# frame the head: the Head part if the model has one, else its top
		var head := model.find_child("Head", true, false) as Node3D
		var at: Vector3
		var span: float
		if head:
			var hb := Icons.bounds(head, model)
			at = hb.get_center()
			span = maxf(0.3, hb.size.y * 1.25)
		else:
			at = box.get_center()
			at.y = box.end.y - box.size.y * 0.3
			span = maxf(box.size.x, maxf(box.size.z, 0.6)) * 0.8
		var dist := span / tan(deg_to_rad(cam.fov) / 2)
		cam.transform = Transform3D(Basis(), Vector3(at.x + dist * 0.3, at.y + span * 0.05, at.z + dist)).looking_at(Vector3(at.x, at.y - span * 0.2, at.z), Vector3.UP))

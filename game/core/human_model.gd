class_name HumanModel
extends Node3D
## A modular human from human_male.glb / human_female.glb (built by
## assets/blender/build_humans.py): one Mixamo-named skeleton with every part
## as its own skinned mesh. Shows one face, hair and beard, one armour piece
## per gear slot, and hides the body under armour (human_parts.json says what
## each piece hides). Skin and hair are tinted per character.

const PARTS := "res://assets/models/human_parts.json"
const LOOK_SLOTS := ["face", "hair", "beard"]

static var _manifest := {}

var sex := "male"
var model: Node3D
var skeleton: Skeleton3D
## look slot -> variant ("" for none), e.g. {"face": "A", "hair": "Short", "beard": ""}
var looks := {"face": "A", "hair": "Short", "beard": ""}
## gear slot -> armour type ("cloth", "leather", "mail", "plate")
var armour := {}
var _meshes := {}
var _skin := StandardMaterial3D.new()
var _hair := StandardMaterial3D.new()


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var res = load(PARTS)
		_manifest = res.data if res is JSON else JSON.parse_string(FileAccess.get_file_as_string(PARTS))
	return _manifest


static func create(body_sex := "male", body_looks := {}) -> HumanModel:
	var h := HumanModel.new()
	h.sex = body_sex
	h.looks.merge(body_looks, true)
	h._build()
	return h


func _build() -> void:
	name = "Human"
	model = Assets.instance(manifest().bodies[sex])
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for m in [_skin, _hair]:
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
	set_skin(Color(0.80, 0.60, 0.48))
	set_hair(Color(0.16, 0.11, 0.07))
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(mi.name)] = mi
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mat_name := src.resource_name if src else ""
			if mat_name == "M_Skin":
				mi.set_surface_override_material(i, _skin)
			elif mat_name == "M_Hair":
				mi.set_surface_override_material(i, _hair)
	_refresh()


## Skin and hair colours (an Origin's look). Brows and beards take the hair colour.
func set_skin(c: Color) -> void:
	_skin.albedo_color = c


func set_hair(c: Color) -> void:
	_hair.albedo_color = c


func set_look(slot: String, variant: String) -> void:
	looks[slot] = variant
	_refresh()


## Puts on armour of a type in a gear slot ("" takes it off). Slots without a
## model (neck, rings, trinkets) are ignored.
func set_armour(slot: String, armour_type: String) -> void:
	if armour_type == "":
		armour.erase(slot)
	else:
		armour[slot] = armour_type
	_refresh()


## Dresses the model from equipped items (gear slot -> item dictionary).
func wear(gear: Dictionary) -> void:
	armour.clear()
	for slot in gear:
		var item = gear[slot]
		if item is Dictionary and item.get("kind") == "armor" and item.has("armourType"):
			armour[slot] = item.armourType
	_refresh()


## The armour piece shown for a slot: the asked-for type, else the nearest one built.
func _piece(slot: String, armour_type: String) -> Dictionary:
	var pieces: Dictionary = manifest().armour.get(slot, {})
	if pieces.has(armour_type):
		return pieces[armour_type]
	for t in ["cloth", "leather", "mail", "plate"]:
		if pieces.has(t):
			return pieces[t]
	return {}


func _refresh() -> void:
	var m := manifest()
	var show := {}
	for part in m.body:
		show[part] = true
	var hidden := {}
	for slot in armour:
		var piece := _piece(slot, armour[slot])
		if piece.is_empty():
			continue
		show[piece.part] = true
		for h in piece.hides:
			hidden[h.to_lower() if h.to_lower() in LOOK_SLOTS else h] = true
	for slot in LOOK_SLOTS:
		var variant: String = looks.get(slot, "")
		if variant != "" and not hidden.has(slot) and m.looks[slot].has(variant):
			show[m.looks[slot][variant]] = true
	for part in _meshes:
		_meshes[part].visible = show.has(part) and not hidden.has(part)


## Holds a node (a weapon, a shield) in a hand: "main" (right) or "off" (left).
func attach(node: Node3D, hand := "main") -> BoneAttachment3D:
	var bone: String = manifest().hand_bones[hand]
	var holder := BoneAttachment3D.new()
	holder.name = "Hold_" + hand
	skeleton.add_child(holder)
	holder.bone_name = bone  # after joining the skeleton, so the bone index resolves
	holder.add_child(node)
	return holder

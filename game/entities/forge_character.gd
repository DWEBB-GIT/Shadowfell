class_name ForgeCharacter
extends RefCounted
## Body-specific v6 mesh assembly. Appearance contains no gameplay equipment.
const ROOT := "res://assets/characters/forge_v6/"
const SLOTS := ["helmet", "shoulders", "chest", "bracers", "gloves", "belt", "legs", "feet", "cloak"]
static var _manifest: Dictionary = {}

static func manifest() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "character_manifest.json"))
	return _manifest

static func asset(path: String) -> String:
	return path.replace("res://assets/", ROOT)

static func defaults() -> Dictionary:
	return {"version": 6, "sex": "male", "face": "standard", "hair": "buzzed", "beard": "none", "moustache": "none", "skin_colour": "warm", "hair_colour": "brown", "eye_colour": "brown"}

static func choices(key: String, sex := "male") -> Array:
	var m := manifest()
	match key:
		"sex": return ["male", "female"]
		"face": return m.sexes[sex].appearance.faces.keys()
		"hair": return ["none"] + m.sexes[sex].appearance.hair.keys()
		"beard": return ["none"] + m.sexes[sex].appearance.beards.keys()
		"moustache": return ["none"] + m.sexes[sex].appearance.moustaches.keys()
		"skin_colour": return m.palettes.skin.keys()
		"hair_colour": return m.palettes.hair.keys()
		"eye_colour": return m.palettes.eyes.keys()
	return []

static func clean(incoming = null) -> Dictionary:
	var state := defaults()
	if incoming is Dictionary:
		for key in state:
			if key != "version" and incoming.get(key) in choices(key, str(incoming.get("sex", "male")) if incoming.get("sex") in ["male", "female"] else "male"):
				state[key] = incoming[key]
	return state

static func build(appearance: Dictionary) -> Node3D:
	var state := clean(appearance)
	var model: Node3D = load(asset(manifest().sexes[state.sex].scene)).instantiate()
	model.name = "MythkeepCharacter"
	model.set_meta("forge_appearance", state)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	# Independent resources: neither previews nor another body can change flags.
	var supplied: AnimationLibrary = load(ROOT + "animations/" + state.sex + "_universal.res")
	var library := supplied.duplicate(true) as AnimationLibrary
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "animation_catalog.json"))
	for key in catalog:
		library.get_animation(key).loop_mode = Animation.LOOP_LINEAR if catalog[key].loop else Animation.LOOP_NONE
	for old in player.get_animation_library_list():
		player.remove_animation_library(old)
	var aliases := {"Run":"Jog_Fwd", "Attack":"Sword_Attack", "Cast":"Spell_Simple_Shoot", "Sit":"Sitting_Idle", "Hit":"Hit_Chest", "Death":"Death01"}
	for key in aliases:
		library.add_animation(key, library.get_animation(aliases[key]))
	player.add_animation_library("", library)
	Rig.isolate_materials(model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.set_meta("forge_body", true)
		for surface in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(surface) as BaseMaterial3D
			if mat:
				mat.metallic = 0
				mat.roughness = 1
				mat.normal_enabled = false
				mat.metallic_specular = 0
				mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
				mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT
	add_sockets(model)
	dress(model, {})
	return model

static func add_sockets(model: Node3D) -> void:
	var sk: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var ap := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var idle := ap.get_animation("Idle")
	var reference := {}
	for bone in sk.get_bone_count():
		var local := sk.get_bone_rest(bone)
		for track in idle.get_track_count():
			if str(idle.track_get_path(track).get_concatenated_subnames()) != sk.get_bone_name(bone): continue
			if idle.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				local.basis = Basis(idle.rotation_track_interpolate(track, 0))
			elif idle.track_get_type(track) == Animation.TYPE_POSITION_3D:
				local.origin = idle.position_track_interpolate(track, 0)
		var parent := sk.get_bone_parent(bone)
		reference[bone] = reference[parent] * local if parent >= 0 else local
	for part in {"Torso":"spine_03", "Head":"Head", "Arm_R":"hand_r", "Arm_L":"hand_l"}:
		var bone_name: String = {"Torso":"spine_03", "Head":"Head", "Arm_R":"hand_r", "Arm_L":"hand_l"}[part]
		var rest: Transform3D = reference[sk.find_bone(bone_name)] if part.begins_with("Arm") else sk.get_bone_global_rest(sk.find_bone(bone_name))
		if part.begins_with("Arm"):
			model.set_meta("grip_reference_" + bone_name, rest)
		var at := BoneAttachment3D.new()
		at.name = "Socket_" + part
		at.bone_name = bone_name
		sk.add_child(at)
		var frame := Node3D.new()
		frame.name = part
		var origin := rest.origin
		if part.begins_with("Arm"):
			origin += Vector3(0, 0.62, -0.02)
		# Legacy item coordinates, carried by the actual animated bone.
		frame.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, origin)
		at.add_child(frame)
		if part.begins_with("Arm"):
			var side := "r" if part == "Arm_R" else "l"
			var wrist := sk.get_bone_global_rest(sk.find_bone("hand_" + side))
			var middle := sk.get_bone_global_rest(sk.find_bone("middle_01_" + side)).origin
			var index := sk.get_bone_global_rest(sk.find_bone("index_01_" + side)).origin
			var pinky := sk.get_bone_global_rest(sk.find_bone("pinky_01_" + side)).origin
			# Blade/shaft axis crosses the palm towards the thumb. The grip
			# is inside the palm, rather than at the wrist joint.
			var y := (index-pinky).normalized()
			var x := (middle-wrist.origin).normalized()
			var z := x.cross(y).normalized()
			x = y.cross(z).normalized()
			var grip := Transform3D(Basis(x,y,z), wrist.origin.lerp(middle,0.65)-z*0.018)
			var local_grip := wrist.affine_inverse()*grip
			model.set_meta("palm_grip_"+side, local_grip)
			model.set_meta("held_grip_"+side, frame.transform.affine_inverse()*local_grip)
		if part == "Arm_R":
			var blade := Assets.instance("worn_sword")
			blade.name = "Weapon"
			blade.transform = held_transform(model, "r", {})
			frame.add_child(blade)
	var forearm := sk.find_bone("lowerarm_l")
	var wrist := sk.find_bone("hand_l")
	var shield_at := BoneAttachment3D.new()
	shield_at.bone_name = "lowerarm_l"
	shield_at.name = "ShieldAttachment"
	sk.add_child(shield_at)
	var shield_frame := Node3D.new()
	shield_frame.name = "ShieldGrip"
	var center: Vector3 = reference[forearm].origin.lerp(reference[wrist].origin,0.55)+Vector3(0.09,0,0)
	shield_frame.transform = (reference[forearm] as Transform3D).affine_inverse()*Transform3D(Basis(Vector3.UP,PI/2),center)
	shield_at.add_child(shield_frame)

static func handle_center(definition: Dictionary) -> float:
	match definition.get("model", ""):
		"oak_club", "ironwood_club": return 0.04
		"greatsword": return -0.05
	return 0.0

static func held_transform(model: Node3D, side: String, definition: Dictionary) -> Transform3D:
	return model.get_meta("held_grip_"+side)*Transform3D(Basis.IDENTITY,Vector3(0,-handle_center(definition),0))

static func dress(model: Node3D, equipment: Dictionary) -> void:
	var state: Dictionary = model.get_meta("forge_appearance")
	var m := manifest()
	var spec: Dictionary = m.sexes[state.sex]
	var selected: Array = []
	var hidden: Array = []
	# The supplied body-fitted outfit is the initial armour visual family.
	# Slot visibility always follows the real inventory, never creator presets.
	var slots := {"head":"helmet", "shoulders":"shoulders", "chest":"chest", "wrists":"bracers", "hands":"gloves", "waist":"belt", "legs":"legs", "feet":"feet", "back":"cloak"}
	var hood := false
	# Plain travel garments are part of the base look, as on the previous body.
	# Equipped lower armour replaces the same fitted surfaces.
	for base_slot in ["legs", "feet"]:
		if not equipment.get(base_slot):
			var garment: Dictionary = spec.modules["ranger_" + base_slot]
			selected.append_array(garment.objects)
			hidden.append_array(garment.hide_skin_zones)
	for slot in slots:
		var item = equipment.get(slot)
		if not item:
			continue
		var definition := Items.get_def(item.id)
		if definition.get("cosmetic") or (slot == "head" and item.id in ["watch_helm", "old_watch_helm"]):
			continue
		var module: Dictionary = spec.modules["ranger_" + slots[slot]]
		selected.append_array(module.objects)
		hidden.append_array(module.hide_skin_zones)
		hood = hood or slot == "head"
	for zone in spec.skin_zones:
		if zone != "head" and zone not in hidden:
			selected.append_array(spec.skin_zones[zone])
	selected.append_array(spec.appearance.faces[state.face])
	if state.hair != "none" and not (equipment.get("head") and equipment.head.id in ["watch_helm", "old_watch_helm"]):
		var hairs: Dictionary = spec.hood_hair if hood else spec.appearance.hair
		selected.append_array(hairs.get(state.hair, spec.appearance.hair[state.hair]))
	var facial: Dictionary = spec.get("face_facial_hair", {}).get(state.face, {})
	if state.beard != "none":
		selected.append_array(facial.get("beards", spec.appearance.beards)[state.beard])
	if state.moustache != "none":
		selected.append_array(facial.get("moustaches", spec.appearance.moustaches)[state.moustache])
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		# Only imported body meshes; held gear is managed by Player.
		if not mi.has_meta("forge_body"):
			continue
		mi.visible = str(mi.name) in selected
		for i in mi.mesh.get_surface_count():
			var mat := mi.get_active_material(i) as StandardMaterial3D
			if not mat:
				continue
			var key := mat.resource_name.to_lower().replace(".", "_")
			for role in ["skin", "hair", "eyes"]:
				var colour: String = state[{"skin":"skin_colour", "hair":"hair_colour", "eyes":"eye_colour"}[role]]
				for entry in spec.colors[role]:
					if key == str(entry.material).to_lower().replace(".", "_"):
						mat.albedo_texture = load(asset(m.palette_images[entry.images[colour]]))
			for material_name in spec.colors.solid_facial_hair:
				if key == str(material_name).to_lower().replace(".", "_"):
					var rgb: Array = m.palettes.hair[state.hair_colour]
					var shade: float = spec.colors.get("solid_hair_scale", 0.35)
					mat.albedo_color = Color(rgb[0] * shade, rgb[1] * shade, rgb[2] * shade)

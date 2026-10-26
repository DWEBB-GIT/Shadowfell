extends SceneTree
## Loads both modular humans and checks the skeleton, part swapping and hiding:
##   godot --headless --path . --script res://game/tests/human_check.gd

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func visible_parts(h: HumanModel) -> Array:
	var out := []
	for n in h._meshes:
		if h._meshes[n].visible:
			out.append(n)
	out.sort()
	return out


func _initialize() -> void:
	for sex in ["male", "female"]:
		var h := HumanModel.create(sex, {"face": "B", "hair": "Long", "beard": "Full"})
		root.add_child(h)
		var sk := h.skeleton
		check(sk.find_bone("mixamorig_Hips") == 0, sex + ": Hips is the root bone")
		check(sk.get_bone_count() == HumanModel.manifest().bones.size(), sex + ": bone count")
		for b in HumanModel.manifest().bones:
			check(sk.find_bone(b) >= 0, sex + ": has bone " + b)
		var v := visible_parts(h)
		check("Face_B" in v and "Hair_Long" in v and "Beard_Full" in v and "Torso" in v, sex + ": base look " + str(v))
		check(not ("Chest_Plate" in v), sex + ": no armour by default")
		h.set_armour("chest", "plate")
		h.set_armour("head", "plate")
		h.set_armour("feet", "leather")
		h.set_armour("neck", "plate")  # no model: ignored
		v = visible_parts(h)
		check("Chest_Plate" in v and "Head_Plate" in v and "Feet_Leather" in v, sex + ": armour shown " + str(v))
		check(not ("Torso" in v or "Arms_Upper" in v or "Feet" in v), sex + ": body under armour hidden")
		check(not ("Face_B" in v or "Hair_Long" in v or "Beard_Full" in v), sex + ": great helm hides the head")
		h.set_armour("head", "cloth")
		v = visible_parts(h)
		check("Face_B" in v and not ("Hair_Long" in v), sex + ": hood hides hair only")
		h.wear({"legs": {"kind": "armor", "armourType": "mail"}, "back": {"kind": "armor", "armourType": "cloth"}})
		v = visible_parts(h)
		check("Legs_Mail" in v and "Back_Cloth" in v and "Torso" in v and not ("Chest_Plate" in v), sex + ": wear() " + str(v))
		var sword := Assets.instance("worn_sword")
		var hold := h.attach(sword)
		check(hold.bone_idx == sk.find_bone("mixamorig_RightHand"), sex + ": sword in right hand")
		var tris := 0
		for n in v:
			var mesh: Mesh = h._meshes[n].mesh
			for i in mesh.get_surface_count():
				tris += mesh.surface_get_array_index_len(i) / 3
		print("%s: %d parts shown, %d triangles" % [sex, v.size(), tris])
	print("human_check: %s" % ("ok" if fails == 0 else "%d failures" % fails))
	quit(1 if fails else 0)

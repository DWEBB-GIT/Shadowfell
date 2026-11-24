extends RefCounted
## The editable scene is read as data. Its editor preview never enters the game.

const PATH := "res://game/world/lantern_coast/placements.tscn"
const PAINT_META := &"path_paint"
const SCENERY_META := &"hidden_scenery"
const GROUPS := ["Props", "NPCs", "Enemies"]
const ANGLER := "lc_mill_angler"
const ANGLER_DEF := {"id": ANGLER, "name": "Nell Tallow", "title": "Millpond Angler",
	"mapIcon": "fishing", "model": "tam", "rig": "warden", "level": 3,
	"tool": "fishing_rod", "toolScale": 0.8}


static func read() -> Dictionary:
	return decode(load(PATH) as PackedScene)


static func read_path_paint(packed: PackedScene = null) -> Dictionary:
	return _read_metadata(PAINT_META, packed)


static func read_hidden_scenery(packed: PackedScene = null) -> Dictionary:
	return _read_metadata(SCENERY_META, packed)


static func dressing_id(prop: Dictionary) -> String:
	var p: Array = prop.position
	return "nature:" + ("%s|%.5f|%.5f" % [prop.model, p[0], p[1]]).md5_text()


static func _read_metadata(key: StringName, packed: PackedScene) -> Dictionary:
	if packed == null:
		packed = load(PATH) as PackedScene
	if packed == null:
		return {}
	var scene := packed.get_state()
	for i in scene.get_node_property_count(0):
		if scene.get_node_property_name(0, i) == "metadata/" + key:
			var stored = scene.get_node_property_value(0, i)
			return stored.duplicate() if stored is Dictionary else {}
	return {}


static func decode(packed: PackedScene) -> Dictionary:
	var out := {"Props": [], "NPCs": [], "Enemies": [], "Landmarks": []}
	if packed == null:
		return out
	var scene := packed.get_state()
	var npc_ids := {}
	var enemy_ids := {}
	for i in range(1, scene.get_node_count()):
		var parent := str(scene.get_node_path(i, true)).trim_prefix("./")
		var group := parent.get_slice("/", 0)
		var instance := scene.get_node_instance(i)
		if instance != null and parent in [".", "Regions", "Props", "NPCs", "Enemies"]:
			# A FileSystem drop normally becomes a sibling of the selection.
			group = "Props"
		elif not GROUPS.has(group) or parent != group:
			continue
		var source := {}
		var xf := Transform3D.IDENTITY
		for j in scene.get_node_property_count(i):
			var property := scene.get_node_property_name(i, j)
			var value = scene.get_node_property_value(i, j)
			if property == &"metadata/record" and value is Dictionary:
				source = value.duplicate(true)
			elif property == &"transform" and value is Transform3D:
				xf = value
		if group == "Props" and instance != null:
			source.model = instance.resource_path
		var record := at_transform(group, source, xf)
		var own_id := "lc_edit_" + str(scene.get_node_path(i)).sha256_text().left(14)
		if group == "Props" and record.get("legacy_scene") is PackedScene:
			record.editor_id = own_id
			out.Landmarks.append(record)
		elif group == "Props" and not str(record.get("model", "")).is_empty():
			out.Props.append(record)
		elif group == "NPCs" and not str(record.get("npc", "")).is_empty():
			var id := str(record.get("person", record.npc))
			if npc_ids.has(id):
				record.person = own_id
				id = own_id
			npc_ids[id] = true
			out.NPCs.append(record)
		elif group == "Enemies" and not str(record.get("enemy", "")).is_empty():
			var id := str(record.get("id", own_id))
			record.id = own_id if id.is_empty() or enemy_ids.has(id) else id
			enemy_ids[record.id] = true
			out.Enemies.append(record)
	return out


static func at_transform(group: String, source: Dictionary, xf: Transform3D) -> Dictionary:
	var out := source.duplicate(true)
	out.position = [xf.origin.x, xf.origin.z]
	var angles := xf.basis.orthonormalized().get_euler() * (180.0 / PI)
	if group == "Props":
		var size := xf.basis.get_scale()
		out.worldY = xf.origin.y
		out.rotation = angles.y
		out.rotation3 = [angles.x, angles.y, angles.z]
		out.scale3 = [size.x, size.y, size.z]
	elif group == "NPCs":
		out.facing = angles.y
	return out


static func model_for(group: String, record: Dictionary) -> String:
	match group:
		"NPCs":
			var id := str(record.get("npc", ""))
			return str((ANGLER_DEF if id == ANGLER else DB.npcs.get(id, {})).get("model", ""))
		"Enemies":
			return str(DB.enemies.get(record.get("enemy", ""), {}).get("model", ""))
	return str(record.get("model", ""))

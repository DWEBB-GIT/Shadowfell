extends RefCounted

const ROOT := "res://assets/models/environment/buildings/mythkeep_kit/"
const FINISHES := ["Original", "Ochre", "Weathered Oak", "Forest Canvas", "Winter Slate"]
const BOXES := {
	"bellharbor_inn": [[0, 0, 9.6, 6.4], [6.4, 1.6, 3.2, 6.4]],
	"counting_house": [[0, 0, 6.4, 6.4]],
	"chapel": [[0, 0, 6.4, 9.6]],
	"wooden_hut": [[0, 0, 6.4, 4.62]],
	"stone_wall": [[0, 0, 6.4, 2.0]],
	"stone_wall_half": [[0, 0, 3.2, 2.0]],
	"stone_wall_landing": [[0, 0, 6.4, 2.0]],
	"stone_wall_low_parapet": [[0, 0, 6.4, 2.0]],
	"stone_wall_corner": [[.28, 0, 2.64, 2.0], [0, -1.29, 2.0, .62]],
	"stone_gate": [[-2.4, 0, 1.6, 2.0], [2.4, 0, 1.6, 2.0]],
	"trail_tent": [[-1.44, 0, .42, 3.30], [1.44, 0, .42, 3.30]],
	"large_tent": [[-2.19, 0, .41, 4.21], [2.19, 0, .41, 4.21]],
	"palisade": [[0, 0, 3.15, .31]],
}
const CYLINDERS := {"round_watchtower": 2.43, "round_tower_base": 2.43,
	"campfire": .75, "barrel": .46}
# Local positions align with the kit's hanging lanterns. The game's existing
# pooled lights handle falloff, visibility and regional atmosphere.
const LIGHTS := {
	"bellharbor_inn": [Vector3(-1.27, 2.21, 4), Vector3(1.27, 2.23, 4), Vector3(5.23, 2.09, 5.53)],
	"counting_house": [Vector3(.16, 2.21, 3.93)],
	"chapel": [Vector3(-1.43, 2.53, 5.57), Vector3(1.43, 2.53, 5.57)],
	"wooden_hut": [Vector3(.49, 1.79, 3.08)],
	"stone_gate": [Vector3(-2.52, 2.57, 1.70), Vector3(2.52, 2.57, 1.70)],
	"campfire": [Vector3(0, .64, 0)],
}
const MATERIALS := {
	"Ochre": {"Plaster": "ochre_plaster", "Timber": "weathered_oak", "Stone": "sandstone",
		"Roof": "clay_shingle", "Paint": Color("814a3a")},
	"Weathered Oak": {"Timber": "weathered_oak", "Roof": Color("514c41")},
	"Forest Canvas": {"Canvas": "canvas_green", "Cloth Trim": "canvas_brown"},
	"Winter Slate": {"Roof": Color("9cabb0"), "Timber": "weathered_oak", "Stone": Color("909c9e")},
}
static var _materials := {}


static func key(path: String) -> String:
	return path.get_file().get_basename() if path.begins_with(ROOT) else ""


static func finish(root: Node3D, style: String) -> void:
	var palette: Dictionary = MATERIALS.get(style, {})
	if palette.is_empty():
		return
	var parts := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		parts.push_front(root)
	for part: MeshInstance3D in parts:
		if not part.mesh:
			continue
		for i in part.mesh.get_surface_count():
			var base := part.mesh.surface_get_material(i)
			if base is StandardMaterial3D and palette.has(base.resource_name):
				part.set_surface_override_material(i, _variant(base, style, palette[base.resource_name]))


static func _variant(base: StandardMaterial3D, style: String, swatch: Variant) -> Material:
	var id := style + "|" + base.resource_name
	if not _materials.has(id):
		var material := base.duplicate() as StandardMaterial3D
		if swatch is Color:
			material.albedo_color = swatch
		else:
			material.albedo_texture = load(ROOT + "finishes/" + str(swatch) + ".png") as Texture2D
		_materials[id] = material
	return _materials[id]

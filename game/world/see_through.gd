class_name SeeThrough
extends RefCounted
## Keeping the player in sight from the fixed camera. Since 2026-11-02 (Dan
## disliked whole houses turning see-through) houses use the same round
## see-through circle as trees and rocks, as Lost Ark, Diablo 4 and Path of
## Exile do: only the part of a house between the camera and the player is
## dithered away, the rest stays solid (game/render/cutaway.gdshaderinc).

const FLAT := preload("res://game/render/flat.gdshader") ## editor previews
const CUTAWAY := preload("res://game/render/cutaway.gdshader")

var game
## {mi, form: the house's shape (Town), fade: always 1 now (windows read it)}
var houses := []
var _mat: ShaderMaterial


func _init(g) -> void:
	game = g
	_mat = ShaderMaterial.new()
	_mat.shader = CUTAWAY
	_mat.set_shader_parameter("albedo", Color.WHITE)


## a house drawn with the see-through circle; `form` is its shape in the
## mesh's frame (ridge along x): {hl, hs, top, ridge, slope, eave, tower?}
func add_house(mi: MeshInstance3D, form: Dictionary) -> void:
	mi.material_override = _mat
	houses.append({"mi": mi, "form": form, "fade": 1.0})


## true if a house stands between the camera at `from` and the point `to`
## (quest ! and ? over a townsfolk's head stay hidden behind roofs and
## walls). Tests the segment against each nearby house's box in its own
## frame, a little shrunk so a marker at the eaves still shows.
func hides(from: Vector3, to: Vector3) -> bool:
	for h in houses:
		var mi: MeshInstance3D = h.mi
		if not is_instance_valid(mi) or not mi.is_inside_tree() or not mi.visible:
			continue
		var gt := mi.global_transform
		var d := gt.origin - to
		if d.x * d.x + d.z * d.z > 900.0:
			continue
		var inv := gt.affine_inverse()
		var box := mi.get_aabb().grow(-0.25)
		if box.intersects_segment(inv * from, inv * to) != null:
			return true
	return false


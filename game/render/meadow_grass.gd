@tool
extends Node3D
## Original short meadow clump: five bent, tapered leaves, 18–24 cm high.
## Shared by streamed cover and placed scenes. No borrowed game textures.


static func make_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for leaf in 5:
		var angle := leaf * 2.399963
		var side := Vector3(cos(angle), 0, sin(angle))
		var bend := Vector3(-sin(angle), 0, cos(angle))
		var root := side * (0.035 + leaf * 0.013)
		var h := 0.18 + (leaf % 3) * 0.025
		var tip := root + Vector3.UP * h + bend * 0.065
		var middle := root + Vector3.UP * h * 0.58 + bend * 0.018
		var verts := [root - side * 0.035, root + side * 0.035,
			middle - side * 0.022, middle + side * 0.022, tip]
		for index in [0, 2, 1, 1, 2, 3, 2, 4, 3]:
			st.set_normal(Vector3.UP)
			st.set_color(Color(0.62, 0.72, 0.45).lerp(Color(0.9, 0.96, 0.69), verts[index].y / h))
			st.add_vertex(verts[index])
	return st.commit()


func _init() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "ShortMeadowClump"
	mi.mesh = make_mesh()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

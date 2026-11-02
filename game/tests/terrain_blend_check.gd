extends SceneTree
## World-space paint continuity, smooth normals and brush/undo integration.
const Sculpt := preload("res://addons/shadowfell_world/sculpt.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
	else:
		print("ok: ", message)

func _initialize() -> void:
	ProjectSettings.set_setting(Terrain.MAP_SETTING, "new")
	DB.ensure()
	var left := Vector2i(-8, -4)
	var right := Vector2i(-7, -4)
	var before := Land.surface_control(left)
	check(before.get_width() == 37 and before.get_height() == 37, "padded control field resolves colours independently of mesh vertices")
	check(_seam(left, right), "neighbour control fields match across their complete shared border")
	var material := Land.ground_material()
	check(material is ShaderMaterial and material.shader != null, "world and editor use the surface-blending shader")
	var mesh_a := Land.chunk_ground(left, material)
	var mesh_b := Land.chunk_ground(right, material)
	var arrays_a: Array = mesh_a.mesh.surface_get_arrays(0)
	var arrays_b: Array = mesh_b.mesh.surface_get_arrays(0)
	var normals := {}
	for i in arrays_a[Mesh.ARRAY_VERTEX].size():
		var v: Vector3 = arrays_a[Mesh.ARRAY_VERTEX][i]
		if is_equal_approx(v.x, -448):
			normals[v] = arrays_a[Mesh.ARRAY_NORMAL][i]
	var matches := 0
	var smooth := true
	var height_ok := true
	for i in arrays_b[Mesh.ARRAY_VERTEX].size():
		var v: Vector3 = arrays_b[Mesh.ARRAY_VERTEX][i]
		height_ok = height_ok and absf(v.y - Terrain.height_at(v.x, v.z)) < 0.001
		if normals.has(v):
			matches += 1
			smooth = smooth and normals[v].distance_to(arrays_b[Mesh.ARRAY_NORMAL][i]) < 0.0001
	check(matches > 10 and smooth, "shared chunk vertices have matching smooth lighting normals")
	check(height_ok, "rendered vertex heights retain the existing collision surface")
	mesh_a.free()
	mesh_b.free()
	var h := Terrain.height_at(-452, -204)
	var walk := Terrain.walk_at(-452, -204)
	var brush := Sculpt.new()
	brush.begin_stroke()
	var redraw: Dictionary = brush.apply(Sculpt.PAINT, -452, -204, 1.0, 1.0, 0.5, 0.0, Terrain.DESERT)
	var states: Array = brush.end_stroke()
	check(redraw.has(right), "painting near a chunk edge refreshes the neighbour's padded texture")
	check(Land.surface_control(left).get_data() != before.get_data(), "the material reads a live painted surface")
	check(_seam(left, right), "painting preserves matching shared-edge colours and road masks")
	check(is_equal_approx(h, Terrain.height_at(-452, -204)) and is_equal_approx(walk, Terrain.walk_at(-452, -204)), "surface painting leaves geometry and walkability unchanged")
	brush.restore(states[0])
	check(Land.surface_control(left).get_data() == before.get_data(), "undo restores the exact earlier control colours")
	check(_seam(left, right), "undo preserves shared-edge continuity")
	print("terrain_blend_check: %d failed" % failures)
	quit(1 if failures else 0)

func _seam(left: Vector2i, right: Vector2i) -> bool:
	var a := Land.surface_control(left)
	var b := Land.surface_control(right)
	for j in a.get_height():
		for i in 5:
			if not a.get_pixel(32 + i, j).is_equal_approx(b.get_pixel(i, j)):
				return false
	return true

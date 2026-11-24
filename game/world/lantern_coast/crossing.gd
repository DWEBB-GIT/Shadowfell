@tool
extends Node3D
## Local Z follows the crossing. The walking surface is exactly local Y = 0.

const STONE := 0
const TIMBER := 1
const RAIL_THICKNESS := 0.44
const RAIL_HEIGHT := 1.05

const STONE_COLORS := [
	Color("#727577"), Color("#81817b"), Color("#939188"), Color("#646965"),
]
const TIMBER_COLORS := [
	Color("#79563a"), Color("#886043"), Color("#6d4b35"), Color("#94704c"),
]

@export_range(4.0, 150.0, 0.1, "suffix:m") var length := 30.0:
	set(value):
		length = clampf(value, 4.0, 150.0)
		_schedule_rebuild()

@export_range(2.0, 20.0, 0.1, "suffix:m") var clear_width := 8.0:
	set(value):
		clear_width = clampf(value, 2.0, 20.0)
		_schedule_rebuild()

@export_enum("Stone", "Timber") var variant: int = STONE:
	set(value):
		variant = clampi(value, STONE, TIMBER)
		_schedule_rebuild()

var _rebuild_queued := false


func _ready() -> void:
	_rebuild()


func _schedule_rebuild() -> void:
	if is_node_ready() and not _rebuild_queued:
		_rebuild_queued = true
		_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	var full_width := clear_width + RAIL_THICKNESS * 2.0
	var rail_offset := (clear_width + RAIL_THICKNESS) * 0.5
	_place_shape($Body/Deck, Vector3(0, -0.32, 0), Vector3(full_width, 0.64, length))
	_place_shape($Body/WestRail, Vector3(-rail_offset, RAIL_HEIGHT * 0.5, 0), Vector3(RAIL_THICKNESS, RAIL_HEIGHT, length))
	_place_shape($Body/EastRail, Vector3(rail_offset, RAIL_HEIGHT * 0.5, 0), Vector3(RAIL_THICKNESS, RAIL_HEIGHT, length))

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.94
	surface.set_material(material)
	_draw_foundation(surface, full_width)
	if variant == TIMBER:
		_draw_timber(surface, full_width, rail_offset)
	else:
		_draw_stone(surface, full_width, rail_offset)
	surface.index()
	$Mesh.mesh = surface.commit()


func _place_shape(node: CollisionShape3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.position = center


func _draw_foundation(surface: SurfaceTool, width: float) -> void:
	var depth := 0.55 if variant == TIMBER else 0.95
	_block(surface, Vector3(0, -depth * 0.5 - 0.05, 0), Vector3(width, depth, length), Color("#494e4b"))
	for side in [-1.0, 1.0]:
		var z: float = side * (length * 0.5 - 0.95)
		_block(surface, Vector3(0, -0.85, z), Vector3(width + 0.55, 0.48, 1.9), STONE_COLORS[1])
		_block(surface, Vector3(0, -2.1, z), Vector3(width + 0.22, 2.2, 1.65), STONE_COLORS[0])
		_block(surface, Vector3(0, -3.17, z), Vector3(width + 0.82, 0.53, 2.2), STONE_COLORS[3])
	var pier_count := clampi(ceili(length / 11.0) - 1, 0, 12)
	for i in range(pier_count):
		var z := -length * 0.5 + length * float(i + 1) / float(pier_count + 1)
		_block(surface, Vector3(0, -0.92, z), Vector3(width + 0.32, 0.57, 1.65), STONE_COLORS[2])
		_block(surface, Vector3(0, -2.2, z), Vector3(width * 0.78, 2.35, 1.2), STONE_COLORS[i % STONE_COLORS.size()])
		_block(surface, Vector3(0, -3.42, z), Vector3(width * 0.88, 0.49, 1.75), STONE_COLORS[3])


func _draw_stone(surface: SurfaceTool, width: float, rail_offset: float) -> void:
	var rows := ceili(length / 1.2)
	var columns := ceili(width / 1.55)
	var step_z := length / float(rows)
	var step_x := width / float(columns)
	for row in range(rows):
		var z := -length * 0.5 + (float(row) + 0.5) * step_z
		for column in range(columns):
			var x := -width * 0.5 + (float(column) + 0.5) * step_x
			var color: Color = STONE_COLORS[(row * 13 + column * 19 + row * column) % STONE_COLORS.size()]
			_block(surface, Vector3(x, -0.09, z), Vector3(step_x - 0.035, 0.18, step_z - 0.035), color)
		for side in [-1.0, 1.0]:
			var x: float = side * rail_offset
			_block(surface, Vector3(x, 0.41, z), Vector3(RAIL_THICKNESS - 0.05, 0.82, step_z - 0.023), STONE_COLORS[(row + 1) % STONE_COLORS.size()])
			_block(surface, Vector3(x, 0.92, z), Vector3(RAIL_THICKNESS + 0.02, 0.23, step_z - 0.02), STONE_COLORS[2])
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var x: float = side * rail_offset
			var z: float = end * (length * 0.5 - 0.34)
			_block(surface, Vector3(x, 0.52, z), Vector3(RAIL_THICKNESS, 1.04, 0.66), STONE_COLORS[1])


func _draw_timber(surface: SurfaceTool, width: float, rail_offset: float) -> void:
	var plank_count := ceili(length / 0.55)
	var plank_width := length / float(plank_count)
	for i in range(plank_count):
		var z := -length * 0.5 + (float(i) + 0.5) * plank_width
		var color: Color = TIMBER_COLORS[(i * 3 + floori(float(i) / 5.0)) % TIMBER_COLORS.size()]
		_block(surface, Vector3(0, -0.09, z), Vector3(width, 0.18, plank_width - 0.025), color)
	var sections := ceili(length / 3.0)
	for side in [-1.0, 1.0]:
		var x: float = side * rail_offset
		_block(surface, Vector3(x, 0.49, 0), Vector3(0.22, 0.15, length), TIMBER_COLORS[2])
		_block(surface, Vector3(x, 0.93, 0), Vector3(0.24, 0.15, length), TIMBER_COLORS[0])
		for i in range(sections + 1):
			var z := lerpf(-length * 0.5 + 0.18, length * 0.5 - 0.18, float(i) / float(sections))
			_block(surface, Vector3(x, 0.51, z), Vector3(0.34, 1.05, 0.34), TIMBER_COLORS[1])


func _block(surface: SurfaceTool, center: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var a := center + Vector3(-h.x, -h.y, -h.z)
	var b := center + Vector3(h.x, -h.y, -h.z)
	var c := center + Vector3(h.x, h.y, -h.z)
	var d := center + Vector3(-h.x, h.y, -h.z)
	var e := center + Vector3(-h.x, -h.y, h.z)
	var f := center + Vector3(h.x, -h.y, h.z)
	var g := center + Vector3(h.x, h.y, h.z)
	var h_corner := center + Vector3(-h.x, h.y, h.z)
	_quad(surface, a, d, c, b, Vector3.FORWARD, color)
	_quad(surface, e, f, g, h_corner, Vector3.BACK, color)
	_quad(surface, a, e, h_corner, d, Vector3.LEFT, color)
	_quad(surface, b, c, g, f, Vector3.RIGHT, color)
	_quad(surface, d, h_corner, g, c, Vector3.UP, color)
	_quad(surface, a, b, f, e, Vector3.DOWN, color)


func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, color: Color) -> void:
	for point in [a, c, b, a, d, c]:
		surface.set_normal(normal)
		surface.set_color(color)
		surface.add_vertex(point)

extends SceneTree
## Sample the shipped Coast collision at one-metre cell centres for bake_exits.py.

const SURFACE := preload("res://game/world/lantern_coast/coast_surface.gd")
const ATLAS := preload("res://game/world/lantern_coast/atlas.tres")

func _initialize() -> void:
	var file := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	if file == null:
		quit(1)
		return
	var coast := SURFACE.new()
	var extents: Array = ATLAS.get_meta("terrain_bounds")
	var width := int(extents[2] - extents[0])
	var states := PackedByteArray()
	states.resize(width)
	var heights := PackedFloat32Array()
	heights.resize(width)
	# The outlet bake uses the same slope limit as runtime movement.
	file.store_float(SURFACE.MAX_GRADE)
	for z in range(int(extents[1]), int(extents[3])):
		for x in width:
			var at := Vector2(extents[0] + x + 0.5, z + 0.5)
			var raw: Vector2 = coast.land.floor_sample(at)
			var depth: float = coast.water_height(at) - raw.x
			var wades := depth > 0.0 and depth <= 4.0 and coast._water_kind(at) == SURFACE.INLAND_WATER
			var bridge: Dictionary = coast._bridge(at)
			if not bridge.is_empty():
				states[x] = 2
				heights[x] = maxf(raw.x, coast._deck_height(at, bridge))
			elif wades:
				states[x] = 3
				heights[x] = raw.x + maxf(0, depth - SURFACE.WADE_DEPTH)
			else:
				var inland: bool = coast._water_kind(at) == SURFACE.INLAND_WATER
				states[x] = (2 if coast.can_walk_grade(raw.y) else 1) if coast._ground_supports(-depth, inland) else 0
				heights[x] = raw.x
		file.store_buffer(states)
		file.store_buffer(heights.to_byte_array())
	file.close()
	coast.land.free()
	print("Sampled Coast traversal at 1 m")
	quit()

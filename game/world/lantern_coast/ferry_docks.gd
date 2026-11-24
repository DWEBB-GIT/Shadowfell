extends RefCounted
## The pier ends and sea lanes are shared by the terrain, map and ferry.

const TIDEMARK := {"id":"tidemark_ferry", "name":"Tidemark Quay", "destination":"Tidemark",
	"a":[119, 306], "b":[119, 331], "width":3.8, "height":1.3, "bank_height":4.9, "ramp":15.0}
const CUTLASS := {"id":"cutlass_cove", "name":"Cutlass Cove Jetty", "destination":"Cutlass Cove",
	"a":[732, 298.7], "b":[732, 313.3], "height":1.3}
const STAR_WEST := {"id":"starfall_west", "name":"Starfall West Jetty", "destination":"Starfall Isles",
	"a":[583, 459], "b":[552, 450], "width":3.8, "height":1.3, "bank_height":4.75, "ramp":18.0}
const STAR_EAST := {"id":"starfall_east", "name":"Starfall East Jetty", "destination":"Starfall Isles",
	"a":[678, 449], "b":[695, 424], "width":3.8, "height":1.3, "bank_height":5.25, "ramp":17.0}
const PIERS := [TIDEMARK, STAR_WEST, STAR_EAST]
const BERTH_REACH := 4.55


static func position_of(raw: Array) -> Vector2:
	return Vector2(raw[0], raw[1])


static func seaward(pier: Dictionary) -> Vector2:
	return position_of(pier.a).direction_to(position_of(pier.b))


static func board_at(pier: Dictionary) -> Vector2:
	return position_of(pier.b) - seaward(pier) * 1.45


static func berth(pier: Dictionary) -> Vector2:
	return position_of(pier.b) + seaward(pier) * BERTH_REACH


static func deck_height(pier: Dictionary, distance: float) -> float:
	var ramp: float = pier.get("ramp", 0.0)
	return lerpf(pier.bank_height, pier.height, clampf(distance / ramp, 0.0, 1.0)) if ramp > 0.0 else pier.height


static func routes() -> Array:
	return [
		_route("Tidemark Ferry", TIDEMARK, STAR_WEST,
			[Vector2(119, 345), Vector2(155, 371), Vector2(234, 405), Vector2(342, 433),
			Vector2(447, 448), Vector2(493, 476), Vector2(528, 480),
			Vector2(539, 465), Vector2(543, 452)]),
		_route("Cutlass Ferry", CUTLASS, STAR_EAST,
			[Vector2(732, 328), Vector2(738, 347), Vector2(738, 366), Vector2(729, 387),
			Vector2(719, 399), Vector2(706.0, 407.8)]),
	]


static func _route(name: String, origin: Dictionary, destination: Dictionary, sea: Array) -> Dictionary:
	var start := board_at(origin)
	var finish := board_at(destination)
	var path := [berth(origin)] + sea + [berth(destination)]
	var line := path.map(func(at): return [at.x, at.y])
	return {"name":name, "from":[start.x, start.y], "to":[finish.x, finish.y], "line":line,
		"path":path, "origin":origin, "destination":destination}

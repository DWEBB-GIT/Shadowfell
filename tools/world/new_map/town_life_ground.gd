extends SceneTree
## Second step of tools/world/new_map/town_life.py: moves each town life
## spawn (and each shopper's shop front) that the generator put on blocked
## ground (a wall, a building, a cliff: Terrain.walk_at < 0.5) to the nearest
## open ground within 20 m, and rewrites data/terrain/new_map/town_life.json.
## run_tests checks every spawn stands on open ground.
##   godot --headless --path . --script res://tools/world/new_map/town_life_ground.gd

const PATH := "res://data/terrain/new_map/town_life.json"


func _init() -> void:
	DB.ensure()
	var doc = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var moved := 0
	var stuck := 0
	for sp in doc.spawns.npcSpawns:
		sp.facing = int(sp.facing) # JSON numbers come back as floats
		var p = _open(sp.position)
		if p == null:
			stuck += 1
		elif p != sp.position:
			sp.position = p
			moved += 1
		for k in sp.get("places", {}):
			var q: Array = sp.places[k]
			var o = _open([q[0], q[1]])
			if o != null and o != [q[0], q[1]]:
				q[0] = o[0]
				q[1] = o[1]
				moved += 1
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, " ", false) + "\n")
	f.close()
	print("town life ground: %d moved, %d with no open ground near" % [moved, stuck])
	quit(1 if stuck else 0)


## the spot itself if open, else the nearest open one within 20 m (rings of 0.5 m)
func _open(at: Array):
	var x: float = at[0]
	var z: float = at[1]
	if Terrain.walk_at(x, z) >= 0.75:
		return at
	for ring in range(1, 41):
		var r := ring * 0.5
		var n := ring * 8
		for i in n:
			var a := TAU * i / n
			var px := snappedf(x + cos(a) * r, 0.1)
			var pz := snappedf(z + sin(a) * r, 0.1)
			if Terrain.walk_at(px, pz) >= 0.75:
				return [px, pz]
	return null

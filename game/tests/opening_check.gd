extends SceneTree
## The opening widens in rings (data/world.json `gates`, `houses`, `townWalls`):
##   godot --headless --path . --script res://game/tests/opening_check.gd
## A new character's town gates and the Neck are shut, a shut gate blocks and
## says why, the town gates open once The Missing Delivery is handed in, the
## Neck at level 5, the felled oak never; houses and the palisade stand on
## open ground and keep townsfolk out of their walls. Exits 1 if anything fails.

var failures := 0
var game
var frame := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	DB.ensure()
	# data: houses on open ground, nobody standing inside one
	for h in Layout.houses:
		check(Terrain.walk_at(h.position[0], h.position[1]) >= 0.5, "%s stands on open ground" % h.id)
		for n in Layout.npcs:
			var inside: bool = absf(n.position[0] - h.position[0]) < h.size[0] / 2.0 + 0.5 and absf(n.position[1] - h.position[1]) < h.size[1] / 2.0 + 0.5
			check(not inside, "%s is not inside %s" % [n.id, h.id])
	for gt in Layout.gates:
		var mid := Vector2((gt.line[0][0] + gt.line[1][0]) / 2.0, (gt.line[0][1] + gt.line[1][1]) / 2.0)
		check(Terrain.walk_at(mid.x, mid.y) >= 0.5, "%s stands across open ground" % gt.id)


func _gate(id: String) -> Dictionary:
	for gt in game.world.town.gates:
		if gt.def.id == id:
			return gt
	return {}


## would a mover standing on the middle of this gate be pushed off it?
func _blocks(id: String) -> bool:
	var gt := _gate(id)
	var mid := Vector3((gt.def.line[0][0] + gt.def.line[1][0]) / 2.0, 0, (gt.def.line[0][1] + gt.def.line[1][1]) / 2.0)
	var out: Vector3 = game.collision.resolve(mid, 0.4)
	return Vector2(out.x - mid.x, out.z - mid.z).length() > 0.2


func _process(_dt: float) -> bool:
	frame += 1
	if frame == 1:
		Store.dir = "user://opening_check_store"
		for f in DirAccess.get_files_at(Store.dir):
			DirAccess.remove_absolute(Store.dir + "/" + f)
		game = load("res://game/main.tscn").instantiate()
		root.add_child(game)
	elif frame == 3:
		var r = game.roster.create("Nobody", "warden")
		game.enter_world(r.character.id)
	elif frame == 10:
		check(game.world.town.group.get_child_count() >= Layout.houses.size() + Layout.gates.size(), "houses, palisades and gates are built")
		check(_gate("brackenford_east_gate").open, "the east gate into town stands open")
		check(not _gate("brackenford_north_gate").open and _blocks("brackenford_north_gate"), "a new character's north gate is shut and blocks")
		check(not _gate("the_neck_barricade").open and _blocks("the_neck_barricade"), "the Neck is barred")
		check(_blocks("felled_oak"), "the felled oak blocks the lane")
		# walking up to a shut gate says why
		var gt := _gate("brackenford_north_gate")
		game.player.place_at((gt.def.line[0][0] + gt.def.line[1][0]) / 2.0, gt.def.line[0][1] + 1.5)
	elif frame == 20:
		check(game.world.town._nagged.has("brackenford_north_gate"), "a shut gate tells you why")
		# hand in The Missing Delivery: the town opens
		game.quests.done["missing_delivery"] = true
	elif frame == 50:
		check(_gate("brackenford_north_gate").open and not _blocks("brackenford_north_gate"), "the town gates open after The Missing Delivery")
		check(_gate("brackenford_south_gate").open, "the south gate opens with it")
		check(not _gate("the_neck_barricade").open, "the Neck stays barred below level 5")
		game.progression.level = 5
	elif frame == 80:
		check(_gate("the_neck_barricade").open and not _blocks("the_neck_barricade"), "the Neck opens at level 5")
		check(not _gate("felled_oak").open and _blocks("felled_oak"), "the felled oak never opens in Act 1")
		print("opening_check: %s (%d failures)" % ["OK" if failures == 0 else "FAILED", failures])
		quit(1 if failures else 0)
	return false

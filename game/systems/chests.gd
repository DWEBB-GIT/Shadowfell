class_name Chests
extends RefCounted
## Chests in the world (data/world.json `chests`; src/systems/chests.js).
## Walk up and open one (E, or click it): what it holds goes into your bags
## (onto the ground beside it if they are full) and its silver into your
## purse. A chest with a `lock` needs its key in your bags, or Lockpicking
## of at least `pick` and a set of lockpicks; each lock picked raises the
## skill. Opened chests stay open: the world state remembers them.

const REACH := 2.4

var game
var list: Array = []


func _init(g) -> void:
	game = g
	for def in DB.world.get("chests", []):
		list.append({"def": def, "x": def.position[0], "z": def.position[1], "group": null, "collider": false})


func spawn_all() -> void:
	for c in list:
		if c.group:
			c.group.queue_free()
		c.group = Node3D.new()
		c.group.add_child(Assets.instance("chest"))
		c.group.position = Vector3(c.x, Terrain.height_at(c.x, c.z), c.z)
		c.group.rotation.y = deg_to_rad(c.def.get("facing", 0))
		game.scene.add_child(c.group)
		if not c.collider:
			game.collision.add(c.x, c.z, 0.45)
		c.collider = true
		_look(c)


func opened(c: Dictionary) -> bool:
	return game.world_state.is_collected("chest:" + c.def.id)


## an opened chest is shown open: darker
func _look(c: Dictionary) -> void:
	var mats := Rig.isolate_materials(c.group)
	if opened(c):
		Rig.tint(mats, Color(0.55, 0.55, 0.55))


## what stops this chest opening: "", or the error
func _lock_state(c: Dictionary) -> String:
	var lock = c.def.get("lock")
	if not lock:
		return ""
	var inventory = game.inventory
	var skills = game.skills
	if lock.get("key") and inventory.count(lock.key) > 0:
		return ""
	if lock.get("pick") and skills.has("lockpicking") and skills.rank("lockpicking") >= lock.pick and inventory.count("lockpicks") > 0:
		return ""
	var ways := []
	if lock.get("key"):
		ways.append("the %s" % Items.get_def(lock.key).name)
	if lock.get("pick"):
		ways.append("Lockpicking %d and lockpicks" % lock.pick)
	return "It's locked. You need %s." % " or ".join(ways)


func interactions() -> Array:
	var out := []
	for c in list:
		if opened(c):
			continue
		var lock = c.def.get("lock")
		var blocked := _lock_state(c)
		var prompt := "Open the %s" % c.def.name
		if lock and blocked == "":
			if lock.get("key") and game.inventory.count(lock.key) > 0:
				prompt = "Unlock the %s (%s)" % [c.def.name, Items.get_def(lock.key).name]
			else:
				prompt = "Pick the lock (Lockpicking %d)" % lock.pick
		if blocked != "":
			prompt = "%s (locked)" % c.def.name
		out.append({"key": "chest:" + c.def.id, "x": c.x, "z": c.z, "bias": -0.2, "reach": REACH, "prompt": prompt, "chest": c, "run": func(): return open(c)})
	return out


func open(c: Dictionary) -> bool:
	var inventory = game.inventory
	var events: Events = game.events
	if opened(c):
		return false
	var blocked := _lock_state(c)
	if blocked != "":
		game.hud.error(blocked)
		return false
	var lock = c.def.get("lock")
	if lock and not (lock.get("key") and inventory.count(lock.key) > 0):
		events.emit("log", {"text": "You pick the lock of the %s." % c.def.name, "kind": "level"})
		game.skills.raise("lockpicking")
	game.world_state.mark_collected("chest:" + c.def.id)
	for it in c.def.get("items", []):
		if not inventory.add_item(it.id, it.get("count", 1)):
			game.loot.drop_at({"id": it.id, "count": it.get("count", 1)}, Vector3(c.x + 0.9, 0, c.z + 0.4))
	if c.def.get("coins"):
		inventory.add_coins(c.def.coins, "in the %s" % c.def.name)
	events.emit("log", {"text": "You open the %s." % c.def.name, "kind": "loot"})
	events.emit("chestOpened", {"id": c.def.id})
	_look(c)
	return true


func near(x: float, z: float):
	for c in list:
		if U.hyp(c.x - x, c.z - z) < 1.2:
			return c
	return null

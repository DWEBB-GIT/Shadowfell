class_name Npcs
extends RefCounted
## Townsfolk (src/systems/npcs.js). Each NPC stands at its post, works (Mara
## hammers at her anvil) and turns to face the player when they talk to them
## (Dan, 2026-10-21: not just for walking past).
## Talking to one opens a conversation (dialogue.gd), which leads to quests
## and the shop. A spawn with `goneWhen` (a dialogue condition, such as a
## story flag) is absent while it holds.


class Npc:
	extends RefCounted
	var game
	var def: Dictionary
	var id: String
	var name: String
	var position: Vector3
	var rest_facing: float
	var facing: float
	var radius := 0.4
	var group: Node3D
	var model: Node3D
	var rig: Rig
	var board := false ## a notice board: never turns or works
	var work_timer: float
	var collider: Dictionary
	var present := true

	func _init(g, d: Dictionary) -> void:
		game = g
		def = d
		id = d.id
		name = d.name
		position = Vector3(d.position[0], 0, d.position[1])
		position.y = Terrain.height_at(position.x, position.z)
		rest_facing = deg_to_rad(d.get("facing", 0))
		facing = rest_facing
		group = Node3D.new()
		group.name = "Npc_" + id
		model = Assets.instance(d.model)
		group.add_child(model)
		rig = Rig.new(model, "warden")
		# townsfolk who share a model are told apart by a tint
		if d.get("tint"):
			Rig.tint(Rig.isolate_materials(model), Color(d.tint))
		board = d.get("board", false)
		work_timer = 1 + randf()
		group.position = position
		collider = game.collision.add(position.x, position.z, radius)

	## Is this person here, given the story so far?
	func update_presence() -> void:
		var here: bool = not d_gone()
		if here == present:
			return
		present = here
		group.visible = here
		collider.off = not here

	func d_gone() -> bool:
		return def.get("goneWhen") != null and Quests.condition_holds(game, def.goneWhen)

	func update(dt: float, player) -> void:
		var dx: float = player.position.x - position.x
		var dz: float = player.position.z - position.z
		# only someone you are talking to turns to you, and keeps an eye on
		# you until you walk off
		var near: bool = (is_same(game.dialogue.npc, self) or is_same(game.merchant.npc, self)) and U.hyp(dx, dz) < 8 and not player.dead
		var anvil = def.get("anvil")
		var want: float
		if board:
			want = rest_facing
		elif near:
			want = atan2(dx, dz)
		elif anvil:
			want = atan2(anvil[0] - position.x, anvil[1] - position.z)
		else:
			want = rest_facing
		var d := want - facing
		d = atan2(sin(d), cos(d))
		facing += d * minf(1, dt * 5)
		# at work: a hammer blow every so often, unless someone wants a word
		if anvil and not near:
			work_timer -= dt
			if work_timer <= 0:
				work_timer = 1.5 + randf() * 0.8
				rig.play("strike", 0.6, 0.45)
				game.events.emit("anvilStrike", {"npc": self, "x": anvil[0], "z": anvil[1]})
		rig.update(dt, 0)
		group.position = position
		group.rotation.y = facing


var game
var all: Array = []


func _init(g) -> void:
	game = g
	for d in Layout.npcs:
		var n := Npc.new(game, d)
		all.append(n)
		game.scene.add_child(n.group)


## the townsfolk who are here now
var list: Array:
	get:
		return all.filter(func(n): return n.present)


func by_id(id: String):
	for n in all:
		if n.present and n.id == id:
			return n
	return null


func update(dt: float) -> void:
	for n in all:
		n.update_presence()
	for n in all:
		if n.present:
			n.update(dt, game.player)


## what the interaction system offers for each NPC
func interactions() -> Array:
	var out := []
	for n in list:
		out.append({"key": "npc:" + n.id, "x": n.position.x, "z": n.position.z, "bias": -0.6, "reach": DB.CONFIG.shop.talkRange, "prompt": "Talk to %s" % n.name, "run": func(): talk(n)})
	return out


func talk(n) -> void:
	# a notice board stays as it was put up; people turn to you
	if not n.board:
		n.facing = atan2(game.player.position.x - n.position.x, game.player.position.z - n.position.z)
	game.dialogue.open(n)

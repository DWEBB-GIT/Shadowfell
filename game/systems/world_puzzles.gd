@tool
class_name WorldPuzzles
extends RefCounted
## Small authored mechanisms. Nodes live in the world, progress in the save;
## examining their clues never substitutes for operating the mechanism.

var game
var visuals := {}
var _clock := 0.0


func _init(g) -> void:
	game = g


static func definition(id: String) -> Dictionary:
	for p in DB.world.get("puzzles", []):
		if p.id == id:
			return p
	return {}


static func valid_saved_states(states) -> bool:
	if not states is Dictionary:
		return false
	for id in states:
		var s = states[id]
		if not id is String or not s is Dictionary:
			return false
		if not s.get("values", []) is Array or not s.get("solved", false) is bool:
			return false
		for v in s.get("values", []):
			if not (v is int or v is float) or v != floorf(v) or v < 0 or v > 100:
				return false
		var n = s.get("progress", 0)
		if not (n is int or n is float) or n != floorf(n) or n < 0 or n > 100:
			return false
	return true


func state(id: String) -> Dictionary:
	var p := definition(id)
	if p.is_empty():
		return {}
	if not game.world_state.puzzles.has(id):
		game.world_state.puzzles[id] = {"values": p.nodes.map(func(_n): return 0), "progress": 0, "solved": false}
	var s: Dictionary = game.world_state.puzzles[id]
	# A later authored dial count must not make an older character unreadable.
	if s.get("values", []).size() != p.nodes.size():
		s.values = p.nodes.map(func(_n): return 0)
	s.progress = clampi(int(s.get("progress", 0)), 0, maxi(0, p.get("answer", []).size() - 1)) if not s.get("solved", false) else p.get("answer", []).size()
	s.solved = bool(s.get("solved", false))
	return s


func solved(id: String) -> bool:
	return not definition(id).is_empty() and state(id).get("solved", false)


func build() -> WorldPuzzles:
	for p in DB.world.get("puzzles", []):
		var root := visual(p)
		root.position = Vector3(p.position[0], Terrain.height_at(p.position[0], p.position[1]), p.position[1])
		game.world.group.add_child(root)
		visuals[p.id] = root
		for n in p.nodes:
			game.collision.add(p.position[0] + n.offset[0], p.position[1] + n.offset[1], 0.28)
	refresh()
	return self


func interactions() -> Array:
	var out := []
	for p in DB.world.get("puzzles", []):
		var s := state(p.id)
		for i in p.nodes.size():
			var n: Dictionary = p.nodes[i]
			var text: String = n.name
			if s.solved:
				text += " — settled"
			elif p.kind == "dials":
				text = "Turn %s (%s)" % [n.name, p.states[int(s.values[i]) % p.states.size()]]
			else:
				text = "Ring %s (%d/%d)" % [n.name, s.progress, p.answer.size()]
			out.append({"key": "puzzle:%s:%d" % [p.id, i], "x": p.position[0] + n.offset[0], "z": p.position[1] + n.offset[1], "bias": 0.0, "reach": 1.65,
				"prompt": text, "run": func(): operate(p.id, i)})
		for action in ["check", "reset"]:
			if action == "check" and p.kind != "dials":
				continue
			var off: Array = p.get(action + "Offset", [0, 2])
			out.append({"key": "puzzle:%s:%s" % [p.id, action], "x": p.position[0] + off[0], "z": p.position[1] + off[1], "bias": 0.0, "reach": 1.5,
				"prompt": ("Read %s" % p.name if s.solved else "Test the flow" if action == "check" else "Reset %s" % p.name), "run": func(): operate(p.id, action)})
	return out


func operate(id: String, action) -> bool:
	var p := definition(id)
	if p.is_empty() or game.player.dead or game.player.ghost:
		return false
	var s := state(id)
	if s.solved:
		_say(p.success)
		return false
	var q: String = p.get("quest", "")
	if q != "" and game.quests.status(q) not in ["active", "ready"]:
		_say(p.get("lockedText", "Ask the keeper about this mechanism first."))
		return false
	# This check also guards direct calls, not only the normal interaction UI.
	var off: Array
	if action is int:
		if action < 0 or action >= p.nodes.size():
			return false
		off = p.nodes[action].offset
	elif action in ["check", "reset"]:
		off = p.get(action + "Offset", [0, 2])
	else:
		return false
	var x: float = p.position[0] + off[0]
	var z: float = p.position[1] + off[1]
	if Vector2(game.player.position.x - x, game.player.position.z - z).length() > 2.2 or game.collision.wall_between(game.player.position.x, game.player.position.z, x, z):
		game.hud.error("Move closer to the mechanism.")
		return false
	var completed := false
	if action is String and action == "reset":
		s.values = p.nodes.map(func(_n): return 0)
		s.progress = 0
		_say(p.get("resetText", "The mechanism returns to its starting position."))
	elif p.kind == "dials":
		if action is String and action == "check":
			# JSON numbers are floats, operated dial indices are integers.
			completed = range(p.answer.size()).all(func(i): return int(s.values[i]) == int(p.answer[i]))
			if not completed:
				_say(p.failure)
		else:
			s.values[action] = (int(s.values[action]) + 1) % p.states.size()
			_say("%s: %s. %s" % [p.nodes[action].name, p.states[s.values[action]], p.get("instruction", "")])
	elif p.kind == "sequence" and action is int:
		if game.audio != null:
			game.audio.bell(0.12, [440.0, 554.37, 659.25, 880.0][action % 4])
		if action == int(p.answer[s.progress]):
			s.progress += 1
			completed = s.progress == p.answer.size()
			if not completed:
				_say("%s answers softly. %d of %d notes hold." % [p.nodes[action].name, s.progress, p.answer.size()])
		else:
			s.progress = 0
			_say(p.failure)
	if completed:
		s.solved = true
		_say(p.success)
		game.events.emit("puzzleSolved", {"id": id})
	refresh()
	game.quests.refresh()
	return completed


func _say(text: String) -> void:
	game.events.emit("log", {"text": text, "kind": "lore"})
	# Keep the transient line inside the screen; the log holds the full clue.
	var brief := text.get_slice(". ", 0)
	if brief.length() > 90:
		brief = brief.left(87) + "…"
	game.hud.toast(brief)


func update(dt: float) -> void:
	_clock -= dt
	if _clock <= 0:
		_clock = 0.25
		refresh()


func refresh() -> void:
	for p in DB.world.get("puzzles", []):
		var s := state(p.id)
		var root: Node3D = visuals.get(p.id)
		if not is_instance_valid(root):
			continue
		var near: bool = game.player != null and Vector2(game.player.position.x - p.position[0], game.player.position.z - p.position[1]).length() < float(p.get("labelRadius", 14.0))
		for i in p.nodes.size():
			var node := root.get_node("Dial%d" % i)
			var label: Label3D = node.get_node("Label")
			label.visible = near
			label.text = p.nodes[i].name
			if p.kind == "dials":
				label.text += "\n" + str(p.states[int(s.values[i]) % p.states.size()])
				node.get_node("Pointer").rotation.y = float(s.values[i]) * TAU / p.states.size()
				node.get_node("Flow").visible = int(s.values[i]) > 0
				node.get_node("Flow").scale.x = 0.5 if int(s.values[i]) == 1 else 1.0
			else:
				label.text += "\n%d / %d notes" % [s.progress, p.answer.size()]
			label.modulate = Color("96e5b2") if s.solved else Color("f6dfaa")
		for action in ["Check", "Reset"]:
			var action_label = root.get_node_or_null(action)
			if action_label:
				action_label.visible = near
		var status: Label3D = root.get_node("Status")
		status.visible = near
		status.text = "%s\n%s" % [p.name, "Settled" if s.solved else p.get("instruction", "")]


## The editor uses the same original primitive geometry as the game.
static func visual(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(p.id)
	for i in p.nodes.size():
		var n: Dictionary = p.nodes[i]
		var holder := Node3D.new()
		holder.name = "Dial%d" % i
		holder.position = Vector3(n.offset[0], 0, n.offset[1])
		root.add_child(holder)
		if p.get("visual") == "hangingBells":
			_hanging_bell(holder, Color(n.get("color", "#b49a62")))
			_label(holder, "Label", n.name, Vector3(0, 1.9, 0))
			continue
		var base := CylinderMesh.new()
		base.top_radius = 0.36
		base.bottom_radius = 0.47
		base.height = 0.85
		_mesh(holder, base, Vector3(0, 0.425, 0), Color("626460"))
		var face := CylinderMesh.new()
		face.top_radius = 0.3
		face.bottom_radius = 0.3
		face.height = 0.12
		_mesh(holder, face, Vector3(0, 0.91, 0), Color(n.get("color", "#b49a62")))
		if p.kind == "sequence":
			var bell := CylinderMesh.new()
			bell.top_radius = 0.12
			bell.bottom_radius = 0.28
			bell.height = 0.35
			_mesh(holder, bell, Vector3(0, 1.14, 0), Color(n.get("color", "#b49a62")))
		else:
			var channel := BoxMesh.new()
			channel.size = Vector3(0.2, 0.035, 1.6)
			_mesh(holder, channel, Vector3(0, 0.06, 1.05), Color("598998"))
			holder.get_child(-1).name = "Flow"
		var pointer := Node3D.new()
		pointer.name = "Pointer"
		pointer.position.y = 1.01
		holder.add_child(pointer)
		var bar := BoxMesh.new()
		bar.size = Vector3(0.08, 0.06, 0.45)
		_mesh(pointer, bar, Vector3(0, 0, -0.16), Color("f0dfb0"))
		_label(holder, "Label", n.name, Vector3(0, 1.65, 0))
	for action in ["check", "reset"]:
		if action == "check" and p.kind != "dials":
			continue
		var off: Array = p.get(action + "Offset", [0, 2])
		var block := BoxMesh.new()
		block.size = Vector3(0.6, 0.65, 0.6)
		_mesh(root, block, Vector3(off[0], 0.325, off[1]), Color("71674f"))
		_label(root, action.capitalize(), "Test flow" if action == "check" else "Reset", Vector3(off[0], 1, off[1]))
	_label(root, "Status", p.name, Vector3(0, 2.8, -0.5))
	return root


## A small weathered bell rack for the garden; no additional lights or particles.
static func _hanging_bell(parent: Node3D, colour: Color) -> void:
	for x in [-0.42, 0.42]:
		var post := BoxMesh.new()
		post.size = Vector3(0.12, 1.6, 0.14)
		_mesh(parent, post, Vector3(x, 0.8, 0), Color("574939"))
	var beam := BoxMesh.new()
	beam.size = Vector3(1.05, 0.14, 0.18)
	_mesh(parent, beam, Vector3(0, 1.55, 0), Color("675442"))
	var bell := CylinderMesh.new()
	bell.top_radius = 0.12
	bell.bottom_radius = 0.32
	bell.height = 0.48
	bell.radial_segments = 12
	_mesh(parent, bell, Vector3(0, 1.18, 0), colour)
	var clapper := SphereMesh.new()
	clapper.radius = 0.07
	clapper.height = 0.14
	clapper.radial_segments = 8
	clapper.rings = 4
	_mesh(parent, clapper, Vector3(0, 0.89, 0), Color("50483c"))


static func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mi.material_override = material
	parent.add_child(mi)


static func _label(parent: Node3D, node_name: String, text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.position = at
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.012
	label.font_size = 32
	label.outline_size = 6
	label.modulate = Color("f6dfaa")
	# Visibility range is measured from the camera, which is ~36 m away even
	# when the player stands at the mechanism. Player distance is handled above.
	label.visibility_range_end = 70
	parent.add_child(label)

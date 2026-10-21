class_name Sparkles
extends RefCounted
## A few gold motes rising from things worth walking over to: unopened
## chests, quest items lying in the world and places still to examine
## (src/render/sparkles.js). One shared MultiMesh, refilled every frame.

const PER := 9 ## motes per thing
const MAX := 40 ## things at once
const RANGE := 30.0 ## metres from the Warden

var game
var mm: MultiMesh
var node: MultiMeshInstance3D
var t := 0.0


func _init(g) -> void:
	game = g
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = q
	mm.instance_count = PER * MAX
	mm.visible_instance_count = 0
	node = MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = Tex.fx_material(Tex.glint(), Color(Color.hex(0xffd27aff), 0.9), true, true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.extra_cull_margin = 16384
	node.name = "Sparkles"
	game.scene.add_child(node)


## [{ x, z, y }] of everything that sparkles right now
func spots() -> Array:
	var out := []
	for c in game.chests.list:
		if not game.chests.opened(c):
			out.append({"x": c.x, "z": c.z, "y": 0.5})
	for l in game.loot.active:
		var id = l.def.get("reward", {}).get("item")
		if not l.def.get("ground") and game.loot.gatherable(l.def) and id and Items.get_def(id).get("quest"):
			out.append({"x": l.x, "z": l.z, "y": l.def.get("heightOffset", 0) + 0.2})
	for p in game.world.examine_points:
		if not game.world_state.examined.has(p.id):
			out.append({"x": p.x, "z": p.z, "y": 0.6})
	return out


func update(dt: float) -> void:
	t += dt
	var p: Vector3 = game.player.position
	var n := 0
	var i := 0
	for s in spots():
		if i >= MAX:
			break
		if U.hyp(s.x - p.x, s.z - p.z) >= RANGE:
			continue
		var base: float = Terrain.height_at(s.x, s.z) + s.y
		for k in PER:
			# each mote rises over 1.6 s on its own phase, drifting round the spot
			var ph := fmod(t / 1.6 + float(k) / PER + i * 0.37, 1.0)
			var a := k * 2.4 + t * 0.8
			var r := 0.35 + 0.15 * sin(k * 1.7)
			mm.set_instance_transform(n, Transform3D(Basis(), Vector3(s.x + cos(a) * r, base + ph * 1.1, s.z + sin(a) * r)))
			n += 1
		i += 1
	mm.visible_instance_count = n

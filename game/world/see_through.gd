class_name SeeThrough
extends RefCounted
## Keeping the player in sight from the fixed camera (Dan, 2026-10-27, after
## Diablo 3/4 and Lost Ark): a house between the camera and the player fades
## evenly as a whole, and the player's silhouette shows through anything
## else that hides them (trees, walls, people).

const FADED := 0.3 ## how solid a house stays while it hides you
const SPEED := 4.0 ## fade steps per second
const NEAR := 40.0 ## only houses this close are tested
const SAMPLES := 64 ## points tested along the line from the camera to you

const FLAT := preload("res://game/render/flat.gdshader")
const FADED_SHADER := preload("res://game/render/faded.gdshader")
const SILHOUETTE := preload("res://game/render/silhouette.gdshader")
const MARK := preload("res://game/render/silhouette_mark.gdshader")

var game
## {mi, solid, faded: materials, form: the house's shape (Town), fade}
var houses := []
var _silhouette: ShaderMaterial
var _dressed := 0.0


func _init(g) -> void:
	game = g
	# every mark pass draws before any silhouette pass, so the player's own
	# arms and legs never show through their body
	_silhouette = ShaderMaterial.new()
	_silhouette.shader = MARK
	_silhouette.render_priority = -10
	var through := ShaderMaterial.new()
	through.shader = SILHOUETTE
	through.render_priority = 10
	_silhouette.next_pass = through


## a house to fade; `form` is its shape in the mesh's frame (ridge along x):
## {hl, hs, top, ridge, slope, eave, tower?: [x, half width, height]}
func add_house(mi: MeshInstance3D, form: Dictionary) -> void:
	var solid := ShaderMaterial.new()
	solid.shader = FLAT
	solid.set_shader_parameter("albedo", Color.WHITE)
	var faded := ShaderMaterial.new()
	faded.shader = FADED_SHADER
	faded.set_shader_parameter("albedo", Color.WHITE)
	mi.material_override = solid
	houses.append({"mi": mi, "solid": solid, "faded": faded, "form": form, "fade": 1.0})


func update(dt: float) -> void:
	var p = game.player
	if p == null or game.camera == null:
		return
	var cam: Vector3 = game.camera.global_position
	var at: Vector3 = p.position
	for h in houses:
		var mi: MeshInstance3D = h.mi
		var want := 1.0
		var c: Vector3 = mi.global_position
		if absf(c.x - at.x) < NEAR and absf(c.z - at.z) < NEAR and not p.hidden and _hides(h, cam, at):
			want = FADED
		if h.fade == want:
			continue
		h.fade = move_toward(h.fade, want, SPEED * dt)
		h.faded.set_shader_parameter("uFade", h.fade)
		mi.material_override = h.solid if h.fade >= 1.0 else h.faded
	# gear changes add meshes, so dress the model again now and then
	_dressed -= dt
	if _dressed <= 0:
		_dressed = 0.5
		_dress(p.model)


## does the house stand between the camera and your head, chest or feet?
func _hides(h: Dictionary, cam: Vector3, at: Vector3) -> bool:
	var inv: Transform3D = h.mi.global_transform.affine_inverse()
	var box: AABB = h.mi.get_aabb()
	var a: Vector3 = inv * cam
	for y in [0.3, 1.0, 1.8]:
		var b: Vector3 = inv * (at + Vector3(0, y, 0))
		if box.intersects_segment(a, b) == null:
			continue
		for i in SAMPLES:
			if _inside(h.form, b.lerp(a, float(i) / SAMPLES * 0.6)):
				return true
	return false


## is a point (in the mesh's frame) inside the walls, the roof or the tower?
static func _inside(f: Dictionary, q: Vector3) -> bool:
	var ax := absf(q.x)
	var az := absf(q.z)
	if q.y < 0:
		return false
	if q.y <= f.top and ax <= f.hl and az <= f.hs:
		return true
	if q.y > f.top - 0.2 and ax <= f.hl + f.eave and az <= f.hs + f.eave and q.y <= f.ridge - az * f.slope:
		return true
	if f.has("tower"):
		var t: Array = f.tower
		return absf(q.x - t[0]) <= t[1] and az <= t[1] and q.y <= t[2]
	return false


func _dress(n: Node) -> void:
	if n == null:
		return
	if n is GeometryInstance3D and n.material_overlay == null:
		n.material_overlay = _silhouette
	for c in n.get_children():
		_dress(c)

@tool
extends SubViewportContainer
## A model from assets/models turning slowly on its own, lit like the item
## icons in the game.

const MODELS := "res://assets/models/%s.glb"

var _vp: SubViewport
var _pivot: Node3D
var _cam: Camera3D


func _init() -> void:
	stretch = true
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("1d1b19")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f0e8d8")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.near = 0.01
	_cam.far = 100
	_cam.environment = env
	_vp.add_child(_cam)
	var light := DirectionalLight3D.new()
	light.light_color = Color("fff0d8")
	light.light_energy = 1.2
	light.transform = Transform3D(Basis(), Vector3(2, 3, 4)).looking_at(Vector3.ZERO, Vector3.UP)
	_vp.add_child(light)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)


func show_model(model_name: String) -> void:
	for c in _pivot.get_children():
		c.queue_free()
	var path := MODELS % model_name
	if model_name == "" or not ResourceLoader.exists(path):
		return
	var scene = load(path)
	if not scene is PackedScene:
		return
	var obj: Node3D = scene.instantiate()
	_pivot.add_child(obj)
	var box = _bounds(obj, Transform3D.IDENTITY, null)
	if box == null:
		return
	# centre it on the pivot and frame its largest side
	obj.position = -box.get_center()
	var radius := maxf(box.size.x, maxf(box.size.y, box.size.z)) / 2
	var dist := radius / tan(deg_to_rad(_cam.fov) / 2) * 1.15 + radius
	_cam.transform = Transform3D(Basis(), Vector3(0, dist * 0.25, dist)).looking_at(Vector3.ZERO, Vector3.UP)


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_pivot.rotation.y += delta * 0.7


static func _bounds(n: Node, parent_xf: Transform3D, box):
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * n.transform
	if n is MeshInstance3D and n.mesh:
		var b: AABB = xf * n.mesh.get_aabb()
		box = b if box == null else box.merge(b)
	for c in n.get_children():
		box = _bounds(c, xf, box)
	return box

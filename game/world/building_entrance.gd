extends RefCounted
## Camera-facing primary entrances for the existing walk-in building kit.
## Side doors remain usable; NPCs, interiors and building footprints stay put.
const HALF_GAP := 1.2
static func walls(b: Dictionary) -> Array:
	var out: Array = []
	var front := float(b.size[1]) * 0.5
	for segment in b.walls:
		if is_equal_approx(float(segment[1]), front) and is_equal_approx(float(segment[3]), front):
			out.append([segment[0],front,-HALF_GAP,front])
			out.append([HALF_GAP,front,segment[2],front])
		else:
			out.append(segment)
	return out
static func make_front(b: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.name = "VisibleFrontEntrance"
	var w := float(b.size[0])
	var front := float(b.size[1]) * 0.5
	var h := 3.2 if str(b.shell).contains("TownHall") else 3.0
	var wall := _material(Color("93856a") if str(b.shell).contains("TownHall") else Color("8a8170"))
	var timber := _material(Color("493525"))
	var trim := _material(Color("b59a6b"))
	var stone := _material(Color("777363"))
	var span := w * 0.5-HALF_GAP
	for side in [-1.0,1.0]:
		_box(g,"FrontWall",Vector3(side*(HALF_GAP+span*0.5),h*0.5,front),Vector3(span,h,0.3),wall)
		_box(g,"DoorJamb",Vector3(side*(HALF_GAP+0.08),1.2,front+0.1),Vector3(0.18,2.4,0.34),trim)
		_box(g,"CornerPost",Vector3(side*(w*0.5-0.1),h*0.5,front+0.02),Vector3(0.22,h,0.36),timber)
		_box(g,"WarmWindow",Vector3(side*w*0.31,1.75,front+0.18),Vector3(0.8,0.8,0.06),_material(Color("d3a65c")))
	_box(g,"AboveDoor",Vector3(0,(h+2.35)*0.5,front),Vector3(HALF_GAP*2,h-2.35,0.3),wall)
	_box(g,"DoorLintel",Vector3(0,2.4,front+0.1),Vector3(2.75,0.23,0.4),trim)
	_box(g,"FrontBeam",Vector3(0,h-0.12,front+0.03),Vector3(w+0.2,0.24,0.36),timber)
	_box(g,"EntranceSign",Vector3(0,2.78,front+0.25),Vector3(3.2,0.42,0.13),timber)
	var sign := Label3D.new()
	sign.name = "EntranceName"
	sign.text = "TOWN HALL" if str(b.name).contains("Town Hall") else "INN" if str(b.name).contains("Inn") else "REST HOUSE"
	sign.font_size = 42
	sign.pixel_size = 0.008
	sign.modulate = Color("ecd4a1")
	sign.position = Vector3(0,2.78,front+0.33)
	g.add_child(sign)
	# The leaf is folded flat inside the right wall, keeping the opening clear.
	_box(g,"OpenDoor",Vector3(1.9,1.1,front-0.2),Vector3(1.1,2.2,0.09),timber)
	_box(g,"Threshold",Vector3(0,0.08,front+0.48),Vector3(2.7,0.16,1.0),stone)
	return g
static func approach(b: Dictionary) -> Node3D:
	var g := Node3D.new()
	g.name = "EntranceApproach"
	var front := float(b.size[1])*0.5
	_box(g,"Doorstep",Vector3(0,0.06,front+1.1),Vector3(3.1,0.12,1.3),_material(Color("827b68")))
	return g
static func _material(colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	m.roughness = 0.9
	return m
static func _box(parent: Node3D, name: String, at: Vector3, size: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var box := BoxMesh.new()
	box.size = size
	mi.mesh = box
	mi.material_override = material
	mi.position = at
	parent.add_child(mi)

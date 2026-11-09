extends Node3D
## Authored longbow: Y is the handle/limb axis, +Z is the arrow direction.
var upper_string: MeshInstance3D
var lower_string: MeshInstance3D
var arrow: Node3D
var pull := 0.08
const TIP := Vector3(0,0.72,0.14)

func material(colour: Color) -> StandardMaterial3D:
	var m:=StandardMaterial3D.new()
	m.albedo_color=colour
	m.roughness=0.9
	return m

func segment(a: Vector3,b: Vector3,radius: float,mat: Material) -> MeshInstance3D:
	var node:=MeshInstance3D.new()
	var mesh:=CylinderMesh.new()
	mesh.top_radius=radius*0.9
	mesh.bottom_radius=radius
	mesh.height=1
	mesh.radial_segments=8
	node.mesh=mesh
	node.material_override=mat
	add_child(node)
	place_segment(node,a,b)
	return node

func place_segment(node: Node3D,a: Vector3,b: Vector3) -> void:
	var delta:=b-a
	# Cylinder length is local Y. Apply its length before rotating the axis.
	node.transform=Transform3D(Basis(Quaternion(Vector3.UP,delta.normalized()))*Basis.from_scale(Vector3(1,delta.length(),1)),(a+b)*0.5)

func build() -> void:
	var wood:=material(Color("59402a"))
	var edge:=material(Color("977148"))
	var leather:=material(Color("2e2118"))
	var thread:=material(Color("c1ab78"))
	for side in [-1.0,1.0]:
		var previous:=Vector3(0,side*0.085,0)
		for i in range(1,13):
			var t:=float(i)/12
			var point:=Vector3(0,side*(0.085+t*0.635),0.14*t*t-0.035*sin(PI*t))
			segment(previous,point,lerpf(0.028,0.011,t),wood if i%3 else edge)
			previous=point
	segment(Vector3(0,-0.1,0),Vector3(0,0.1,0),0.027,leather)
	for y in [-0.09,-0.055,-0.02,0.02,0.055,0.09]:
		segment(Vector3(0,y-0.004,0),Vector3(0,y+0.004,0),0.029,edge)
	batch_static_limbs()
	upper_string=segment(TIP,Vector3(0,0,-pull),0.0028,thread)
	upper_string.name="UpperString"
	lower_string=segment(Vector3(TIP.x,-TIP.y,TIP.z),Vector3(0,0,-pull),0.0028,thread)
	lower_string.name="LowerString"
	arrow=Node3D.new()
	arrow.name="NockedArrow"
	add_child(arrow)
	var shaft:=segment(Vector3.ZERO,Vector3(0,0,0.7),0.004,edge)
	remove_child(shaft)
	arrow.add_child(shaft)
	for side in [-1.0,1.0]:
		var feather:=MeshInstance3D.new()
		var mesh:=BoxMesh.new()
		mesh.size=Vector3(0.03,0.003,0.085)
		feather.mesh=mesh
		feather.material_override=thread
		feather.position=Vector3(side*0.012,0,0.07)
		arrow.add_child(feather)
	set_draw(0,false)

func _ready() -> void:
	upper_string=get_node("UpperString")
	lower_string=get_node("LowerString")
	arrow=get_node("NockedArrow")
	set_draw(0,false)

func batch_static_limbs() -> void:
	var groups:Dictionary={}
	for child in get_children():
		if child is MeshInstance3D:
			var mat:Material=child.material_override
			if not groups.has(mat):groups[mat]=[]
			groups[mat].append(child)
	var combined:=ArrayMesh.new()
	for mat in groups:
		var surface:=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for child in groups[mat]:
			surface.append_from(child.mesh,0,child.transform)
			remove_child(child)
			child.free()
		surface.set_material(mat)
		surface.commit(combined)
	var assembly:=MeshInstance3D.new()
	assembly.name="LimbAssembly"
	assembly.mesh=combined
	add_child(assembly)

func set_draw(amount: float,show_arrow: bool=true) -> void:
	pull=0.08+clampf(amount,0,1)*0.34
	var nock:=Vector3(0,0,-pull)
	place_segment(upper_string,TIP,nock)
	place_segment(lower_string,Vector3(0,-TIP.y,TIP.z),nock)
	arrow.position=nock
	arrow.visible=show_arrow

func muzzle_local() -> Vector3:
	return Vector3(0,0,0.7-pull)

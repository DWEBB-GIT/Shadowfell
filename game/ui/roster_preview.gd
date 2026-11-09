class_name RosterPreview
extends TextureRect
## Independent dressing room using the actual Player model and gear builder.
var viewport: SubViewport
var pivot: Node3D
var actor
var equipment := {}
var turn := 0.0
var dragging := false
var clock := 0.0

func center_character() -> void:
	var camera: Camera3D = viewport.find_children("*", "Camera3D", true, false)[0]
	camera.position = Vector3(0, 1.8, 6.6)
	camera.transform = camera.transform.looking_at(Vector3(0, 0.85, 0), Vector3.UP)

func _init() -> void:
	expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode=TextureRect.STRETCH_SCALE
	mouse_default_cursor_shape=Control.CURSOR_DRAG
	viewport=SubViewport.new()
	viewport.own_world_3d=true
	viewport.size=Vector2i(800,800)
	viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport)
	texture=viewport.get_texture()
	var environment := Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("15282c")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("99b8bb")
	environment.ambient_light_energy=0.35
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var camera := Camera3D.new()
	camera.environment=environment
	camera.fov=30
	camera.position=Vector3(-1.15,1.8,6.6)
	viewport.add_child(camera)
	camera.transform=camera.transform.looking_at(Vector3(-1.15,0.85,0),Vector3.UP)
	for spec in [[Color("ffdaa3"),0.95,Vector3(2,4,3)],[Color("88bbde"),0.55,Vector3(-2,3,-2)]]:
		var light := DirectionalLight3D.new()
		light.light_color=spec[0]
		light.light_energy=spec[1]
		light.position=spec[2]
		viewport.add_child(light)
		light.transform=light.transform.looking_at(Vector3.ZERO,Vector3.UP)
	var stage := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius=1.65
	mesh.bottom_radius=1.8
	mesh.height=0.18
	stage.mesh=mesh
	stage.position.y=-0.12
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("485353")
	material.roughness=0.95
	stage.material_override=material
	viewport.add_child(stage)
	var ground:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(40,40)
	ground.mesh=plane
	ground.position.y=-0.23
	var soil:=StandardMaterial3D.new()
	soil.albedo_color=Color("203532")
	soil.roughness=1.0
	ground.material_override=soil
	viewport.add_child(ground)
	# the pines come with the world's pack (game.pck): the lobby has none yet
	var pines := ResourceLoader.exists("res://assets/environment/nature/trees/Pine_1.gltf")
	for spec in ([[-2.8,-3.2,0.8],[2.7,-3.7,0.9],[-3.8,-5.5,1.0],[4.1,-6.0,1.2]] if pines else []):
		var tree := Assets.instance("res://assets/environment/nature/trees/Pine_1.gltf")
		tree.position=Vector3(spec[0],-0.1,spec[1])
		tree.scale=Vector3.ONE*spec[2]
		viewport.add_child(tree)
	for x in [-2.0,2.0]:
		var lamp := Assets.instance("camp")
		lamp.position=Vector3(x,-0.1,-1.2)
		lamp.scale=Vector3.ONE*0.65
		viewport.add_child(lamp)
		var glow := OmniLight3D.new()
		glow.position=Vector3(x,0.8,-1.2)
		glow.light_color=Color("ffc080")
		glow.light_energy=3
		glow.omni_range=6
		viewport.add_child(glow)
	pivot=Node3D.new()
	viewport.add_child(pivot)

func show_character(gear: Dictionary, appearance = null) -> void:
	equipment=gear.duplicate(true)
	if actor!=null:
		actor.group.queue_free()
	actor=Player.new({"inventory":{"equipment":equipment},"time":0.0})
	pivot.add_child(actor.group)
	actor.set_appearance(appearance)
	actor.group.position=Vector3.ZERO
	actor.group.rotation=Vector3.ZERO
	actor.model.scale/=DB.CONFIG.player.visualScale
	actor.ground_shadow.visible=false
	actor.show_equipment(equipment)
	turn=0
	clock=1

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		dragging=event.pressed
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		turn+=event.relative.x*0.012
		accept_event()

func _process(dt: float) -> void:
	if not is_visible_in_tree():
		dragging=false
		return
	clock+=dt
	var wanted:=Vector2i(maxi(64,int(size.x)),maxi(64,int(size.y)))
	if viewport.size!=wanted:
		viewport.size=wanted
	if clock<1.0/30.0 or actor==null:
		return
	actor.rig.update(minf(clock,0.1),0.0)
	clock=0
	pivot.rotation.y=turn
	viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

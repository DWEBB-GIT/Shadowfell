extends CharacterBody3D
## A local survey character for the Lantern Coast terrain scene.

const SPEED := 8.0
const GRAVITY := 22.0
const JUMP_SPEED := 6.0
const STEP_HEIGHT := 0.25
const CAMERA_FOCUS := Vector3(0.0, 0.85, 0.0)
const CAMERA_DISTANCE := 37.0

var view_camera: Camera3D
var use_test_input := false
var test_controls := Vector2.ZERO
var test_jump := false

var _avatar: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _gait_time := 0.0
var _jump_held := false


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_max_angle = deg_to_rad(38.0)
	floor_snap_length = 0.4
	floor_constant_speed = true
	floor_block_on_wall = true

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	var shape := CollisionShape3D.new()
	shape.position.y = capsule.height * 0.5
	shape.shape = capsule
	add_child(shape)

	_build_avatar()
	_build_camera()


func _build_camera() -> void:
	view_camera = Camera3D.new()
	view_camera.name = "IsometricCamera"
	view_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	view_camera.size = 24.0
	view_camera.near = 0.15
	view_camera.far = 220.0
	add_child(view_camera)
	var pitch := deg_to_rad(40.0)
	var diagonal := cos(pitch) / sqrt(2.0)
	view_camera.position = CAMERA_FOCUS + Vector3(diagonal, sin(pitch), diagonal) * CAMERA_DISTANCE
	view_camera.look_at(to_global(CAMERA_FOCUS), Vector3.UP)
	view_camera.make_current()


func warp_to(destination: Vector3) -> void:
	velocity = Vector3.ZERO
	global_position = destination
	reset_physics_interpolation()


func _movement_input() -> Vector2:
	if use_test_input:
		return test_controls.limit_length()
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	var forward := Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
	var back := Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
	return Vector2(int(right) - int(left), int(back) - int(forward)).limit_length()


func _physics_process(delta: float) -> void:
	var controls := _movement_input()
	var screen_right := view_camera.global_basis.x
	var screen_back := view_camera.global_basis.z
	screen_right.y = 0.0
	screen_back.y = 0.0
	var direction := screen_right.normalized() * controls.x + screen_back.normalized() * controls.y

	var jump_down := test_jump if use_test_input else Input.is_physical_key_pressed(KEY_SPACE)
	var jumping := jump_down and not _jump_held and is_on_floor()
	_jump_held = jump_down
	if jumping:
		velocity.y = JUMP_SPEED
	elif is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= GRAVITY * delta

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED
	var step := Vector3(velocity.x, 0.0, velocity.z) * delta
	if jumping or not is_on_floor() or not _step_over_lip(step):
		move_and_slide()
	_animate_avatar(direction, delta)


func _step_over_lip(step: Vector3) -> bool:
	if step.length_squared() < 0.000001:
		return false

	var base := global_transform
	var wall := KinematicCollision3D.new()
	if not test_move(base, step, wall) or wall.get_normal().y >= cos(floor_max_angle):
		return false

	var rise := Vector3.UP * STEP_HEIGHT
	if test_move(base, rise):
		return false
	base.origin += rise
	if test_move(base, step):
		return false
	base.origin += step

	var landing := KinematicCollision3D.new()
	if not test_move(base, Vector3.DOWN * (STEP_HEIGHT + 0.08), landing):
		return false
	if landing.get_normal().y < cos(floor_max_angle):
		return false
	global_position = base.origin + landing.get_travel()
	return true


func _animate_avatar(direction: Vector3, delta: float) -> void:
	if direction.length_squared() > 0.01:
		_avatar.rotation.y = lerp_angle(
			_avatar.rotation.y, atan2(direction.x, direction.z), minf(1.0, 16.0 * delta)
		)
	var stride := clampf(get_real_velocity().length() / SPEED, 0.0, 1.0) if is_on_floor() else 0.0
	_gait_time += delta * 15.0 * stride
	var swing := sin(_gait_time) * stride
	for side in 2:
		var phase := 1.0 if side == 0 else -1.0
		_legs[side].rotation.x = swing * 0.58 * phase
		_arms[side].rotation.x = swing * -0.45 * phase


func _build_avatar() -> void:
	_avatar = Node3D.new()
	_avatar.name = "Surveyor"
	add_child(_avatar)

	var coat := _material(Color("#355d62"))
	var mantle := _material(Color("#a96b30"))
	var leather := _material(Color("#46372c"))
	var lining := _material(Color("#222e39"))
	var skin := _material(Color("#d2a27a"))
	var brass := _material(Color("#d0a45b"))
	var hair := _material(Color("#584436"))

	_taper(_avatar, Vector3(0.0, 1.08, 0.0), 0.30, 0.25, 0.52, coat, Vector3(1.0, 1.0, 0.70))
	_taper(_avatar, Vector3(0.0, 0.80, 0.0), 0.26, 0.31, 0.32, coat, Vector3(1.0, 1.0, 0.68))
	_taper(_avatar, Vector3(0.0, 0.94, 0.0), 0.27, 0.27, 0.12, leather, Vector3(1.0, 1.0, 0.76))
	_box(_avatar, Vector3(0.0, 0.94, 0.21), Vector3(0.13, 0.105, 0.04), brass)
	_box(_avatar, Vector3(0.24, 0.86, 0.04), Vector3(0.13, 0.22, 0.18), leather)
	_box(_avatar, Vector3(0.0, 1.09, -0.21), Vector3(0.36, 0.48, 0.17), mantle)
	_box(_avatar, Vector3(0.0, 1.31, 0.14), Vector3(0.35, 0.12, 0.12), mantle)
	_box(_avatar, Vector3(-0.10, 1.28, 0.23), Vector3(0.075, 0.085, 0.032), brass)
	_taper(_avatar, Vector3(0.0, 1.38, 0.0), 0.09, 0.10, 0.17, skin)
	_orb(_avatar, Vector3(0.0, 1.59, 0.02), 0.19, Vector3(0.92, 1.12, 0.92), skin)
	_orb(_avatar, Vector3(0.0, 1.69, -0.02), 0.18, Vector3(1.05, 0.7, 0.98), hair)
	_box(_avatar, Vector3(0.0, 1.58, -0.13), Vector3(0.29, 0.21, 0.10), hair)

	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.14, 0.77, 0.0)
		_avatar.add_child(leg)
		_legs.append(leg)
		_taper(leg, Vector3(0.0, -0.26, 0.0), 0.12, 0.087, 0.52, lining)
		_taper(leg, Vector3(0.0, -0.57, 0.02), 0.091, 0.097, 0.27, leather)
		_box(leg, Vector3(0.0, -0.70, 0.058), Vector3(0.196, 0.14, 0.29), leather)

		var arm := Node3D.new()
		arm.position = Vector3(side * 0.29, 1.27, 0.0)
		arm.rotation.z = side * 0.13
		_avatar.add_child(arm)
		_arms.append(arm)
		_orb(arm, Vector3.ZERO, 0.13, Vector3(1.0, 0.82, 1.03), mantle)
		_taper(arm, Vector3(0.0, -0.19, 0.0), 0.10, 0.074, 0.38, coat)
		_taper(arm, Vector3(0.0, -0.38, 0.0), 0.083, 0.076, 0.19, leather)
		_orb(arm, Vector3(0.0, -0.49, 0.0), 0.079, Vector3(0.93, 1.13, 0.90), skin)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.92
	return material


func _part(
	parent: Node3D, mesh: Mesh, center: Vector3, material: Material, proportions := Vector3.ONE
) -> void:
	var part := MeshInstance3D.new()
	part.position = center
	part.scale = proportions
	part.mesh = mesh
	part.material_override = material
	parent.add_child(part)


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_part(parent, mesh, center, material)


func _taper(
	parent: Node3D, center: Vector3, top: float, bottom: float, height: float,
	material: Material, proportions := Vector3.ONE
) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 0
	_part(parent, mesh, center, material, proportions)


func _orb(parent: Node3D, center: Vector3, radius: float, proportions: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	_part(parent, mesh, center, material, proportions)

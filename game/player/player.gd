extends CharacterBody3D
## The player: WASD or the left stick moves them across the ground (no sprint),
## and they turn to face the way they move. The camera is fixed, so up is
## always north (-z).

@export var speed := 5.6 ## metres per second: a run
@export var turn_speed := 12.0

var bounds: Dictionary


func _ready() -> void:
	var start: Dictionary = GameData.section("world", "playerStart")
	bounds = GameData.section("world", "bounds")
	position = Vector3(start.position[0], Terrain.height_at(start.position[0], start.position[1]), start.position[1])
	rotation.y = deg_to_rad(start.get("facing", 0.0))


func _physics_process(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move := Vector3(input.x, 0.0, input.y)
	velocity = move * speed
	move_and_slide()
	position.x = clampf(position.x, bounds.minX, bounds.maxX)
	position.z = clampf(position.z, bounds.minZ, bounds.maxZ)
	position.y = Terrain.height_at(position.x, position.z)
	if move.length() > 0.1:
		var want := atan2(move.x, move.z)
		rotation.y = lerp_angle(rotation.y, want, minf(1.0, delta * turn_speed))

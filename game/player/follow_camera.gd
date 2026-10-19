extends Camera3D
## The fixed isometric camera: it sits behind and above the player at
## `offset`, always looking the same way, and eases after them. The mouse
## wheel zooms between zoom_min and zoom_max of the offset.

@export var target: Node3D
@export var offset := Vector3(0, 11, 10)
@export var look_ahead := 0.5 ## metres north of the player the camera centres on
@export var follow_sharpness := 8.0
@export var zoom_min := 0.6
@export var zoom_max := 1.35
@export var zoom_step := 0.08

var zoom := 1.0
var _focus := Vector3.ZERO


func _ready() -> void:
	if target:
		_focus = target.global_position
		_place(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		zoom = clampf(zoom - zoom_step, zoom_min, zoom_max)
	elif event.is_action_pressed("zoom_out"):
		zoom = clampf(zoom + zoom_step, zoom_min, zoom_max)


func _process(delta: float) -> void:
	if target:
		_place(1.0 - exp(-follow_sharpness * delta))


func _place(blend: float) -> void:
	_focus = _focus.lerp(target.global_position + Vector3(0, 0, -look_ahead), blend)
	global_position = _focus + offset * zoom
	look_at(_focus, Vector3.UP)

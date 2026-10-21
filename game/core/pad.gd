class_name Pad
extends RefCounted
## Gamepad support (src/core/gamepad.js), with the buttons in the browser's
## "standard" order so the gameplay code reads the same. Triggers count as
## buttons when pressed past half way.

const BUTTONS := {"A": 0, "B": 1, "X": 2, "Y": 3, "LB": 4, "RB": 5, "LT": 6, "RT": 7, "VIEW": 8, "START": 9, "LS": 10, "RS": 11, "UP": 12, "DOWN": 13, "LEFT": 14, "RIGHT": 15}
## Godot's button for each standard index (-1: a trigger axis)
const GODOT := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER, -1, -1, JOY_BUTTON_BACK, JOY_BUTTON_START, JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK, JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]
const DEADZONE := 0.22

var device := -1
var prev: Array = []
var now: Array = []
var left := Vector3.ZERO ## x, y, magnitude
var right := Vector3.ZERO
var active := false ## true once the pad has been used, to switch prompts
var repeat := {} ## menu navigation auto-repeat timers


static func shape(x: float, y: float) -> Vector3:
	var m := Vector2(x, y).length()
	if m < DEADZONE:
		return Vector3.ZERO
	var k := minf(1, (m - DEADZONE) / (1 - DEADZONE)) / m
	return Vector3(x * k, y * k, minf(1, m))


func poll() -> void:
	prev = now
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		device = -1
		now = []
		left = Vector3.ZERO
		right = Vector3.ZERO
		return
	if not pads.has(device):
		device = pads[0]
	now = []
	for i in GODOT.size():
		var b: int = GODOT[i]
		if b >= 0:
			now.append(Input.is_joy_button_pressed(device, b))
		else:
			now.append(Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT if i == 6 else JOY_AXIS_TRIGGER_RIGHT) > 0.5)
	left = shape(Input.get_joy_axis(device, JOY_AXIS_LEFT_X), Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	right = shape(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
	if now.any(func(v): return v) or left.z > 0 or right.z > 0:
		active = true


func held(b: int) -> bool:
	return b < now.size() and now[b]


func pressed(b: int) -> bool:
	return held(b) and not (b < prev.size() and prev[b])


## Menu navigation: a direction from the d-pad or left stick, repeating
## while held. Returns 'up' | 'down' | 'left' | 'right' | "".
func nav_direction(dt: float) -> String:
	var dirs := {
		"up": held(BUTTONS.UP) or left.y < -0.6,
		"down": held(BUTTONS.DOWN) or left.y > 0.6,
		"left": held(BUTTONS.LEFT) or left.x < -0.6,
		"right": held(BUTTONS.RIGHT) or left.x > 0.6,
	}
	for d in dirs:
		if not dirs[d]:
			repeat.erase(d)
			continue
		if not repeat.has(d):
			repeat[d] = 0.35
			return d
		repeat[d] -= dt
		if repeat[d] <= 0:
			repeat[d] = 0.12
			return d
	return ""

class_name GameInput
extends Node
## Keyboard and mouse state (src/core/input.js). Gameplay reads held keys
## each frame and consumes one-shot presses, so a press is never processed
## twice. Keys are named as the browser names them ('KeyW', 'Digit1',
## 'Space', 'Shift+Digit1'), so key bindings carry over unchanged.

var held := {}
var pressed := {}
var mouse := {"x": 0.0, "y": 0.0, "ndcX": 0.0, "ndcY": 0.0, "clicked": false, "rightClicked": false, "leftHeld": false, "onCanvas": true}
var wheel := 0
var capture := Callable() ## set while Settings waits for a key to bind
var is_bound := func(_code): return false ## key bindings say which other keys the game uses


## the browser's KeyboardEvent.code for a Godot key
static func code_of(k: int) -> String:
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return "Numpad%d" % (k - KEY_KP_0)
	if k >= KEY_F1 and k <= KEY_F12:
		return "F%d" % (k - KEY_F1 + 1)
	match k:
		KEY_SPACE: return "Space"
		KEY_TAB: return "Tab"
		KEY_ESCAPE: return "Escape"
		KEY_ENTER, KEY_KP_ENTER: return "Enter"
		KEY_SHIFT: return "ShiftLeft"
		KEY_CTRL: return "ControlLeft"
		KEY_ALT: return "AltLeft"
		KEY_UP: return "ArrowUp"
		KEY_DOWN: return "ArrowDown"
		KEY_LEFT: return "ArrowLeft"
		KEY_RIGHT: return "ArrowRight"
		KEY_QUOTELEFT: return "Backquote"
		KEY_MINUS: return "Minus"
		KEY_EQUAL: return "Equal"
		KEY_BRACKETLEFT: return "BracketLeft"
		KEY_BRACKETRIGHT: return "BracketRight"
		KEY_SEMICOLON: return "Semicolon"
		KEY_APOSTROPHE: return "Quote"
		KEY_COMMA: return "Comma"
		KEY_PERIOD: return "Period"
		KEY_SLASH: return "Slash"
		KEY_BACKSLASH: return "Backslash"
		KEY_CAPSLOCK: return "CapsLock"
		KEY_BACKSPACE: return "Backspace"
		KEY_DELETE: return "Delete"
	return OS.get_keycode_string(k)


func _input(e: InputEvent) -> void:
	if e is InputEventKey:
		var code := code_of(e.physical_keycode if e.physical_keycode else e.keycode)
		if e.pressed:
			if capture.is_valid():
				if not e.echo:
					capture.call(code, e.shift_pressed)
				get_viewport().set_input_as_handled()
				return
			# typing in a text field (the character name) is not a game key
			var focus := get_viewport().gui_get_focus_owner()
			if focus is LineEdit or focus is TextEdit:
				return
			# with Shift held a key is its Shift binding if it has one (Shift-1:
			# utility slot 1), else the key itself (Shift+W still walks)
			var shifted := "Shift+" + code if e.shift_pressed and not code.begins_with("Shift") and is_bound.call("Shift+" + code) else ""
			if not e.echo:
				pressed[shifted if shifted != "" else code] = true
			held[code] = true
		else:
			held.erase(code)
	elif e is InputEventMouseMotion:
		_mouse(e.position)
	elif e is InputEventMouseButton:
		_mouse(e.position)
		# a held left button (mouse aim) lets go wherever the mouse is
		if e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
			mouse.leftHeld = false


## Clicks and the wheel on HUD windows never reach here: the GUI takes them
## first, so a click on a button does not also walk or select in the world.
func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or not e.pressed:
		return
	match e.button_index:
		MOUSE_BUTTON_LEFT:
			mouse.clicked = true
			mouse.leftHeld = true
		MOUSE_BUTTON_RIGHT:
			mouse.rightClicked = true
		MOUSE_BUTTON_WHEEL_UP:
			wheel -= 1
		MOUSE_BUTTON_WHEEL_DOWN:
			wheel += 1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		held.clear()
		mouse.leftHeld = false


func _mouse(p: Vector2) -> void:
	var size := get_viewport().get_visible_rect().size
	mouse.x = p.x
	mouse.y = p.y
	mouse.ndcX = p.x / size.x * 2 - 1
	mouse.ndcY = -(p.y / size.y) * 2 + 1
	mouse.onCanvas = get_viewport().gui_get_hovered_control() == null # not over a window or button


func is_held(code: String) -> bool:
	return held.has(code)


func consume(code: String) -> bool:
	if pressed.has(code):
		pressed.erase(code)
		return true
	return false


func consume_wheel() -> int:
	var w := wheel
	wheel = 0
	return w


func consume_click() -> bool:
	var c: bool = mouse.clicked
	mouse.clicked = false
	return c


func consume_right_click() -> bool:
	var c: bool = mouse.rightClicked
	mouse.rightClicked = false
	return c


## Call at the end of every frame so stale presses don't fire later.
func end_frame() -> void:
	pressed.clear()
	mouse.clicked = false
	mouse.rightClicked = false


## Movement axis in world space: W is north (-z), D is east (+x); the arrow
## keys move too. Diagonal input is normalised.
func move_axis() -> Vector2:
	var x := 0.0
	var z := 0.0
	if is_held("KeyW") or is_held("ArrowUp"):
		z -= 1
	if is_held("KeyS") or is_held("ArrowDown"):
		z += 1
	if is_held("KeyA") or is_held("ArrowLeft"):
		x -= 1
	if is_held("KeyD") or is_held("ArrowRight"):
		x += 1
	var v := Vector2(x, z)
	return v.normalized() if v.length() > 0 else v

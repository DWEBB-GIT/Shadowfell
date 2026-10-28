class_name ISlot
extends Control
## One slot (style.css .islot / .aslot): a bag cell, an equipment slot, a
## bag socket, a shop item, a spell in the spellbook, or a spell-bar slot.
## `loc` names what it shows, as the browser build does: 'b:<bag>:<slot>',
## 'e:<slot>', 's:<socket>', 'm:<item>', 'y:<n>', 'k:<ability>', 'a:<slot>'.
## It draws itself; the window that owns it decides what it holds and
## handles its clicks (`on_input`, `on_hover`).

const FRAME := 0.1 ## the kit frame's width, as a share of the slot
const EMPTY_BORDER := Color("5e4a2c")
const KIND_BORDER := {"weapon": Color("8a7450"), "armor": Color("62788c"), "bag": Color("8a6838")}

var loc := ""
var icon: Texture2D
var letter := ""
var count := ""
var count_colour := Color("f0e4c8")
var count_centre := false ## a quiver's arrows: centred along the bottom
var count_size := 12
var placeholder := ""
var placeholder_size := 8
var ghost: Texture2D ## Dan's ghosted outline for an empty slot, over the placeholder word
var key := ""
var border := EMPTY_BORDER
var bar := false ## a spell-bar slot (darker, its own border)
var worn := "" ## '', 'worn' or 'broken'
var lit := false
var focused := false
var carried := false
var hovered := false
var dim := 1.0 ## the whole slot's opacity (an empty bar slot)
var icon_tint := Color.WHITE
var cooldown := 0.0 ## 0..1 of a turn still to go (the browser's conic sweep)
var cd_left := 0.0 ## seconds still to go, drawn as a countdown over the sweep
var gcd := 0.0
var glow := Color(0, 0, 0, 0) ## an outer glow (Brace up, an active item)
var inner := Color(0, 0, 0, 0) ## an inner ring
var overlay := Color(0, 0, 0, 0) ## a wash over the icon (out of range)
var painter := Callable() ## draws in place of an icon (the backpack)
var on_input := Callable()
var on_hover := Callable()


func _init(location := "", px := 42) -> void:
	loc = location
	custom_minimum_size = Vector2(px, px)
	size = custom_minimum_size
	# never stretched by a row or column: a slot is always square
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		hovered = true
		queue_redraw()
		if on_hover.is_valid():
			on_hover.call(self, true))
	mouse_exited.connect(func():
		hovered = false
		queue_redraw()
		if on_hover.is_valid():
			on_hover.call(self, false))


func _gui_input(e: InputEvent) -> void:
	if on_input.is_valid() and e is InputEventMouseButton:
		# taken first: a click that buys or uses may rebuild the window and
		# take this slot out of the tree, and an unaccepted click would fall
		# through to the world and walk you (Dan, 2026-10-28)
		accept_event()
		on_input.call(self, e)


## Set what an item slot shows from a stack (or null for an empty slot).
func show_stack(stack, icons: Icons, ph := "") -> void:
	icon = null
	letter = ""
	count = ""
	placeholder = ""
	worn = ""
	border = EMPTY_BORDER
	if stack != null:
		var def := Items.view(stack)
		icon = icons.item(stack.id) if icons else null
		if icon == null:
			letter = str(def.name).substr(0, 1)
		if stack.get("count", 1) > 1:
			count = str(stack.count)
		border = KIND_BORDER.get(def.get("kind"), border)
		var rarity: String = def.get("rarity", "common")
		if rarity != "junk" and rarity != "common":
			border = Items.rarity_colour(rarity)
		var dur := Items.durability(stack)
		if dur == 0:
			worn = "broken"
		elif dur != -1 and dur <= 25:
			worn = "worn"
	else:
		placeholder = ph
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var a := (0.35 if carried else 1.0) * dim
	modulate.a = a
	# the UI kit's slot frame: bronze on the spell bar, iron in bags
	draw_texture_rect(UI.kit("slot_bar" if bar else "slot_item"), r, false)
	var well := r.grow(-FRAME * size.x)
	var tint := icon_tint
	if worn == "broken":
		tint = Color(0.62, 0.32, 0.26)
	if icon:
		draw_texture_rect(icon, well, false, tint)
	elif painter.is_valid():
		painter.call(self)
	elif letter != "":
		_text(letter, r.get_center(), 18, UI.GOLD, true)
	elif ghost:
		draw_texture_rect(ghost, well, false)
	elif placeholder != "":
		_placeholder(r)
	if overlay.a > 0:
		draw_rect(well, overlay)
	# cooldown sweeps inside the frame, a cold blue-black as on the kit; the
	# darker one for the slot's own cooldown
	if cooldown > 0:
		_sweep(well, cooldown, Color(4 / 255.0, 8 / 255.0, 18 / 255.0, 0.74))
	if gcd > 0:
		_sweep(well, gcd, Color(10 / 255.0, 14 / 255.0, 24 / 255.0, 0.6))
	# an item's kind or rarity as a thin line inside the frame
	if border != EMPTY_BORDER:
		draw_rect(well.grow(0.5), border, false, 1)
	# the seconds left, WoW-style (tenths under 3 s on short ones would flicker, so whole seconds)
	if cd_left > 0.05 and cooldown > 0:
		var txt := "%dm" % ceili(cd_left / 60.0) if cd_left >= 60 else str(ceili(cd_left))
		var fs := 18 if bar else 15
		var tw := UI.bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := Vector2((size.x - tw) / 2, (size.y + UI.bold.get_ascent(fs) - UI.bold.get_descent(fs)) / 2)
		draw_string_outline(UI.bold, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
		draw_string(UI.bold, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("fff0c8"))
	if lit:
		draw_rect(well, Color(240 / 255.0, 200 / 255.0, 120 / 255.0, 0.14))
	if worn != "":
		draw_rect(well.grow(-1), Color(230 / 255.0, 170 / 255.0, 40 / 255.0, 0.75) if worn == "worn" else Color(220 / 255.0, 50 / 255.0, 40 / 255.0, 0.9), false, 2)
	if inner.a > 0:
		draw_rect(well.grow(-1), inner, false, 2)
	# the kit's gold highlight frame: lit, or under the mouse
	if lit or hovered:
		draw_texture_rect(UI.kit("slot_glow"), r, false, Color(1, 1, 1, 1.0 if lit else 0.7))
	if glow.a > 0:
		for i in 4:
			draw_rect(r.grow(1.5 + i * 1.5), Color(glow, glow.a * (1.0 - i / 4.0)), false, 1.5)
	if key != "":
		var f := UI.font
		var ks := 10 if bar else 9
		var kp := Vector2(well.position.x + 1, well.position.y + f.get_ascent(ks))
		draw_string_outline(f, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, 3, Color.BLACK)
		draw_string(f, kp, key, HORIZONTAL_ALIGNMENT_LEFT, -1, ks, UI.GOLD)
	if count != "":
		var f := UI.bold if count_centre else UI.font
		var w := f.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, count_size).x
		var p := Vector2((size.x - w) / 2 if count_centre else well.end.x - w - 1, well.end.y - f.get_descent(count_size))
		draw_string_outline(f, p, count, HORIZONTAL_ALIGNMENT_LEFT, -1, count_size, 3, Color.BLACK)
		draw_string(f, p, count, HORIZONTAL_ALIGNMENT_LEFT, -1, count_size, count_colour)
	if focused:
		draw_rect(r.grow(2), Color("f2d27a"), false, 2)


## the conic cooldown wash: what is left of the turn. The lit part grows
## clockwise from the top, as in WoW, so the dark part's edge sweeps
## clockwise too (Dan, 2026-10-21). Its edge is a true ray to the slot's
## border, through the corners, so it moves at an even pace.
func _sweep(r: Rect2, k: float, col: Color) -> void:
	k = clampf(k, 0, 1)
	if k <= 0.002:
		return
	if k >= 0.998:
		draw_rect(r, col)
		return
	var c := r.get_center()
	var h := r.size / 2
	var a0 := -PI / 2 + TAU * (1 - k)
	var a1 := -PI / 2 + TAU
	var pts := PackedVector2Array([c, _edge(c, h, a0)])
	var corners := []
	for q in [Vector2(h.x, h.y), Vector2(-h.x, h.y), Vector2(-h.x, -h.y), Vector2(h.x, -h.y)]:
		var ang := atan2(q.y, q.x)
		while ang < -PI / 2:
			ang += TAU
		if ang > a0 and ang < a1:
			corners.append([ang, c + q])
	corners.sort_custom(func(x, y): return x[0] < y[0])
	for q in corners:
		pts.append(q[1])
	pts.append(_edge(c, h, a1))
	draw_colored_polygon(pts, col)


## where a ray from the centre at angle `a` meets the slot's border
static func _edge(c: Vector2, h: Vector2, a: float) -> Vector2:
	var d := Vector2(cos(a), sin(a))
	var tx := h.x / absf(d.x) if absf(d.x) > 1e-6 else INF
	var ty := h.y / absf(d.y) if absf(d.y) > 1e-6 else INF
	return c + d * minf(tx, ty)


func _text(t: String, at: Vector2, px: int, col: Color, outline := false) -> void:
	var f := UI.font
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var p := Vector2(at.x - w / 2, at.y + (f.get_ascent(px) - f.get_descent(px)) / 2)
	if outline:
		draw_string_outline(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color.BLACK)
	draw_string(f, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## the empty slot's name in small capitals, wrapped to fit
func _placeholder(r: Rect2) -> void:
	var f := UI.font
	var px := placeholder_size
	var words := placeholder.to_upper().split(" ")
	var lines: Array = []
	for w in words:
		if lines.size() and f.get_string_size(lines[-1] + " " + w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x < r.size.x - 4:
			lines[-1] += " " + w
		else:
			lines.append(w)
	var lh := px * 1.15
	var y0 := r.get_center().y - lh * (lines.size() - 1) / 2.0
	for i in lines.size():
		_text(lines[i], Vector2(r.get_center().x, y0 + i * lh), px, Color("8c7a58"))

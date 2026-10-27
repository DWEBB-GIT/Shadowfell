class_name UI
extends RefCounted
## The HUD's shared look: dark panels in bronze frames from Dan's UI kit
## (assets/ui), parchment text, small buttons, money with coin icons, and rich
## text that can hold item and spell icons. Every window is built from these.

# Brighter and warmer than the browser build's palette: on top of the graded
# 3D view the old browns read as flat grey.
const PANEL := Color(24 / 255.0, 19 / 255.0, 13 / 255.0, 0.84)
const PANEL_SOLID := Color("1c1711")
const WINDOW := Color(24 / 255.0, 19 / 255.0, 13 / 255.0, 0.96)
const BORDER := Color("8f6f3c")
const BORDER_DIM := Color("57452a")
const GOLD := Color("e6b85e")
const TEXT := Color("ebdfc2")
const TEXT_DIM := Color("b0a386")
const BRIGHT := Color("fbefcf")
const UP := Color("8fdf6a")
const DOWN := Color("e06a5a")
const GREEN := Color("8cbf78")
const WARN := Color("d8a070")
const MIN_TEXT := 12 ## no text smaller than this, so every line stays readable
const QUEST_GOLD := Color("ffd23c")

static var font: Font
static var bold: Font
static var italic: Font
## the Icons node, so rich text can show item and spell icons
static var icons


static func setup_fonts() -> void:
	if font:
		return
	# The browser build's serif (Palatino, else Georgia) where the system has
	# it; else, and always on the web (which has no system fonts), the
	# bundled DejaVu Serif. Symbols the serif lacks (⇧, ☠, ⚔) come from
	# DejaVu Sans. Licence: game/fonts/DejaVu-LICENSE.txt
	var serif: FontFile = load("res://game/fonts/DejaVuSerif.ttf")
	var serif_bold: FontFile = load("res://game/fonts/DejaVuSerif-Bold.ttf")
	var sym: FontFile = load("res://game/fonts/DejaVuSans.ttf")
	if OS.has_feature("web"):
		font = _with([serif, sym])
		bold = _with([serif_bold, sym])
	else:
		var names := PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia"])
		var sys := SystemFont.new()
		sys.font_names = names
		sys.allow_system_fallback = false
		sys.fallbacks = [serif, sym]
		font = sys
		var sys_bold := SystemFont.new()
		sys_bold.font_names = names
		sys_bold.font_weight = 700
		sys_bold.allow_system_fallback = false
		sys_bold.fallbacks = [serif_bold, sym]
		bold = sys_bold
	# a slanted copy for italics (lore lines), as the bundled serif has none
	var it := FontVariation.new()
	it.base_font = font
	it.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	italic = it


static func _with(list: Array) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = list[0]
	f.fallbacks = list.slice(1)
	return f


## the theme every HUD control inherits: the serif, parchment text, the buttons
static func theme() -> Theme:
	setup_fonts()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	# WoW-style crisp text: a dark drop shadow under every label and button
	for k in ["Label", "Button"]:
		t.set_color("font_shadow_color", k, Color(0, 0, 0, 0.85))
		t.set_constant("shadow_offset_x", k, 1)
		t.set_constant("shadow_offset_y", k, 1)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0.8))
	t.set_constant("shadow_offset_x", "RichTextLabel", 1)
	t.set_constant("shadow_offset_y", "RichTextLabel", 1)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font("italics_font", "RichTextLabel", italic)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)
	t.set_font_size("bold_font_size", "RichTextLabel", 14)
	t.set_font_size("italics_font_size", "RichTextLabel", 14)
	# .btn: a small bronze frame (the UI kit); a gold frame on hover
	t.set_stylebox("normal", "Button", frame(Vector4(6, 1, 6, 1), "button", 6))
	t.set_stylebox("hover", "Button", frame(Vector4(6, 1, 6, 1), "button_hover", 7))
	t.set_stylebox("pressed", "Button", frame(Vector4(6, 2, 6, 0), "button_pressed", 6))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("disabled", "Button", frame(Vector4(6, 1, 6, 1), "button_disabled", 6))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("f2e6c6"))
	t.set_color("font_pressed_color", "Button", Color("f2e6c6"))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_font_size("font_size", "Button", 13)
	t.set_stylebox("normal", "LineEdit", box(Color(16 / 255.0, 13 / 255.0, 10 / 255.0, 0.92), BORDER, 0, 1, Vector4(10, 7, 10, 7)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), GOLD, 0, 1))
	t.set_color("font_color", "LineEdit", Color("f2e6c6"))
	t.set_stylebox("panel", "PanelContainer", frame(6))
	t.set_stylebox("slider", "HSlider", box(Color("0b0908"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area", "HSlider", box(Color("6b5a2c"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color("a48a45"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("panel", "TooltipPanel", box(Color(10 / 255.0, 9 / 255.0, 14 / 255.0, 0.96), Color("5a5a70"), 10))
	return t


## A panel's look: a fill, a 1 px border and inner padding (or per side:
## left, top, right, bottom).
static func box(bg: Color, border: Color, pad := 6, width := 1, sides = null) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.anti_aliasing = false
	if sides is Vector4:
		s.content_margin_left = sides.x
		s.content_margin_top = sides.y
		s.content_margin_right = sides.z
		s.content_margin_bottom = sides.w
	else:
		s.set_content_margin_all(pad)
	return s


## The UI kit's textures (assets/ui), cut from Dan's style sheet.
static var _kit := {}


static func kit(name: String) -> Texture2D:
	if not _kit.has(name):
		_kit[name] = load("res://assets/ui/%s.png" % name)
	return _kit[name]


## A bronze nine-patch frame from the UI kit: `tex` names the texture and
## `margin` its frame width in texture pixels. The padding (all sides, or
## left, top, right, bottom) is box()'s, but never less than the frame.
static func frame(sides = 6, tex := "panel", margin := 8) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = kit(tex)
	s.set_texture_margin_all(margin)
	var inset := minf(margin * 0.6, 8)
	var v: Vector4 = sides if sides is Vector4 else Vector4(sides, sides, sides, sides)
	s.content_margin_left = maxf(v.x, inset)
	s.content_margin_top = maxf(v.y, inset)
	s.content_margin_right = maxf(v.z, inset)
	s.content_margin_bottom = maxf(v.w, inset)
	return s


## the action bar's frame: thick bronze with an end cap on each side
static func capped_frame(sides = 6) -> CappedFrame:
	var s := CappedFrame.new()
	s.inner = frame(sides, "bar_frame", 10)
	s.left = kit("cap_left")
	s.right = kit("cap_right")
	s.content_margin_left = s.inner.content_margin_left + s.cap_room
	s.content_margin_top = s.inner.content_margin_top
	s.content_margin_right = s.inner.content_margin_right + s.cap_room
	s.content_margin_bottom = s.inner.content_margin_bottom
	return s


## a bar's empty track: the kit's dark stone strip
## a smoky dark band behind text on the world (the log, the objectives):
## solid on the `solid` side ("left" or "right"), fading out to the other
static func shade(solid := "left", alpha := 0.62, margin := Vector4(10, 6, 10, 6)) -> StyleBoxTexture:
	var g := Gradient.new()
	var dark := Color(0.03, 0.025, 0.02, alpha)
	g.set_color(0, dark if solid == "left" else Color(dark, 0))
	g.set_color(1, Color(dark, 0) if solid == "left" else dark)
	g.add_point(0.7 if solid == "left" else 0.3, dark)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 4
	var s := StyleBoxTexture.new()
	s.texture = t
	s.content_margin_left = margin.x
	s.content_margin_top = margin.y
	s.content_margin_right = margin.z
	s.content_margin_bottom = margin.w
	return s


static func bar_track() -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = kit("bar_track")
	s.set_texture_margin_all(4)
	s.set_content_margin_all(0)
	return s


static func panel(parent: Node, pad := 6, bg := PANEL, border := BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	if border == BORDER and (bg == PANEL or bg == WINDOW):
		p.add_theme_stylebox_override("panel", frame(pad, "panel" if bg == PANEL else "window", 8 if bg == PANEL else 20))
	else:
		p.add_theme_stylebox_override("panel", box(bg, border, pad))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if parent:
		parent.add_child(p)
	return p


static func label(parent: Node, text := "", size := 15, colour := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(size, MIN_TEXT))
	l.add_theme_color_override("font_color", colour)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(l)
	return l


static func vbox(parent: Node, gap := 4) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", gap)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(v)
	return v


static func hbox(parent: Node, gap := 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", gap)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(h)
	return h


static func gap(parent: Node, h := 6, w := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## a thin rule (border-bottom: 1px solid the dim border)
static func rule(parent: Node, colour := BORDER_DIM) -> ColorRect:
	var r := ColorRect.new()
	r.color = colour
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


## a small square button (×, −, +): the kit frame with no padding
static func square_button(parent: Node, text: String, cb := Callable(), px := 22) -> Button:
	var b := button(parent, text, cb, 14)
	for st in [["normal", "button"], ["hover", "button_hover"], ["pressed", "button_pressed"], ["disabled", "button_disabled"]]:
		b.add_theme_stylebox_override(st[0], frame(0, st[1], 6))
		var f: StyleBoxTexture = b.get_theme_stylebox(st[0])
		f.set_content_margin_all(0)
	b.custom_minimum_size = Vector2(px, px)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return b


static func button(parent: Node, text: String, cb := Callable(), size := 12) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", maxi(size, MIN_TEXT))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if cb.is_valid():
		b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


## Rich text: BBCode, sized to its content, wrapping at its width.
static func rich(parent: Node, size := 13, width := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = maxi(size, MIN_TEXT)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	if width > 0:
		r.custom_minimum_size = Vector2(width, 0)
	if parent:
		parent.add_child(r)
	_presize(r, width)
	return r


## Wrapped text is measured at the width it has, and a new label has none
## until its container lays it out a frame later: without this its first
## size is as tall as one word per line, and its window flashes huge.
static func _presize(c: Control, width := 0.0) -> void:
	var w := width
	var p := c.get_parent() as Control
	if w <= 0 and p != null:
		w = p.size.x
	if w > 0:
		c.size = Vector2(w, c.size.y)


## a label that wraps at its container's width (see _presize)
static func wrapped(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_presize(l)
	return l


## Size a floating panel to its contents, and keep it out of sight while
## that size is still settling (two frames the same): a window or tip with
## wrapped text otherwise shows for a frame at the wrong size, very large,
## before it shrinks into place (Dan, 2026-10-21).
static func fit_steady(c: Control) -> Vector2:
	var s := c.get_combined_minimum_size()
	var f := Engine.get_process_frames()
	var n: int = c.get_meta("fit_n", 0)
	if c.get_meta("fit_last", Vector2(-1, -1)) != s:
		n = 0
	elif c.get_meta("fit_f", -1) != f:
		n += 1
	c.set_meta("fit_last", s)
	c.set_meta("fit_n", n)
	c.set_meta("fit_f", f)
	c.modulate.a = 1.0 if n >= 1 else 0.0
	c.size = s
	return s


const _TOKEN := "\\{(gold|silver|item:[^}]+|ability:[^}]+|model:[^}]+)\\}"
static var _token_re: RegEx


## Fill rich text from BBCode with icon tokens: {gold} and {silver} coins,
## {item:<id>:<px>} an item's icon, {ability:<id>:<px>} a spell's.
static func set_rich(r: RichTextLabel, s: String) -> void:
	r.clear()
	if _token_re == null:
		_token_re = RegEx.create_from_string(_TOKEN)
	var at := 0
	for m in _token_re.search_all(s):
		if m.get_start() > at:
			r.append_text(s.substr(at, m.get_start() - at))
		var tok := m.get_string(1)
		var tex: Texture2D = null
		var px := 11
		if tok == "gold" or tok == "silver":
			tex = coin(tok)
		elif icons:
			var parts := tok.split(":")
			px = int(parts[2]) if parts.size() > 2 else 26
			if parts[0] == "item":
				var def = Items.get_def(parts[1])
				tex = icons.items.get(def.get("model", "")) if def else null
			elif parts[0] == "ability":
				tex = icons.abilities.get(parts[1])
		if tex:
			r.add_image(tex, px, px, Color.WHITE, INLINE_ALIGNMENT_CENTER)
		at = m.get_end()
	if at < s.length():
		r.append_text(s.substr(at))


## "1 gold 20 silver" as rich text with coins (money.js moneyHTML)
static func money(n: int) -> String:
	var g := floori(maxi(0, n) / 100.0)
	var s := maxi(0, n) % 100
	var out := ""
	if g:
		out += "[color=#ffd56a]%d[/color]{gold} " % g
	if s or not g:
		out += "[color=#e8edf2]%d[/color]{silver}" % s
	return out.strip_edges()


static var _coins := {}


## a coin icon: a small shaded disc (style.css .coin)
static func coin(kind: String) -> Texture2D:
	if _coins.has(kind):
		return _coins[kind]
	var stops := [Color("fff6c0"), Color("f2c030"), Color("8a5c0c")] if kind == "gold" else [Color("ffffff"), Color("cdd6e0"), Color("68707a")]
	var s := 22
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var c := Vector2(s / 2.0, s / 2.0)
	var hi := Vector2(s * 0.35, s * 0.35)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			if d > s / 2.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			if d > s / 2.0 - 2:
				img.set_pixel(x, y, Color(0, 0, 0, clampf(s / 2.0 - d, 0, 1)))
				continue
			var t := clampf(p.distance_to(hi) / (s * 0.75), 0, 1)
			var col: Color = stops[0].lerp(stops[1], t / 0.55) if t < 0.55 else stops[1].lerp(stops[2], (t - 0.55) / 0.45)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	_coins[kind] = ImageTexture.create_from_image(img)
	return _coins[kind]


## A window's frame (.window.panel with .window-head): a title in gold, the
## close button, a rule, then the body.
static func window(parent: Node, title: String, width := 0.0, on_close := Callable()) -> Dictionary:
	var p := panel(parent, 0, WINDOW, BORDER)
	p.add_theme_stylebox_override("panel", frame(Vector4(18, 14, 18, 16), "window", 20))
	if width > 0:
		p.custom_minimum_size = Vector2(width, 0)
	var v := vbox(p, 6)
	var head := hbox(v, 8)
	var t := label(head, title, 18, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close: Button = null
	if on_close.is_valid():
		close = square_button(head, "×", on_close)
	rule(v)
	var body := vbox(v, 6)
	return {"panel": p, "body": body, "head": head, "title": t, "close": close}


## a hint line under a window (.window-hint)
static func hint(parent: Node) -> Label:
	return wrapped(label(parent, "", 11, TEXT_DIM))


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func esc(s) -> String:
	return str(s).replace("[", "[lb]")


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)

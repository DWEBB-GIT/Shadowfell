class_name UI
extends RefCounted
## The HUD's shared look (style.css): dark translucent panels with thin warm
## borders, parchment text, small buttons, money with coin icons, and rich
## text that can hold item and spell icons. Every window is built from these.

const PANEL := Color(14 / 255.0, 12 / 255.0, 10 / 255.0, 0.78)
const PANEL_SOLID := Color("15120f")
const WINDOW := Color(16 / 255.0, 13 / 255.0, 10 / 255.0, 0.95)
const BORDER := Color("6b5532")
const BORDER_DIM := Color("3e3220")
const GOLD := Color("c9a45c")
const TEXT := Color("d9cdb0")
const TEXT_DIM := Color("9a8f78")
const BRIGHT := Color("efe2c0")
const UP := Color("8fdf6a")
const DOWN := Color("e06a5a")
const GREEN := Color("8cbf78")
const WARN := Color("d8a070")
const QUEST_GOLD := Color("ffd23c")

static var font: Font
static var bold: Font
static var italic: Font
## the Icons node, so rich text can show item and spell icons
static var icons


static func setup_fonts() -> void:
	if font:
		return
	var names := PackedStringArray(["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "serif"])
	font = SystemFont.new()
	font.font_names = names
	bold = SystemFont.new()
	bold.font_names = names
	bold.font_weight = 700
	italic = SystemFont.new()
	italic.font_names = names
	italic.font_italic = true
	# symbols the serif lacks (⇧, ☠, ⚔) come from a sans font
	var sym := SystemFont.new()
	sym.font_names = PackedStringArray(["DejaVu Sans", "Segoe UI Symbol", "Noto Sans Symbols2", "sans-serif"])
	for f in [font, bold, italic]:
		f.fallbacks = [sym]


## the theme every HUD control inherits: the serif, parchment text, the buttons
static func theme() -> Theme:
	setup_fonts()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_font("italics_font", "RichTextLabel", italic)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_font_size("bold_font_size", "RichTextLabel", 13)
	t.set_font_size("italics_font_size", "RichTextLabel", 13)
	# .btn: dark wood with a warm border; gold edge on hover
	t.set_stylebox("normal", "Button", box(Color("1d1812"), BORDER, 0, 1, Vector4(8, 2, 8, 2)))
	t.set_stylebox("hover", "Button", box(Color("2a2219"), GOLD, 0, 1, Vector4(8, 2, 8, 2)))
	t.set_stylebox("pressed", "Button", box(Color("2a2219"), GOLD, 0, 1, Vector4(8, 2, 8, 2)))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GOLD, 0, 1))
	t.set_stylebox("disabled", "Button", box(Color("1d1812"), BORDER_DIM, 0, 1, Vector4(8, 2, 8, 2)))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("f2e6c6"))
	t.set_color("font_pressed_color", "Button", Color("f2e6c6"))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_font_size("font_size", "Button", 12)
	t.set_stylebox("normal", "LineEdit", box(Color(16 / 255.0, 13 / 255.0, 10 / 255.0, 0.92), BORDER, 0, 1, Vector4(10, 7, 10, 7)))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0), GOLD, 0, 1))
	t.set_color("font_color", "LineEdit", Color("f2e6c6"))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, BORDER, 6))
	t.set_stylebox("slider", "HSlider", box(Color("0b0908"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area", "HSlider", box(Color("6b5a2c"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color("a48a45"), BORDER_DIM, 0, 1, Vector4(0, 3, 0, 3)))
	t.set_stylebox("panel", "TooltipPanel", box(Color(10 / 255.0, 9 / 255.0, 14 / 255.0, 0.96), Color("5a5a70"), 6))
	return t


## A panel's look: a fill, a 1 px border and inner padding (or per side:
## left, top, right, bottom).
static func box(bg: Color, border: Color, pad := 6, width := 1, sides = null) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	if sides is Vector4:
		s.content_margin_left = sides.x
		s.content_margin_top = sides.y
		s.content_margin_right = sides.z
		s.content_margin_bottom = sides.w
	else:
		s.set_content_margin_all(pad)
	return s


static func panel(parent: Node, pad := 6, bg := PANEL, border := BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(bg, border, pad))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if parent:
		parent.add_child(p)
	return p


static func label(parent: Node, text := "", size := 15, colour := TEXT, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
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


static func button(parent: Node, text: String, cb := Callable(), size := 12) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", size)
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
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	if width > 0:
		r.custom_minimum_size = Vector2(width, 0)
	if parent:
		parent.add_child(r)
	return r


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
		out += "[color=#efe2c0]%d[/color]{gold} " % g
	if s or not g:
		out += "[color=#efe2c0]%d[/color]{silver}" % s
	return out.strip_edges()


static var _coins := {}


## a coin icon: a small shaded disc (style.css .coin)
static func coin(kind: String) -> Texture2D:
	if _coins.has(kind):
		return _coins[kind]
	var stops := [Color("fff2b0"), Color("e0b030"), Color("7a5410")] if kind == "gold" else [Color("ffffff"), Color("b8c0c8"), Color("5a6068")]
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
	p.add_theme_stylebox_override("panel", box(WINDOW, BORDER, 0, 1, Vector4(12, 10, 12, 12)))
	if width > 0:
		p.custom_minimum_size = Vector2(width, 0)
	var v := vbox(p, 6)
	var head := hbox(v, 8)
	var t := label(head, title, 18, GOLD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close: Button = null
	if on_close.is_valid():
		close = button(head, "×", on_close, 14)
	rule(v)
	var body := vbox(v, 6)
	return {"panel": p, "body": body, "head": head, "title": t, "close": close}


## a hint line under a window (.window-hint)
static func hint(parent: Node) -> Label:
	var l := label(parent, "", 11, TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


static func esc(s) -> String:
	return str(s).replace("[", "[lb]")


static func hex(c: Color) -> String:
	return "#" + c.to_html(false)

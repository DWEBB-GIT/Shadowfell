class_name SkillTracker
extends PanelContainer
## The pinned skill on the HUD (Skills window: Track), RuneScape's XP
## tracker: the skill's icon and level, a bar to the next level, and the
## experience per hour and time to the next level while you work at it.
## It sits under the objectives, or under the minimap when there are none.

var game
var hud
var icon: TextureRect
var title: Label
var rate: Label
var fill: ColorRect
var left: Label
var _shown := ""
var _redraw := 0.0


func _init(g, h) -> void:
	game = g
	hud = h
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UI.box(Color(0, 0, 0, 0.55), Color(UI.BORDER_DIM, 0.8), 0, 1, Vector4(8, 5, 8, 5)))
	custom_minimum_size.x = 210
	var v := UI.vbox(self, 3)
	var top := UI.hbox(v, 6)
	icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(icon)
	title = UI.label(top, "", 12, Color("f0e4c8"), 4)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rate = UI.label(top, "", 11, UI.TEXT_DIM, 4)
	var track := ColorRect.new()
	track.color = Color.BLACK
	track.custom_minimum_size = Vector2(0, 5)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(track)
	fill = ColorRect.new()
	fill.color = Color("c8a040")
	fill.anchor_bottom = 1
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	left = UI.label(v, "", 11, UI.TEXT_DIM, 4)
	visible = false
	game.events.on("skillsChanged", func(_e): _redraw = 0.0)


func update(dt: float) -> void:
	var sk = game.skills
	var id: String = sk.tracked if sk != null else ""
	visible = id != "" and sk.has(id)
	if not visible:
		return
	_redraw -= dt
	if _redraw <= 0.0 or _shown != id:
		_redraw = 1.0
		_shown = id
		_fill(id)
	var tr: Control = hud.quests.tracker
	var vp := get_viewport_rect().size
	size = get_combined_minimum_size()
	var y: float = tr.position.y + tr.size.y + 6 if tr.visible else tr.position.y
	position = Vector2(vp.x - size.x - 4, roundf(y))


func _fill(id: String) -> void:
	var sk = game.skills
	var d: Dictionary = DB.skills[id]
	icon.texture = hud.icons.profession(id)
	var lvl: int = sk.rank(id)
	title.text = "%s %d" % [d.name, lvl]
	var capped: bool = lvl >= sk.cap(id)
	var per_hour: float = sk.xp_rate(id)
	rate.text = "%s xp/hr" % U.n(roundi(per_hour)) if per_hour > 0 and not capped else ""
	if not sk.laddered(id):
		fill.anchor_right = clampf(float(lvl) / maxf(1, sk.cap(id)), 0, 1)
		left.text = "Rises as you use it"
		return
	var need: int = Skills.xp_needed(lvl)
	var have := int(sk.xp.get(id, 0))
	fill.anchor_right = 1.0 if capped else clampf(float(have) / need, 0, 1)
	if capped:
		left.text = "At the %s's limit" % sk.rank_name(id)
	else:
		var to_go := need - have
		var eta := ""
		if per_hour > 0:
			var mins := ceili(to_go / per_hour * 60.0)
			eta = "  ~%d min" % mins if mins < 120 else "  ~%d h" % ceili(mins / 60.0)
		left.text = "%s xp to level %d%s" % [U.n(to_go), lvl + 1, eta]

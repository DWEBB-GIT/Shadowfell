class_name Boons
extends RefCounted
## Timed boons (data/boons.json). Inspired: more experience for a while, so
## the reward for curiosity is more play rather than skipped play. You are
## Inspired by reading a lore document for the first time, or by paying the
## bard at the Ford Inn for a tale (once a day). The clock runs only while
## you play, and a new Inspired starts it again rather than stacking.

var game
var inspired := 0.0 ## seconds of Inspired left
var read := {} ## lore documents already read
var tale_day := "" ## the day (YYYY-MM-DD) of the last tale
var tales_heard := 0


func _init(g) -> void:
	game = g
	game.events.on("documentRead", func(e): _read(e.id))


func reset() -> void:
	inspired = 0.0
	read = {}
	tale_day = ""
	tales_heard = 0


static func rule() -> Dictionary:
	return DB.boons.get("inspired", {"name": "Inspired", "xpBonus": 10, "seconds": 1800})


## percent more experience now
var xp_bonus: float:
	get:
		return rule().get("xpBonus", 10) if inspired > 0 else 0.0

## the buff row's entry
var aura:
	get:
		if inspired <= 0:
			return null
		var r := rule()
		return {"id": "inspired", "icon": "battleCry", "name": r.get("name", "Inspired"), "left": inspired, "total": r.get("seconds", 1800), "text": r.get("desc", "")}


func inspire(why: String) -> void:
	var r := rule()
	inspired = r.get("seconds", 1800)
	game.events.emit("log", {"text": "%s You are %s: +%s%% experience for %d minutes." % [why, r.get("name", "Inspired"), U.n(r.get("xpBonus", 10)), U.jround(inspired / 60.0)], "kind": "level"})
	if game.hud:
		game.hud.toast(r.get("name", "Inspired"))
	game.events.emit("boonsChanged", {})


func _read(id: String) -> void:
	var doc = DB.text.documents.get(id)
	if doc == null or not doc.get("lore") or read.has(id):
		return
	read[id] = true
	inspire("What you read stays with you.")


# ------------------------------------------------------------ the bard
static func bard() -> Dictionary:
	return DB.boons.get("bard", {})


static func today() -> String:
	return Time.get_date_string_from_system()


## Has the bard a tale for you today?
var tale_ready: bool:
	get:
		return tale_day != today()


## Pay for a tale: the next in turn, and Inspired.
func hear_tale() -> String:
	var b := bard()
	if not tale_ready:
		return ""
	var price := int(b.get("price", 5))
	if game.inventory.coins < price:
		if game.hud:
			game.hud.error("You cannot afford a tale")
		return ""
	game.inventory.lose_coins(price)
	var tales: Array = b.get("tales", [""])
	var tale: String = tales[tales_heard % tales.size()]
	tales_heard += 1
	tale_day = today()
	inspire("The tale stirs your blood.")
	return tale


func update(dt: float) -> void:
	if inspired > 0:
		inspired = maxf(0, inspired - dt)
		if inspired == 0:
			game.events.emit("log", {"text": "%s fades." % rule().get("name", "Inspired"), "kind": "muted"})
			game.events.emit("boonsChanged", {})


func serialize() -> Dictionary:
	return {"inspired": U.jround(inspired), "read": read.keys(), "taleDay": tale_day, "tales": tales_heard}


func apply(data) -> void:
	reset()
	if typeof(data) != TYPE_DICTIONARY:
		return
	var i = data.get("inspired", 0)
	if (typeof(i) == TYPE_INT or typeof(i) == TYPE_FLOAT) and i > 0:
		inspired = minf(float(i), rule().get("seconds", 1800))
	for id in data.get("read", []):
		if typeof(id) == TYPE_STRING and DB.text.documents.has(id):
			read[id] = true
	if typeof(data.get("taleDay")) == TYPE_STRING:
		tale_day = data.taleDay
	tales_heard = int(data.get("tales", 0))

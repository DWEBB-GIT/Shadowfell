class_name Items
extends RefCounted
## Items: random rolls, what one particular item is, what a merchant pays,
## and loot table rolls. A port of src/data/items.js; the field list of an
## item record is documented there.

const BACKPACK_SLOTS := 16
const BAG_SOCKETS := 4 ## socket 0 is the backpack and cannot be removed
const TOOL_SOCKET := 4 ## one more socket after the bags, for the tool pack

const ROLLS := {"spread": 0.2, "damageSpread": 0.12, "valuePerPoint": 4}
const ROLLED_KINDS := ["weapon", "armor", "shield", "jewellery"]
const SUFFIX_RARITY := "enhanced"
const RENAMED_STATS := {"might": "strength", "finesse": "agility", "vitality": "stamina"}
const RETIRED_STATS := ["blockRating"]


static func get_def(id) -> Dictionary:
	return DB.items.get(id, {})


## Enhanced drops of common gear gain a suffix (WoW's "of the Bear"). One
## name is always one item: the stats come from the item and its suffix
## alone, never a hidden roll, so two Helms of the Old Watch are the same.
## `rand` is a Callable returning [0, 1). Returns the rolls, or null.
static func roll_item(id: String, rand: Callable, rarity = null):
	var d := get_def(id)
	if rarity == null:
		rarity = d.get("rarity")
	if d.is_empty() or not ROLLED_KINDS.has(d.kind) or d.get("quest", false):
		return null
	if DB.rarities.has(rarity) and DB.rarities[rarity].get("suffix") and d.rarity == "common":
		var keys := DB.suffixes.keys()
		return {"suffix": keys[mini(keys.size() - 1, int(floor(rand.call() * keys.size())))]}
	return null


## The stats a suffix adds to an item: its share of the enhanced budget.
static func suffix_stats(d: Dictionary, suffix: String) -> Dictionary:
	var out := {}
	var sfx: Array = DB.suffixes[suffix].stats
	var points := Scaling.item_budget(d, SUFFIX_RARITY) / sfx.size()
	for k in sfx:
		out[k] = maxi(1, U.jround(points / Scaling.stat_cost(k, d.itemLevel)))
	return out


## What one particular item is: the database entry with its rolls applied.
## A broken item (durability 0) still shows what it was, but gives nothing.
static func view(stack: Dictionary) -> Dictionary:
	var v := _rolled_view(stack)
	if not v.is_empty() and stack.get("dur", -1) == 0 and DB.DURABLE_KINDS.has(v.kind):
		v = v.duplicate()
		v.stats = {}
		v.broken = true
	return v


## Durability in percent, or -1 for things that do not wear.
static func durability(stack) -> int:
	if stack == null or not DB.DURABLE_KINDS.has(get_def(stack.id).get("kind")):
		return -1
	return int(stack.get("dur", 100))


static func _rolled_view(stack: Dictionary) -> Dictionary:
	var d := get_def(stack.get("id"))
	var r = stack.get("rolls")
	if d.is_empty() or r == null:
		return d
	var stats: Dictionary = d.get("stats", {}).duplicate()
	# older saves kept a small random spread on stats and damage; it is
	# dropped, so every copy of an item matches (the suffix is all that varies)
	var rs: Dictionary = suffix_stats(d, r.suffix) if r.has("suffix") and DB.suffixes.has(r.suffix) else {}
	for k in rs:
		var key: String = RENAMED_STATS.get(k, k)
		if not DB.STAT_KEYS.has(key):
			continue
		stats[key] = stats.get(key, 0) + rs[k]
	for k in stats.keys():
		if stats[k] <= 0:
			stats.erase(k)
	var bonus := 0.0
	for k in rs:
		bonus += maxf(0, rs[k]) * Scaling.stat_cost(RENAMED_STATS.get(k, k), d.get("itemLevel", 1))
	var out := d.duplicate()
	if r.has("suffix"):
		out.name = "%s %s" % [d.name, DB.suffixes[r.suffix].name]
	out.rarity = "enhanced" if r.has("suffix") and d.rarity == "common" else d.rarity
	out.stats = stats
	out.price = d.get("price", 0) + (U.jround(bonus * ROLLS.valuePerPoint) if r.has("suffix") else 0)
	return out


## Are these rolls well formed? (saves are checked before they are applied)
static func valid_rolls(id: String, r) -> bool:
	if r == null:
		return true
	var d := get_def(id)
	if d.is_empty() or typeof(r) != TYPE_DICTIONARY or not ROLLED_KINDS.has(d.kind):
		return false
	if r.has("stats"):
		if typeof(r.stats) != TYPE_DICTIONARY:
			return false
		for k in r.stats:
			var v = r.stats[k]
			if not (DB.STAT_KEYS.has(k) or RENAMED_STATS.has(k) or RETIRED_STATS.has(k)):
				return false
			if not _is_int(v) or absf(v) > 1000:
				return false
	if r.has("damage"):
		var dm = r.damage
		if typeof(dm) != TYPE_ARRAY or dm.size() != 2 or not _is_int(dm[0]) or not _is_int(dm[1]) or dm[0] < 1 or dm[1] > 1000 or dm[0] > dm[1]:
			return false
	if r.has("suffix") and not DB.suffixes.has(r.suffix):
		return false
	return true


static func _is_int(v) -> bool:
	return (typeof(v) == TYPE_INT) or (typeof(v) == TYPE_FLOAT and v == floor(v))


## What a merchant pays for one of an item (a stack, or just an id).
static func sell_price(item, fraction: float) -> int:
	var stack: Dictionary = {"id": item} if typeof(item) == TYPE_STRING else item
	var d := get_def(stack.get("id"))
	if d.is_empty() or d.get("quest", false):
		return 0
	return int(floor(view(stack).get("price", 0) * fraction))


## What one enemy drops: every `always` item, then `rolls` tries at `chance`,
## each a rarity by weight and then an item. Returns [{ id, count, rarity }].
static func roll_loot(table, rand: Callable) -> Array:
	var out := []
	if table == null or table.is_empty():
		return out
	for a in table.get("always", []):
		var n := int(a.min) + int(floor(rand.call() * (a.max - a.min + 1)))
		if n > 0:
			out.append({"id": a.item, "count": n, "rarity": get_def(a.item).get("rarity")})
	var drops = table.get("drops")
	if drops:
		for i in int(drops.rolls):
			if rand.call() >= drops.chance:
				continue
			var tiers := []
			for r in DB.rarities:
				if drops.rarity.get(r):
					tiers.append({"r": r, "weight": drops.rarity[r]})
			var rarity: String = _pick_weighted(tiers, rand).r
			out.append({"id": _pick_weighted(drops.items[rarity], rand).item, "count": 1, "rarity": rarity})
	return out


static func _pick_weighted(list: Array, rand: Callable) -> Dictionary:
	var total := 0.0
	for e in list:
		total += e.weight
	var pick: float = rand.call() * total
	for e in list:
		pick -= e.weight
		if pick < 0:
			return e
	return list[list.size() - 1]


## Unique drops: an enemy type with `uniqueDrop` leaves that item where it falls, once.
static func unique_drops() -> Dictionary:
	var out := {}
	for id in DB.enemies:
		var e: Dictionary = DB.enemies[id]
		if not e.has("uniqueDrop"):
			continue
		var item := get_def(e.uniqueDrop)
		out[e.uniqueDrop] = {"id": e.uniqueDrop, "model": item.get("model", ""), "prompt": "Take %s" % item.name, "reward": {"item": e.uniqueDrop}, "droppedBy": e.name}
	return out


static func rarity_colour(rarity) -> Color:
	return Color(DB.rarities.get(rarity, DB.rarities.get("common", {})).get("colour", "#e8e0d0"))

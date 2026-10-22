class_name Gems
extends RefCounted
## Gems (data/gems.json): every gem type in every quality is an item, made
## here from the two lists rather than written out in items.json. A gem in a
## socket gives back the slice of the item budget the socket took
## (Scaling.socket_share), worked out from its quality's level, so sockets
## never lift gear past the formula. Utility gems (Moonstone, Jade) give an
## `effect` instead of stats.


static func types() -> Array:
	return DB.gems.get("gemTypes", [])


static func qualities() -> Array:
	return DB.gems.get("gemQualities", [])


static func type_def(id: String) -> Dictionary:
	for t in types():
		if t.id == id:
			return t
	return {}


static func gem_id(type: String, quality: String) -> String:
	return "%s_%s" % [type, quality]


## { type, quality, q (index, 0 for the lowest) } of a gem item, or {}
static func parse(item_id) -> Dictionary:
	var d := Items.get_def(item_id)
	if d.get("kind") != "gem":
		return {}
	return {"type": d.gemType, "quality": d.gemQuality, "q": int(d.gemTier)}


## The gem item records (DB.setup adds them to DB.items).
static func item_records() -> Array:
	var out := []
	var qs := qualities()
	for t in types():
		for i in qs.size():
			var q: Dictionary = qs[i]
			var rec := {
				"id": gem_id(t.id, q.id), "name": "%s %s" % [q.name, t.name], "kind": "gem", "rarity": q.get("rarity", "common"),
				"stack": 20, "price": q.get("price", 1), "model": t.get("model", "rock0"), "icon": t.get("model", "rock0"),
				"gemType": t.id, "gemQuality": q.id, "gemTier": i, "description": t.get("desc", ""),
			}
			if t.has("slots"):
				rec.gemSlots = t.slots
			out.append(rec)
	return out


## The stats a gem gives in a socket (empty for a utility gem).
static func stats(item_id) -> Dictionary:
	var g := parse(item_id)
	if g.is_empty():
		return {}
	var t := type_def(g.type)
	var q: Dictionary = qualities()[g.q]
	var points: float = DB.gems.get("pointsPerLevel", 0.1) * Scaling.growth(q.level)
	var keys: Array = t.get("stats", [t.stat] if t.has("stat") else [])
	var out := {}
	for k in keys:
		out[k] = maxi(1, U.jround(points / keys.size() / Scaling.stat_cost(k, q.level)))
	return out


## A utility gem's effect value, or 0.
static func effect(item_id, kind: String) -> float:
	var g := parse(item_id)
	if g.is_empty():
		return 0.0
	var t := type_def(g.type)
	if t.get("effect") != kind:
		return 0.0
	var per: Array = t.get("perQuality", [])
	return float(per[mini(g.q, per.size() - 1)]) if not per.is_empty() else 0.0


## What a gem does, as one line for its tooltip.
static func bonus_text(item_id) -> String:
	var g := parse(item_id)
	if g.is_empty():
		return ""
	var t := type_def(g.type)
	if t.get("effect") == "gatherSkill":
		return "+%s Mining, Skinning and Fishing" % U.n(effect(item_id, "gatherSkill"))
	if t.get("effect") == "buffDuration":
		return "Well Fed lasts %s%% longer" % U.n(effect(item_id, "buffDuration"))
	var parts := []
	var s := stats(item_id)
	for k in s:
		parts.append("+%s %s" % [U.n(s[k]), k.capitalize()])
	return ", ".join(parts)


## Can this gem sit in that item? (Starstone only in a weapon)
static func fits(item_id, gear: Dictionary) -> bool:
	var d := Items.get_def(item_id)
	if d.get("kind") != "gem":
		return false
	var only = d.get("gemSlots")
	return only == null or only.has(gear.get("slot"))


## What these make at a jeweller: [{ from, count, to }], one row a gem you
## could make (shards to the lowest quality, then three of one into the next).
static func recipes() -> Array:
	var out := []
	var qs := qualities()
	for t in types():
		if qs.is_empty():
			break
		out.append({"from": t.shard, "count": int(t.get("shardCount", qs[0].count)), "to": gem_id(t.id, qs[0].id)})
		for i in range(1, qs.size()):
			out.append({"from": gem_id(t.id, qs[i - 1].id), "count": int(qs[i].count), "to": gem_id(t.id, qs[i].id)})
	return out

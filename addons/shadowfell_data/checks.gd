@tool
extends RefCounted
## The rules the browser build's `npm run validate` applies to items, loot
## tables and rewards (src/data/schema.js), so a problem shows in the editor
## before the build refuses the data.

const DataStore := preload("store.gd")


static func run(s: DataStore) -> PackedStringArray:
	var out := PackedStringArray()
	_items(s, out)
	_tables(s, out)
	_rewards(s, out)
	return out


static func _is_int(v) -> bool:
	return (v is int or v is float) and v == floorf(v)


static func _is_num(v) -> bool:
	return v is int or v is float


static func _items(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	var armour := s.armour_types.map(func(a): return a.id)
	var table_ids := s.loot_tables.map(func(t): return t.id)
	for d in s.items:
		var id: String = str(d.get("id", ""))
		var bad := func(msg): out.append("Item %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		if id != DataStore.slug(id) or id == "":
			bad.call("id must be lower_snake_case")
		if str(d.get("name", "")) == "" or str(d.get("description", "")) == "":
			bad.call("needs a name and a description")
		var kind = d.get("kind")
		if not DataStore.KINDS.has(kind):
			bad.call("unknown type %s" % kind)
		if s.rarity(d.get("rarity")).is_empty():
			bad.call("unknown rarity %s" % d.get("rarity"))
		if d.get("quest") and d.get("rarity") != "quest":
			bad.call("a quest item has the quest rarity")
		if not (_is_int(d.get("stack")) and d.stack >= 1):
			bad.call("stack must be a whole number of at least 1")
		if not (_is_int(d.get("price")) and d.price >= 0):
			bad.call("price must be a whole number of coins")
		for k in ["model", "icon"]:
			var m = d.get(k)
			if m == null or str(m) == "":
				bad.call("needs a %s" % k)
			elif not s.models.has(m):
				bad.call("%s %s is not in assets/models" % [k, m])
		if d.has("sprite") and not s.sprites.has(d.sprite):
			bad.call("sprite %s is not in assets/icons" % d.sprite)
		var equips := DataStore.EQUIPPABLE.has(kind)
		if equips and not DataStore.SLOTS.has(d.get("slot")):
			bad.call("needs a slot")
		if not equips and d.has("slot"):
			bad.call("only weapons, armour, shields, jewellery and torches have a slot")
		if kind == "armor" and not armour.has(d.get("armourType")):
			bad.call("armour needs an armour type")
		if DataStore.GEAR.has(kind) or kind == "jewellery":
			if not (_is_int(d.get("itemLevel")) and d.itemLevel >= 1):
				bad.call("gear needs an item level of at least 1")
			for k in d.get("statSplit", {}):
				if not DataStore.STAT_KEYS.has(k):
					bad.call("unknown stat %s" % k)
				elif not (d.statSplit[k] > 0):
					bad.call("stat %s needs a share above 0" % k)
			if d.has("statSplit") and d.get("rarity") in ["junk", "common", "quest"]:
				bad.call("a %s item has no stat points to split (make it Enhanced or better)" % d.get("rarity"))
		if kind == "weapon" and not (_is_num(d.get("speed")) and d.speed >= 1 and d.speed <= 5):
			bad.call("a weapon needs a swing speed of 1 to 5 seconds")
		if d.get("slot") == "ranged" and not (_is_num(d.get("range")) and d.range >= 8 and d.range <= 40):
			bad.call("a ranged weapon needs a range of 8 to 40 metres")
		if kind == "bag" and not (d.get("bagSlots", 0) > 0):
			bad.call("a bag needs bag slots")
		if kind == "ammo" and not _is_num(d.get("ammoDps")):
			bad.call("ammo needs the damage a second it adds")
		if kind == "torch" and not (d.get("light", 0) > 0):
			bad.call("a torch needs light")
		if d.has("use"):
			var u: Dictionary = d.use
			var food: Dictionary = u.get("food", {})
			if not (u.get("heal", 0) > 0 or (food.get("heal", 0) > 0 and food.get("seconds", 0) > 0)):
				bad.call("its use must heal, or be food that heals over some seconds")
		for t in d.get("reservedFor", []):
			if not table_ids.has(t):
				bad.call("reserved for unknown loot table %s" % t)


static func _tables(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	for t in s.loot_tables:
		var id: String = str(t.get("id", ""))
		var bad := func(msg): out.append("Loot table %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		for a in t.get("always", []):
			var d := s.item(a.get("item"))
			if d.is_empty():
				bad.call("always drops unknown item %s" % a.get("item"))
			elif d.get("quest"):
				bad.call("quest item %s cannot be loot" % d.id)
			if not (_is_int(a.get("min")) and _is_int(a.get("max")) and a.min >= 0 and a.min <= a.max):
				bad.call("%s needs whole numbers, min no more than max" % a.get("item"))
			_reserved(d, id, bad)
		if not t.has("drops"):
			continue
		var drops: Dictionary = t.drops
		if not (_is_int(drops.get("rolls")) and drops.rolls >= 1):
			bad.call("rolls must be a whole number of at least 1")
		if not (_is_num(drops.get("chance")) and drops.chance >= 0 and drops.chance <= 1):
			bad.call("chance must be 0% to 100%")
		var weights: Dictionary = drops.get("rarity", {})
		var lists: Dictionary = drops.get("items", {})
		if weights.is_empty():
			bad.call("random drops need at least one rarity")
		for r in weights:
			if s.rarity(r).is_empty() or s.rarity(r).get("drops", true) == false:
				bad.call("rarity %s cannot drop" % r)
			if not (weights[r] > 0):
				bad.call("rarity %s needs a weight above 0" % r)
			if lists.get(r, []).is_empty():
				bad.call("rarity %s has no items to roll" % r)
		for r in lists:
			if not weights.has(r):
				bad.call("items listed under %s, which it never rolls" % r)
			for e in lists[r]:
				var d := s.item(e.get("item"))
				if d.is_empty():
					bad.call("%s lists unknown item %s" % [r, e.get("item")])
					continue
				if not (e.get("weight", 0) > 0):
					bad.call("%s needs a weight above 0" % d.id)
				var rolls_up: bool = r == "enhanced" and d.get("rarity") == "common" and DataStore.GEAR.has(d.get("kind"))
				if d.get("rarity") != r and not rolls_up:
					bad.call("%s is %s and cannot be listed under %s" % [d.id, d.get("rarity"), r])
				_reserved(d, id, bad)


static func _reserved(d: Dictionary, table: String, bad: Callable) -> void:
	if d.has("reservedFor") and not d.reservedFor.has(table):
		bad.call("%s is kept for %s only" % [d.id, ", ".join(d.reservedFor)])


static func _rewards(s: DataStore, out: PackedStringArray) -> void:
	for q in s.quests:
		for e in q.get("reward", {}).get("items", []):
			if s.item(e.get("item")).is_empty():
				out.append("Quest %s: reward names unknown item %s" % [q.id, e.get("item")])
			if not (_is_int(e.get("count")) and e.count >= 1):
				out.append("Quest %s: reward %s needs a count of at least 1" % [q.id, e.get("item")])
	for c in s.chests:
		for e in c.get("items", []):
			if s.item(e.get("id")).is_empty():
				out.append("Chest %s: names unknown item %s" % [c.id, e.get("id")])

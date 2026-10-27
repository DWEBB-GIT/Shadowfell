@tool
extends RefCounted
## The rules the browser build's `npm run validate` applies to items, loot
## tables, quests, npcs and shops (src/data/schema.js), so a problem shows in the editor
## before the build refuses the data.

const DataStore := preload("store.gd")
## models the game draws in code rather than loading (schema.js PROCEDURAL_MODELS)
const PROCEDURAL_MODELS := ["training_dummy", "town_board"]


static func run(s: DataStore) -> PackedStringArray:
	var out := PackedStringArray()
	_items(s, out)
	_tables(s, out)
	_bands(s, out)
	_enemies(s, out)
	_rewards(s, out)
	_quests(s, out)
	_npcs(s, out)
	_shops(s, out)
	_dialogues(s, out)
	_abilities(s, out)
	_skills(s, out)
	_classes(s, out)
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
			var drink: Dictionary = u.get("drink", {})
			if not (u.get("heal", 0) > 0 or (food.get("heal", 0) > 0 and food.get("seconds", 0) > 0) or (drink.get("mana", 0) > 0 and drink.get("seconds", 0) > 0)):
				bad.call("its use must heal, be food that heals over some seconds or a drink that restores mana over some seconds")
		for t in d.get("reservedFor", []):
			if not table_ids.has(t):
				bad.call("reserved for unknown loot table %s" % t)


static func _tables(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	for t in s.loot_tables + s.world_drops:
		var id: String = str(t.get("id", ""))
		var label := "World drops" if s.is_band(t) else "Loot table"
		var bad := func(msg): out.append("%s %s: %s" % [label, id, msg])
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
		for qd in t.get("questDrops", []):
			var q := DataStore.find(s.quests, qd.get("quest"))
			if s.item(qd.get("item")).is_empty():
				bad.call("quest drop names unknown item %s" % qd.get("item"))
			if q.is_empty():
				bad.call("quest drop names unknown quest %s" % qd.get("quest"))
			elif not q.get("objectives", []).any(func(o): return o.get("type") == "collect" and o.get("target") == qd.get("item")):
				bad.call("quest %s has no objective to collect %s" % [q.id, qd.get("item")])
			if not (qd.get("chance", 0) > 0 and qd.get("chance", 0) <= 1):
				bad.call("quest drop %s needs a chance above 0%%" % qd.get("item"))
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


## world-drop bands: whole levels, no two overlapping
static func _bands(s: DataStore, out: PackedStringArray) -> void:
	var bands := s.world_drops.duplicate()
	bands.sort_custom(func(a, b): return a.get("minLevel", 0) < b.get("minLevel", 0))
	for i in bands.size():
		var b: Dictionary = bands[i]
		if not (_is_int(b.get("minLevel")) and _is_int(b.get("maxLevel")) and b.minLevel >= 1 and b.minLevel <= b.maxLevel):
			out.append("World drops %s: needs whole levels, min no more than max" % b.id)
		elif i > 0 and b.minLevel <= bands[i - 1].get("maxLevel", 0):
			out.append("World drops %s: its levels overlap %s" % [b.id, bands[i - 1].id])


static func _enemies(s: DataStore, out: PackedStringArray) -> void:
	for e in s.enemies:
		var r := s.resolved(e)
		if e.has("base") and DataStore.find(s.enemies, e.base).is_empty():
			out.append("Enemy %s: its base %s does not exist" % [e.id, e.base])
		if r.has("maxLevel") and not (_is_int(r.maxLevel) and r.maxLevel >= r.get("level", 1)):
			out.append("Enemy %s: max level must be at least its level" % e.id)
		for k in ["lootTable", "skin"]:
			if str(r.get(k, "")) != "" and DataStore.find(s.loot_tables, r[k]).is_empty():
				out.append("Enemy %s: %s names unknown loot table %s" % [e.id, k, r[k]])


static func _reserved(d: Dictionary, table: String, bad: Callable) -> void:
	if d.has("reservedFor") and not d.reservedFor.has(table):
		bad.call("%s is kept for %s only" % [d.id, ", ".join(d.reservedFor)])


static func _coins_ok(c) -> bool:
	if c is Dictionary:
		return _is_int(c.get("min")) and _is_int(c.get("max")) and c.min >= 0 and c.max >= c.min
	return c == null or (_is_int(c) and c >= 0)


static func _rewards(s: DataStore, out: PackedStringArray) -> void:
	for c in s.chests:
		if not _coins_ok(c.get("coins")):
			out.append("Chest %s: coins must be whole silver, or a min to max range" % c.id)
		for e in c.get("items", []):
			if s.item(e.get("id")).is_empty():
				out.append("Chest %s: names unknown item %s" % [c.id, e.get("id")])


static func _quests(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	var choices := {}
	for q in s.quests:
		var id := str(q.get("id", ""))
		var bad := func(msg): out.append("Quest %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		if id != DataStore.slug(id) or id == "":
			bad.call("id must be lower_snake_case")
		for k in ["name", "summary", "progress", "complete"]:
			if str(q.get(k, "")) == "":
				bad.call("needs %s text" % k)
		if not q.get("autoAccept", false) and str(q.get("offer", "")) == "":
			bad.call("needs an offer (what the giver says)")
		for k in ["giver", "turnIn"]:
			if s.npc(q.get(k)).is_empty():
				bad.call("%s names unknown npc %s" % ["giver" if k == "giver" else "hand-in", q.get(k)])
		for r in q.get("requires", []):
			if s.quest(r).is_empty():
				bad.call("requires unknown quest %s" % r)
			if r == id:
				bad.call("cannot require itself")
		var objs: Array = q.get("objectives", [])
		if objs.is_empty():
			bad.call("needs at least one objective")
		var oids := {}
		for o in objs:
			var oid := str(o.get("id", ""))
			var label := "objective %s" % oid
			if oid == "" or oids.has(oid):
				bad.call("each objective needs its own id (%s)" % oid)
			oids[oid] = true
			if str(o.get("label", "")) == "":
				bad.call("%s needs a label" % label)
			match o.get("type"):
				"kill":
					if DataStore.find(s.enemies, o.get("target")).is_empty():
						bad.call("%s names unknown enemy %s" % [label, o.get("target")])
					else:
						var placed := s.enemy_spawns.filter(func(sp): return sp.get("enemy") == o.target).size()
						if o.get("count", 1) > placed:
							bad.call("%s needs %d %s but the world only has %d" % [label, o.get("count", 1), o.target, placed])
				"collect":
					if s.item(o.get("target")).is_empty():
						bad.call("%s names unknown item %s" % [label, o.get("target")])
				"examine":
					if not s.examine_points.has(o.get("target")):
						bad.call("%s names unknown examine point %s" % [label, o.get("target")])
				"talk":
					if o.get("target") != q.get("turnIn"):
						bad.call("%s: a talk objective names the hand-in npc (%s)" % [label, q.get("turnIn")])
				_:
					bad.call("%s: type must be kill, collect, examine or talk" % label)
			if o.has("count") and not (_is_int(o.count) and o.count >= 1):
				bad.call("%s: count must be a whole number of at least 1" % label)
			if o.has("location") and DataStore.find(s.locations, o.location).is_empty():
				bad.call("%s names unknown map area %s" % [label, o.location])
		var r: Dictionary = q.get("reward", {})
		if not _coins_ok(r.get("coins")):
			bad.call("reward coins must be whole silver, or a min to max range")
		if r.has("xp") and not _is_int(r.xp):
			bad.call("reward xp must be a whole number")
		for e in r.get("items", []):
			if s.item(e.get("item")).is_empty():
				bad.call("reward names unknown item %s" % e.get("item"))
			if not (_is_int(e.get("count", 1)) and e.get("count", 1) >= 1):
				bad.call("reward %s needs a count of at least 1" % e.get("item"))
		for f in r.get("reputation", {}):
			if DataStore.find(s.factions, f).is_empty():
				bad.call("reward names unknown faction %s" % f)
			elif not _is_int(r.reputation[f]):
				bad.call("reputation with %s must be a whole number" % f)
		if q.has("choice"):
			if str(q.choice) == "":
				bad.call("choice must be a name")
			else:
				choices[q.choice] = choices.get(q.choice, []) + [id]
	for c in choices:
		if choices[c].size() < 2:
			out.append("Quest %s: choice %s needs at least one other quest to choose between" % [choices[c][0], c])
	# a quest that requires itself, however far round, can never be offered
	for q in s.quests:
		if _loops(s, q.get("id"), []):
			out.append("Quest %s: its requirements loop back to it" % q.get("id"))


static func _loops(s: DataStore, id, path: Array) -> bool:
	if path.has(id):
		return true
	for r in s.quest(id).get("requires", []):
		if r != id and _loops(s, r, path + [id]):
			return true
	return false


static func _npcs(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	var icons := ["vendor", "blacksmith", "fishing", "cooking", "innkeeper", "trainer", "tanner"]
	for n in s.npcs:
		var id := str(n.get("id", ""))
		var bad := func(msg): out.append("NPC %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		if id != DataStore.slug(id) or id == "":
			bad.call("id must be lower_snake_case")
		if str(n.get("name", "")) == "":
			bad.call("needs a name")
		if not (_is_int(n.get("level")) and n.level >= 1):
			bad.call("needs a level (a whole number, 1 or more)")
		if not s.models.has(n.get("model")) and not PROCEDURAL_MODELS.has(n.get("model")):
			bad.call("model %s is not in assets/models" % n.get("model"))
		if n.has("shop") and s.shop(n.shop).is_empty():
			bad.call("keeps unknown shop %s" % n.shop)
		if n.has("dialogue") and s.dialogue(n.dialogue).is_empty():
			bad.call("names unknown dialogue %s" % n.dialogue)
		if n.has("mapIcon") and not icons.has(n.mapIcon):
			bad.call("map icon must be one of " + ", ".join(icons))
		if n.has("tint") and not (str(n.tint).length() == 7 and str(n.tint).begins_with("#") and str(n.tint).substr(1).is_valid_hex_number()):
			bad.call("tint must be a colour like #7a6a66")
	for sp in s.npc_spawns:
		if s.npc(sp.get("npc")).is_empty():
			out.append("NPC %s: placed in the world but not in npcs.json" % sp.get("npc"))


static func _shops(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	for sh in s.shops:
		var id := str(sh.get("id", ""))
		var bad := func(msg): out.append("Shop %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		var vt := s.vendor_type(sh.get("vendorType"))
		if vt.is_empty():
			bad.call("unknown vendor type %s" % sh.get("vendorType"))
		if sh.has("faction") and DataStore.find(s.factions, sh.faction).is_empty():
			bad.call("unknown faction %s" % sh.faction)
		for it in sh.get("stock", []):
			var d := s.item(it)
			if d.is_empty():
				bad.call("sells unknown item %s" % it)
				continue
			if d.get("quest", false):
				bad.call("quest item %s cannot be sold" % it)
			if d.has("reservedFor"):
				bad.call("%s is a boss's own drop and cannot be sold" % it)
			if not vt.is_empty() and not vt.get("sells", []).has(d.get("kind")):
				bad.call("a %s does not sell %s (%s)" % [vt.get("name", ""), DataStore.KIND_NAMES.get(d.get("kind"), d.get("kind")).to_lower(), it])


## a dialogue `when`: { quest, status }, { flag } or { examined }
static func _condition(s: DataStore, c, bad: Callable, where: String) -> void:
	if c == null:
		return
	if not c is Dictionary or c.is_empty() or c.keys().any(func(k): return not (k in ["quest", "status", "flag", "examined"])):
		bad.call("%s: a condition is a quest's status, a flag or an examined point" % where)
		return
	if c.has("quest"):
		if s.quest(c.quest).is_empty():
			bad.call("%s names unknown quest %s" % [where, c.quest])
		if not (c.get("status") in ["not_started", "available", "active", "ready", "done"]):
			bad.call("%s needs a quest status" % where)
	if c.has("flag") and str(c.flag) == "":
		bad.call("%s needs a flag name" % where)
	if c.has("examined") and not s.examine_points.has(c.examined):
		bad.call("%s names unknown examine point %s" % [where, c.examined])


static func _dialogues(s: DataStore, out: PackedStringArray) -> void:
	for d in s.dialogues:
		var bad := func(msg): out.append("Dialogue %s: %s" % [d.get("id"), msg])
		var nodes := {}
		for n in d.get("nodes", []):
			if nodes.has(n.get("id")):
				bad.call("node %s is there twice" % n.get("id"))
			nodes[n.get("id")] = true
		if d.get("greetings", []).is_empty():
			bad.call("needs at least one greeting")
		for i in d.get("greetings", []).size():
			var g: Dictionary = d.greetings[i]
			if str(g.get("text", "")) == "":
				bad.call("greeting %d needs text" % (i + 1))
			_condition(s, g.get("when"), bad, "greeting %d" % (i + 1))
		for t in d.get("topics", []):
			if str(t.get("prompt", "")) == "":
				bad.call("topic %s needs what the player asks" % t.get("id"))
			if not nodes.has(t.get("node")):
				bad.call("topic %s opens unknown node %s" % [t.get("id"), t.get("node")])
			_condition(s, t.get("when"), bad, "topic %s" % t.get("id"))
		for n in d.get("nodes", []):
			if str(n.get("text", "")) == "":
				bad.call("node %s needs text" % n.get("id"))
			if n.get("replies", []).is_empty():
				bad.call("node %s needs at least one reply" % n.get("id"))
			for r in n.get("replies", []):
				if str(r.get("text", "")) == "":
					bad.call("node %s: a reply needs text" % n.get("id"))
				if r.has("node") and not nodes.has(r.node):
					bad.call("node %s: a reply opens unknown node %s" % [n.get("id"), r.node])


static func _abilities(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	var res := s.resource_ids()
	for a in s.abilities:
		var id := str(a.get("id", ""))
		var bad := func(msg): out.append("Ability %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		if not id.is_valid_ascii_identifier():
			bad.call("id must be letters and digits, like hallowedBolt")
		if str(a.get("name", "")) == "" or str(a.get("desc", "")) == "":
			bad.call("needs a name and a description")
		if not DataStore.TARGETS.has(a.get("target")):
			bad.call("target must be an enemy, the ground or yourself")
		if a.get("target") == "enemy" and not _is_num(a.get("range")):
			bad.call("an enemy-targeted ability needs a range")
		if a.has("school") and not DataStore.SCHOOLS.has(a.school):
			bad.call("unknown school %s" % a.school)
		if a.has("skill") and s.skill(a.skill).is_empty():
			bad.call("names unknown skill %s" % a.skill)
		if not a.get("tuning") is Dictionary or not a.tuning.values().all(func(v): return _is_num(v)):
			bad.call("its numbers must all be numbers")
		for f in ["cost", "gain"]:
			for r in a.get(f, {}):
				if not res.has(r):
					bad.call("%s names unknown resource %s" % [f, r])
				elif not (_is_num(a[f][r]) and a[f][r] > 0):
					bad.call("%s of %s must be above 0" % [f, r])
		if a.has("kind"):
			var k: Dictionary = DataStore.SPELL_KINDS.get(a.kind, {})
			if k.is_empty():
				bad.call("unknown kind %s" % a.kind)
				continue
			var ok: bool = a.get("target") == "enemy" if k.enemy else (a.get("target") == "self" or (k.get("ground", false) and a.get("target") == "ground"))
			if not ok:
				bad.call("a %s spell must target %s" % [a.kind, "an enemy" if k.enemy else "yourself or the ground" if k.get("ground") else "yourself"])
			if a.has("ranged") and (a.ranged != true or not (a.kind in ["instant", "dot", "cast"])):
				bad.call("only instant, dot and cast spells can be shot from a bow")
			for t in DataStore.needed_tuning(a):
				if not (_is_num(a.get("tuning", {}).get(t)) and a.tuning[t] >= 0):
					bad.call("a %s spell needs %s of at least 0" % [a.kind, t])
			if a.kind == "control" and not a.has("applies"):
				bad.call("a control spell needs an applies aura (Other fields)")
			if a.kind == "purge" and not a.has("spendsAll"):
				bad.call("a purge needs spendsAll (Other fields)")
		for f in ["inShadow", "follow", "spreads"]:
			if a.has(f) and s.ability(a[f]).is_empty():
				bad.call("%s names unknown ability %s" % [f, a[f]])


static func _skills(s: DataStore, out: PackedStringArray) -> void:
	var seen := {}
	for sk in s.skills:
		var id := str(sk.get("id", ""))
		var bad := func(msg): out.append("Skill %s: %s" % [id, msg])
		if seen.has(id):
			bad.call("the id is used twice")
		seen[id] = true
		if str(sk.get("name", "")) == "" or str(sk.get("desc", "")) == "":
			bad.call("needs a name and a description")
		if s.npc(sk.get("trainer")).is_empty():
			bad.call("trainer %s is not an npc" % sk.get("trainer"))
		if not (_is_int(sk.get("cost")) and sk.cost >= 0):
			bad.call("cost must be whole coins")
		if sk.has("maxRank") and not (_is_int(sk.maxRank) and sk.maxRank >= 1):
			bad.call("top rank must be a whole number of at least 1")
		for ab in sk.get("teaches", []):
			if s.ability(ab).is_empty():
				bad.call("teaches unknown ability %s" % ab)
			elif s.ability(ab).get("skill") != id:
				bad.call("teaches %s, which does not name it as its skill" % ab)


static func _classes(s: DataStore, out: PackedStringArray) -> void:
	for c in s.archetypes:
		var bad := func(msg): out.append("Class %s: %s" % [c.get("name", c.id), msg])
		for id in c.get("abilities", []):
			if s.ability(id).is_empty():
				bad.call("its spellbook names unknown ability %s" % id)
			elif s.ability(id).has("skill"):
				bad.call("%s is a skill's tool, not a class spell" % id)
		for id in c.get("later", []):
			if not c.get("abilities", []).has(id):
				bad.call("%s is left for a later trainer but is not in its spellbook" % id)
			if c.get("bar", []).has(id) or c.get("trained", []).any(func(t): return t.get("ability") == id):
				bad.call("%s is left for a later trainer, so it cannot be on its bar or taught now" % id)
		for t in c.get("trained", []):
			var id = t.get("ability")
			if not c.get("abilities", []).has(id):
				bad.call("a trainer teaches %s, which is not in its spellbook" % id)
			if c.get("bar", []).has(id):
				bad.call("%s is on its starting bar, so a trainer cannot teach it" % id)
			if s.npc(t.get("trainer")).is_empty():
				bad.call("%s's trainer %s is not an npc" % [id, t.get("trainer")])
			if t.has("quest") and s.quest(t.quest).is_empty():
				bad.call("%s waits on unknown quest %s" % [id, t.quest])
			if not (_is_int(t.get("level")) and t.level >= 1 and _is_int(t.get("cost")) and t.cost >= 0):
				bad.call("%s needs a level and a cost in whole numbers" % id)

class_name SaveManager
extends RefCounted
## Versioned saves (src/systems/save.js). Loaded data is validated before
## anything is applied; a save that fails validation is kept under a backup
## key and never silently overwritten. Version 1 saves (a flat item list)
## are upgraded on load.

const SAVE_KEY := "shadowfall.save"
const BACKUP_KEY := "shadowfall.save.unreadable"
const SAVE_VERSION := 2
## The world's layout: 1 was the 72 x 225 m strip, 2 the whole world
## (data/world_map.json). Older saves start again at the Last Cart.
const MAP_VERSION := 2

var game
var autosave_enabled := true
var key := SAVE_KEY ## each character saves under its own key (see characters.gd)


static func _is_num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(v)


static func _is_int(v) -> bool:
	return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and is_finite(v) and v == floor(v))


static func _is_str_array(v) -> bool:
	return typeof(v) == TYPE_ARRAY and v.all(func(s): return typeof(s) == TYPE_STRING)


static func _in_bounds(p) -> bool:
	var b: Dictionary = Layout.bounds
	return typeof(p) == TYPE_DICTIONARY and _is_num(p.get("x")) and _is_num(p.get("z")) and p.x >= b.minX - 1 and p.x <= b.maxX + 1 and p.z >= b.minZ - 1 and p.z <= b.maxZ + 1


static func _is_stack(s) -> bool:
	if typeof(s) != TYPE_DICTIONARY or typeof(s.get("id")) != TYPE_STRING or not DB.items.has(s.id):
		return false
	if not _is_int(s.get("count")) or s.count < 1 or s.count > DB.items[s.id].get("stack", 1):
		return false
	if not Items.valid_rolls(s.id, s.get("rolls")):
		return false
	return not s.has("dur") or (_is_int(s.dur) and s.dur >= 0 and s.dur <= 100)


## Upgrade a build-1 save: its flat item list goes into the backpack, its
## weapon into the main hand. Anything else is returned unchanged.
static func migrate_save(data):
	if typeof(data) != TYPE_DICTIONARY or data.get("version") != 1.0 or not data.get("inventory"):
		return data
	var old: Dictionary = data.inventory
	var slots := []
	slots.resize(Items.BACKPACK_SLOTS)
	var i := [0]
	var put := func(id, count):
		if i[0] < slots.size() and DB.items.has(id):
			slots[i[0]] = {"id": id, "count": mini(int(count), int(DB.items[id].get("stack", 1)))}
			i[0] += 1
	if _is_int(old.get("draughts")) and old.draughts > 0:
		put.call("healing_draught", old.draughts)
	for id in (old.items if typeof(old.get("items")) == TYPE_ARRAY else []):
		if id != old.get("equipped") and DB.items.has(id) and DB.items[id].kind != "consumable":
			put.call(id, 1)
	var equipment := {}
	for s in DB.EQUIP_SLOTS:
		equipment[s.id] = null
	equipment.mainHand = {"id": old.equipped, "count": 1} if DB.items.has(old.get("equipped", "")) else null
	equipment.chest = {"id": "travelling_clothes", "count": 1}
	var out: Dictionary = data.duplicate()
	out.version = 2
	out.migratedFrom = 1
	out.inventory = {"coins": old.get("coins", 0), "sockets": [{"id": "backpack", "slots": slots}, null, null, null], "equipment": equipment}
	if data.get("world"):
		out.world = data.world.duplicate()
		out.world.ground = []
	return out


## Fit a save made before bags and stacks shrank (2026-10-27): an
## oversized stack splits into free slots of its bag; a bag that is now
## smaller packs its things to the front. Nothing is lost: what no longer
## fits stays in extra backpack slots, which go once they are emptied.
static func fit_bags(data):
	if typeof(data) != TYPE_DICTIONARY or typeof(data.get("inventory")) != TYPE_DICTIONARY:
		return data
	var sk = data.inventory.get("sockets")
	if typeof(sk) != TYPE_ARRAY or sk.is_empty() or typeof(sk[0]) != TYPE_DICTIONARY or typeof(sk[0].get("slots")) != TYPE_ARRAY:
		return data
	var overflow := []
	for i in sk.size():
		var s = sk[i]
		if typeof(s) != TYPE_DICTIONARY or typeof(s.get("slots")) != TYPE_ARRAY:
			continue
		var def = DB.items.get(s.get("id", ""), {})
		var size: int = Items.BACKPACK_SLOTS if i == 0 else int(def.get("bagSlots", s.slots.size()))
		var stacks := []
		for x in s.slots:
			if typeof(x) != TYPE_DICTIONARY or not DB.items.has(x.get("id", "")) or not _is_int(x.get("count")):
				if x != null:
					stacks.append(x)
				continue
			var cap := int(DB.items[x.id].get("stack", 1))
			var left := int(x.count)
			while left > cap:
				var part: Dictionary = x.duplicate()
				part.count = cap
				stacks.append(part)
				left -= cap
			var rest: Dictionary = x.duplicate()
			rest.count = left
			stacks.append(rest)
		if stacks.size() <= s.slots.size() and s.slots.size() == size and stacks.size() == s.slots.filter(func(x): return x != null).size():
			continue # unchanged
		var slots := []
		slots.resize(size)
		for k in stacks.size():
			if k < size:
				slots[k] = stacks[k]
			else:
				overflow.append(stacks[k])
		s.slots = slots
	var back: Array = sk[0].slots
	for x in overflow:
		var free := back.find(null)
		if free >= 0:
			back[free] = x
		else:
			back.append(x)
	return data


static func _validate_inventory(inv: Dictionary, check: Callable) -> void:
	check.call(_is_int(inv.get("coins")) and inv.coins >= 0, "coins")
	var sk = inv.get("sockets")
	# (saves from before the tool pack have no tool socket)
	check.call(typeof(sk) == TYPE_ARRAY and (sk.size() == Items.BAG_SOCKETS or sk.size() == Items.TOOL_SOCKET + 1), "bag sockets")
	if typeof(sk) == TYPE_ARRAY:
		for i in sk.size():
			var s = sk[i]
			if i == 0:
				check.call(typeof(s) == TYPE_DICTIONARY and s.get("id") == "backpack" and typeof(s.get("slots")) == TYPE_ARRAY and s.slots.size() >= Items.BACKPACK_SLOTS, "backpack")
			elif s != null:
				var def = DB.items.get(s.get("id", "")) if typeof(s) == TYPE_DICTIONARY else null
				check.call(def != null and def.kind == "bag" and bool(def.get("toolPack", false)) == (i == Items.TOOL_SOCKET) and typeof(s.get("slots")) == TYPE_ARRAY and s.slots.size() == def.bagSlots, "bag in socket %d" % i)
			if typeof(s) == TYPE_DICTIONARY and typeof(s.get("slots")) == TYPE_ARRAY:
				check.call(s.slots.all(func(x): return x == null or _is_stack(x)), "contents of bag %d" % i)
	var eq = inv.get("equipment")
	check.call(typeof(eq) == TYPE_DICTIONARY, "equipment")
	if typeof(eq) == TYPE_DICTIONARY:
		var ids := DB.EQUIP_SLOTS.map(func(s): return s.id)
		for slot in eq:
			check.call(ids.has(slot), "unknown equipment slot %s" % slot)
			var st = eq[slot]
			check.call(st == null or (_is_stack(st) and DB.slot_fits(slot, DB.items[st.id].get("slot"))), "equipment in %s" % slot)


static func validate_save(data) -> Array:
	var errors := []
	var check := func(cond, msg):
		if not cond:
			errors.append(msg)
	if typeof(data) != TYPE_DICTIONARY:
		return ["not an object"]
	check.call(data.get("version") == float(SAVE_VERSION) or data.get("version") == SAVE_VERSION, "unknown save version")
	var p = data.get("player")
	check.call(typeof(p) == TYPE_DICTIONARY, "missing player")
	if typeof(p) == TYPE_DICTIONARY:
		check.call(_in_bounds(p.get("position")), "player position")
		check.call(_is_num(p.get("facing")), "player facing")
		check.call(_is_num(p.get("health")) and p.health > 0, "player health")
		check.call(_is_num(p.get("maxHealth")) and p.maxHealth >= 1 and _is_num(p.get("health")) and p.health <= p.maxHealth, "player max health")
	var pr = data.get("progression")
	check.call(typeof(pr) == TYPE_DICTIONARY and _is_int(pr.get("level")) and pr.level >= 1 and pr.level < 100 and _is_num(pr.get("xp")) and pr.xp >= 0, "progression")
	var inv = data.get("inventory")
	check.call(typeof(inv) == TYPE_DICTIONARY, "missing inventory")
	if typeof(inv) == TYPE_DICTIONARY:
		_validate_inventory(inv, check)
	if data.has("bar"):
		var bar = data.bar
		check.call(typeof(bar) == TYPE_ARRAY and [6, 7, ActionBar.BAR_SLOTS.size()].has(bar.size()) and bar.all(func(a): return a == null or DB.abilities.has(a) or a == "dodge" or a == "draught" or (ActionBar.item_ref(a) != null and DB.items.has(ActionBar.item_ref(a)))), "spell bar")
	# the quest log (saves from before it have none, and start from the story flag)
	if data.has("quests"):
		var q = data.quests
		var known := func(l): return _is_str_array(l) and l.all(func(id): return DB.quests.has(id))
		check.call(typeof(q) == TYPE_DICTIONARY and known.call(q.get("accepted")) and known.call(q.get("done")) and known.call(q.get("tracked")), "quest log")
	if data.has("titles"):
		var t = data.titles
		check.call(typeof(t) == TYPE_DICTIONARY and (t.get("chosen") == null or typeof(t.get("chosen")) == TYPE_STRING) and _is_str_array(t.get("slain")) and _is_str_array(t.get("known")), "titles")
	if data.has("renown"):
		var r = data.renown
		check.call(typeof(r) == TYPE_DICTIONARY and _is_num(r.get("points")) and _is_num(r.get("carry")), "renown")
	if data.has("reputation"):
		check.call(typeof(data.reputation) == TYPE_DICTIONARY and data.reputation.values().all(func(n): return _is_num(n)), "reputation")
	if data.has("cooking"):
		var c = data.cooking
		check.call(typeof(c) == TYPE_DICTIONARY and _is_str_array(c.get("recipes")) and c.recipes.all(func(id): return DB.recipes.has(id)), "recipes")
	if data.has("law"):
		var l = data.law
		check.call(typeof(l) == TYPE_DICTIONARY and _is_num(l.get("infamy", 0)) and typeof(l.get("bounty", {})) == TYPE_DICTIONARY, "crime and infamy")
	if data.has("skills"):
		var s = data.skills
		check.call(typeof(s) == TYPE_DICTIONARY and s.keys().all(func(id): return DB.skills.has(id) and _is_int(s[id]) and s[id] >= 1), "skills")
	if data.has("spells"):
		check.call(_is_str_array(data.spells), "learned spells")
	var w = data.get("world")
	check.call(typeof(w) == TYPE_DICTIONARY, "missing world")
	if typeof(w) == TYPE_DICTIONARY:
		check.call(_is_str_array(w.get("defeated")) and _is_str_array(w.get("collected")) and _is_str_array(w.get("examined")), "world lists")
		check.call(typeof(w.get("drops")) == TYPE_DICTIONARY and w.drops.values().all(func(d): return _in_bounds(d)), "world drops")
		check.call(w.get("shrineActivated") == null or typeof(w.get("shrineActivated")) == TYPE_STRING, "shrine state")
		check.call(w.get("respawn") == null or _in_bounds(w.respawn), "respawn position")
		check.call(typeof(w.get("ground")) == TYPE_ARRAY and w.ground.all(func(g): return _is_stack(g) and _is_int(g.get("uid")) and g.uid >= 1 and _in_bounds(g)), "items on the ground")
		if w.has("camp"):
			check.call(w.camp == null or _in_bounds(w.camp), "camp position")
		if w.has("restPoint"):
			var rp = w.restPoint
			check.call(rp == "camp" or rp == "shrine" or (typeof(rp) == TYPE_STRING and rp.begins_with("inn:")), "rest point")
		if w.has("nemesis"):
			check.call(w.nemesis == null or typeof(w.nemesis) == TYPE_STRING, "nemesis")
		if w.has("respawnAt"):
			check.call(typeof(w.respawnAt) == TYPE_DICTIONARY and w.respawnAt.values().all(func(t): return _is_num(t)), "respawn timers")
		if w.has("corpses"):
			check.call(typeof(w.corpses) == TYPE_DICTIONARY and w.corpses.values().all(func(c): return _in_bounds(c) and _is_int(c.get("coins")) and c.coins >= 0), "bodies to loot")
	return errors


func _init(g) -> void:
	game = g


static func _round(n: float) -> float:
	return roundf(n * 1000) / 1000


func serialize() -> Dictionary:
	var player = game.player
	return {
		"version": SAVE_VERSION,
		"map": MAP_VERSION,
		"savedAt": Time.get_datetime_string_from_system(true) + "Z",
		"player": {
			"position": {"x": _round(player.position.x), "z": _round(player.position.z)},
			"facing": _round(player.facing),
			"health": player.health,
			"maxHealth": player.max_health,
		},
		"progression": game.progression.serialize(),
		"inventory": game.inventory.serialize(),
		"world": game.world_state.serialize(),
		"bar": game.action_bar.serialize(),
		"quests": game.quests.serialize(),
		"skills": game.skills.serialize(),
		"skillLadder": game.skills.serialize_ladder(),
		"spells": game.skills.serialize_spells(),
		"reputation": game.reputation.serialize(),
		"renown": game.reputation.serialize_renown(),
		"titles": game.titles.serialize(),
		"cooking": game.cooking.serialize(),
		"builds": game.builds.serialize(),
		"law": game.law.serialize(),
		"boons": game.boons.serialize(),
	}


## Returns { ok, reason }. Only reports success once the data reads back.
func save(manual := false) -> Dictionary:
	if game.player.dead:
		return {"ok": false, "reason": "You cannot save while defeated."}
	var text := JSON.stringify(serialize())
	if not Store.set_item(key, text) or Store.get_item(key) != text:
		push_warning("Save failed")
		return {"ok": false, "reason": "The game could not be saved. Storage may be full or disabled."}
	if manual:
		autosave_enabled = true # an explicit save re-enables autosave after a failed load
	return {"ok": true}


func has_save() -> bool:
	return Store.get_item(key) != null


## Returns { status: 'none' | 'ok' | 'invalid', data?, errors?, raw? }
func read(k = null) -> Dictionary:
	if k == null:
		k = key
	var text = Store.get_item(k)
	if text == null:
		return {"status": "none"}
	var data = JSON.parse_string(text)
	if data == null:
		return {"status": "invalid", "errors": ["not valid JSON"], "raw": text}
	data = fit_bags(migrate_save(data))
	var errors := validate_save(data)
	if not errors.is_empty():
		return {"status": "invalid", "errors": errors, "raw": text}
	return {"status": "ok", "data": data}


## Keep an unreadable save safe, and stop autosave from replacing it.
func quarantine(raw, k = null) -> void:
	if k == null:
		k = key
	if k == key:
		autosave_enabled = false
	if raw != null:
		Store.set_item(BACKUP_KEY if k == SAVE_KEY else "%s.unreadable" % k, raw)


func apply(data: Dictionary) -> void:
	var player = game.player
	var progression = game.progression
	var inventory = game.inventory
	var ws = game.world_state
	var old_map := int(data.get("map", 1)) < MAP_VERSION
	ws.apply(data.world)
	if old_map:
		ws.forget_places()
	game.quests.apply(data.get("quests"), ws.flags)
	game.skills.apply(data.get("skills"))
	game.skills.apply_ladder(data.get("skillLadder"))
	game.skills.apply_spells(data.get("spells"))
	game.cooking.apply(data.get("cooking"))
	game.reputation.apply(data.get("reputation"), data.get("renown"))
	if data.get("bar"):
		game.action_bar.apply(data.bar)
	progression.apply(data.progression)
	inventory.apply(data.inventory)
	game.builds.apply(data.get("builds"))
	game.law.apply(data.get("law"))
	game.boons.apply(data.get("boons"))
	# renown and titles; saves from before renown start with what their
	# finished quests, levels and reputation would have earned
	if not data.get("renown"):
		var rep := 0.0
		for n in data.get("reputation", {}).values():
			rep += maxf(0, n)
		game.reputation.renown = game.quests.done.size() * DB.renown.perQuest + (progression.level - 1) * DB.renown.perLevel + floorf(rep / DB.renown.perReputation)
	game.titles.apply(data.get("titles"))
	game.titles._check_new()
	# rewards added to a quest after it was handed in (the tool pack, for the
	# story quest) are given now, once
	for id in game.quests.done:
		for g in DB.quests[id].get("reward", {}).get("items", []):
			if Items.get_def(g.item).get("toolPack") and inventory.tool_pack == null:
				inventory.add_item(g.item, 1)
	game.recompute_max_health()
	player.health = minf(data.player.health, player.max_health)
	game.resources.reset()
	if old_map:
		var start: Dictionary = DB.world.playerStart
		player.place_at(start.position[0], start.position[1], deg_to_rad(start.get("facing", 180)))
	else:
		player.place_at(data.player.position.x, data.player.position.z, data.player.facing)


func autosave() -> void:
	if not autosave_enabled or not game.started:
		return
	save()

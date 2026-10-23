class_name Inventory
extends RefCounted
## Bags, equipment and currency, laid out as classic WoW does it
## (src/systems/inventory.js). A location is a short string the UI, gamepad
## and tests share:
##   'b:<socket>:<slot>'  a slot inside a bag
##   'e:<slotId>'         a character equipment slot
##   's:<socket>'         a bag socket (1-3, or 4 for the tool pack)
##   'e:ammo'             the ammo slot: which arrows Auto Shot uses

const AMMO_LOC := "e:ammo"

var game
var coins := 0
var sockets: Array = []
var equipment := {}
var ammo_choice = null
var prev_off_hand = null


func _init(g) -> void:
	game = g
	reset()


static func parse_loc(loc: String) -> Dictionary:
	var p := loc.split(":")
	if p[0] == "b":
		return {"type": "bag", "socket": int(p[1]), "slot": int(p[2])}
	if p[0] == "e":
		return {"type": "equip", "slot": p[1]}
	if p[0] == "s":
		return {"type": "socket", "socket": int(p[1])}
	return {}


static func clone(s):
	if s == null:
		return null
	var c := {"id": s.id, "count": int(s.count)}
	if s.get("rolls") != null:
		c.rolls = s.rolls
	if s.has("dur") and s.dur < 100:
		c.dur = int(s.dur)
	return c


static func _empty_slots(n: int) -> Array:
	var a := []
	a.resize(n)
	return a


func reset() -> void:
	coins = DB.CONFIG.player.startCoins
	sockets = [{"id": "backpack", "slots": _empty_slots(Items.BACKPACK_SLOTS)}, null, null, null, null]
	equipment = {}
	for s in DB.EQUIP_SLOTS:
		equipment[s.id] = null
	sockets[0].slots[0] = {"id": "healing_draught", "count": DB.CONFIG.player.startDraughts}
	ammo_choice = null
	var arch: Dictionary = game.stats.archetype if game.stats else DB.archetypes[DB.CONFIG.player.archetype]
	# food for everyone, and a drink for a class with mana
	var bag: Array = sockets[0].slots
	bag[1] = {"id": ActionBar.STARTER_FOOD, "count": DB.CONFIG.player.startFood}
	if arch.get("resources", {}).has("mana"):
		bag[2] = {"id": ActionBar.STARTER_DRINK, "count": DB.CONFIG.player.startDrinks}
	var gear: Dictionary = arch.get("startingGear", {})
	for slot in gear:
		if slot == "ammo":
			var at: int = bag.find(null)
			bag[at] = {"id": gear.ammo[0], "count": int(gear.ammo[1])}
			ammo_choice = gear.ammo[0]
		else:
			equipment[slot] = {"id": gear[slot], "count": 1}


# ------------------------------------------------------------ queries
func get_at(loc: String):
	var p := parse_loc(loc)
	if p.is_empty():
		return null
	if loc == AMMO_LOC:
		return {"id": ammo_choice, "count": count(ammo_choice)} if ammo_choice else null
	if p.type == "bag":
		var s = sockets[p.socket] if p.socket < sockets.size() else null
		return s.slots[p.slot] if s and p.slot < s.slots.size() else null
	if p.type == "equip":
		return equipment.get(p.slot)
	if p.type == "socket":
		var s = sockets[p.socket] if p.socket < sockets.size() else null
		return {"id": s.id, "count": 1} if s and s.id != "backpack" else null
	return null


func bag_locations() -> Array:
	var out := []
	for i in sockets.size():
		var s = sockets[i]
		if s:
			for j in s.slots.size():
				out.append("b:%d:%d" % [i, j])
	return out


func count(id) -> int:
	if id == null:
		return 0
	var n := 0
	for s in sockets:
		if s:
			for st in s.slots:
				if st and st.id == id:
					n += st.count
	return n


func has(id: String) -> bool:
	if count(id) > 0:
		return true
	for k in equipment:
		if equipment[k] and equipment[k].id == id:
			return true
	for s in sockets:
		if s and s.id == id:
			return true
	return false


## Every item id carried, equipped or socketed.
var items: Array:
	get:
		var ids := {}
		for loc in bag_locations():
			var s = get_at(loc)
			if s:
				ids[s.id] = true
		for k in equipment:
			if equipment[k]:
				ids[equipment[k].id] = true
		for s in sockets:
			if s and s.id != "backpack":
				ids[s.id] = true
		return ids.keys()


## the main-hand weapon's view; a broken weapon swings like bare hands
var weapon: Dictionary:
	get:
		var s = equipment.mainHand
		var v := Items.view(s) if s else {}
		if v.is_empty() or v.get("broken", false):
			return {"name": "%s (broken)" % v.name if not v.is_empty() else "Bare hands", "damage": DB.CONFIG.stats.fistDamage}
		return v

## a working weapon in the off hand (dual wielding), else null
var off_weapon:
	get:
		var s = equipment.offHand
		if s == null or Items.get_def(s.id).get("kind") != "weapon":
			return null
		var v := Items.view(s)
		return null if v.get("broken", false) else v

## the arrows Auto Shot will use
var ammo:
	get:
		if ammo_choice and count(ammo_choice) > 0:
			return ammo_choice
		return best_ammo()


func best_ammo():
	var best = null
	for loc in bag_locations():
		var s = get_at(loc)
		var d := Items.get_def(s.id) if s else {}
		if d.get("kind") == "ammo" and (best == null or d.ammoDps > Items.get_def(best).ammoDps):
			best = s.id
	return best


func arrows_in(socket: int) -> int:
	var s = sockets[socket]
	var n := 0
	if s:
		for st in s.slots:
			if st and Items.get_def(st.id).get("kind") == "ammo":
				n += st.count
	return n


func set_ammo(id: String) -> Dictionary:
	if Items.get_def(id).get("kind") != "ammo":
		return _refuse("Only arrows go in the ammo slot.")
	if ammo_choice != id:
		ammo_choice = id
		game.events.emit("log", {"text": "Auto Shot now uses %ss." % Items.get_def(id).name.to_lower(), "kind": "muted", "throttle": "ammo-set"})
	_changed()
	return {"ok": true}


func _refill_ammo() -> void:
	var had = ammo_choice
	if had and count(had) > 0:
		return
	var next = best_ammo()
	if next == had:
		return
	ammo_choice = next
	if had and next:
		game.events.emit("log", {"text": "Out of %ss. Auto Shot now uses %ss." % [Items.get_def(had).name.to_lower(), Items.get_def(next).name.to_lower()], "kind": "muted"})
	elif had:
		game.events.emit("log", {"text": "You are out of arrows.", "kind": "muted", "throttle": "no-ammo"})


## a quiver in a bag slot quickens Auto Shot (percent; the best one counts)
var quiver_haste: float:
	get:
		var best := 0.0
		for s in sockets:
			if s:
				best = maxf(best, Items.get_def(s.id).get("rangedHaste", 0))
		return best

## a working bow in the ranged slot, else null
var ranged_weapon:
	get:
		var s = equipment.ranged
		if s == null or Items.get_def(s.id).get("kind") != "weapon":
			return null
		var v := Items.view(s)
		return null if v.get("broken", false) else v

var draughts: int:
	get:
		return count("healing_draught")
	set(n):
		remove_all("healing_draught")
		if n > 0:
			_insert("healing_draught", n)


func free_slots() -> int:
	var n := 0
	for loc in bag_locations():
		if get_at(loc) == null:
			n += 1
	return n


# ------------------------------------------------------------ mutation
func _put(loc: String, stack) -> void:
	var p := parse_loc(loc)
	if p.type == "bag":
		sockets[p.socket].slots[p.slot] = stack
	elif p.type == "equip":
		equipment[p.slot] = stack
	elif p.type == "socket":
		sockets[p.socket] = {"id": stack.id, "slots": _empty_slots(int(Items.get_def(stack.id).bagSlots))} if stack else null


## What a bag slot may hold, as a list of item kinds (null: anything).
func _bag_holds(socket: int):
	var s = sockets[socket] if socket < sockets.size() else null
	var h = Items.get_def(s.id).get("holds") if s else null
	if h == null:
		return null
	return h if h is Array else [h]


static func _socket_of(loc: String) -> int:
	return int(loc.split(":")[1])


## The bag slots an item can go in, best first: arrows into a quiver and
## tools into the tool pack before the ordinary bags.
func _slots_for(id: String) -> Array:
	var kind: String = Items.get_def(id).kind
	var special := []
	var plain := []
	for l in bag_locations():
		var h = _bag_holds(_socket_of(l))
		if h == null:
			plain.append(l)
		elif h.has(kind):
			special.append(l)
	return special + plain


var tool_pack:
	get:
		return sockets[Items.TOOL_SOCKET]


func _fit_tool_pack(id: String) -> void:
	_put("s:%d" % Items.TOOL_SOCKET, {"id": id, "count": 1})
	_stow_tools()
	game.events.emit("log", {"text": "Your tools go into the %s, out of your bags." % Items.get_def(id).name.to_lower(), "kind": "loot"})


## Move tools lying in the ordinary bags into free tool pack slots.
func _stow_tools() -> void:
	var pack = tool_pack
	if not pack:
		return
	var holds = _bag_holds(Items.TOOL_SOCKET)
	for loc in bag_locations():
		if loc.begins_with("b:%d:" % Items.TOOL_SOCKET):
			continue
		var s = get_at(loc)
		if s == null or not holds.has(Items.get_def(s.id).kind):
			continue
		var free: int = pack.slots.find(null)
		if free < 0:
			return
		pack.slots[free] = s
		_put(loc, null)


## Put `count` of `id` into bags; returns how many did not fit.
func _insert(id: String, n: int, rolls = null) -> int:
	var def := Items.get_def(id)
	var stack_max := int(def.stack)
	var left := n
	var locs := _slots_for(id)
	for loc in locs:
		var s = get_at(loc)
		if left > 0 and rolls == null and s and s.id == id and s.get("rolls") == null and s.count < stack_max:
			var add := mini(stack_max - s.count, left)
			s.count += add
			left -= add
	for loc in locs:
		if left > 0 and get_at(loc) == null:
			var add := mini(stack_max, left)
			_put(loc, {"id": id, "count": add, "rolls": rolls} if rolls else {"id": id, "count": add})
			left -= add
	return left


## Returns true if everything fitted. A full bag leaves loot where it is.
func add_item(id: String, n := 1, quiet := false, rolls = null) -> bool:
	var def := Items.get_def(id)
	if def.is_empty():
		return false
	if def.get("toolPack", false):
		if tool_pack:
			return false
		_fit_tool_pack(id)
		if not quiet:
			game.events.emit("log", {"text": "Taken: %s." % def.name, "kind": "loot"})
		_changed()
		return true
	if room_for(id) < n:
		game.events.emit("log", {"text": "Your bags are full.", "kind": "muted", "throttle": "bags-full"})
		return false
	_insert(id, n, rolls)
	if not quiet:
		var name: String = Items.view({"id": id, "rolls": rolls}).name
		game.events.emit("log", {"text": "Taken: %s%s." % [name, " ×%d" % n if n > 1 else ""], "kind": "loot"})
		var k: String = def.kind
		if k == "weapon" or k == "armor" or k == "shield":
			game.events.emit("log", {"text": "Drag it onto your character (C) to equip it.", "kind": "muted", "throttle": "equip-hint"})
		if k == "bag":
			game.events.emit("log", {"text": "Drag it into an empty bag slot to carry more.", "kind": "muted", "throttle": "bag-hint"})
	_changed()
	return true


func room_for(id: String) -> int:
	var def := Items.get_def(id)
	if def.get("toolPack", false):
		return 0 if tool_pack else 1
	var room := 0
	for loc in _slots_for(id):
		var s = get_at(loc)
		if s == null:
			room += int(def.stack)
		elif s.id == id:
			room += int(def.stack) - s.count
	return room


func remove_all(id: String) -> void:
	for loc in bag_locations():
		var s = get_at(loc)
		if s and s.id == id:
			_put(loc, null)


## Take `n` of an item from the bags, smallest stacks first.
func remove_count(id: String, n: int) -> int:
	var left := n
	var locs := []
	for l in bag_locations():
		var s = get_at(l)
		if s and s.id == id:
			locs.append(l)
	locs.sort_custom(func(a, b): return get_at(a).count < get_at(b).count)
	for loc in locs:
		if left <= 0:
			break
		var s = get_at(loc)
		var k := mini(left, s.count)
		if k >= s.count:
			_put(loc, null)
		else:
			s.count -= k
		left -= k
	_changed()
	return n - left


## Remove up to `n` from one location; returns the removed stack.
func take(loc: String, n := 1 << 30):
	if loc == AMMO_LOC:
		return null
	var s = get_at(loc)
	if s == null:
		return null
	var p := parse_loc(loc)
	if p.type == "socket" and not _bag_empty(p.socket):
		return null
	var k := mini(n, s.count)
	if k >= s.count:
		_put(loc, null)
	else:
		s.count -= k
	if p.type == "equip":
		_equipment_changed()
	_changed()
	return {"id": s.id, "count": k, "rolls": s.rolls} if s.get("rolls") != null else {"id": s.id, "count": k}


func _bag_empty(socket: int) -> bool:
	var s = sockets[socket]
	if not s:
		return true
	for x in s.slots:
		if x:
			return false
	return true


## Can this stack sit at that location?
func accepts(loc: String, stack) -> bool:
	if stack == null:
		return true
	var p := parse_loc(loc)
	var def := Items.get_def(stack.id)
	if p.is_empty() or def.is_empty():
		return false
	if loc == AMMO_LOC:
		return def.kind == "ammo"
	if p.type == "equip":
		return DB.slot_fits(p.slot, def.get("slot")) and can_wear(def, p.slot)
	if p.type == "socket":
		if p.socket == Items.TOOL_SOCKET:
			return def.get("toolPack", false)
		return p.socket > 0 and p.socket < Items.BAG_SOCKETS and def.kind == "bag" and not def.get("toolPack", false)
	if p.type == "bag":
		var h = _bag_holds(p.socket)
		var bag = sockets[p.socket] if p.socket < sockets.size() else null
		return not def.get("toolPack", false) and bag != null and p.slot < bag.slots.size() and (h == null or h.has(def.kind))
	return false


## Armour types, shields and dual wielding are limited by archetype, as in WoW.
func can_wear(def: Dictionary, slot = null) -> bool:
	var a: Dictionary = game.stats.archetype
	if def.has("armourType") and not a.armourTypes.has(def.armourType):
		return false
	if def.kind == "shield" and not a.get("shields", false):
		return false
	if slot == "offHand" and def.kind == "weapon" and not a.get("dualWield", false):
		return false
	if def.has("weaponType") and a.get("bannedWeaponTypes", []).has(def.weaponType):
		return false
	return true


## Move or swap the stacks at two locations. Returns { ok, reason }.
func move(from: String, to: String) -> Dictionary:
	if from == to:
		return {"ok": false, "reason": ""}
	if to == AMMO_LOC:
		return set_ammo(get_at(from).id) if get_at(from) else {"ok": false, "reason": ""}
	if from == AMMO_LOC:
		return _refuse("Drag other arrows onto the ammo slot to change them.")
	var a = get_at(from)
	var b = get_at(to)
	if a == null:
		return {"ok": false, "reason": ""}
	var pf := parse_loc(from)
	var pt := parse_loc(to)
	if pf.type == "socket" and not _bag_empty(pf.socket):
		return _refuse("Empty that bag before moving it.")
	if pt.type == "socket" and b and not _bag_empty(pt.socket):
		return _refuse("Empty that bag before replacing it.")
	if pf.type == "socket" and pt.type == "bag" and pt.socket == pf.socket:
		return _refuse("A bag cannot go inside itself.")
	if pt.type == "socket" and pf.type == "bag" and pf.socket == pt.socket:
		return _refuse("A bag cannot go inside itself.")
	if not accepts(to, a):
		return _refuse(_why(to, a))
	var stack_max := int(Items.get_def(a.id).stack)
	if b and b.id == a.id and stack_max > 1 and pt.type == "bag" and pf.type == "bag":
		var k := mini(stack_max - b.count, a.count)
		b.count += k
		a.count -= k
		if a.count <= 0:
			_put(from, null)
		_changed()
		return {"ok": true}
	if b and not accepts(from, b):
		return _refuse(_why(from, b))
	if pt.type == "socket" or pf.type == "socket":
		_put(from, null)
		_put(to, clone(a))
		if b:
			_put(from, clone(b))
	else:
		_put(to, a)
		_put(from, b)
	if pf.type == "equip" or pt.type == "equip":
		_equipment_changed()
	_changed()
	return {"ok": true}


func _why(loc: String, stack: Dictionary) -> String:
	var p := parse_loc(loc)
	var def := Items.get_def(stack.id)
	var arch: Dictionary = game.stats.archetype
	if p.type == "equip" and DB.slot_fits(p.slot, def.get("slot")) and not can_wear(def, p.slot):
		if def.has("weaponType") and arch.get("bannedWeaponTypes", []).has(def.weaponType):
			return "A %s cannot use %ss." % [arch.name, def.weaponType]
		if def.kind == "weapon":
			return "A %s cannot dual wield." % arch.name
		var what: String = "shields" if def.kind == "shield" else "%s armour" % DB.armour_types[def.armourType].name.to_lower()
		return "A %s cannot use %s." % [arch.name, what]
	if p.type == "equip":
		return "The %s does not go there." % def.name
	if def.get("toolPack", false):
		return "The %s stays in its own slot." % def.name.to_lower()
	if p.type == "socket":
		return "The backpack cannot be removed." if p.socket == 0 else "Only a tool pack goes in the tool slot." if p.socket == Items.TOOL_SOCKET else "Only bags go in bag slots."
	if p.type == "bag" and _bag_holds(p.socket) != null:
		return "Only %s go in the %s." % ["arrows" if _bag_holds(p.socket).has("ammo") else "tools", Items.get_def(sockets[p.socket].id).name.to_lower()]
	return "That will not fit there."


func _refuse(reason: String) -> Dictionary:
	if reason:
		game.events.emit("log", {"text": reason, "kind": "muted", "throttle": "inv-refuse"})
		# and in red mid-screen, as WoW says "You can't equip that"
		if game.hud:
			game.hud.error(reason.trim_suffix("."))
	return {"ok": false, "reason": reason}


func first_free():
	for l in bag_locations():
		if get_at(l) == null:
			return l
	return null


## Right-click / gamepad X: the obvious action for whatever is there.
func use(loc: String) -> bool:
	var s = get_at(loc)
	if s == null:
		return false
	var def := Items.get_def(s.id)
	var p := parse_loc(loc)
	if loc == AMMO_LOC:
		return false
	if def.kind == "ammo":
		return set_ammo(s.id).ok
	if p.type == "socket" and def.get("toolPack", false):
		_refuse("The %s stays in its own slot." % def.name.to_lower())
		return false
	if p.type == "equip" or p.type == "socket":
		var free = null
		for l in _slots_for(s.id):
			if get_at(l) == null:
				free = l
				break
		if free == null:
			free = first_free()
		if free == null:
			_refuse("Your bags are full.")
			return false
		return move(loc, free).ok
	if def.get("use", {}).has("food") or def.get("use", {}).has("drink"):
		return game.cooking.eat(loc)
	if def.kind == "consumable":
		return use_draught(loc)
	if def.kind == "document":
		game.hud.open_document(s.id)
		return true
	if def.has("slot"):
		return move(loc, "e:" + slot_for(def)).ok
	if def.kind == "bag":
		for i in [1, 2, 3]:
			if not sockets[i]:
				return move(loc, "s:%d" % i).ok
		_refuse("All your bag slots are in use.")
		return false
	return false


func _find(id) -> Variant:
	for l in bag_locations():
		var s = get_at(l)
		if s and s.id == id:
			return l
	return null


## An item used from the spell bar. An off-hand item (a torch) is swapped
## with whatever was in the off hand, and back again on the next press.
func use_from_bar(id: String) -> bool:
	var def := Items.get_def(id)
	if def.is_empty():
		return false
	if def.get("slot") == "offHand" and equipment.offHand and equipment.offHand.id == id:
		var back = _find(prev_off_hand) if prev_off_hand else null
		if back:
			var ok: bool = move(back, "e:offHand").ok
			if ok:
				_stow_tools()
				_changed()
			return ok
		return use("e:offHand")
	var loc = _find(id)
	if loc == null:
		game.hud.error("You have no %s." % def.name.to_lower())
		return false
	if def.get("slot") == "offHand":
		prev_off_hand = equipment.offHand.id if equipment.offHand else null
	return use(loc)


## Equip by item id (kept for scripts and tests).
func equip(id: String) -> bool:
	var loc = _find(id)
	if loc == null:
		return false
	return move(loc, "e:" + slot_for(Items.get_def(id))).ok


## Which character slot an item goes in: the empty one of a pair if there is one.
func slot_for(def: Dictionary) -> String:
	var fits := []
	for s in DB.EQUIP_SLOTS:
		if DB.slot_fits(s.id, def.get("slot")):
			fits.append(s.id)
	for id in fits:
		if not equipment[id]:
			return id
	return fits[0] if fits.size() else def.get("slot", "")


# ------------------------------------------------------------ durability
## Death wears every worn weapon and piece of armour by `percent`.
func wear(percent: int) -> Array:
	var broke := []
	for k in equipment:
		var s = equipment[k]
		var d := Items.durability(s)
		if d < 0 or d == 0:
			continue
		s.dur = maxi(0, d - percent)
		if s.dur == 0:
			broke.append(Items.view(s).name)
	for name in broke:
		game.events.emit("log", {"text": "Your %s is broken. Have it repaired by a smith." % name, "kind": "muted"})
	_equipment_changed()
	_changed()
	return broke


func repair_cost(stack) -> int:
	var d := Items.durability(stack)
	if d < 0 or d >= 100:
		return 0
	var price: float = Items.view(stack).get("price", 0)
	return maxi(1, ceili(price * DB.CONFIG.durability.repairFraction * (100 - d) / 100.0))


func _worn() -> Array:
	var all := []
	for k in equipment:
		all.append(equipment[k])
	for s in sockets:
		if s:
			all.append_array(s.slots)
	return all.filter(func(s): return s != null and repair_cost(s) > 0)


var repair_all_cost: int:
	get:
		var t := 0
		for s in _worn():
			t += repair_cost(s)
		return t


func repair_all() -> bool:
	var cost := repair_all_cost
	if not cost:
		return false
	if coins < cost:
		game.events.emit("log", {"text": "You need %s to repair everything." % U.money(cost), "kind": "muted", "throttle": "repair"})
		return false
	coins -= cost
	for s in _worn():
		s.erase("dur")
	game.events.emit("coins", {"amount": -cost})
	game.events.emit("log", {"text": "Your gear is repaired for %s." % U.money(cost), "kind": "loot"})
	_equipment_changed()
	_changed()
	return true


func _equipment_changed() -> void:
	game.player.show_equipment(equipment)
	game.recompute_max_health()
	game.events.emit("equipmentChanged")
	var st = game.stats
	var r: Array = st.swing_range
	game.events.emit("log", {"text": "Auto attack is now %d–%d every %ss (%s)." % [r[0], r[1], U.fixed(st.attack_cooldown, 1), weapon.name], "kind": "level", "throttle": "equip-dmg-%d-%d" % [r[0], r[1]]})


func _changed() -> void:
	_refill_ammo()
	game.events.emit("inventoryChanged")


# ------------------------------------------------------------ currency
func add_coins(n: int, source := "") -> void:
	coins += n
	game.events.emit("coins", {"amount": n})
	game.events.emit("log", {"text": "%s%s." % [U.money(n), " " + source if source else ""], "kind": "loot"})
	_changed()


func lose_coins(n: int) -> int:
	var lost := mini(coins, n)
	coins -= lost
	_changed()
	return lost


# ------------------------------------------------------------ draughts
func use_draught(loc = null) -> bool:
	var player = game.player
	var events = game.events
	if player.dead:
		return false
	var where = loc if loc else _find("healing_draught")
	if where == null:
		events.emit("log", {"text": "You have no healing draughts left.", "kind": "muted", "throttle": "no-draught"})
		return false
	if player.health >= player.max_health:
		events.emit("log", {"text": "You are not wounded.", "kind": "muted", "throttle": "not-wounded"})
		return false
	if player.cooldowns.draught > 0:
		return false
	take(where, 1)
	player.cooldowns.draught = DB.CONFIG.draught.cooldown
	var healed: float = player.heal(Items.get_def("healing_draught").use.heal)
	events.emit("damageNumber", {"target": player, "amount": U.jround(healed), "kind": "heal"})
	player.rig.play("drink", 0.6, 0.5)
	events.emit("draught")
	events.emit("log", {"text": "You drink a healing draught (+%s). %d left." % [U.n(healed), draughts], "kind": "heal"})
	return true


# ------------------------------------------------------------ saving
func serialize() -> Dictionary:
	var sk := []
	for s in sockets:
		sk.append({"id": s.id, "slots": s.slots.map(func(x): return clone(x))} if s else null)
	var eq := {}
	for k in equipment:
		eq[k] = clone(equipment[k])
	return {"coins": coins, "sockets": sk, "equipment": eq, "granted": ["kite_shield"], "ammo": ammo_choice}


func apply(data: Dictionary) -> void:
	coins = int(data.coins)
	sockets = []
	for s in data.sockets:
		sockets.append({"id": s.id, "slots": s.slots.map(func(x): return clone(x))} if s else null)
	while sockets.size() <= Items.TOOL_SOCKET:
		sockets.append(null)
	equipment = {}
	for s in DB.EQUIP_SLOTS:
		equipment[s.id] = clone(data.equipment.get(s.id))
	ammo_choice = data.get("ammo") if DB.items.has(data.get("ammo", "")) else null
	if not data.get("granted", []).has("kite_shield"):
		if not equipment.offHand:
			equipment.offHand = {"id": "kite_shield", "count": 1}
		else:
			_insert("kite_shield", 1)
	game.player.show_equipment(equipment)
	_changed()

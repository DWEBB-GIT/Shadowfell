class_name Forge
extends RefCounted
## Forge, enchanter and jeweller services (data/forge.json,
## data/enchanting.json, data/gems.json), offered by any npc with
## `forge: true` (a smith), `enchanter: true` or `jeweller: true`, so every
## town's smith (or enchanter) does the same work. The rule that holds it together: an upgrade
## makes a loved item last a few more levels, never forever, and what you
## put into it comes back when you scrap it.
##
## - Enchant (an enchanter): +1 item level a rank, up to a cap by rarity;
##   each rank costs more dust (of the item's level band) and coins. In code
##   and saves a rank is still called `temper`.
## - Scrap (an enchanter): break magic gear into dust, `refund` of every
##   enchanting material put in, and its gems; preview first. No metal.
## - Reforge: swap one stat for another, from options shown up front.
## - Sockets: a forge punches one (skyiron); a jeweller makes gems from
##   shards, sets them, and takes them out free.

var game


func _init(g) -> void:
	game = g


static func rules() -> Dictionary:
	return DB.forge


# ------------------------------------------------------------ where gear is
## Bag and worn locations holding gear (weapons, armour, shields, jewellery).
func gear_locations() -> Array:
	var inv = game.inventory
	var out := []
	for loc in inv.equipment.keys().map(func(k): return "e:" + k) + inv.bag_locations():
		var st = inv.get_at(loc)
		if st != null and loc != Inventory.AMMO_LOC and Items.ROLLED_KINDS.has(Items.get_def(st.id).get("kind")) and not Items.get_def(st.id).get("quest", false):
			out.append(loc)
	return out


func _changed(loc: String) -> void:
	var inv = game.inventory
	if loc.begins_with("e:"):
		inv._equipment_changed()
	inv._changed()


func _rolls_of(stack: Dictionary) -> Dictionary:
	var r = stack.get("rolls")
	r = r.duplicate(true) if typeof(r) == TYPE_DICTIONARY else {}
	stack.rolls = r
	return r


static func _band(list: Array, level: float) -> String:
	for b in list:
		if level <= b.upToLevel:
			return b.item
	return list[list.size() - 1].item if not list.is_empty() else ""


# ------------------------------------------------------------ enchanting
## Enchanting rules (data/enchanting.json).
static func enchant_rules() -> Dictionary:
	return DB.enchanting


func temper_cap(stack: Dictionary) -> int:
	return int(enchant_rules().get("enchant", {}).get("caps", {}).get(Items.view(stack).get("rarity", "common"), 0))


## What one rank costs at a level: { items: [{ item, count }], coins }
static func rank_cost(base_level: float, rank: int, cap: int, rarity: String) -> Dictionary:
	var t: Dictionary = enchant_rules().get("enchant", {})
	var ranks: Array = t.get("ranks", [])
	if rank < 1 or rank > ranks.size():
		return {}
	var rk: Dictionary = ranks[rank - 1]
	var level := base_level + rank - 1 # each rank before this one counts as a level
	var items := []
	var bands: Dictionary = t.get("bands", {})
	for mat in bands:
		if rk.get(mat, 0) > 0:
			items.append({"item": _band(bands[mat], level), "count": int(rk[mat])})
	var last: Dictionary = t.get("lastRank", {})
	if rank == cap and last.get("rarities", []).has(rarity):
		items.append({"item": last.item, "count": int(last.get("count", 1))})
	return {"items": items, "coins": int(rk.get("coins", 0)) + U.jround(t.get("coinsPerItemLevel", 0) * level)}


## The next rank's cost for this item, or {} when it can go no higher.
func temper_cost(stack: Dictionary) -> Dictionary:
	var d := Items.get_def(stack.id)
	var cap := temper_cap(stack)
	var now := Items.temper_of(stack)
	if now >= cap or not d.has("itemLevel"):
		return {}
	var c := rank_cost(d.itemLevel, now + 1, cap, Items.view(stack).rarity)
	if not c.is_empty():
		c.rank = now + 1
		c.cap = cap
	return c


func affordable(cost: Dictionary) -> bool:
	if game.inventory.coins < cost.get("coins", 0):
		return false
	for x in cost.get("items", []):
		if game.inventory.count(x.item) < x.count:
			return false
	return true


## "3 Faint dust (5), 26c"
func cost_text(cost: Dictionary) -> String:
	var parts := []
	for x in cost.get("items", []):
		parts.append("%d %s (%d)" % [x.count, Items.get_def(x.item).get("name", x.item), game.inventory.count(x.item)])
	if cost.get("coins", 0):
		parts.append(U.money(cost.coins))
	return ", ".join(parts)


## Enchant an item one rank (+1 item level). Saves keep the rank as `temper`.
func temper(loc: String) -> bool:
	var inv = game.inventory
	var st = inv.get_at(loc)
	if st == null:
		return false
	var cost := temper_cost(st)
	if cost.is_empty():
		_say("That can be enchanted no further")
		return false
	if not affordable(cost):
		_say("You don't have what that needs")
		return false
	for x in cost.items:
		inv.remove_count(x.item, x.count)
	inv.lose_coins(cost.coins)
	var r := _rolls_of(st)
	r.temper = cost.rank
	_changed(loc)
	game.events.emit("itemEnchanted", {"loc": loc, "rank": cost.rank})
	game.events.emit("log", {"text": "Enchanted: %s (item level %s)." % [Items.view(st).name, U.n(Items.view(st).itemLevel)], "kind": "level"})
	return true


## What scrapping gives: { items: [{ item, count }], gems: [ids] }, or {}
## when the item holds no magic (plain gear). Gear breaks down into dust and
## its gems, never metal or leather.
func scrap_preview(stack: Dictionary) -> Dictionary:
	var d := Items.get_def(stack.id)
	var v := Items.view(stack)
	var de: Dictionary = enchant_rules().get("scrap", {})
	var n := int(de.get("dust", {}).get(v.get("rarity", "common"), 0))
	if n <= 0 or not d.has("itemLevel"):
		return {}
	var level: float = d.itemLevel
	var got := {}
	var dust := _band(enchant_rules().get("enchant", {}).get("bands", {}).get("dust", []), level)
	got[dust] = n
	var extra: Dictionary = de.get("extra", {})
	if extra.get("rarities", []).has(v.rarity):
		got[extra.item] = got.get(extra.item, 0) + int(extra.get("count", 1))
	# a share of every enchanting material put in comes back
	var put := {}
	var cap := temper_cap(stack)
	for rank in range(1, Items.temper_of(stack) + 1):
		for x in rank_cost(level, rank, cap, v.rarity).get("items", []):
			put[x.item] = put.get(x.item, 0) + x.count
	for item in put:
		var back := int(floor(put[item] * de.get("refund", 0.75)))
		if back > 0:
			got[item] = got.get(item, 0) + back
	return _preview(got, stack)


func scrap(loc: String) -> bool:
	var st = game.inventory.get_at(loc)
	if st == null or not gear_locations().has(loc):
		return false
	var p := scrap_preview(st)
	if p.is_empty():
		_say("There's nothing in that worth breaking down")
		return false
	var name_was: String = Items.view(st).name
	_break(loc, p)
	game.events.emit("log", {"text": "Scrapped: %s. %s" % [name_was, _list_text(p)], "kind": "loot"})
	game.events.emit("itemScrapped", {"id": st.id})
	return true


func _preview(got: Dictionary, stack: Dictionary) -> Dictionary:
	var items := []
	for item in got:
		items.append({"item": item, "count": got[item]})
	return {"items": items, "gems": Items.gems_of(stack).filter(func(g): return g != null)}


## Destroy the item at loc and hand over what the preview promised; what
## will not fit lies at your feet.
func _break(loc: String, p: Dictionary) -> void:
	var inv = game.inventory
	inv.take(loc)
	if loc.begins_with("e:"):
		inv._equipment_changed()
	for x in p.items:
		if not inv.add_item(x.item, x.count, true):
			game.loot.drop_at({"id": x.item, "count": x.count}, game.player.position)
	for g in p.gems:
		if not inv.add_item(g, 1, true):
			game.loot.drop_at({"id": g, "count": 1}, game.player.position)
	inv._changed()


func _list_text(p: Dictionary) -> String:
	var parts := []
	for x in p.get("items", []):
		parts.append("%d %s" % [x.count, Items.get_def(x.item).name])
	for g in p.get("gems", []):
		parts.append(Items.get_def(g).name)
	return "You get back: %s." % ", ".join(parts) if not parts.is_empty() else "Nothing comes of it."


func scrap_text(stack: Dictionary) -> String:
	return _list_text(scrap_preview(stack))


# ------------------------------------------------------------ reforging
## The stats on an item that can be reforged, and what each could become:
## [{ from, to: [3 stats] }]
func reforge_options(stack: Dictionary) -> Array:
	var rf: Dictionary = rules().get("reforge", {})
	var pool: Array = rf.get("stats", [])
	var d := Items.get_def(stack.id)
	if not d.has("itemLevel"):
		return []
	# work it out from the item before any earlier reforge
	var plain: Dictionary = stack.duplicate(true)
	if typeof(plain.get("rolls")) == TYPE_DICTIONARY:
		plain.rolls.erase("reforge")
		plain.rolls.erase("gems")
	var stats: Dictionary = Items.view(plain).get("stats", {})
	var out := []
	for k in pool:
		if not stats.has(k):
			continue
		var to := pool.filter(func(x): return x != k and not stats.has(x))
		out.append({"from": k, "to": to.slice(0, int(rf.get("options", 3)))})
	return out


func reforge_price(stack: Dictionary) -> int:
	var rf: Dictionary = rules().get("reforge", {})
	return int(rf.get("coins", 10)) + U.jround(rf.get("coinsPerItemLevel", 0) * Items.get_def(stack.id).get("itemLevel", 1))


func reforge(loc: String, from: String, to: String) -> bool:
	var inv = game.inventory
	var st = inv.get_at(loc)
	if st == null:
		return false
	var ok := false
	for o in reforge_options(st):
		if o.from == from and o.to.has(to):
			ok = true
	if not ok:
		return false
	var price := reforge_price(st)
	if inv.coins < price:
		_say("You cannot afford that")
		return false
	inv.lose_coins(price)
	var r := _rolls_of(st)
	r.reforge = {"from": from, "to": to}
	_changed(loc)
	game.events.emit("anvilStrike", {"x": game.player.position.x, "z": game.player.position.z})
	game.events.emit("log", {"text": "Reforged: %s now gives %s instead of %s." % [Items.view(st).name, to.capitalize(), from.capitalize()], "kind": "level"})
	return true


# ------------------------------------------------------------ sockets
func punch_cost(stack: Dictionary) -> Dictionary:
	var sk: Dictionary = rules().get("sockets", {})
	var v := Items.view(stack)
	var ranks := DB.rarities.keys()
	if ranks.find(v.rarity) < ranks.find(sk.get("minRarity", "enhanced")) or v.rarity == "quest":
		return {}
	if Items.sockets_of(stack) >= int(sk.get("max", 2)):
		return {}
	var r = stack.get("rolls")
	if typeof(r) == TYPE_DICTIONARY and int(r.get("socket", 0)) >= 1:
		return {} # a forge punches one socket an item
	var p: Dictionary = sk.get("punch", {})
	return {"items": [{"item": p.get("item", "skyiron"), "count": int(p.get("count", 1))}], "coins": int(p.get("coins", 0))}


func punch(loc: String) -> bool:
	var inv = game.inventory
	var st = inv.get_at(loc)
	if st == null:
		return false
	var cost := punch_cost(st)
	if cost.is_empty() or not affordable(cost):
		_say("You don't have what that needs")
		return false
	for x in cost.items:
		inv.remove_count(x.item, x.count)
	inv.lose_coins(cost.coins)
	var r := _rolls_of(st)
	r.socket = 1
	_changed(loc)
	game.events.emit("anvilStrike", {"x": game.player.position.x, "z": game.player.position.z})
	game.events.emit("log", {"text": "A socket is punched into %s." % Items.view(st).name, "kind": "level"})
	return true


# ------------------------------------------------------------ the jeweller
## Gems you could make now: [{ from, count, to, can }]
func combine_rows() -> Array:
	var out := []
	for rc in Gems.recipes():
		var have: int = game.inventory.count(rc.from)
		if have <= 0:
			continue
		var row: Dictionary = rc.duplicate()
		row.have = have
		row.can = have >= rc.count
		out.append(row)
	return out


func combine(to: String) -> bool:
	var inv = game.inventory
	for rc in Gems.recipes():
		if rc.to != to:
			continue
		if inv.count(rc.from) < rc.count:
			_say("You need %d %s" % [rc.count, Items.get_def(rc.from).name])
			return false
		inv.remove_count(rc.from, rc.count)
		if not inv.add_item(to, 1, true):
			game.loot.drop_at({"id": to, "count": 1}, game.player.position)
		game.events.emit("log", {"text": "The jeweller makes you %s %s." % [U.article(Items.get_def(to).name), Items.get_def(to).name], "kind": "loot"})
		game.events.emit("gemMade", {"id": to})
		return true
	return false


## Gear with an empty socket
func socketed_with_room() -> Array:
	return gear_locations().filter(func(loc): return Items.gems_of(game.inventory.get_at(loc)).has(null))


## Gear with gems in it
func socketed_with_gems() -> Array:
	return gear_locations().filter(func(loc): return Items.gems_of(game.inventory.get_at(loc)).any(func(g): return g != null))


## Gems in your bags that fit the item at `loc`: [ids]
func gems_for(loc: String) -> Array:
	var st = game.inventory.get_at(loc)
	if st == null:
		return []
	var out := []
	for id in DB.items:
		if DB.items[id].get("kind") == "gem" and game.inventory.count(id) > 0 and Gems.fits(id, Items.get_def(st.id)):
			out.append(id)
	return out


func set_gem(loc: String, gem: String) -> bool:
	var inv = game.inventory
	var st = inv.get_at(loc)
	if st == null or not gems_for(loc).has(gem):
		return false
	var gems := Items.gems_of(st)
	var i := gems.find(null)
	if i < 0:
		_say("Every socket is full")
		return false
	inv.remove_count(gem, 1)
	gems[i] = gem
	var r := _rolls_of(st)
	r.gems = gems
	_changed(loc)
	game.events.emit("log", {"text": "%s is set in %s." % [Items.get_def(gem).name, Items.view(st).name], "kind": "level"})
	return true


## Take every gem out of an item, back into your bags (free).
func remove_gems(loc: String) -> bool:
	var inv = game.inventory
	var st = inv.get_at(loc)
	if st == null:
		return false
	var gems := Items.gems_of(st)
	var any := false
	for i in gems.size():
		if gems[i] == null:
			continue
		if not inv.add_item(gems[i], 1, true):
			game.loot.drop_at({"id": gems[i], "count": 1}, game.player.position)
		gems[i] = null
		any = true
	if not any:
		return false
	var r := _rolls_of(st)
	r.erase("gems")
	_changed(loc)
	game.events.emit("log", {"text": "The stones come out of %s, whole." % Items.view(st).name, "kind": "loot"})
	return true


func _say(text: String) -> void:
	if game.hud:
		game.hud.error(text)

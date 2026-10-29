class_name Merchant
extends RefCounted
## Buying and selling, WoW style (src/systems/merchant.js). A shop sells its
## stock at the item database's price and buys at CONFIG.shop.sellFraction
## of it. Anything sold this session can be bought back for what it fetched.
## Quest items are never sold.

var game
var current = null ## shop id while a shop is open
var npc = null
var buyback: Array = [] ## [{ id, count, rolls?, paid }]


func _init(g) -> void:
	game = g


## what the shop window shows: who keeps it, what kind of vendor, the stock
var def:
	get:
		if current == null:
			return null
		var shop: Dictionary = DB.shops[current]
		var keeper = DB.npcs.get(npc.id) if npc != null else null
		var vt: Dictionary = DB.vendor_types[shop.vendorType]
		return {"name": keeper.name if keeper else shop.name, "title": vt.name, "stock": shop.stock, "repair": vt.get("repairs", false)}

var stock: Array:
	get:
		return DB.shops[current].stock if current != null else []


func open(id: String, n) -> void:
	current = id
	npc = n
	game.events.emit("merchantOpened", {"id": id})


func close() -> void:
	if current == null:
		return
	current = null
	npc = null
	game.events.emit("merchantClosed", {})


## walking away closes the shop
func update() -> void:
	if current == null or npc == null:
		return
	var p: Vector3 = game.player.position
	if game.player.dead or U.hyp(p.x - npc.position.x, p.z - npc.position.z) > DB.CONFIG.shop.leaveRange:
		close()


## the item's price, less this shop's faction discount (Friendly and up)
func price_of(id: String) -> int:
	var shop = DB.shops.get(current) if current != null else null
	var off: float = game.reputation.discount(shop.get("faction")) if shop else 0.0
	var price: float = Items.get_def(id).get("price", 0) * (1 + game.law.markup / 100.0)
	return maxi(1 if off and price else 0, int(floor(price * (100 - off) / 100.0)))


## An Outlaw is not served (data/infamy.json); says so, and returns true.
func refuses() -> bool:
	if not game.law.outlaw:
		return false
	game.events.emit("log", {"text": "%s won't deal with an outlaw." % (def.name if def else "The merchant"), "kind": "muted", "throttle": "shop-refuse"})
	return true


func buy(id: String) -> bool:
	var inventory = game.inventory
	var events: Events = game.events
	if current == null or not stock.has(id):
		return false
	if refuses():
		return false
	var price := price_of(id)
	var name: String = Items.get_def(id).name
	if inventory.coins < price:
		events.emit("log", {"text": "You cannot afford the %s (%s)." % [name, U.money(price)], "kind": "muted", "throttle": "shop-refuse"})
		return false
	var n := int(Items.get_def(id).get("buyCount", 1)) # arrows come by the hundred
	if not inventory.add_item(id, n, true):
		return false # bags full: add_item says so
	inventory.coins -= price
	events.emit("coins", {"amount": -price, "bought": true})
	events.emit("itemBought", {"id": id, "price": price})
	events.emit("log", {"text": "Bought: %s%s for %s." % [name, " ×%d" % n if n > 1 else "", U.money(price)], "kind": "loot"})
	inventory._changed()
	return true


## Sell the whole stack at an inventory location.
func sell(loc: String) -> bool:
	var inventory = game.inventory
	var events: Events = game.events
	if current == null or refuses():
		return false
	var stack = inventory.get_at(loc)
	if stack == null or loc.begins_with("s:") or loc == Inventory.AMMO_LOC:
		return false
	var v := Items.view(stack)
	if v.get("quest"):
		events.emit("log", {"text": "%s has no use for that, and you should not part with it." % def.name, "kind": "muted", "throttle": "shop-refuse"})
		return false
	var each := Items.sell_price(stack, DB.CONFIG.shop.sellFraction)
	var taken = inventory.take(loc)
	if taken == null:
		return false
	var paid: int = each * int(taken.count)
	inventory.coins += paid
	var b: Dictionary = taken.duplicate()
	b.paid = paid
	buyback.push_front(b)
	if buyback.size() > DB.CONFIG.shop.buybackSlots:
		buyback.resize(int(DB.CONFIG.shop.buybackSlots))
	events.emit("coins", {"amount": paid})
	events.emit("itemSold", {"id": taken.id, "count": taken.count, "paid": paid})
	events.emit("log", {"text": "Sold: %s%s for %s." % [v.name, " ×%d" % taken.count if taken.count > 1 else "", U.money(paid)], "kind": "loot"})
	if loc.begins_with("e:"):
		inventory._equipment_changed()
	inventory._changed()
	return true


## Sell every junk-quality item in your bags at once (WoW's "Sell junk").
func sell_junk() -> int:
	if current == null or refuses():
		return 0
	var total := 0
	for loc in game.inventory.bag_locations():
		var stack = game.inventory.get_at(loc)
		if stack == null or Items.view(stack).get("rarity", "common") != "junk":
			continue
		var before: int = game.inventory.coins
		if sell(loc):
			total += game.inventory.coins - before
	if total == 0:
		game.events.emit("log", {"text": "You have no junk to sell.", "kind": "muted", "throttle": "shop-refuse"})
	return total


func buy_back(index: int) -> bool:
	var inventory = game.inventory
	if current == null or index < 0 or index >= buyback.size():
		return false
	var b: Dictionary = buyback[index]
	if inventory.coins < b.paid:
		game.events.emit("log", {"text": "You cannot afford to buy that back.", "kind": "muted", "throttle": "shop-refuse"})
		return false
	if not inventory.add_item(b.id, b.count, true, b.get("rolls")):
		return false
	inventory.coins -= b.paid
	buyback.remove_at(index)
	game.events.emit("log", {"text": "Bought back: %s." % Items.view(b).name, "kind": "loot"})
	inventory._changed()
	return true

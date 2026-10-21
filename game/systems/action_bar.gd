class_name ActionBar
extends RefCounted
## The spell bar (src/systems/actionBar.js). Six spell slots (1 2 3 4 Q E)
## and four utility slots (Shift-1 to Shift-4; on a pad, hold D-pad left and
## press a face button), each with a fixed key. The player decides which
## ability sits in which slot, Diablo style. The utility slots take items
## and tools (Fishing, Set Camp, Cooking) only, never spells. A slot can
## also hold an item, as 'item:<id>'.

const BAR_SLOTS := [
	{"kbm": "1", "pad": "X"},
	{"kbm": "2", "pad": "Y"},
	{"kbm": "3", "pad": "RB"},
	{"kbm": "4", "pad": "LB"},
	{"kbm": "Q", "pad": "LT"},
	{"kbm": "E", "pad": "B"},
	{"kbm": "⇧1", "pad": "◀X", "utility": true},
	{"kbm": "⇧2", "pad": "◀Y", "utility": true},
	{"kbm": "⇧3", "pad": "◀A", "utility": true},
	{"kbm": "⇧4", "pad": "◀B", "utility": true},
]
## the bow abilities go onto free spell slots the first time a bow is equipped
const BOW_ABILITIES := ["quickShot", "venomArrow"]
const UTILITY_ABILITIES := ["fish", "setCamp", "cook"]
## abilities that no longer exist, mapped to what replaced them (old saves)
const RENAMED := {"dodge": "brace", "draught": "item:healing_draught"}

var game
var slots: Array
var clicked := {} ## abilities clicked on the bar this frame
var had_bow := false


## a class's starting bar: its six spells, then a draught on the first utility slot
static func default_bar(archetype: Dictionary) -> Array:
	var out: Array = archetype.bar.duplicate()
	out.append_array(["item:healing_draught", null, null, null])
	return out


static func item_ref(a):
	return a.substr(5) if typeof(a) == TYPE_STRING and a.begins_with("item:") else null


static func is_slot_utility(i: int) -> bool:
	return BAR_SLOTS[i].get("utility", false)


static func _valid_entry(a) -> bool:
	if a == null:
		return false
	var ref = item_ref(a)
	if ref != null:
		return DB.items.has(ref)
	return DB.abilities.has(a) and DB.abilities[a].get("bar", true) != false


## what a bar entry is called, ability or item
static func entry_name(a) -> String:
	var ref = item_ref(a)
	if ref != null:
		return Items.get_def(ref).get("name", "")
	return DB.abilities.get(a, {}).get("name", "")


## the first free slot for something new: a utility slot if one is free
static func free_slot(s: Array) -> int:
	for k in [6, 7, 8, 9, 0, 1, 2, 3, 4, 5]:
		if not s[k]:
			return k
	return -1


## the first free spell slot (1 2 3 4 Q E), or -1
static func free_spell_slot(s: Array) -> int:
	for k in BAR_SLOTS.size():
		if not is_slot_utility(k) and not s[k]:
			return k
	return -1


## what may sit in a utility slot: items and skill tools, never class spells
static func utility_ok(a) -> bool:
	return not a or item_ref(a) != null or DB.abilities.get(a, {}).has("skill")


## may this ability sit on the bar (and show in the spellbook)?
static func bar_ability(g, id) -> bool:
	return DB.abilities.has(id) and DB.abilities[id].get("bar", true) != false and g.skills.knows_ability(id)


func _init(g) -> void:
	game = g
	slots = default_bar(DB.archetypes[DB.CONFIG.player.archetype])
	# a bow coming into the ranged slot brings its abilities to the bar
	game.events.on("equipmentChanged", func(_e):
		var bow: bool = game.stats != null and game.stats.has_ranged
		if bow and not had_bow:
			add_bow_abilities()
		had_bow = bow)


func add_bow_abilities() -> void:
	for ab in BOW_ABILITIES:
		if slots.has(ab) or not bar_ability(game, ab):
			continue
		var free := free_spell_slot(slots)
		if free >= 0:
			place(ab, free)


func reset() -> void:
	apply(default_bar(game.stats.archetype))


## may `a` go in slot `index`? (says why not if it may not)
func fits(a, index: int) -> bool:
	if index < 0 or index >= BAR_SLOTS.size() or not is_slot_utility(index) or utility_ok(a):
		return true
	if game.hud:
		game.hud.error("Only items and tools go on the utility bar")
	return false


## Swap two slots (either may be empty).
func move(from: int, to: int) -> void:
	if from == to:
		return
	if not fits(slots[from], to) or not fits(slots[to], from):
		return
	var a = slots[from]
	slots[from] = slots[to]
	slots[to] = a
	_changed()


## Put an ability in a slot; it leaves any slot it was in, and whatever was
## in the target slot goes back to the spellbook.
func place(ability, index: int) -> void:
	if item_ref(ability) == null and not bar_ability(game, ability):
		return
	if not fits(ability, index):
		return
	var was := slots.find(ability)
	if was >= 0:
		slots[was] = null
	slots[index] = ability
	_changed()


func remove(index: int) -> void:
	if not slots[index]:
		return
	slots[index] = null
	_changed()


## Which abilities fire this frame, given which slots were triggered.
func actions(triggered: Array) -> Dictionary:
	var out := {}
	for i in triggered.size():
		if triggered[i] and i < slots.size() and slots[i]:
			out[slots[i]] = true
	for a in clicked:
		out[a] = true
	clicked.clear()
	# items on the bar are used straight away
	for a in out.keys():
		var ref = item_ref(a)
		if ref == null:
			continue
		out.erase(a)
		game.inventory.use_from_bar(ref)
	return out


func _changed() -> void:
	game.events.emit("barChanged", {})


## Put an item on the bar.
func place_item(id: String, index: int) -> void:
	if not DB.items.has(id):
		return
	var ref := "item:" + id
	var was := slots.find(ref)
	if was >= 0:
		slots[was] = null
	slots[index] = ref
	_changed()


func serialize() -> Array:
	return slots.duplicate()


func apply(saved: Array) -> void:
	# bars saved before click-to-target had seven slots, the mouse buttons in
	# the middle: keep the keyed slots, and find room for what was on them
	var list := saved
	if saved.size() == 7:
		list = [saved[0], saved[1], saved[2], saved[3], null, saved[6], null, null, null, null]
		for a in [saved[5], saved[4]]:
			var free := list.find(null)
			if a and free >= 0 and free < BAR_SLOTS.size() - 1:
				list[free] = a
	# only what this class knows, and no spells on the utility slots
	slots = []
	for i in BAR_SLOTS.size():
		var a = list[i] if i < list.size() else null
		if typeof(a) == TYPE_STRING and RENAMED.has(a):
			a = RENAMED[a]
		var ok: bool = _valid_entry(a) and (item_ref(a) != null or bar_ability(game, a)) and (not is_slot_utility(i) or utility_ok(a))
		slots.append(a if ok else null)
	# a bar saved before the class kits: its empty spell slots take the base
	# kit's spells it lacks
	for a in game.stats.archetype.get("bar", []):
		var free := free_spell_slot(slots)
		if a and free >= 0 and not slots.has(a):
			slots[free] = a
	# bars saved before the utility slots: move Fishing and Set Camp there
	if saved.size() < BAR_SLOTS.size():
		for u in UTILITY_ABILITIES:
			var at := slots.find(u)
			var free := -1
			for k in BAR_SLOTS.size():
				if not slots[k] and is_slot_utility(k):
					free = k
					break
			if at >= 0 and not is_slot_utility(at) and free >= 0:
				slots[at] = null
				slots[free] = u
	_changed()

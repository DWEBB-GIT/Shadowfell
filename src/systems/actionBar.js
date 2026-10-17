import { DB } from '../data/db.js';
import { ITEMS } from '../data/items.js';

// The spell bar. Six combat slots and four utility slots (keys 6-9; on a pad,
// hold D-pad left and press a face button, like FFXIV's cross hotbar), each
// with a fixed key (and pad button); the
// player decides which ability sits in which slot, Diablo style. Abilities
// can be dragged between slots, dragged off the bar, and put back from the
// spellbook. A slot location is 'a:<index>', a spellbook entry 'k:<ability>'.

// Abilities come from data/abilities.json. `target`: 'enemy' abilities go to
// the selected enemy (or the one nearest your aim) within `range`; 'ground'
// ones land at the aim point; 'self' ones need no aim. `tuning` holds the
// numbers each runs on. Abilities with `bar: false` (auto attack, id
// `strike`) never go on the bar or in the spellbook.
export const ABILITIES = DB.abilities;

// Key labels for keyboard/mouse and gamepad, in slot order. The last slot is
// the defensive slot on Space, which each archetype fills with its own move.
export const BAR_SLOTS = [
  { kbm: '1', pad: 'X' },
  { kbm: '2', pad: 'Y' },
  { kbm: '3 / Q', pad: 'RB' },
  { kbm: '4', pad: 'LB' },
  { kbm: '5', pad: 'LT' },
  { kbm: 'Space', pad: 'B', defensive: true },
  { kbm: '6', pad: '◀X', utility: true },
  { kbm: '7', pad: '◀Y', utility: true },
  { kbm: '8', pad: '◀A', utility: true },
  { kbm: '9', pad: '◀B', utility: true },
];

export const DEFAULT_BAR = ['lunge', 'shieldBreak', 'item:healing_draught', 'hallowedBolt', 'rebuke', 'brace', null, null, null, null];
// the bow abilities go onto free slots the first time a bow is equipped
export const BOW_ABILITIES = ['quickShot', 'venomArrow'];

// A slot can also hold an item (WoW style), as 'item:<id>': the torch,
// lockpicks or anything else used from the bags.
export const itemRef = (a) => (typeof a === 'string' && a.startsWith('item:') ? a.slice(5) : null);
const validEntry = (a) => (itemRef(a) ? !!ITEMS[itemRef(a)] : !!ABILITIES[a] && ABILITIES[a].bar !== false);
// what a bar entry is called and shows, ability or item
export const entryName = (a) => (itemRef(a) ? ITEMS[itemRef(a)]?.name || '' : ABILITIES[a]?.name || '');
// the first free slot for something new: a utility slot if one is free
export function freeSlot(slots) {
  const order = [...BAR_SLOTS.keys()].filter((i) => !BAR_SLOTS[i].defensive).sort((a, b) => !!BAR_SLOTS[b].utility - !!BAR_SLOTS[a].utility);
  const i = order.find((k) => !slots[k]);
  return i === undefined ? -1 : i;
}
export const UTILITY_ABILITIES = ['fish', 'setCamp', 'cook'];

// may this ability sit on the bar (and show in the spellbook)?
export const barAbility = (game, id) => !!ABILITIES[id] && ABILITIES[id].bar !== false && game.skills.knowsAbility(id);

// abilities that no longer exist, mapped to what replaced them (old saves)
const RENAMED = { dodge: 'brace', draught: 'item:healing_draught' };

export class ActionBar {
  constructor(game) {
    this.game = game;
    this.slots = [...DEFAULT_BAR];
    this.clicked = new Set(); // abilities clicked on the bar this frame
    // a bow coming into the ranged slot brings its abilities to the bar
    this.hadBow = false;
    game.events.on('equipmentChanged', () => {
      const bow = !!game.stats?.hasRanged;
      if (bow && !this.hadBow) this.addBowAbilities();
      this.hadBow = bow;
    });
  }

  addBowAbilities() {
    for (const ab of BOW_ABILITIES) {
      if (this.slots.includes(ab) || !barAbility(this.game, ab)) continue;
      const free = freeSlot(this.slots);
      if (free >= 0) this.place(ab, free);
    }
  }

  reset() {
    this.apply([...DEFAULT_BAR]);
  }

  // Swap two slots (either may be empty).
  move(from, to) {
    if (from === to) return;
    [this.slots[from], this.slots[to]] = [this.slots[to], this.slots[from]];
    this._changed();
  }

  // Put an ability in a slot; it leaves any slot it was in, and whatever was
  // in the target slot goes back to the spellbook.
  place(ability, index) {
    if (!itemRef(ability) && !barAbility(this.game, ability)) return;
    const was = this.slots.indexOf(ability);
    if (was >= 0) this.slots[was] = null;
    this.slots[index] = ability;
    this._changed();
  }

  remove(index) {
    if (!this.slots[index]) return;
    this.slots[index] = null;
    this._changed();
  }

  // Which abilities fire this frame, given which slots were triggered.
  actions(triggered) {
    const out = {};
    triggered.forEach((on, i) => {
      if (on && this.slots[i]) out[this.slots[i]] = true;
    });
    for (const a of this.clicked) out[a] = true;
    this.clicked.clear();
    // items on the bar are used straight away
    for (const a of Object.keys(out)) {
      if (!itemRef(a)) continue;
      delete out[a];
      this.game.inventory.useFromBar(itemRef(a));
    }
    return out;
  }

  _changed() {
    this.game.events.emit('barChanged', {});
  }

  // Put an item on the bar.
  placeItem(id, index) {
    if (!ITEMS[id]) return;
    const ref = 'item:' + id;
    const was = this.slots.indexOf(ref);
    if (was >= 0) this.slots[was] = null;
    this.slots[index] = ref;
    this._changed();
  }

  serialize() {
    return [...this.slots];
  }

  apply(slots) {
    // bars saved before click-to-target had seven slots, the mouse buttons
    // in the middle: keep the keyed slots, and find room for what was on
    // the mouse buttons
    let list = slots;
    if (slots.length === 7) {
      list = [slots[0], slots[1], slots[2], slots[3], null, slots[6], null, null, null, null];
      for (const a of [slots[5], slots[4]]) {
        const free = list.indexOf(null);
        if (a && free >= 0 && free < BAR_SLOTS.length - 1) list[free] = a;
      }
    }
    this.slots = BAR_SLOTS.map((_, i) => {
      const a = RENAMED[list[i]] || list[i];
      return validEntry(a) ? a : null;
    });
    // bars saved before the utility slots: move Fishing and Set Camp there
    if (slots.length < BAR_SLOTS.length) {
      for (const u of UTILITY_ABILITIES) {
        const at = this.slots.indexOf(u);
        const free = this.slots.findIndex((x, k) => !x && BAR_SLOTS[k].utility);
        if (at >= 0 && !BAR_SLOTS[at].utility && free >= 0) [this.slots[at], this.slots[free]] = [null, u];
      }
    }
    this._changed();
  }
}

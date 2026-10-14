// The spell bar. Seven slots, each with a fixed key (and pad button); the
// player decides which ability sits in which slot, Diablo style. Abilities
// can be dragged between slots, dragged off the bar, and put back from the
// spellbook. A slot location is 'a:<index>', a spellbook entry 'k:<ability>'.

// `target`: 'enemy' abilities go to the soft- or hard-locked enemy within
// `range`; 'ground' ones land at the aim point; 'self' ones need no aim.
export const ABILITIES = {
  strike: { name: 'Strike', target: 'enemy', range: 2.4, desc: 'A sword blow at the enemy you are aiming at. Off the global cooldown.' },
  shieldBreak: { name: 'Shield Break', target: 'self', desc: 'A close-range blow that strikes everything around you and interrupts ordinary attacks. Triggers the global cooldown.' },
  lunge: { name: 'Lunge', target: 'enemy', range: 6.6, desc: 'Charge at the enemy you are aiming at and strike on arrival. Triggers the global cooldown.' },
  brace: { name: 'Brace', target: 'self', defensive: true, desc: 'Raise your shield: the next blow within 2.5 seconds, even a Grave Slam, is turned aside. The Warden\'s defensive ability. 7 second cooldown.' },
  draught: { name: 'Healing draught', target: 'self', desc: 'Drink a healing draught from your bags.', item: 'healing_draught' },
};

// Key labels for keyboard/mouse and gamepad, in slot order. The last slot is
// the defensive slot on Space, which each archetype fills with its own move.
export const BAR_SLOTS = [
  { kbm: '1', pad: 'RB' },
  { kbm: '2 / Q', pad: 'LB' },
  { kbm: '3', pad: 'LT' },
  { kbm: '4', pad: 'D-pad ←' },
  { kbm: 'LMB', pad: 'X / RT', mouse: true },
  { kbm: 'RMB', pad: 'Y', mouse: true },
  { kbm: 'Space', pad: 'B', defensive: true },
];

export const DEFAULT_BAR = ['lunge', 'draught', null, null, 'strike', 'shieldBreak', 'brace'];

// abilities that no longer exist, mapped to what replaced them (old saves)
const RENAMED = { dodge: 'brace' };

export class ActionBar {
  constructor(game) {
    this.game = game;
    this.slots = [...DEFAULT_BAR];
    this.clicked = new Set(); // abilities clicked on the bar this frame
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
    if (!ABILITIES[ability]) return;
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
    return out;
  }

  _changed() {
    this.game.events.emit('barChanged', {});
  }

  serialize() {
    return [...this.slots];
  }

  apply(slots) {
    this.slots = BAR_SLOTS.map((_, i) => {
      const a = RENAMED[slots[i]] || slots[i];
      return ABILITIES[a] ? a : null;
    });
    this._changed();
  }
}

import { CONFIG } from '../config.js';
import { ITEMS, EQUIP_SLOTS, BACKPACK_SLOTS, BAG_SOCKETS, itemView } from '../data/items.js';

// Bags, equipment and currency, laid out the way classic WoW does it:
//   * four bag sockets; socket 0 is the fixed backpack, the others take bags
//   * every bag has numbered slots holding a stack { id, count }, plus
//     `rolls` for gear that dropped with random stats (see data/items.js)
//   * the character panel has one slot per equipment position
// Currency is kept apart from items.
//
// A location is a short string so the UI, gamepad and tests share one shape:
//   'b:<socket>:<slot>'  a slot inside a bag
//   'e:<slotId>'         a character equipment slot
//   's:<socket>'         a bag socket (1-3; the bag item itself)

export const parseLoc = (loc) => {
  const [t, a, b] = loc.split(':');
  if (t === 'b') return { type: 'bag', socket: +a, slot: +b };
  if (t === 'e') return { type: 'equip', slot: a };
  if (t === 's') return { type: 'socket', socket: +a };
  return null;
};

const clone = (s) => (s ? (s.rolls ? { id: s.id, count: s.count, rolls: s.rolls } : { id: s.id, count: s.count }) : null);

export class Inventory {
  constructor(game) {
    this.game = game;
    this.reset();
  }

  reset() {
    this.coins = CONFIG.player.startCoins;
    this.sockets = [{ id: 'backpack', slots: new Array(BACKPACK_SLOTS).fill(null) }, null, null, null];
    this.equipment = Object.fromEntries(EQUIP_SLOTS.map((s) => [s.id, null]));
    this.equipment.mainHand = { id: 'worn_longsword', count: 1 };
    this.equipment.chest = { id: 'travelling_clothes', count: 1 };
    this.equipment.offHand = { id: 'kite_shield', count: 1 };
    this.sockets[0].slots[0] = { id: 'healing_draught', count: CONFIG.player.startDraughts };
  }

  // ------------------------------------------------------------ queries
  get(loc) {
    const p = parseLoc(loc);
    if (!p) return null;
    if (p.type === 'bag') return this.sockets[p.socket]?.slots[p.slot] ?? null;
    if (p.type === 'equip') return this.equipment[p.slot] ?? null;
    if (p.type === 'socket') {
      const s = this.sockets[p.socket];
      return s && s.id !== 'backpack' ? { id: s.id, count: 1 } : null;
    }
    return null;
  }

  bagLocations() {
    const out = [];
    this.sockets.forEach((s, i) => s && s.slots.forEach((_, j) => out.push(`b:${i}:${j}`)));
    return out;
  }

  count(id) {
    let n = 0;
    for (const loc of this.bagLocations()) {
      const s = this.get(loc);
      if (s && s.id === id) n += s.count;
    }
    return n;
  }

  has(id) {
    return this.count(id) > 0 || Object.values(this.equipment).some((s) => s && s.id === id) || this.sockets.some((s) => s && s.id === id);
  }

  // Every item id carried, equipped or socketed (for summaries and tests).
  get items() {
    const ids = new Set();
    for (const loc of this.bagLocations()) if (this.get(loc)) ids.add(this.get(loc).id);
    for (const s of Object.values(this.equipment)) if (s) ids.add(s.id);
    for (const s of this.sockets) if (s && s.id !== 'backpack') ids.add(s.id);
    return [...ids];
  }

  get equipped() {
    return this.equipment.mainHand ? this.equipment.mainHand.id : null;
  }

  get weapon() {
    const s = this.equipment.mainHand;
    return s ? itemView(s) : { name: 'Bare hands', damage: CONFIG.stats.fistDamage };
  }

  get draughts() {
    return this.count('healing_draught');
  }

  set draughts(n) {
    // used by tests and save migration: set the total number of draughts
    this.removeAll('healing_draught');
    if (n > 0) this._insert('healing_draught', n);
  }

  freeSlots() {
    return this.bagLocations().filter((l) => !this.get(l)).length;
  }

  // ------------------------------------------------------------ mutation
  _set(loc, stack) {
    const p = parseLoc(loc);
    if (p.type === 'bag') this.sockets[p.socket].slots[p.slot] = stack;
    else if (p.type === 'equip') this.equipment[p.slot] = stack;
    else if (p.type === 'socket') {
      this.sockets[p.socket] = stack ? { id: stack.id, slots: new Array(ITEMS[stack.id].bagSlots).fill(null) } : null;
    }
  }

  // Put `count` of `id` into bags; returns how many did not fit.
  _insert(id, count, rolls = null) {
    const def = ITEMS[id];
    let left = count;
    const locs = this.bagLocations();
    for (const loc of locs) {
      const s = this.get(loc);
      if (left > 0 && !rolls && s && s.id === id && !s.rolls && s.count < def.stack) {
        const add = Math.min(def.stack - s.count, left);
        s.count += add;
        left -= add;
      }
    }
    for (const loc of locs) {
      if (left > 0 && !this.get(loc)) {
        const add = Math.min(def.stack, left);
        this._set(loc, rolls ? { id, count: add, rolls } : { id, count: add });
        left -= add;
      }
    }
    return left;
  }

  // Returns true if everything fitted. A full bag leaves loot where it is.
  addItem(id, count = 1, { quiet = false, rolls = null } = {}) {
    if (!ITEMS[id]) return false;
    if (this.roomFor(id) < count) {
      this.game.events.emit('log', { text: 'Your bags are full.', kind: 'muted', throttle: 'bags-full' });
      return false;
    }
    this._insert(id, count, rolls);
    if (!quiet) {
      const name = itemView({ id, rolls }).name;
      this.game.events.emit('log', { text: `Taken: ${name}${count > 1 ? ` ×${count}` : ''}.`, kind: 'loot' });
      const k = ITEMS[id].kind;
      if (k === 'weapon' || k === 'armor' || k === 'shield') this.game.events.emit('log', { text: 'Drag it onto your character (C) to equip it.', kind: 'muted', throttle: 'equip-hint' });
      if (k === 'bag') this.game.events.emit('log', { text: 'Drag it into an empty bag slot to carry more.', kind: 'muted', throttle: 'bag-hint' });
    }
    this._changed();
    return true;
  }

  roomFor(id) {
    const def = ITEMS[id];
    let room = 0;
    for (const loc of this.bagLocations()) {
      const s = this.get(loc);
      if (!s) room += def.stack;
      else if (s.id === id) room += def.stack - s.count;
    }
    return room;
  }

  removeAll(id) {
    for (const loc of this.bagLocations()) if (this.get(loc)?.id === id) this._set(loc, null);
  }

  // Take `count` of an item from the bags, smallest stacks first.
  removeCount(id, count) {
    let left = count;
    const locs = this.bagLocations().filter((l) => this.get(l)?.id === id).sort((a, b) => this.get(a).count - this.get(b).count);
    for (const loc of locs) {
      if (left <= 0) break;
      const s = this.get(loc);
      const n = Math.min(left, s.count);
      if (n >= s.count) this._set(loc, null);
      else s.count -= n;
      left -= n;
    }
    this._changed();
    return count - left;
  }

  // Remove up to `count` from one location; returns the removed stack.
  take(loc, count = Infinity) {
    const s = this.get(loc);
    if (!s) return null;
    const p = parseLoc(loc);
    if (p.type === 'socket' && !this._bagEmpty(p.socket)) return null;
    const n = Math.min(count, s.count);
    if (n >= s.count) this._set(loc, null);
    else s.count -= n;
    if (p.type === 'equip') this._equipmentChanged();
    this._changed();
    return s.rolls ? { id: s.id, count: n, rolls: s.rolls } : { id: s.id, count: n };
  }

  _bagEmpty(socket) {
    const s = this.sockets[socket];
    return !s || s.slots.every((x) => !x);
  }

  // Can this stack sit at that location?
  accepts(loc, stack) {
    if (!stack) return true;
    const p = parseLoc(loc);
    const def = ITEMS[stack.id];
    if (!p || !def) return false;
    if (p.type === 'equip') return def.slot === p.slot && this.canWear(def);
    if (p.type === 'socket') return p.socket > 0 && p.socket < BAG_SOCKETS && def.kind === 'bag';
    if (p.type === 'bag') return !!this.sockets[p.socket] && p.slot < this.sockets[p.socket].slots.length;
    return false;
  }

  // Armour types and shields are limited by archetype, as in WoW.
  canWear(def) {
    const a = this.game.stats.archetype;
    if (def.armourType && !a.armourTypes.includes(def.armourType)) return false;
    if (def.kind === 'shield' && !a.shields) return false;
    return true;
  }

  // Move or swap the stacks at two locations. Returns { ok, reason }.
  move(from, to) {
    if (from === to) return { ok: false, reason: '' };
    const a = this.get(from);
    const b = this.get(to);
    if (!a) return { ok: false, reason: '' };
    const pf = parseLoc(from);
    const pt = parseLoc(to);
    // a bag that still holds things cannot be lifted out of its socket
    if (pf.type === 'socket' && !this._bagEmpty(pf.socket)) return this._refuse('Empty that bag before moving it.');
    if (pt.type === 'socket' && b && !this._bagEmpty(pt.socket)) return this._refuse('Empty that bag before replacing it.');
    // nor can a bag be put inside itself
    if (pf.type === 'socket' && pt.type === 'bag' && pt.socket === pf.socket) return this._refuse('A bag cannot go inside itself.');
    if (pt.type === 'socket' && pf.type === 'bag' && pf.socket === pt.socket) return this._refuse('A bag cannot go inside itself.');
    if (!this.accepts(to, a)) return this._refuse(this._why(to, a));
    if (b && b.id === a.id && ITEMS[a.id].stack > 1 && pt.type === 'bag' && pf.type === 'bag') {
      const room = ITEMS[a.id].stack - b.count;
      const n = Math.min(room, a.count);
      b.count += n;
      a.count -= n;
      if (a.count <= 0) this._set(from, null);
      this._changed();
      return { ok: true };
    }
    if (b && !this.accepts(from, b)) return this._refuse(this._why(from, b));
    if (pt.type === 'socket' || pf.type === 'socket') {
      // sockets rebuild their slot arrays, so set them with care
      this._set(from, null);
      this._set(to, clone(a));
      if (b) this._set(from, clone(b));
    } else {
      this._set(to, a);
      this._set(from, b);
    }
    if (pf.type === 'equip' || pt.type === 'equip') this._equipmentChanged();
    this._changed();
    return { ok: true };
  }

  _why(loc, stack) {
    const p = parseLoc(loc);
    const def = ITEMS[stack.id];
    if (p.type === 'equip' && def.slot === p.slot && !this.canWear(def)) {
      const what = def.kind === 'shield' ? 'shields' : `${CONFIG.armourTypes[def.armourType].name.toLowerCase()} armour`;
      return `A ${this.game.stats.archetype.name} cannot use ${what}.`;
    }
    if (p.type === 'equip') return `The ${def.name} does not go there.`;
    if (p.type === 'socket') return p.socket === 0 ? 'The backpack cannot be removed.' : 'Only bags go in bag slots.';
    return 'That will not fit there.';
  }

  _refuse(reason) {
    if (reason) this.game.events.emit('log', { text: reason, kind: 'muted', throttle: 'inv-refuse' });
    return { ok: false, reason };
  }

  firstFree() {
    return this.bagLocations().find((l) => !this.get(l)) || null;
  }

  // Right-click / gamepad X: the obvious action for whatever is there.
  use(loc) {
    const s = this.get(loc);
    if (!s) return false;
    const def = ITEMS[s.id];
    const p = parseLoc(loc);
    if (p.type === 'equip' || p.type === 'socket') {
      const free = this.firstFree();
      if (!free) return !!this._refuse('Your bags are full.');
      return this.move(loc, free).ok;
    }
    if (def.kind === 'consumable') return this.useDraught(loc);
    if (def.kind === 'document') {
      this.game.hud.openDocument(s.id);
      return true;
    }
    if (def.slot) return this.move(loc, `e:${def.slot}`).ok;
    if (def.kind === 'bag') {
      const socket = [1, 2, 3].find((i) => !this.sockets[i]);
      if (socket === undefined) return !!this._refuse('All your bag slots are in use.');
      return this.move(loc, `s:${socket}`).ok;
    }
    return false;
  }

  // Equip by item id (kept for scripts and tests).
  equip(id) {
    const loc = this.bagLocations().find((l) => this.get(l)?.id === id);
    if (!loc) return false;
    return this.move(loc, `e:${ITEMS[id].slot}`).ok;
  }

  _equipmentChanged() {
    const { player, combat, events } = this.game;
    player.showEquipment(this.equipment);
    this.game.recomputeMaxHealth();
    events.emit('equipmentChanged', {});
    const [lo, hi] = this.game.stats.abilityRange(1);
    events.emit('log', { text: `Strike damage is now ${lo}–${hi} (${this.weapon.name}).`, kind: 'level', throttle: `equip-dmg-${lo}-${hi}` });
  }

  _changed() {
    this.game.events.emit('inventoryChanged', {});
  }

  // ------------------------------------------------------------ currency
  addCoins(n, source = '') {
    this.coins += n;
    this.game.events.emit('coins', { amount: n });
    this.game.events.emit('log', { text: `${n} coin${n === 1 ? '' : 's'}${source ? ' ' + source : ''}.`, kind: 'loot' });
    this._changed();
  }

  loseCoins(n) {
    const lost = Math.min(this.coins, n);
    this.coins -= lost;
    this._changed();
    return lost;
  }

  // ------------------------------------------------------------ draughts
  useDraught(loc = null) {
    const { player, events } = this.game;
    if (player.dead) return false;
    const where = loc || this.bagLocations().find((l) => this.get(l)?.id === 'healing_draught');
    if (!where) {
      events.emit('log', { text: 'You have no healing draughts left.', kind: 'muted', throttle: 'no-draught' });
      return false;
    }
    if (player.health >= player.maxHealth) {
      events.emit('log', { text: 'You are not wounded.', kind: 'muted', throttle: 'not-wounded' });
      return false;
    }
    if (player.cooldowns.draught > 0) return false;
    this.take(where, 1);
    player.cooldowns.draught = CONFIG.draught.cooldown;
    const healed = player.heal(ITEMS.healing_draught.use.heal);
    events.emit('damageNumber', { target: player, amount: healed, kind: 'heal' });
    player.rig.play('drink', 0.6, 0.5);
    events.emit('draught', {});
    events.emit('log', { text: `You drink a healing draught (+${healed}). ${this.draughts} left.`, kind: 'heal' });
    return true;
  }

  // ------------------------------------------------------------ saving
  serialize() {
    return {
      coins: this.coins,
      sockets: this.sockets.map((s) => (s ? { id: s.id, slots: s.slots.map(clone) } : null)),
      equipment: Object.fromEntries(Object.entries(this.equipment).map(([k, v]) => [k, clone(v)])),
      granted: ['kite_shield'],
    };
  }

  apply(data) {
    this.coins = data.coins;
    this.sockets = data.sockets.map((s) => (s ? { id: s.id, slots: s.slots.map(clone) } : null));
    this.equipment = Object.fromEntries(EQUIP_SLOTS.map((s) => [s.id, clone(data.equipment[s.id] || null)]));
    // saves from before shields existed: hand the Warden theirs, once
    if (!(data.granted || []).includes('kite_shield')) {
      if (!this.equipment.offHand) this.equipment.offHand = { id: 'kite_shield', count: 1 };
      else this._insert('kite_shield', 1);
    }
    this.game.player.showEquipment(this.equipment);
    this._changed();
  }
}

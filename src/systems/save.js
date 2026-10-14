import { ITEMS, EQUIP_SLOTS, BACKPACK_SLOTS, BAG_SOCKETS, validRolls } from '../data/items.js';
import { BOUNDS } from '../world/layout.js';
import { ABILITIES } from './actionBar.js';
import { DB } from '../data/db.js';

// Versioned save in localStorage. Loaded data is validated before anything is
// applied; a save that fails validation is preserved under a backup key and
// never silently overwritten.
//
// Version 2 (build 2) stores bags, bag slots, equipment and items dropped on
// the ground. Version 1 saves (a flat item list) are upgraded on load.

export const SAVE_KEY = 'shadowfall.save';
export const BACKUP_KEY = 'shadowfall.save.unreadable';
export const SAVE_VERSION = 2;

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isInt = (v) => Number.isInteger(v);
const isStrArray = (v) => Array.isArray(v) && v.every((s) => typeof s === 'string');
const inBounds = (p) => p && isNum(p.x) && isNum(p.z) && p.x >= BOUNDS.minX - 1 && p.x <= BOUNDS.maxX + 1 && p.z >= BOUNDS.minZ - 1 && p.z <= BOUNDS.maxZ + 1;

const isStack = (s) => s && typeof s === 'object' && typeof s.id === 'string' && ITEMS[s.id] && isInt(s.count) && s.count >= 1 && s.count <= ITEMS[s.id].stack && validRolls(s.id, s.rolls);

// Upgrade a build-1 save: its flat item list goes into the backpack, its
// weapon into the main hand. Anything else is returned unchanged.
export function migrateSave(data) {
  if (!data || typeof data !== 'object' || data.version !== 1 || !data.inventory) return data;
  const old = data.inventory;
  const slots = new Array(BACKPACK_SLOTS).fill(null);
  let i = 0;
  const put = (id, count) => {
    if (i < slots.length && ITEMS[id]) slots[i++] = { id, count: Math.min(count, ITEMS[id].stack) };
  };
  if (isInt(old.draughts) && old.draughts > 0) put('healing_draught', old.draughts);
  const items = Array.isArray(old.items) ? old.items : [];
  for (const id of items) if (id !== old.equipped && ITEMS[id] && ITEMS[id].kind !== 'consumable') put(id, 1);
  const equipment = Object.fromEntries(EQUIP_SLOTS.map((s) => [s.id, null]));
  equipment.mainHand = ITEMS[old.equipped] ? { id: old.equipped, count: 1 } : null;
  equipment.chest = { id: 'travelling_clothes', count: 1 };
  return {
    ...data,
    version: 2,
    migratedFrom: 1,
    inventory: { coins: old.coins, sockets: [{ id: 'backpack', slots }, null, null, null], equipment },
    world: data.world ? { ...data.world, ground: [] } : data.world,
  };
}

function validateInventory(inv, check) {
  check(isInt(inv.coins) && inv.coins >= 0, 'coins');
  const sk = inv.sockets;
  check(Array.isArray(sk) && sk.length === BAG_SOCKETS, 'bag sockets');
  if (Array.isArray(sk)) {
    sk.forEach((s, i) => {
      if (i === 0) {
        check(s && s.id === 'backpack' && Array.isArray(s.slots) && s.slots.length === BACKPACK_SLOTS, 'backpack');
      } else if (s !== null) {
        const def = s && ITEMS[s.id];
        check(def && def.kind === 'bag' && Array.isArray(s.slots) && s.slots.length === def.bagSlots, `bag in socket ${i}`);
      }
      if (s && Array.isArray(s.slots)) check(s.slots.every((x) => x === null || isStack(x)), `contents of bag ${i}`);
    });
  }
  const eq = inv.equipment;
  check(eq && typeof eq === 'object', 'equipment');
  if (eq && typeof eq === 'object') {
    for (const [slot, st] of Object.entries(eq)) {
      check(EQUIP_SLOTS.some((s) => s.id === slot), `unknown equipment slot ${slot}`);
      check(st === null || (isStack(st) && ITEMS[st.id].slot === slot), `equipment in ${slot}`);
    }
  }
}

export function validateSave(data) {
  const errors = [];
  const check = (cond, msg) => {
    if (!cond) errors.push(msg);
  };
  if (!data || typeof data !== 'object') return ['not an object'];
  check(data.version === SAVE_VERSION, 'unknown save version');
  const p = data.player;
  check(p && typeof p === 'object', 'missing player');
  if (p) {
    check(inBounds(p.position), 'player position');
    check(isNum(p.facing), 'player facing');
    check(isNum(p.health) && p.health > 0, 'player health');
    check(isNum(p.maxHealth) && p.maxHealth >= 1 && p.health <= p.maxHealth, 'player max health');
  }
  const pr = data.progression;
  check(pr && isInt(pr.level) && pr.level >= 1 && pr.level < 100 && isNum(pr.xp) && pr.xp >= 0, 'progression');
  const inv = data.inventory;
  check(inv && typeof inv === 'object', 'missing inventory');
  if (inv) {
    validateInventory(inv, check);
  }
  if (data.bar !== undefined) {
    check(Array.isArray(data.bar) && data.bar.length === 7 && data.bar.every((a) => a === null || ABILITIES[a] || a === 'dodge'), 'spell bar');
  }
  // the quest log (saves from before it have none, and start from the story flag)
  if (data.quests !== undefined) {
    const q = data.quests;
    const known = (l) => isStrArray(l) && l.every((id) => DB.quests[id]);
    check(q && known(q.accepted) && known(q.done) && known(q.tracked), 'quest log');
  }
  const w = data.world;
  check(w && typeof w === 'object', 'missing world');
  if (w) {
    check(isStrArray(w.defeated) && isStrArray(w.collected) && isStrArray(w.examined), 'world lists');
    check(w.drops && typeof w.drops === 'object' && Object.values(w.drops).every(inBounds), 'world drops');
    check(w.shrineActivated === null || typeof w.shrineActivated === 'string', 'shrine state');
    check(w.respawn === null || inBounds(w.respawn), 'respawn position');
    check(
      Array.isArray(w.ground) && w.ground.every((g) => isStack(g) && isInt(g.uid) && g.uid >= 1 && inBounds(g)),
      'items on the ground',
    );
    if (w.corpses !== undefined) {
      check(w.corpses && typeof w.corpses === 'object' && Object.values(w.corpses).every((c) => inBounds(c) && isInt(c.coins) && c.coins >= 0), 'bodies to loot');
    }
  }
  return errors;
}

export class SaveManager {
  constructor(game) {
    this.game = game;
    this.autosaveEnabled = true;
  }

  serialize() {
    const { player, progression, inventory, worldState } = this.game;
    return {
      version: SAVE_VERSION,
      savedAt: new Date().toISOString(),
      player: {
        position: { x: round(player.position.x), z: round(player.position.z) },
        facing: round(player.facing),
        health: player.health,
        maxHealth: player.maxHealth,
      },
      progression: progression.serialize(),
      inventory: inventory.serialize(),
      world: worldState.serialize(),
      bar: this.game.actionBar.serialize(),
      quests: this.game.quests.serialize(),
    };
  }

  // Returns { ok, reason }. Only reports success once the data reads back.
  save({ manual = false } = {}) {
    const { player } = this.game;
    if (player.dead) return { ok: false, reason: 'You cannot save while defeated.' };
    let text;
    try {
      text = JSON.stringify(this.serialize());
      localStorage.setItem(SAVE_KEY, text);
      if (localStorage.getItem(SAVE_KEY) !== text) throw new Error('read-back mismatch');
    } catch (err) {
      console.warn('Save failed', err);
      return { ok: false, reason: 'The game could not be saved. Browser storage may be full or disabled.' };
    }
    if (manual) this.autosaveEnabled = true; // an explicit save re-enables autosave after a failed load
    return { ok: true };
  }

  hasSave() {
    try {
      return localStorage.getItem(SAVE_KEY) !== null;
    } catch {
      return false;
    }
  }

  // Returns { status: 'none' | 'ok' | 'invalid', data?, errors? }
  read() {
    let text;
    try {
      text = localStorage.getItem(SAVE_KEY);
    } catch (err) {
      return { status: 'invalid', errors: ['storage unavailable'] };
    }
    if (text === null) return { status: 'none' };
    let data;
    try {
      data = JSON.parse(text);
    } catch {
      return { status: 'invalid', errors: ['not valid JSON'], raw: text };
    }
    data = migrateSave(data);
    const errors = validateSave(data);
    if (errors.length) return { status: 'invalid', errors, raw: text };
    return { status: 'ok', data };
  }

  // Keep an unreadable save safe, and stop autosave from replacing it.
  quarantine(raw) {
    this.autosaveEnabled = false;
    try {
      if (raw != null) localStorage.setItem(BACKUP_KEY, raw);
    } catch {
      /* the original is still under SAVE_KEY, untouched */
    }
  }

  apply(data) {
    const { player, progression, inventory, worldState } = this.game;
    worldState.apply(data.world);
    this.game.quests.apply(data.quests, worldState.flags);
    if (data.bar) this.game.actionBar.apply(data.bar);
    progression.apply(data.progression);
    inventory.apply(data.inventory);
    this.game.recomputeMaxHealth();
    player.health = Math.min(data.player.health, player.maxHealth);
    player.placeAt(data.player.position.x, data.player.position.z, data.player.facing);
  }

  autosave() {
    if (!this.autosaveEnabled || !this.game.started) return;
    this.save();
  }
}

function round(n) {
  return Math.round(n * 1000) / 1000;
}

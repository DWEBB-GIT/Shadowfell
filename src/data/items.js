// Items: the database entries (data/items.json, loaded by data/db.js) and
// the rules around them: random rolls, what one particular item is, and what
// a merchant pays for it. Fields of an item record:
//
// name, description
// kind:       weapon | armor | shield | jewellery | torch | tool | bag | consumable | material | junk | document
// slot:       the character slot an equippable item goes into (or finger / trinket)
// armourType: an armour type id (who may wear it: see archetypes.json)
// rarity:     a data/rarities.json id: junk | common | enhanced | rare | epic |
//             legendary | quest (the colour of its name and border)
// reservedFor: the only loot tables that may drop it (a boss's own weapon)
// itemLevel:  gear only: the level its numbers are worked out for. Its armour,
//             a shield's block chance, a weapon's damage per swing and its
//             stat points all come from item level, slot, armour type and
//             rarity (src/data/scaling.js), so gear is never hand-tuned
// statSplit:  how its stat points are shared out, e.g. { strength: 1, stamina: 1 }
//             (shares, not points; white gear has none to share)
// speed:      a weapon's seconds between auto attack swings (haste shortens it)
// damage:     worked out: a weapon's [min, max] per swing (state it only for a special item)
// stats:      worked out: armour, attributes, block chance and haste it gives;
//             a stat stated in the data wins (a special item; the data check
//             flags one more than 10% over budget unless `budgetException`)
// use:        what using it does, e.g. { heal: 42 }
// bagSlots:   slots a bag adds
// light:      a torch's light radius in metres (it lets the Warrior into obscured areas)
// bait:       percent added to the fishing catch chance (one is used per strike)
// stack:      how many fit in one bag slot (1 = does not stack)
// price:      what a merchant asks; merchants pay CONFIG.shop.sellFraction of it
// quest:      quest items cannot be sold or dropped
// model:      Blender model for the world object; icon: model the icon is drawn from

import { DB } from './db.js';
import { STAT_KEYS } from './schema.js';
import { scaledItem, itemBudget, statCost } from './scaling.js';

export { KINDS, RARITIES, EQUIP_SLOTS, ITEM_SLOTS, DURABLE_KINDS, slotFits, validateItems } from './schema.js';
import { DURABLE_KINDS } from './schema.js';
// every item, with gear's numbers worked out from its item level
export const ITEMS = Object.fromEntries(Object.entries(DB.items).map(([id, d]) => [id, scaledItem(d)]));
export const RARITY = DB.rarities; // id -> { name, colour, suffix?, drops? }, lowest first

export const BACKPACK_SLOTS = 16;
export const BAG_SOCKETS = 4; // socket 0 is the backpack and cannot be removed

// ------------------------------------------------------------ random rolls
// Gear that drops from enemies rolls a little, Diablo style: its stats and
// weapon damage move a few points either side of the database values, and
// pieces that drop at a rarity with `suffix` (enhanced) gain a WoW-style
// suffix ("of the Bear"): their magical property, which spends the green
// stat budget of the item's level and slot.
// A stack keeps only what differs from the database, as `rolls`:
//   { stats: { armour: 2 }, damage: [13, 18], suffix: 'bear' }
// so a balance change to the item still reaches items already in bags.

export const SUFFIXES = DB.suffixes;

const ROLLS = { spread: 0.2, damageSpread: 0.12, valuePerPoint: 4 };
const ROLLED_KINDS = ['weapon', 'armor', 'shield', 'jewellery'];

// `rarity` is the rarity it dropped at (its own, unless common gear rolled
// up to enhanced).
export function rollItem(id, rand, rarity = ITEMS[id] && ITEMS[id].rarity) {
  const d = ITEMS[id];
  if (!d || !ROLLED_KINDS.includes(d.kind) || d.quest) return null;
  const r = {};
  const stats = {};
  for (const [k, v] of Object.entries(d.stats || {})) {
    // small numbers stay put; bigger ones move up to 20% either way
    const delta = Math.round(v * ROLLS.spread * (2 * rand() - 1));
    if (delta) stats[k] = delta;
  }
  if (d.damage) {
    const k = 1 + ROLLS.damageSpread * (2 * rand() - 1);
    const lo = Math.max(1, Math.round(d.damage[0] * k));
    const hi = Math.max(lo, Math.round(d.damage[1] * k));
    if (lo !== d.damage[0] || hi !== d.damage[1]) r.damage = [lo, hi];
  }
  if (RARITY[rarity] && RARITY[rarity].suffix && d.rarity === 'common') {
    const keys = Object.keys(SUFFIXES);
    r.suffix = keys[Math.min(keys.length - 1, Math.floor(rand() * keys.length))];
    // the green budget, shared between the suffix's stats, each +-20%
    const sfx = SUFFIXES[r.suffix].stats;
    const points = itemBudget(d, rarity) / sfx.length;
    for (const k of sfx) {
      const v = (points / statCost(k, d.itemLevel)) * (1 + ROLLS.spread * (2 * rand() - 1));
      stats[k] = (stats[k] || 0) + Math.max(1, Math.round(v));
    }
  }
  if (Object.keys(stats).length) r.stats = stats;
  return Object.keys(r).length ? r : null;
}

// What one particular item is: the database entry with its rolls applied.
export function itemView(stack) {
  const v = rolledView(stack);
  // a broken item (durability 0) still shows what it was, but gives nothing
  if (v && stack.dur === 0 && DURABLE_KINDS.includes(v.kind)) return { ...v, stats: {}, broken: true };
  return v;
}

// Durability in percent: a stack keeps `dur` only once it has worn.
export const durability = (stack) => (stack && DURABLE_KINDS.includes(ITEMS[stack.id]?.kind) ? stack.dur ?? 100 : null);

function rolledView(stack) {
  const d = ITEMS[stack.id];
  const r = stack.rolls;
  if (!d || !r) return d;
  const stats = { ...(d.stats || {}) };
  for (const [k, v] of Object.entries(r.stats || {})) {
    const key = RENAMED_STATS[k] || k;
    if (!STAT_KEYS.includes(key)) continue; // block rating, folded into block chance
    stats[key] = (stats[key] || 0) + v;
  }
  for (const k of Object.keys(stats)) if (stats[k] <= 0) delete stats[k];
  // a suffix adds to the price by the stat points its rolls are worth
  const bonus = Object.entries(r.stats || {}).reduce((a, [k, v]) => a + Math.max(0, v) * statCost(RENAMED_STATS[k] || k, d.itemLevel), 0);
  return {
    ...d,
    name: r.suffix ? `${d.name} ${SUFFIXES[r.suffix].name}` : d.name,
    rarity: r.suffix && d.rarity === 'common' ? 'enhanced' : d.rarity,
    stats,
    damage: r.damage ? swingScale(r.damage, d) : d.damage,
    price: d.price + (r.suffix ? Math.round(bonus * ROLLS.valuePerPoint) : 0),
  };
}

// Stats renamed after saves held them in rolls (Might, Finesse, Vitality),
// and block rating, which saves may hold but no longer counts.
const RENAMED_STATS = { might: 'strength', finesse: 'agility', vitality: 'stamina' };
const RETIRED_STATS = ['blockRating'];

// Weapon damage became per swing when weapons gained a speed; rolls saved
// before then (a few points either side of the old, smaller numbers) are
// scaled up to match.
function swingScale(dmg, d) {
  // the 2026-10-15 rebalance cut weapon damage to an eighth; rolls saved
  // before it are far above the item and fall back to its own damage
  if (dmg[0] + dmg[1] > (d.damage[0] + d.damage[1]) * 2) return d.damage;
  if (!d.speed || dmg[0] + dmg[1] > (d.damage[0] + d.damage[1]) * 0.6) return dmg;
  const k = d.speed / 0.6;
  return [Math.round(dmg[0] * k), Math.round(dmg[1] * k)];
}

// Are these rolls well formed? (saves are checked before they are applied)
export function validRolls(id, r) {
  if (r === undefined) return true;
  const d = ITEMS[id];
  if (!d || !r || typeof r !== 'object' || !ROLLED_KINDS.includes(d.kind)) return false;
  const okNum = (v) => Number.isInteger(v) && Math.abs(v) <= 1000;
  if (r.stats !== undefined && !(r.stats && typeof r.stats === 'object' && Object.entries(r.stats).every(([k, v]) => (STAT_KEYS.includes(k) || RENAMED_STATS[k] || RETIRED_STATS.includes(k)) && okNum(v)))) return false;
  if (r.damage !== undefined && !(Array.isArray(r.damage) && r.damage.length === 2 && r.damage.every((v) => Number.isInteger(v) && v >= 1 && v <= 1000) && r.damage[0] <= r.damage[1])) return false;
  if (r.suffix !== undefined && !SUFFIXES[r.suffix]) return false;
  return true;
}

// What a merchant pays for one of an item (a stack, or just an id).
export function sellPrice(item, fraction) {
  const stack = typeof item === 'string' ? { id: item } : item;
  const d = stack && ITEMS[stack.id];
  return d && !d.quest ? Math.floor(itemView(stack).price * fraction) : 0;
}

// What one enemy drops (data/loot_tables.json): every `always` item, then
// `rolls` tries at `chance`, each rolling a rarity by weight and then an item
// from that rarity's list. Returns [{ id, count, rarity }].
export function rollLoot(table, rand) {
  const out = [];
  if (!table) return out;
  for (const { item, min, max } of table.always || []) {
    const n = min + Math.floor(rand() * (max - min + 1));
    if (n > 0) out.push({ id: item, count: n, rarity: ITEMS[item].rarity });
  }
  const drops = table.drops;
  for (let i = 0; drops && i < drops.rolls; i++) {
    if (rand() >= drops.chance) continue;
    // rarities in their order, lowest first, so a roll means the same thing in every table
    const tiers = Object.keys(RARITY).filter((r) => drops.rarity[r]);
    const rarity = pickWeighted(tiers.map((r) => ({ r, weight: drops.rarity[r] })), rand).r;
    out.push({ id: pickWeighted(drops.items[rarity], rand).item, count: 1, rarity });
  }
  return out;
}

function pickWeighted(list, rand) {
  let pick = rand() * list.reduce((a, e) => a + e.weight, 0);
  return list.find((e) => (pick -= e.weight) < 0) || list[list.length - 1];
}

// Loot placed in the world (data/world.json placedLoot).
export const LOOT = DB.world.placedLoot;

// Unique drops: an enemy type with `uniqueDrop` leaves that item where it
// falls, once (the Brute's Watchman's Edge). Keyed by item id, which is also
// how the world state records it.
export const UNIQUE_DROPS = Object.fromEntries(
  Object.values(DB.enemies)
    .filter((e) => e.uniqueDrop)
    .map((e) => {
      const item = DB.items[e.uniqueDrop];
      return [e.uniqueDrop, { id: e.uniqueDrop, model: item.model, prompt: `Take ${item.name}`, reward: { item: e.uniqueDrop }, droppedBy: e.name }];
    }),
);

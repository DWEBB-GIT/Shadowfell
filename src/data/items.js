// The item database. Every item is defined in items.json (one entry per id;
// ids are stable because saves store them). This module loads, checks and
// exposes it. Fields:
//
// name, description
// kind:       weapon | armor | shield | bag | consumable | material | document
// slot:       the character slot an equippable item goes into
// armourType: cloth | leather | mail | plate (who may wear it: see archetypes)
// quality:    poor | common | uncommon | rare | quest (tooltip colour)
// damage:     a weapon's [min, max]
// stats:      attributes, armour, block, block rating, haste it adds
// use:        what using it does, e.g. { heal: 42 }
// bagSlots:   slots a bag adds
// stack:      how many fit in one bag slot (1 = does not stack)
// price:      what a merchant asks; merchants pay CONFIG.shop.sellFraction of it
// quest:      quest items cannot be sold or dropped
// model:      Blender model for the world object; icon: model the icon is drawn from

import DB from './items.json';

export const KINDS = ['weapon', 'armor', 'shield', 'bag', 'consumable', 'material', 'document'];
export const QUALITIES = ['poor', 'common', 'uncommon', 'rare', 'quest'];
const STAT_KEYS = ['might', 'finesse', 'intellect', 'vitality', 'armour', 'resistance', 'block', 'blockRating', 'haste'];

// Problems with the database, as readable strings (empty when it is sound).
export function validateItems(items, slots, armourTypes) {
  const errors = [];
  for (const [id, d] of Object.entries(items)) {
    const bad = (msg) => errors.push(`${id}: ${msg}`);
    if (!/^[a-z0-9_]+$/.test(id)) bad('id must be lower_snake_case');
    if (!d.name || !d.description) bad('needs a name and a description');
    if (!KINDS.includes(d.kind)) bad(`unknown kind ${d.kind}`);
    if (!QUALITIES.includes(d.quality)) bad(`unknown quality ${d.quality}`);
    if (!Number.isInteger(d.stack) || d.stack < 1) bad('stack must be a whole number of at least 1');
    if (!Number.isInteger(d.price) || d.price < 0) bad('price must be a whole number of coins');
    if (!d.model || !d.icon) bad('needs a model and an icon');
    const equips = ['weapon', 'armor', 'shield'].includes(d.kind);
    if (equips && !slots.includes(d.slot)) bad(`unknown slot ${d.slot}`);
    if (!equips && d.slot) bad('only weapons, armour and shields have a slot');
    if (d.kind === 'armor' && d.slot !== 'mainHand' && !armourTypes.includes(d.armourType)) bad('armour needs an armour type');
    if (d.kind === 'weapon' && !(Array.isArray(d.damage) && d.damage.length === 2 && d.damage[0] <= d.damage[1])) bad('a weapon needs damage [min, max]');
    if (d.kind === 'bag' && !(d.bagSlots > 0)) bad('a bag needs bagSlots');
    for (const k of Object.keys(d.stats || {})) if (!STAT_KEYS.includes(k)) bad(`unknown stat ${k}`);
  }
  return errors;
}

export const ITEMS = DB.items;

// Drop tables (data/drops.json) may only name real items and enemy types.
export function validateDrops(drops, enemyTypes) {
  const errors = [];
  for (const [type, t] of Object.entries(drops)) {
    if (type.startsWith('_')) continue;
    if (!enemyTypes.includes(type)) errors.push(`drops: unknown enemy type ${type}`);
    for (const id of Object.keys(t.always || {})) if (!ITEMS[id]) errors.push(`drops.${type}: unknown item ${id}`);
    for (const id of Object.keys((t.gear && t.gear.table) || {})) if (!ITEMS[id]) errors.push(`drops.${type}: unknown item ${id}`);
    if (t.gear && !(t.gear.chance >= 0 && t.gear.chance <= 1)) errors.push(`drops.${type}: chance must be between 0 and 1`);
  }
  return errors;
}

export const EQUIP_SLOTS = [
  { id: 'head', label: 'Head' },
  { id: 'chest', label: 'Chest' },
  { id: 'hands', label: 'Hands' },
  { id: 'legs', label: 'Legs' },
  { id: 'feet', label: 'Feet' },
  { id: 'mainHand', label: 'Main hand' },
  { id: 'offHand', label: 'Off hand' },
];

export const BACKPACK_SLOTS = 16;
export const BAG_SOCKETS = 4; // socket 0 is the backpack and cannot be removed

// ------------------------------------------------------------ random rolls
// Gear that drops from enemies rolls a little, Diablo style: its stats and
// weapon damage move a few points either side of the database values, and
// some pieces gain a WoW-style suffix with a bonus attribute ("of the Bear").
// A stack keeps only what differs from the database, as `rolls`:
//   { stats: { armour: 2 }, damage: [13, 18], suffix: 'bear' }
// so a balance change to the item still reaches items already in bags.

export const SUFFIXES = {
  might: { name: 'of Might', stats: ['might'] },
  vigour: { name: 'of Vigour', stats: ['vitality'] },
  finesse: { name: 'of Finesse', stats: ['finesse'] },
  bear: { name: 'of the Bear', stats: ['might', 'vitality'] },
  tiger: { name: 'of the Tiger', stats: ['might', 'finesse'] },
  swiftness: { name: 'of Swiftness', stats: ['haste'] },
};

const ROLLS = { spread: 0.2, damageSpread: 0.12, suffixChance: 0.35, suffixMax: 2, valuePerPoint: 4 };
const ROLLED_KINDS = ['weapon', 'armor', 'shield'];

export function rollItem(id, rand) {
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
  if (rand() < ROLLS.suffixChance) {
    const keys = Object.keys(SUFFIXES);
    r.suffix = keys[Math.min(keys.length - 1, Math.floor(rand() * keys.length))];
    for (const k of SUFFIXES[r.suffix].stats) stats[k] = (stats[k] || 0) + 1 + Math.floor(rand() * ROLLS.suffixMax);
  }
  if (Object.keys(stats).length) r.stats = stats;
  return Object.keys(r).length ? r : null;
}

// What one particular item is: the database entry with its rolls applied.
export function itemView(stack) {
  const d = ITEMS[stack.id];
  const r = stack.rolls;
  if (!d || !r) return d;
  const stats = { ...(d.stats || {}) };
  for (const [k, v] of Object.entries(r.stats || {})) stats[k] = (stats[k] || 0) + v;
  for (const k of Object.keys(stats)) if (stats[k] <= 0) delete stats[k];
  const bonus = Object.values(r.stats || {}).reduce((a, v) => a + Math.max(0, v), 0);
  return {
    ...d,
    name: r.suffix ? `${d.name} ${SUFFIXES[r.suffix].name}` : d.name,
    quality: r.suffix && d.quality === 'common' ? 'uncommon' : d.quality,
    stats,
    damage: r.damage || d.damage,
    price: d.price + (r.suffix ? bonus * ROLLS.valuePerPoint : 0),
  };
}

// Are these rolls well formed? (saves are checked before they are applied)
export function validRolls(id, r) {
  if (r === undefined) return true;
  const d = ITEMS[id];
  if (!d || !r || typeof r !== 'object' || !ROLLED_KINDS.includes(d.kind)) return false;
  const okNum = (v) => Number.isInteger(v) && Math.abs(v) <= 100;
  if (r.stats !== undefined && !(r.stats && typeof r.stats === 'object' && Object.entries(r.stats).every(([k, v]) => STAT_KEYS.includes(k) && okNum(v)))) return false;
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

// Loot placed in the world. `reward` is what collecting it grants.
export const LOOT = [
  {
    id: 'manifest',
    model: 'manifest',
    position: [-5.3, -4.6],
    heightOffset: 0.9,
    prompt: 'Read the manifest',
    reward: { item: 'manifest' },
    opensDocument: 'manifest',
  },
  {
    id: 'grave_iron',
    model: 'grave_iron',
    position: [-8.4, -1.4],
    heightOffset: 0.05,
    prompt: 'Take the grave-iron',
    reward: { item: 'grave_iron', count: 2 },
  },
  {
    id: 'purse_graves',
    model: 'coin_purse',
    position: [-26.5, 7.5],
    prompt: 'Take the coin purse',
    reward: { coins: 6 },
  },
  {
    id: 'purse_wall',
    model: 'coin_purse',
    position: [9.5, -37.2],
    prompt: 'Take the coin purse',
    reward: { coins: 5 },
  },
  {
    id: 'draught_rocks',
    model: 'draught',
    position: [25.2, 13.2],
    prompt: 'Take the healing draught',
    reward: { item: 'healing_draught' },
  },
  {
    id: 'satchel_ruin',
    model: 'satchel',
    position: [-12.0, -29.6],
    prompt: "Take the traveller's satchel",
    reward: { item: 'travellers_satchel' },
  },
  {
    id: 'helm_rocks',
    model: 'watch_helm',
    position: [28.2, -38.6],
    prompt: 'Take the dented helm',
    reward: { item: 'watch_helm' },
  },
  // the Blackwood
  {
    id: 'purse_den',
    model: 'coin_purse',
    position: [-16.4, -82.8],
    prompt: 'Take the coin purse',
    reward: { coins: 9 },
  },
  {
    id: 'sabatons_camp',
    model: 'plate_sabatons',
    position: [14.2, -91.0],
    prompt: 'Take the blackened sabatons',
    reward: { item: 'plate_sabatons' },
  },
  {
    id: 'draught_glade',
    model: 'draught',
    position: [-10.2, -119.0],
    prompt: 'Take the healing draught',
    reward: { item: 'healing_draught' },
  },
];

// Dropped by the elite when defeated. Its position is recorded on drop.
export const ELITE_DROP = {
  id: 'watchmans_edge',
  model: 'watchmans_edge',
  prompt: "Take Watchman's Edge",
  reward: { item: 'watchmans_edge' },
};

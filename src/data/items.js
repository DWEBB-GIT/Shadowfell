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

export function sellPrice(id, fraction) {
  const d = ITEMS[id];
  return d && !d.quest ? Math.floor(d.price * fraction) : 0;
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
];

// Dropped by the elite when defeated. Its position is recorded on drop.
export const ELITE_DROP = {
  id: 'watchmans_edge',
  model: 'watchmans_edge',
  prompt: "Take Watchman's Edge",
  reward: { item: 'watchmans_edge' },
};

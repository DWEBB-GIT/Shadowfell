// Item definitions. Ids are stable: they are written into save files.
//
// kind:  weapon | armor | shield | bag | consumable | material | document
// slot:  the character slot an equippable item goes into
// stack: how many fit in one bag slot (1 = does not stack)
// model: Blender model used for the world object and the generated icon
// damage: a weapon's [min, max]; stats: attributes, armour, block, haste it adds
// armourType: cloth | leather | mail | plate (who may wear it: see archetypes)

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

export const ITEMS = {
  worn_longsword: {
    name: 'Worn longsword',
    kind: 'weapon',
    slot: 'mainHand',
    damage: [12, 16],
    stack: 1,
    model: 'worn_sword',
    description: 'Your own blade. Nicked, honest and in need of a whetstone.',
  },
  watchmans_edge: {
    name: "Watchman's Edge",
    kind: 'weapon',
    slot: 'mainHand',
    damage: [16, 22],
    stats: { haste: 4 },
    stack: 1,
    model: 'watchmans_edge',
    description: 'A soldier\'s sword in better repair than its last owner. The watch sigil is still legible on the guard.',
  },
  travelling_clothes: {
    name: 'Travelling clothes',
    kind: 'armor',
    slot: 'chest',
    armourType: 'leather',
    stats: { armour: 20 },
    stack: 1,
    model: 'clothes',
    description: 'Wool and leather, patched at the elbows. Keeps the rain off, mostly.',
  },
  watch_helm: {
    name: 'Dented watch helm',
    kind: 'armor',
    slot: 'head',
    armourType: 'mail',
    stats: { armour: 10, vitality: 1 },
    stack: 1,
    model: 'watch_helm',
    description: 'An iron cap from the old garrison. Someone took a blow in it and walked away.',
  },
  kite_shield: {
    name: 'Battered kite shield',
    kind: 'shield',
    slot: 'offHand',
    stats: { block: 10 },
    stack: 1,
    model: 'kite_shield',
    description: 'Oak boards under a skin of hide, rimmed in iron. It has turned a good many blows.',
  },
  travellers_satchel: {
    name: "Traveller's satchel",
    kind: 'bag',
    bagSlots: 8,
    stack: 1,
    model: 'satchel',
    description: 'A sturdy shoulder bag. Place it in an empty bag slot to carry more.',
  },
  healing_draught: {
    name: 'Healing draught',
    kind: 'consumable',
    stack: 5,
    model: 'draught',
    description: 'A small bottle of something bitter and red. Restores 42 health.',
  },
  grave_iron: {
    name: 'Grave-iron bar',
    kind: 'material',
    stack: 10,
    model: 'grave_iron',
    description: 'A short bar of dark iron, cold to the touch and stamped with a smith\'s mark.',
  },
  manifest: {
    name: 'Carriage manifest',
    kind: 'document',
    stack: 1,
    model: 'manifest',
    description: 'A carter\'s manifest, damp at the edges. The driver\'s name has been scratched out.',
  },
};

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

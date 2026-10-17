// The shape of the game's data (the JSON files in /data) and the checks that
// keep it sound. Pure functions that import only the pure scaling formulas,
// so the same checks run in the game at start-up and in Node
// (tests/validate-data.mjs) before a commit.
//
// The rules, in short:
//   * every record has a lower_snake_case `id`, unique within its file
//   * records point at each other by id only, and every id they name exists
//   * numbers are numbers, required fields are present, enums are known
// Each check returns readable strings such as
//   "loot_tables.json ghoul: gear entry names unknown item iron_glvoes".

import { SCALING, isScaledItem, itemSpend, overBudget } from './scaling.js';

export const KINDS = ['weapon', 'armor', 'shield', 'jewellery', 'torch', 'tool', 'key', 'bag', 'ammo', 'consumable', 'material', 'junk', 'document'];
// rarity ids, lowest first (data/rarities.json holds their names and colours)
export const RARITIES = ['junk', 'common', 'enhanced', 'rare', 'epic', 'legendary', 'quest'];
const GEAR = ['weapon', 'armor', 'shield'];
const EQUIPPABLE = ['weapon', 'armor', 'shield', 'jewellery', 'torch'];
export const STAT_KEYS = ['stamina', 'strength', 'agility', 'intellect', 'armour', 'resistance', 'block', 'haste'];
// Character slots, laid out as in WoW: `col` is where the panel shows it.
// An item's `slot` names the slot it goes in, or a slot type (`fits`) when
// there are two of them: a ring goes on either finger, a trinket in either
// trinket slot.
export const EQUIP_SLOTS = [
  { id: 'head', label: 'Head', col: 'left' },
  { id: 'neck', label: 'Neck', col: 'left' },
  { id: 'shoulders', label: 'Shoulder', col: 'left' },
  { id: 'back', label: 'Back', col: 'left' },
  { id: 'chest', label: 'Chest', col: 'left' },
  { id: 'wrists', label: 'Wrists', col: 'left' },
  { id: 'hands', label: 'Hands', col: 'left' },
  { id: 'waist', label: 'Waist', col: 'right' },
  { id: 'legs', label: 'Legs', col: 'right' },
  { id: 'feet', label: 'Feet', col: 'right' },
  { id: 'finger1', label: 'Finger', fits: 'finger', col: 'right' },
  { id: 'finger2', label: 'Finger', fits: 'finger', col: 'right' },
  { id: 'trinket1', label: 'Trinket', fits: 'trinket', col: 'right' },
  { id: 'trinket2', label: 'Trinket', fits: 'trinket', col: 'right' },
  // a one-handed weapon (slot `oneHand`) goes in either hand; the off hand
  // only for a class that can dual wield
  { id: 'mainHand', label: 'Main hand', col: 'bottom', also: ['oneHand'] },
  { id: 'offHand', label: 'Off hand', col: 'bottom', also: ['oneHand'] },
  // a bow, for Auto Shot at targets beyond melee reach (any class, as in WoW)
  { id: 'ranged', label: 'Ranged', col: 'bottom' },
];
// what an item's `slot` may say: a slot id, or a slot type
export const ITEM_SLOTS = [...new Set(EQUIP_SLOTS.flatMap((s) => [s.fits || s.id, ...(s.also || [])]))];
// does an item with this `slot` go in that character slot?
export const slotFits = (slotId, itemSlot) => {
  const s = EQUIP_SLOTS.find((x) => x.id === slotId);
  return !!s && (s.id === itemSlot || s.fits === itemSlot || (s.also || []).includes(itemSlot));
};
// what wears out: weapons, armour and shields (and jewellery)
export const DURABLE_KINDS = ['weapon', 'armor', 'shield', 'jewellery'];
const ABILITY_TARGETS = ['enemy', 'ground', 'self'];
const SCHOOLS = ['physical', 'shadow', 'holy', 'nature'];
// Spells run by the generic spell engine (src/systems/spells.js): the tuning
// numbers each kind needs, and whether it goes on an enemy.
export const SPELL_KINDS = {
  cast: { enemy: true, tuning: ['castTime', 'damageMin', 'damageMax', 'projectileSpeed'] },
  dot: { enemy: true, tuning: ['duration', 'tickInterval', 'tickMultiplier'] },
  instant: { enemy: true, tuning: ['damageMin', 'damageMax'] },
  aoe: { enemy: false, tuning: ['radius', 'duration', 'tickInterval', 'damageMin', 'damageMax'] },
  cleave: { enemy: false, tuning: ['damageMultiplier', 'coneDegrees', 'range', 'maxTargets', 'windup'] },
  burst: { enemy: false, tuning: ['damageMultiplier', 'radius', 'windup', 'stagger', 'knockback'] }, // optional interrupts: 1
  charge: { enemy: true, tuning: ['damageMultiplier', 'distance', 'duration', 'hitRadius'] },
  guard: { enemy: false, tuning: ['window'] }, // Brace: the next blow within `window` s is turned aside
  interrupt: { enemy: true, tuning: ['lockout', 'damageMin', 'damageMax'] }, // breaks an interruptible enemy cast
  buff: { enemy: false, tuning: ['duration', 'damageBonus'] },
  camp: { enemy: false, tuning: ['castTime'] }, // Set Camp: a cast, then the camp is pitched
};
const ID = /^[a-z][a-z0-9_]*$/;
// models built in code (src/assets/fallback.js) rather than in Blender
const PROCEDURAL_MODELS = ['training_dummy', 'town_board'];
const ABILITY_ID = /^[a-z][a-zA-Z0-9]*$/; // abilities are camelCase, as saved spell bars use them

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isInt = (v) => Number.isInteger(v);
const isStr = (v) => typeof v === 'string' && v.length > 0;
const isStrList = (v) => Array.isArray(v) && v.every(isStr);
const isVec2 = (v) => Array.isArray(v) && v.length === 2 && v.every(isNum);

// Turn a list of records into a map by id, noting missing and repeated ids.
export function indexById(list, where, errors, idPattern = ID) {
  const map = {};
  if (!Array.isArray(list)) {
    errors.push(`${where}: expected a list of records`);
    return map;
  }
  list.forEach((r, i) => {
    if (!r || typeof r !== 'object') return errors.push(`${where} #${i + 1}: not a record`);
    if (!isStr(r.id) || !idPattern.test(r.id)) return errors.push(`${where} #${i + 1}: id "${r.id}" must be ${idPattern === ID ? 'lower_snake_case' : 'camelCase'}`);
    if (map[r.id]) errors.push(`${where}: duplicate id ${r.id}`);
    map[r.id] = r;
  });
  return map;
}

// Item records as a map, checked on their own (the item database check the
// game has always run; the tests also feed it deliberately broken items).
export function validateItems(items, slots, armourTypes, rarities = RARITIES) {
  const errors = [];
  for (const [id, d] of Object.entries(items)) {
    const bad = (msg) => errors.push(`${id}: ${msg}`);
    if (!ID.test(id)) bad('id must be lower_snake_case');
    if (!d.name || !d.description) bad('needs a name and a description');
    if (!KINDS.includes(d.kind)) bad(`unknown kind ${d.kind}`);
    if (!rarities.includes(d.rarity)) bad(`unknown rarity ${d.rarity}`);
    if (d.quest && d.rarity !== 'quest') bad('a quest item has the quest rarity');
    if (!isInt(d.stack) || d.stack < 1) bad('stack must be a whole number of at least 1');
    if (!isInt(d.price) || d.price < 0) bad('price must be a whole number of coins');
    if (!d.model || !d.icon) bad('needs a model and an icon');
    const equips = EQUIPPABLE.includes(d.kind);
    if (equips && !slots.includes(d.slot)) bad(`unknown slot ${d.slot}`);
    if (!equips && d.slot) bad('only weapons, armour and shields have a slot');
    if (d.kind === 'armor' && !armourTypes.includes(d.armourType)) bad('armour needs an armour type');
    if (d.armourType && !armourTypes.includes(d.armourType)) bad(`unknown armour type ${d.armourType}`);
    // gear's numbers come from its item level (src/data/scaling.js)
    if (GEAR.includes(d.kind) || d.kind === 'jewellery') {
      if (!(isInt(d.itemLevel) && d.itemLevel >= 1)) bad('gear needs an itemLevel (a whole number of at least 1)');
      for (const [k, v] of Object.entries(d.statSplit || {})) {
        if (!STAT_KEYS.includes(k)) bad(`statSplit names unknown stat ${k}`);
        else if (!(isNum(v) && v > 0)) bad(`statSplit ${k} must be a share above 0`);
      }
      const r = SCALING.rarity[d.rarity];
      if (d.statSplit && r && !r.budget) bad(`a ${d.rarity} item has no stat points to split`);
      if (isScaledItem(d) && rarities.includes(d.rarity) && overBudget(d)) {
        const { budget, spent } = itemSpend(d);
        bad(`spends ${spent.toFixed(1)} stat points of its ${budget.toFixed(1)} (or states damage above its item level's); mark it budgetException if that is meant`);
      }
    }
    if (d.damage !== undefined && !(Array.isArray(d.damage) && d.damage.length === 2 && d.damage.every(isNum) && d.damage[0] <= d.damage[1])) bad('damage must be [min, max]');
    if (d.kind === 'weapon' && !(isNum(d.speed) && d.speed >= 1 && d.speed <= 5)) bad('a weapon needs a swing speed in seconds (1 to 5)');
    if (d.slot === 'ranged' && !(isNum(d.range) && d.range >= 8 && d.range <= 40)) bad('a ranged weapon needs a range in metres (8 to 40)');
    if (d.kind === 'bag' && !(d.bagSlots > 0)) bad('a bag needs bagSlots');
    // a quiver: a bag that holds only arrows and quickens Auto Shot
    if (d.holds !== undefined && !(d.kind === 'bag' && KINDS.includes(d.holds))) bad('holds must name an item kind, on a bag');
    if (d.rangedHaste !== undefined && !(d.holds === 'ammo' && isNum(d.rangedHaste) && d.rangedHaste > 0 && d.rangedHaste <= 30)) bad('rangedHaste (percent, up to 30) is for a quiver (a bag that holds ammo)');
    // arrows: used one a shot, adding `ammoDps` damage a second of bow speed
    if (d.kind === 'ammo' && !(isNum(d.ammoDps) && d.ammoDps >= 0)) bad('ammo needs ammoDps (damage a second it adds)');
    if (d.buyCount !== undefined && !(isInt(d.buyCount) && d.buyCount > 1 && d.buyCount <= d.stack)) bad('buyCount (how many a vendor sells at the price) must be a whole number from 2 to the stack size');
    if (d.kind === 'torch' && !(isNum(d.light) && d.light > 0)) bad('a torch needs light (metres)');
    if (d.bait !== undefined && !(isNum(d.bait) && d.bait > 0)) bad('bait must be a bonus to fishing skill above 0');
    if (d.fishingSkill !== undefined && !(isNum(d.fishingSkill) && d.fishingSkill > 0)) bad('fishingSkill must be a bonus to fishing skill above 0');
    for (const [k, v] of Object.entries(d.stats || {})) {
      if (!STAT_KEYS.includes(k)) bad(`unknown stat ${k}`);
      else if (!isNum(v)) bad(`stat ${k} must be a number`);
    }
  }
  return errors;
}

// Check every data file together. `raw` holds each file's parsed JSON by
// file name; `opts.models` (optional) is the list of model names that exist,
// so a typo in a model name is caught too.
export function validateGameData(raw, opts = {}) {
  const errors = [];
  const need = (file) => {
    if (!raw[file] || typeof raw[file] !== 'object') errors.push(`${file}: missing`);
    return raw[file] || {};
  };
  const itemsF = need('items.json');
  const archF = need('archetypes.json');
  const abilF = need('abilities.json');
  const enemF = need('enemies.json');
  const lootF = need('loot_tables.json');
  const rarF = need('rarities.json');
  const shopF = need('shops.json');
  const npcF = need('npcs.json');
  const questF = need('quests.json');
  const dialF = need('dialogue.json');
  const worldF = need('world.json');
  const sceneF = need('scenery.json');
  const textF = need('text.json');
  const skillF = need('skills.json');

  const armourTypes = indexById(itemsF.armourTypes, 'items.json armourTypes', errors);
  const suffixes = indexById(itemsF.suffixes, 'items.json suffixes', errors);
  const rarities = indexById(rarF.rarities, 'rarities.json', errors);
  const skills = indexById(skillF.skills, 'skills.json', errors);
  const facF = need('factions.json');
  const factions = indexById(facF.factions || [], 'factions.json', errors);
  if (!Array.isArray(facF.standings) || !facF.standings.length || facF.standings.some((t, i) => !isStr(t.name) || !isNum(t.min) || !isNum(t.discount) || (i && t.min <= facF.standings[i - 1].min))) errors.push('factions.json: standings need a name, a rising min and a discount');
  const repRefs = (w, map) => {
    if (map === undefined) return;
    if (!map || typeof map !== 'object') return errors.push(`${w}: reputation must map faction ids to points`);
    for (const [f, n] of Object.entries(map)) {
      ref(w + ' reputation', 'faction', factions, f);
      if (!isInt(n)) errors.push(`${w}: reputation with ${f} must be a whole number`);
    }
  };
  const items = indexById(itemsF.items, 'items.json items', errors);
  const archetypes = indexById(archF.archetypes, 'archetypes.json', errors);
  const abilities = indexById(abilF.abilities, 'abilities.json', errors, ABILITY_ID);
  const enemies = indexById(enemF.enemies, 'enemies.json', errors);
  const lootTables = indexById(lootF.lootTables, 'loot_tables.json', errors);
  const vendorTypes = indexById(shopF.vendorTypes, 'shops.json vendorTypes', errors);
  const shops = indexById(shopF.shops, 'shops.json shops', errors);
  const npcs = indexById(npcF.npcs, 'npcs.json', errors);
  const quests = indexById(questF.quests, 'quests.json', errors);
  const spawns = indexById(worldF.enemySpawns, 'world.json enemySpawns', errors);
  const placed = indexById(worldF.placedLoot, 'world.json placedLoot', errors);
  const shrines = indexById(worldF.shrines, 'world.json shrines', errors);
  const regions = indexById(worldF.regions, 'world.json regions', errors);
  const locations = indexById(worldF.locations || [], 'world.json locations', errors);
  const dialogues = indexById(dialF.dialogues, 'dialogue.json', errors);
  const documents = (textF.documents && typeof textF.documents === 'object') ? textF.documents : {};
  const examine = (textF.examine && typeof textF.examine === 'object') ? textF.examine : {};

  const ref = (where, what, table, id) => {
    if (!table[id]) errors.push(`${where}: names unknown ${what} ${id}`);
  };
  const model = (where, name) => {
    if (!isStr(name)) errors.push(`${where}: needs a model`);
    else if (opts.models && !opts.models.includes(name) && !PROCEDURAL_MODELS.includes(name)) errors.push(`${where}: model ${name} does not exist in assets/models`);
  };

  // ---- items
  for (const id of RARITIES) if (!rarities[id]) errors.push(`rarities.json: missing the ${id} rarity`);
  for (const [id, r] of Object.entries(rarities)) {
    if (!RARITIES.includes(id)) errors.push(`rarities.json ${id}: unknown rarity (the engine knows ${RARITIES.join(', ')})`);
    if (!isStr(r.name) || !/^#[0-9a-f]{6}$/i.test(r.colour || '')) errors.push(`rarities.json ${id}: needs a name and a #rrggbb colour`);
  }
  for (const e of validateItems(items, ITEM_SLOTS, Object.keys(armourTypes), Object.keys(rarities))) errors.push('items.json ' + e);
  // an item kept for certain loot tables (a boss's own blade) drops from those alone
  for (const [id, d] of Object.entries(items)) for (const t of d.reservedFor || []) ref(`items.json ${id} reservedFor`, 'loot table', lootTables, t);
  for (const [id, d] of Object.entries(items)) {
    model(`items.json ${id}`, d.model);
    model(`items.json ${id} icon`, d.icon);
    const food = d.use?.food;
    if (d.use && !((isNum(d.use.heal) && d.use.heal > 0) || (food && isNum(food.heal) && food.heal > 0 && isNum(food.seconds) && food.seconds > 0))) errors.push(`items.json ${id}: use must say what it does, e.g. { "heal": 42 } or { "food": { "heal": 60, "seconds": 15 } }`);
  }
  for (const [id, s] of Object.entries(suffixes)) {
    if (!isStr(s.name)) errors.push(`items.json suffix ${id}: needs a name`);
    if (!Array.isArray(s.stats) || !s.stats.length || !s.stats.every((k) => STAT_KEYS.includes(k))) errors.push(`items.json suffix ${id}: stats must list known stats`);
  }

  // ---- archetypes
  for (const [id, a] of Object.entries(archetypes)) {
    const w = `archetypes.json ${id}`;
    if (!isStr(a.name)) errors.push(`${w}: needs a name`);
    if (!STAT_KEYS.includes(a.mainStat)) errors.push(`${w}: unknown main stat ${a.mainStat}`);
    for (const k of Object.keys({ ...a.base, ...a.perLevel })) if (!STAT_KEYS.includes(k)) errors.push(`${w}: unknown stat ${k}`);
    for (const t of a.armourTypes || []) ref(w, 'armour type', armourTypes, t);
    ref(w, 'ability', abilities, a.defensive);
    const r = a.resources || {};
    if (r.mana && !['base', 'perIntellect', 'regenPerSecond', 'regenOutOfCombat'].every((k) => isNum(r.mana[k]))) errors.push(`${w}: mana needs base, perIntellect, regenPerSecond and regenOutOfCombat`);
    if (r.gauge && (!isStr(r.gauge.id) || !isStr(r.gauge.name) || !['max', 'perSwing', 'perHitTaken', 'perBlock', 'decayAfter', 'decayPerSecond'].every((k) => isNum(r.gauge[k])))) errors.push(`${w}: the gauge needs an id, a name and max, perSwing, perHitTaken, perBlock, decayAfter and decayPerSecond`);
  }
  // every resource some class has: what ability costs may name
  const RESOURCE_IDS = new Set(['mana', ...Object.values(archetypes).map((a) => a.resources?.gauge?.id).filter(Boolean)]);

  // ---- abilities
  if (!isNum(abilF.globalCooldown)) errors.push('abilities.json: globalCooldown must be a number');
  for (const k of ['spellQueueWindow', 'castPushback', 'maxPushbacks']) if (!isNum(abilF[k]) || abilF[k] < 0) errors.push(`abilities.json: ${k} must be a number of at least 0`);
  for (const [id, a] of Object.entries(abilities)) {
    const w = `abilities.json ${id}`;
    if (!isStr(a.name) || !isStr(a.desc)) errors.push(`${w}: needs a name and a desc`);
    if (!ABILITY_TARGETS.includes(a.target)) errors.push(`${w}: target must be one of ${ABILITY_TARGETS.join(', ')}`);
    if (a.target === 'enemy' && !isNum(a.range)) errors.push(`${w}: an enemy-targeted ability needs a range`);
    if (a.item) ref(w, 'item', items, a.item);
    if (a.requiresItem) ref(w, 'item', items, a.requiresItem);
    if (a.skill) ref(w, 'skill', skills, a.skill);
    if (!a.tuning || typeof a.tuning !== 'object' || !Object.values(a.tuning).every(isNum)) errors.push(`${w}: tuning must be a set of numbers`);
    if (a.school && !SCHOOLS.includes(a.school)) errors.push(`${w}: unknown school ${a.school}`);
    for (const f of ['cost', 'gain']) {
      if (a[f] === undefined) continue;
      if (typeof a[f] !== 'object' || !Object.values(a[f]).every((n) => isNum(n) && n > 0)) errors.push(`${w}: ${f} must be resource amounts above 0`);
      else for (const k of Object.keys(a[f])) if (!RESOURCE_IDS.has(k)) errors.push(`${w}: ${f} names an unknown resource ${k}`);
    }
    if (a.kind !== undefined) {
      const k = SPELL_KINDS[a.kind];
      if (!k) errors.push(`${w}: kind must be one of ${Object.keys(SPELL_KINDS).join(', ')}`);
      else {
        if (k.enemy !== (a.target === 'enemy')) errors.push(`${w}: a ${a.kind} spell must target ${k.enemy ? 'an enemy' : 'self'}`);
        // a bow ability (`ranged`) is an instant or dot from a bow roll:
        // an instant needs damageMultiplier instead of its own damage range
        if (a.ranged !== undefined && (a.ranged !== true || !['instant', 'dot'].includes(a.kind))) errors.push(`${w}: ranged: true is only for instant and dot spells`);
        const need = a.ranged === true && a.kind === 'instant' ? ['damageMultiplier'] : k.tuning;
        for (const t of ['cooldown', ...need]) if (!isNum(a.tuning?.[t]) || a.tuning[t] < 0) errors.push(`${w}: a ${a.kind} spell needs tuning.${t} of at least 0`);
        if (isNum(a.tuning?.damageMin) && a.tuning.damageMax < a.tuning.damageMin) errors.push(`${w}: damageMax is below damageMin`);
      }
    }
  }

  // ---- enemies and loot tables
  if (!isNum(enemF.leashDistance)) errors.push('enemies.json: leashDistance must be a number');
  for (const [id, e] of Object.entries(enemies)) {
    const w = `enemies.json ${id}`;
    if (!isStr(e.name)) errors.push(`${w}: needs a name`);
    model(w, e.model);
    repRefs(`enemies.json ${e.id}`, e.reputation);
    if (e.respawn !== undefined && !(isNum(e.respawn) && e.respawn >= 0)) errors.push(`enemies.json ${e.id}: respawn must be seconds (0 = never)`);
    // a type sizes health, damage, attack speed and armour from the level
    // (src/data/scaling.js); a number stated in the record wins
    const type = SCALING.enemyTypes[e.type];
    if (e.type !== undefined && !type) errors.push(`${w}: type must be one of ${Object.keys(SCALING.enemyTypes).join(', ')}`);
    if (e.armourClass !== undefined && SCALING.armourClasses[e.armourClass] === undefined) errors.push(`${w}: armourClass must be one of ${Object.keys(SCALING.armourClasses).join(', ')}`);
    const sized = { health: 'health', damage: 'hit', attackInterval: 'interval' };
    for (const k of ['level', 'health', 'damage', 'attackInterval', 'windup', 'detection', 'meleeRange', 'speed', 'radius', 'xp', 'coins']) {
      if (e[k] === undefined && type && type[sized[k]] !== undefined) continue;
      if (!isNum(e[k]) || e[k] < 0) errors.push(`${w}: ${k} must be a number of at least 0${sized[k] ? ' (or give the enemy a type that sizes it)' : ''}`);
    }
    if (e.armour !== undefined && !(isNum(e.armour) && e.armour >= 0)) errors.push(`${w}: armour must be a number of at least 0`);
    if (e.lootTable) ref(w, 'loot table', lootTables, e.lootTable);
    if (e.uniqueDrop) ref(w, 'item', items, e.uniqueDrop);
    if (e.ranged && !(isNum(e.ranged.range) && (isNum(e.ranged.damage) || type?.hit !== undefined) && isNum(e.ranged.windup))) errors.push(`${w}: ranged needs range, damage (or a type) and windup`);
    if (e.special && !(isNum(e.special.damage) || type?.special !== undefined)) errors.push(`${w}: special needs damage (or an elite, heavy or boss type)`);
    if (e.circle && !isNum(e.circle.damage)) errors.push(`${w}: circle needs damage`);
    for (const att of [e.ranged, e.circle]) if (att && att.school && !SCHOOLS.includes(att.school)) errors.push(`${w}: unknown school ${att.school}`);
    if ((e.ranged?.mana || e.circle?.mana) && !(e.mana > 0)) errors.push(`${w}: spends mana but has none`);
  }
  for (const [id, t] of Object.entries(lootTables)) {
    const w = `loot_tables.json ${id}`;
    for (const a of t.always || []) {
      ref(w + ' always', 'item', items, a.item);
      if (items[a.item] && items[a.item].quest) errors.push(`${w}: quest item ${a.item} cannot be loot`);
      if (!(isInt(a.min) && isInt(a.max) && a.min >= 0 && a.min <= a.max)) errors.push(`${w}: always ${a.item} needs whole min <= max`);
    }
    // the rarity roll, then the item roll from that rarity's list
    const drops = t.drops;
    if (drops) {
      if (!(isInt(drops.rolls) && drops.rolls >= 1)) errors.push(`${w}: drops.rolls must be a whole number of at least 1`);
      if (!(isNum(drops.chance) && drops.chance >= 0 && drops.chance <= 1)) errors.push(`${w}: drops.chance must be between 0 and 1`);
      const weights = drops.rarity || {};
      const lists = drops.items || {};
      for (const [r, wt] of Object.entries(weights)) {
        if (!rarities[r] || rarities[r].drops === false) errors.push(`${w}: rarity ${r} cannot drop`);
        if (!(isNum(wt) && wt > 0)) errors.push(`${w}: rarity ${r} needs a weight above 0`);
        if (!Array.isArray(lists[r]) || !lists[r].length) errors.push(`${w}: rarity ${r} has no items to roll`);
      }
      if (!Object.keys(weights).length) errors.push(`${w}: drops.rarity needs at least one rarity`);
      for (const [r, list] of Object.entries(lists)) {
        if (!(r in weights)) errors.push(`${w}: items listed for ${r}, which this table never rolls`);
        for (const e of Array.isArray(list) ? list : []) {
          ref(`${w} ${r} entry`, 'item', items, e.item);
          if (!(isNum(e.weight) && e.weight > 0)) errors.push(`${w}: ${r} entry ${e.item} needs a weight above 0`);
          const d = items[e.item];
          if (!d) continue;
          // common gear may roll up to enhanced (it gains a suffix); otherwise an item drops at its own rarity
          const rollsUp = r === 'enhanced' && d.rarity === 'common' && GEAR.includes(d.kind);
          if (d.rarity !== r && !rollsUp) errors.push(`${w}: ${e.item} is ${d.rarity} and cannot be listed under ${r}`);
        }
      }
    }
    const named = [...(t.always || []), ...Object.values(drops?.items || {}).flat()].map((e) => e && e.item);
    for (const it of named) {
      const res = items[it] && items[it].reservedFor;
      if (res && !res.includes(id)) errors.push(`${w}: ${it} is kept for ${res.join(', ')} and cannot drop here`);
    }
  }

  // ---- skills: learned from a trainer, they unlock abilities
  for (const [id, s] of Object.entries(skills)) {
    const w = `skills.json ${id}`;
    if (!isStr(s.name) || !isStr(s.desc)) errors.push(`${w}: needs a name and a desc`);
    ref(w, 'trainer npc', npcs, s.trainer);
    if (!(isInt(s.cost) && s.cost >= 0)) errors.push(`${w}: cost must be a whole number of coins`);
    if (s.maxRank !== undefined && !(isInt(s.maxRank) && s.maxRank >= 1)) errors.push(`${w}: maxRank must be a whole number of at least 1`);
    for (const ab of s.teaches || []) {
      ref(w, 'ability', abilities, ab);
      if (abilities[ab] && abilities[ab].skill !== id) errors.push(`${w}: teaches ${ab}, which does not name ${id} as its skill`);
    }
  }

  // ---- shops and npcs
  for (const [id, v] of Object.entries(vendorTypes)) {
    if (!isStr(v.name)) errors.push(`shops.json vendor type ${id}: needs a name`);
    for (const k of v.sells || []) if (!KINDS.includes(k)) errors.push(`shops.json vendor type ${id}: unknown item kind ${k}`);
  }
  for (const [id, s] of Object.entries(shops)) {
    const w = `shops.json ${id}`;
    ref(w, 'vendor type', vendorTypes, s.vendorType);
    if (s.faction !== undefined) ref(w, 'faction', factions, s.faction);
    const vt = vendorTypes[s.vendorType];
    for (const it of s.stock || []) {
      ref(w + ' stock', 'item', items, it);
      if (items[it] && items[it].quest) errors.push(`${w}: quest item ${it} cannot be sold`);
      if (items[it] && items[it].reservedFor) errors.push(`${w}: ${it} is a boss's own drop and cannot be sold`);
      if (items[it] && vt && !(vt.sells || []).includes(items[it].kind)) errors.push(`${w}: a ${vt.name} does not sell ${items[it].kind} (${it})`);
    }
  }
  for (const [id, n] of Object.entries(npcs)) {
    const w = `npcs.json ${id}`;
    if (!isStr(n.name)) errors.push(`${w}: needs a name`);
    if (!(Number.isInteger(n.level) && n.level >= 1)) errors.push(`${w}: needs a level (a whole number, 1 or more)`);
    model(w, n.model);
    if (n.shop) ref(w, 'shop', shops, n.shop);
    if (n.dialogue !== undefined) ref(w, 'dialogue', dialogues, n.dialogue);
  }

  // ---- quests
  const QUEST_STATUSES = ['not_started', 'available', 'active', 'ready', 'done'];
  const condition = (where, c) => {
    if (c === undefined) return;
    if (!c || typeof c !== 'object') return errors.push(`${where}: a condition must be an object`);
    const keys = Object.keys(c);
    if (!keys.length || keys.some((k) => !['quest', 'status', 'flag', 'examined'].includes(k))) errors.push(`${where}: a condition is { quest, status }, { flag } or { examined }`);
    if (c.quest !== undefined) {
      ref(where, 'quest', quests, c.quest);
      if (!QUEST_STATUSES.includes(c.status)) errors.push(`${where}: quest status must be one of ${QUEST_STATUSES.join(', ')}`);
    }
    if (c.flag !== undefined && !isStr(c.flag)) errors.push(`${where}: flag must be a name`);
    if (c.examined !== undefined && !examine[c.examined]) errors.push(`${where}: names unknown examine point ${c.examined}`);
  };
  for (const [id, q] of Object.entries(quests)) {
    const w = `quests.json ${id}`;
    for (const k of ['name', 'summary', 'progress', 'complete']) if (!isStr(q[k])) errors.push(`${w}: needs ${k}`);
    if (!q.autoAccept && !isStr(q.offer)) errors.push(`${w}: needs an offer (what the giver says)`);
    ref(w, 'giver npc', npcs, q.giver);
    ref(w, 'turn-in npc', npcs, q.turnIn);
    for (const r of q.requires || []) {
      ref(w + ' requires', 'quest', quests, r);
      if (r === id) errors.push(`${w}: cannot require itself`);
    }
    const objectives = indexById(q.objectives, w + ' objectives', errors);
    if (!Object.keys(objectives).length) errors.push(`${w}: needs at least one objective`);
    for (const [oid, o] of Object.entries(objectives)) {
      const ow = `${w} objective ${oid}`;
      if (!isStr(o.label)) errors.push(`${ow}: needs a label`);
      if (o.type === 'kill') ref(ow, 'enemy type', enemies, o.target);
      else if (o.type === 'collect') ref(ow, 'item', items, o.target);
      else if (o.type === 'examine') {
        if (!examine[o.target]) errors.push(`${ow}: names unknown examine point ${o.target}`);
      } else errors.push(`${ow}: type must be kill, collect or examine`);
      if (o.count !== undefined && !(isInt(o.count) && o.count >= 1)) errors.push(`${ow}: count must be a whole number of at least 1`);
      if (o.type === 'kill' && enemies[o.target]) {
        const placedCount = Object.values(spawns).filter((s) => s.enemy === o.target).length;
        if ((o.count || 1) > placedCount) errors.push(`${ow}: needs ${o.count || 1} ${o.target} but the world only has ${placedCount}`);
      }
      if (o.location !== undefined) ref(ow, 'location', locations, o.location);
    }
    const r = q.reward || {};
    repRefs(w, r.reputation);
    if (!(isInt(r.coins ?? 0) && isInt(r.xp ?? 0))) errors.push(`${w}: reward coins and xp must be whole numbers`);
    for (const it of r.items || []) {
      ref(w + ' reward', 'item', items, it.item);
      if (!(isInt(it.count ?? 1) && (it.count ?? 1) >= 1)) errors.push(`${w} reward: item count must be a whole number`);
    }
    if (q.setsFlag !== undefined && !isStr(q.setsFlag)) errors.push(`${w}: setsFlag must be a name`);
  }
  // a quest that requires itself, however far round, can never be offered
  const seen = {};
  const loops = (id, path) => {
    if (path.includes(id)) return true;
    if (seen[id] !== undefined) return seen[id];
    return (seen[id] = (quests[id]?.requires || []).some((r) => quests[r] && loops(r, [...path, id])));
  };
  for (const id of Object.keys(quests)) if (loops(id, [])) errors.push(`quests.json ${id}: its requirements loop back to it`);

  // ---- dialogue
  for (const [id, d] of Object.entries(dialogues)) {
    const w = `dialogue.json ${id}`;
    const nodes = indexById(d.nodes || [], w + ' nodes', errors);
    if (!Array.isArray(d.greetings) || !d.greetings.length) errors.push(`${w}: needs at least one greeting`);
    (d.greetings || []).forEach((g, i) => {
      if (!isStr(g.text)) errors.push(`${w} greeting #${i + 1}: needs text`);
      condition(`${w} greeting #${i + 1}`, g.when);
    });
    for (const t of Object.values(indexById(d.topics || [], w + ' topics', errors))) {
      if (!isStr(t.prompt)) errors.push(`${w} topic ${t.id}: needs a prompt`);
      ref(`${w} topic ${t.id}`, 'node', nodes, t.node);
      condition(`${w} topic ${t.id}`, t.when);
    }
    for (const [nid, n] of Object.entries(nodes)) {
      if (!isStr(n.text)) errors.push(`${w} node ${nid}: needs text`);
      if (!Array.isArray(n.replies) || !n.replies.length) errors.push(`${w} node ${nid}: needs at least one reply`);
      for (const rep of n.replies || []) {
        if (!isStr(rep.text)) errors.push(`${w} node ${nid}: a reply needs text`);
        if (rep.node !== undefined) ref(`${w} node ${nid}`, 'node', nodes, rep.node);
      }
    }
  }

  // ---- the world
  const b = worldF.bounds;
  const inWorld = (p) => isVec2(p) && b && p[0] >= b.minX && p[0] <= b.maxX && p[1] >= b.minZ && p[1] <= b.maxZ;
  const pos = (where, p) => {
    if (!inWorld(p)) errors.push(`${where}: position ${JSON.stringify(p)} is not [x, z] inside the world bounds`);
  };
  if (!(b && ['minX', 'maxX', 'minZ', 'maxZ'].every((k) => isNum(b[k])))) errors.push('world.json: bounds need minX, maxX, minZ and maxZ');
  for (const [id, r] of Object.entries(regions)) if (!isStr(r.name) || !(r.minZ === null || isNum(r.minZ))) errors.push(`world.json region ${id}: needs a name and minZ (a number, or null for the last)`);
  for (const road of worldF.roads || []) if (!Array.isArray(road.points) || road.points.length < 2 || !road.points.every(isVec2)) errors.push(`world.json road ${road.id}: needs at least two [x, z] points`);
  if (!worldF.playerStart || !inWorld(worldF.playerStart.position)) errors.push('world.json: playerStart needs a position inside the world');
  for (const wa of worldF.water || []) {
    const w = `world.json water ${wa.id}`;
    pos(w, wa.position);
    if (!(isNum(wa.radius) && wa.radius > 0)) errors.push(`${w}: needs a radius`);
    ref(w, 'fish loot table', lootTables, wa.fishTable);
  }
  for (const o of worldF.obscured || []) {
    const w = `world.json obscured ${o.id}`;
    pos(w, o.position);
    if (!(isNum(o.radius) && o.radius > 0) || !isStr(o.name)) errors.push(`${w}: needs a name and a radius`);
  }
  for (const [id, s] of Object.entries(shrines)) {
    pos(`world.json shrine ${id}`, s.position);
    if (!isStr(s.label)) errors.push(`world.json shrine ${id}: needs a label (shown on the death screen)`);
  }
  for (const [id, l] of Object.entries(locations)) {
    pos(`world.json location ${id}`, l.position);
    if (!isStr(l.name) || !(isNum(l.radius) && l.radius > 0)) errors.push(`world.json location ${id}: needs a name and a radius`);
  }
  for (const s of worldF.npcSpawns || []) {
    ref('world.json npcSpawns', 'npc', npcs, s.npc);
    pos(`world.json npcSpawn ${s.npc}`, s.position);
  }
  for (const [id, s] of Object.entries(spawns)) {
    ref(`world.json enemySpawn ${id}`, 'enemy type', enemies, s.enemy);
    pos(`world.json enemySpawn ${id}`, s.position);
  }
  for (const [id, l] of Object.entries(placed)) {
    const w = `world.json placedLoot ${id}`;
    pos(w, l.position);
    model(w, l.model);
    if (!isStr(l.prompt)) errors.push(`${w}: needs a prompt`);
    const r = l.reward || {};
    if (!r.item && !r.coins) errors.push(`${w}: reward needs an item or coins`);
    if (r.item) ref(w, 'item', items, r.item);
    if (l.quest !== undefined) ref(w, 'quest', quests, l.quest);
    if (l.respawn !== undefined && !(l.respawn > 0)) errors.push(`${w}: respawn must be seconds above 0`);
    if (l.opensDocument && !documents[l.opensDocument]) errors.push(`${w}: names unknown document ${l.opensDocument}`);
  }
  for (const [id, c] of Object.entries(indexById(worldF.chests || [], 'world.json chests', errors))) {
    const w = `world.json chest ${id}`;
    pos(w, c.position);
    if (!isStr(c.name)) errors.push(`${w}: needs a name`);
    for (const it of c.items || []) ref(w, 'item', items, it.id);
    if (c.coins !== undefined && !(isInt(c.coins) && c.coins >= 0)) errors.push(`${w}: coins must be whole silver`);
    if (c.lock) {
      if (!c.lock.key && !c.lock.pick) errors.push(`${w}: a lock needs a key or a pick rank`);
      if (c.lock.key) ref(w, 'key item', items, c.lock.key);
      if (c.lock.pick !== undefined && !(isInt(c.lock.pick) && c.lock.pick >= 1)) errors.push(`${w}: pick must be a Lockpicking rank of at least 1`);
    }
  }
  for (const z of worldF.dangerZones || []) {
    pos('world.json dangerZone', z.position);
    ref('world.json dangerZone', 'enemy spawn', spawns, z.enemySpawn);
  }

  // ---- scenery
  (sceneF.props || []).forEach((p, i) => {
    const w = `scenery.json prop #${i + 1} (${p.model})`;
    model(w, p.model);
    pos(w, p.position);
    if (p.examine && !examine[p.examine]) errors.push(`${w}: names unknown examine text ${p.examine}`);
    const c = p.collider;
    const box = c && !Array.isArray(c) && typeof c === 'object' && Array.isArray(c.box) && c.box.length === 2 && c.box.every((v) => isNum(v) && v > 0);
    if (!(c === undefined || isNum(c) || box || (Array.isArray(c) && c.every((x) => Array.isArray(x) && x.length === 3 && x.every(isNum))))) errors.push(`${w}: collider must be a radius, a list of [x, z, radius] or { "box": [width, depth] }`);
  });
  for (const l of sceneF.lights || []) pos('scenery.json light', l.position);

  // ---- buildings you can enter, cooking stations, levelled ground
  for (const b of worldF.buildings || []) {
    const w = `world.json building ${b.id}`;
    pos(w, b.position);
    for (const m of [b.shell, b.front, b.roof]) model(w, m);
    if (!(Array.isArray(b.size) && b.size.length === 2 && b.size.every((v) => isNum(v) && v > 0))) errors.push(`${w}: size must be [width, depth]`);
    if (!Array.isArray(b.walls) || !b.walls.every((s) => Array.isArray(s) && s.length === 4 && s.every(isNum))) errors.push(`${w}: walls must be a list of [x1, z1, x2, z2] segments`);
    for (const f of b.furniture || []) if (!(Array.isArray(f) && f.length === 3 && f.every(isNum))) errors.push(`${w}: furniture must be [x, z, radius] circles`);
  }
  for (const s of worldF.stations || []) {
    pos(`world.json station ${s.id}`, s.position);
    if (s.kind !== 'fire') errors.push(`world.json station ${s.id}: kind must be fire`);
  }
  for (const s of worldF.signposts || []) {
    const w = `world.json signpost ${s.id}`;
    pos(w, s.position);
    if (!Array.isArray(s.points) || !s.points.length || s.points.length > 4) errors.push(`${w}: points must list 1 to 4 places`);
    for (const p of s.points || []) {
      ref(w, 'location', locations, p.to);
      if (p.label !== undefined && !isStr(p.label)) errors.push(`${w}: a label must be text`);
    }
  }
  for (const p of worldF.pads || []) if (!(Array.isArray(p) && p.length === 3 && p.every(isNum))) errors.push('world.json pads: each must be [x, z, radius]');

  // ---- recipes (crafting skills: cooking)
  const recF = raw['recipes.json'] || { recipes: [] };
  const recipes = indexById(recF.recipes, 'recipes.json', errors);
  for (const [id, r] of Object.entries(recipes)) {
    const w = `recipes.json ${id}`;
    ref(w, 'skill', skills, r.skill);
    if (skills[r.skill] && !skills[r.skill].maxRank) errors.push(`${w}: its skill ${r.skill} has no ranks`);
    if (!(isInt(r.rank) && r.rank >= 1)) errors.push(`${w}: rank must be a whole number of at least 1`);
    if (!(Array.isArray(r.skillUp) && r.skillUp.length === 3 && r.skillUp.every(isInt) && r.skillUp[0] > r.rank && r.skillUp[0] < r.skillUp[1] && r.skillUp[1] < r.skillUp[2])) errors.push(`${w}: skillUp must be three rising ranks (yellow, green, grey) above its rank`);
    if (!Array.isArray(r.inputs) || !r.inputs.length) errors.push(`${w}: needs inputs`);
    for (const x of [...(r.inputs || []), r.output || {}]) {
      ref(w, 'item', items, x.item);
      if (!(isInt(x.count) && x.count >= 1)) errors.push(`${w}: counts must be whole numbers of at least 1`);
    }
    if (r.station !== 'fire') errors.push(`${w}: station must be fire`);
    if (r.trainer !== undefined) {
      ref(w, 'trainer npc', npcs, r.trainer);
      if (!(isInt(r.cost) && r.cost >= 0)) errors.push(`${w}: a taught recipe needs a cost in coins`);
    }
  }

  // ---- text
  if (!isStr(textF.intro)) errors.push('text.json: needs an intro');
  const ttl = textF.title;
  if (!ttl || typeof ttl !== 'object') errors.push('text.json: needs a title section (title screen and character creation)');
  else {
    if (!isStr(ttl.build) || !isStr(ttl.tagline)) errors.push('text.json title: needs a build label and a tagline');
    if (!(isInt(ttl.maxCharacters) && ttl.maxCharacters >= 1)) errors.push('text.json title: maxCharacters must be a whole number of at least 1');
    const classes = Array.isArray(ttl.classes) ? ttl.classes : [];
    if (!classes.some((c) => c.archetype)) errors.push('text.json title: at least one class needs a playable archetype');
    const seen = new Set();
    for (const c of classes) {
      const w = `text.json title class ${c.id}`;
      if (!isStr(c.id) || seen.has(c.id)) errors.push(`${w}: needs a unique id`);
      seen.add(c.id);
      if (!isStr(c.name) || !isStr(c.role) || !isStr(c.blurb) || !isStrList(c.traits)) errors.push(`${w}: needs a name, role, blurb and a list of traits`);
      if (c.archetype !== undefined && !archetypes[c.archetype]) errors.push(`${w}: names unknown archetype ${c.archetype}`);
    }
    const n = ttl.names || {};
    if (!isStrList(n.first) || !n.first.length || !isStrList(n.last) || !n.last.length) errors.push('text.json title: names needs non-empty first and last lists');
    else if ([...n.first, ...n.last].some((x) => !/^[A-Z][a-z]{1,11}$/.test(x))) errors.push('text.json title: every name must be a capitalised word of 2 to 12 letters');
  }
  for (const [id, d] of Object.entries(documents)) if (!isStr(d.title) || !Array.isArray(d.body)) errors.push(`text.json document ${id}: needs a title and a body (a list of paragraphs)`);

  return errors;
}

// JSON.parse keeps only the last of two equal keys, so repeated keys in the
// text maps would vanish silently. This scans the raw file text for them.
export function findDuplicateKeys(text, file) {
  const errors = [];
  const stack = [];
  let i = 0;
  const str = () => {
    let s = '';
    i++; // opening quote
    while (i < text.length && text[i] !== '"') {
      if (text[i] === '\\') {
        s += text[i + 1];
        i += 2;
      } else s += text[i++];
    }
    i++;
    return s;
  };
  while (i < text.length) {
    const ch = text[i];
    if (ch === '{') {
      stack.push({ keys: new Set(), expectKey: true });
      i++;
    } else if (ch === '[') {
      stack.push(null);
      i++;
    } else if (ch === '}' || ch === ']') {
      stack.pop();
      i++;
    } else if (ch === '"') {
      const top = stack[stack.length - 1];
      const s = str();
      if (top && top.expectKey) {
        if (top.keys.has(s)) errors.push(`${file}: key "${s}" appears twice in the same object`);
        top.keys.add(s);
        top.expectKey = false;
      }
    } else if (ch === ',') {
      const top = stack[stack.length - 1];
      if (top) top.expectKey = true;
      i++;
    } else i++;
  }
  return errors;
}

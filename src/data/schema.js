// The shape of the game's data (the JSON files in /data) and the checks that
// keep it sound. Pure functions with no imports, so the same checks run in
// the game at start-up and in Node (tests/validate-data.mjs) before a commit.
//
// The rules, in short:
//   * every record has a lower_snake_case `id`, unique within its file
//   * records point at each other by id only, and every id they name exists
//   * numbers are numbers, required fields are present, enums are known
// Each check returns readable strings such as
//   "loot_tables.json ghoul: gear entry names unknown item iron_glvoes".

export const KINDS = ['weapon', 'armor', 'shield', 'bag', 'consumable', 'material', 'document'];
export const QUALITIES = ['poor', 'common', 'uncommon', 'rare', 'quest'];
export const STAT_KEYS = ['might', 'finesse', 'intellect', 'vitality', 'armour', 'resistance', 'block', 'blockRating', 'haste'];
export const EQUIP_SLOTS = [
  { id: 'head', label: 'Head' },
  { id: 'chest', label: 'Chest' },
  { id: 'hands', label: 'Hands' },
  { id: 'legs', label: 'Legs' },
  { id: 'feet', label: 'Feet' },
  { id: 'mainHand', label: 'Main hand' },
  { id: 'offHand', label: 'Off hand' },
];
const ABILITY_TARGETS = ['enemy', 'ground', 'self'];
const SCHOOLS = ['physical', 'shadow'];
const ID = /^[a-z][a-z0-9_]*$/;
const ABILITY_ID = /^[a-z][a-zA-Z0-9]*$/; // abilities are camelCase, as saved spell bars use them

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);
const isInt = (v) => Number.isInteger(v);
const isStr = (v) => typeof v === 'string' && v.length > 0;
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
export function validateItems(items, slots, armourTypes) {
  const errors = [];
  for (const [id, d] of Object.entries(items)) {
    const bad = (msg) => errors.push(`${id}: ${msg}`);
    if (!ID.test(id)) bad('id must be lower_snake_case');
    if (!d.name || !d.description) bad('needs a name and a description');
    if (!KINDS.includes(d.kind)) bad(`unknown kind ${d.kind}`);
    if (!QUALITIES.includes(d.quality)) bad(`unknown quality ${d.quality}`);
    if (!isInt(d.stack) || d.stack < 1) bad('stack must be a whole number of at least 1');
    if (!isInt(d.price) || d.price < 0) bad('price must be a whole number of coins');
    if (!d.model || !d.icon) bad('needs a model and an icon');
    const equips = ['weapon', 'armor', 'shield'].includes(d.kind);
    if (equips && !slots.includes(d.slot)) bad(`unknown slot ${d.slot}`);
    if (!equips && d.slot) bad('only weapons, armour and shields have a slot');
    if (d.kind === 'armor' && !armourTypes.includes(d.armourType)) bad('armour needs an armour type');
    if (d.armourType && !armourTypes.includes(d.armourType)) bad(`unknown armour type ${d.armourType}`);
    if (d.kind === 'weapon' && !(Array.isArray(d.damage) && d.damage.length === 2 && d.damage[0] <= d.damage[1])) bad('a weapon needs damage [min, max]');
    if (d.kind === 'bag' && !(d.bagSlots > 0)) bad('a bag needs bagSlots');
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
  const shopF = need('shops.json');
  const npcF = need('npcs.json');
  const questF = need('quests.json');
  const worldF = need('world.json');
  const sceneF = need('scenery.json');
  const textF = need('text.json');

  const armourTypes = indexById(itemsF.armourTypes, 'items.json armourTypes', errors);
  const suffixes = indexById(itemsF.suffixes, 'items.json suffixes', errors);
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
  const documents = (textF.documents && typeof textF.documents === 'object') ? textF.documents : {};
  const examine = (textF.examine && typeof textF.examine === 'object') ? textF.examine : {};

  const ref = (where, what, table, id) => {
    if (!table[id]) errors.push(`${where}: names unknown ${what} ${id}`);
  };
  const model = (where, name) => {
    if (!isStr(name)) errors.push(`${where}: needs a model`);
    else if (opts.models && !opts.models.includes(name)) errors.push(`${where}: model ${name} does not exist in assets/models`);
  };

  // ---- items
  for (const e of validateItems(items, EQUIP_SLOTS.map((s) => s.id), Object.keys(armourTypes))) errors.push('items.json ' + e);
  for (const [id, d] of Object.entries(items)) {
    model(`items.json ${id}`, d.model);
    model(`items.json ${id} icon`, d.icon);
    if (d.use && !(isNum(d.use.heal) && d.use.heal > 0)) errors.push(`items.json ${id}: use must say what it does, e.g. { "heal": 42 }`);
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
  }

  // ---- abilities
  if (!isNum(abilF.globalCooldown)) errors.push('abilities.json: globalCooldown must be a number');
  for (const [id, a] of Object.entries(abilities)) {
    const w = `abilities.json ${id}`;
    if (!isStr(a.name) || !isStr(a.desc)) errors.push(`${w}: needs a name and a desc`);
    if (!ABILITY_TARGETS.includes(a.target)) errors.push(`${w}: target must be one of ${ABILITY_TARGETS.join(', ')}`);
    if (a.target === 'enemy' && !isNum(a.range)) errors.push(`${w}: an enemy-targeted ability needs a range`);
    if (a.item) ref(w, 'item', items, a.item);
    if (!a.tuning || typeof a.tuning !== 'object' || !Object.values(a.tuning).every(isNum)) errors.push(`${w}: tuning must be a set of numbers`);
  }

  // ---- enemies and loot tables
  if (!isNum(enemF.leashDistance)) errors.push('enemies.json: leashDistance must be a number');
  for (const [id, e] of Object.entries(enemies)) {
    const w = `enemies.json ${id}`;
    if (!isStr(e.name)) errors.push(`${w}: needs a name`);
    model(w, e.model);
    for (const k of ['level', 'health', 'damage', 'attackInterval', 'windup', 'detection', 'meleeRange', 'speed', 'radius', 'xp', 'coins']) {
      if (!isNum(e[k]) || e[k] < 0) errors.push(`${w}: ${k} must be a number of at least 0`);
    }
    if (e.lootTable) ref(w, 'loot table', lootTables, e.lootTable);
    if (e.uniqueDrop) ref(w, 'item', items, e.uniqueDrop);
    if (e.ranged && !(isNum(e.ranged.range) && isNum(e.ranged.damage) && isNum(e.ranged.windup))) errors.push(`${w}: ranged needs range, damage and windup`);
    for (const att of [e.ranged, e.circle]) if (att && att.school && !SCHOOLS.includes(att.school)) errors.push(`${w}: unknown school ${att.school}`);
    if ((e.ranged?.mana || e.circle?.mana) && !(e.mana > 0)) errors.push(`${w}: spends mana but has none`);
  }
  for (const [id, t] of Object.entries(lootTables)) {
    const w = `loot_tables.json ${id}`;
    for (const a of t.always || []) {
      ref(w + ' always', 'item', items, a.item);
      if (!(isInt(a.min) && isInt(a.max) && a.min >= 0 && a.min <= a.max)) errors.push(`${w}: always ${a.item} needs whole min <= max`);
    }
    if (t.gear) {
      if (!(isNum(t.gear.chance) && t.gear.chance >= 0 && t.gear.chance <= 1)) errors.push(`${w}: gear chance must be between 0 and 1`);
      if (!Array.isArray(t.gear.entries) || !t.gear.entries.length) errors.push(`${w}: gear needs entries`);
      for (const g of t.gear.entries || []) {
        ref(w + ' gear entry', 'item', items, g.item);
        if (!(isNum(g.weight) && g.weight > 0)) errors.push(`${w}: gear entry ${g.item} needs a weight above 0`);
      }
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
    const vt = vendorTypes[s.vendorType];
    for (const it of s.stock || []) {
      ref(w + ' stock', 'item', items, it);
      if (items[it] && items[it].quest) errors.push(`${w}: quest item ${it} cannot be sold`);
      if (items[it] && vt && !(vt.sells || []).includes(items[it].kind)) errors.push(`${w}: a ${vt.name} does not sell ${items[it].kind} (${it})`);
    }
  }
  for (const [id, n] of Object.entries(npcs)) {
    const w = `npcs.json ${id}`;
    if (!isStr(n.name)) errors.push(`${w}: needs a name`);
    model(w, n.model);
    if (n.shop) ref(w, 'shop', shops, n.shop);
    for (const q of n.quests || []) ref(w, 'quest', quests, q);
  }

  // ---- quests
  for (const [id, q] of Object.entries(quests)) {
    const w = `quests.json ${id}`;
    if (!isStr(q.name)) errors.push(`${w}: needs a name`);
    ref(w, 'npc', npcs, q.giver);
    const stages = indexById(q.stages, w + ' stages', errors, /^[a-z][a-zA-Z0-9]*$/);
    for (const [sid, s] of Object.entries(stages)) {
      if (!isStr(s.text) || !isStr(s.label)) errors.push(`${w} stage ${sid}: needs text and a label`);
      const c = s.when;
      if (c) {
        if (c.collected) ref(`${w} stage ${sid}`, 'placed loot', placed, c.collected);
        if (c.examined && !examine[c.examined]) errors.push(`${w} stage ${sid}: names unknown examine point ${c.examined}`);
        if (c.flag !== undefined && !isStr(c.flag)) errors.push(`${w} stage ${sid}: flag must be a name`);
      }
    }
    if (q.stages && q.stages[0] && q.stages[0].when) errors.push(`${w}: the first stage must have no condition`);
    const t = q.turnIn;
    if (t) {
      ref(w + ' turnIn', 'npc', npcs, t.npc);
      ref(w + ' turnIn', 'item', items, t.item);
      if (!stages[t.atStage]) errors.push(`${w} turnIn: unknown stage ${t.atStage}`);
      if (!isStr(t.setsFlag)) errors.push(`${w} turnIn: needs setsFlag`);
      else if (!Object.values(stages).some((s) => s.when && s.when.flag === t.setsFlag)) errors.push(`${w} turnIn: no stage waits for flag ${t.setsFlag}`);
    }
    if (q.reward && !(isInt(q.reward.coins ?? 0) && isInt(q.reward.xp ?? 0))) errors.push(`${w}: reward coins and xp must be whole numbers`);
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
  for (const [id, s] of Object.entries(shrines)) {
    pos(`world.json shrine ${id}`, s.position);
    if (!isStr(s.label)) errors.push(`world.json shrine ${id}: needs a label (shown on the death screen)`);
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
    if (l.opensDocument && !documents[l.opensDocument]) errors.push(`${w}: names unknown document ${l.opensDocument}`);
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
    if (!(c === undefined || isNum(c) || (Array.isArray(c) && c.every((x) => Array.isArray(x) && x.length === 3 && x.every(isNum))))) errors.push(`${w}: collider must be a radius or a list of [x, z, radius]`);
  });
  for (const l of sceneF.lights || []) pos('scenery.json light', l.position);

  // ---- text
  if (!isStr(textF.intro)) errors.push('text.json: needs an intro');
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

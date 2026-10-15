// Checks every file in /data before the game is opened: shapes, ids,
// references between files, model names, and repeated keys. Then proves the
// checks bite by breaking a copy of the data in a few typical ways.
//
//   npm run validate        (also the first step of npm test)

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateGameData, findDuplicateKeys } from '../src/data/schema.js';
import { isScaledItem, itemSpend } from '../src/data/scaling.js';

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const DATA = path.join(ROOT, 'data');
const MODELS = fs.readdirSync(path.join(ROOT, 'assets', 'models')).filter((f) => f.endsWith('.glb')).map((f) => f.slice(0, -4));

const raw = {};
const texts = {};
const problems = [];
for (const f of fs.readdirSync(DATA).filter((f) => f.endsWith('.json')).sort()) {
  texts[f] = fs.readFileSync(path.join(DATA, f), 'utf8');
  try {
    raw[f] = JSON.parse(texts[f]);
  } catch (err) {
    problems.push(`${f}: not valid JSON (${err.message})`);
  }
  problems.push(...findDuplicateKeys(texts[f], f));
}
problems.push(...validateGameData(raw, { models: MODELS }));

const count = (f, key) => (raw[f] && Array.isArray(raw[f][key]) ? raw[f][key].length : 0);
console.log(
  `data: ${count('items.json', 'items')} items, ${count('enemies.json', 'enemies')} enemy types, ${count('loot_tables.json', 'lootTables')} loot tables, ` +
    `${count('npcs.json', 'npcs')} npcs, ${count('shops.json', 'shops')} shops, ${count('quests.json', 'quests')} quests, ${count('dialogue.json', 'dialogues')} dialogues, ${count('abilities.json', 'abilities')} abilities, ` +
    `${count('world.json', 'enemySpawns')} enemy spawns, ${count('scenery.json', 'props')} props`,
);

// gear with stats: the stat points it spends against its budget (white gear has none)
const budgets = (raw['items.json']?.items || []).filter((d) => isScaledItem(d) && itemSpend(d).budget > 0);
if (budgets.length) {
  console.log('item budgets, stat points spent / budget (src/data/scaling.js):');
  for (const d of budgets) {
    const { budget, spent } = itemSpend(d);
    console.log(`  ${d.id.padEnd(20)} level ${String(d.itemLevel).padEnd(3)} ${d.rarity.padEnd(10)} ${d.slot.padEnd(9)} ${spent.toFixed(1)} / ${budget.toFixed(1)}`);
  }
}

// the checks must catch typical mistakes, or they are no use
const broken = [
  ['a loot table naming an item that does not exist', (d) => (d['loot_tables.json'].lootTables[0].drops.items.common[0].item = 'iron_glvoes'), /unknown item iron_glvoes/],
  ['two items with the same id', (d) => d['items.json'].items.push({ ...d['items.json'].items[0] }), /duplicate id/],
  ['a shop selling a quest item', (d) => d['shops.json'].shops[0].stock.push('manifest'), /quest item manifest cannot be sold/],
  ['an npc pointing at a missing shop', (d) => (d['npcs.json'].npcs[0].shop = 'nowhere'), /unknown shop nowhere/],
  ['an enemy spawn of an unknown type', (d) => (d['world.json'].enemySpawns[0].enemy = 'dragon'), /unknown enemy type dragon/],
  ['a spawn outside the world', (d) => (d['world.json'].enemySpawns[0].position = [500, 0]), /not \[x, z\] inside the world bounds/],
  ['a prop with a misspelt model', (d) => (d['scenery.json'].props[0].model = 'crat'), /model crat does not exist/],
  ['a quest objective naming an examine point that does not exist', (d) => (d['quests.json'].quests[1].objectives[0].target = 'kart'), /unknown examine point kart/],
  ['a quest needing more kills than the world has enemies', (d) => (d['quests.json'].quests[2].objectives[1].count = 9), /world only has/],
  ['quests that require each other', (d) => d['quests.json'].quests[0].requires = ['the_glade_seer'], /loop back/],
  ['a dialogue reply leading to a missing node', (d) => (d['dialogue.json'].dialogues[0].nodes[0].replies[0].node = 'nowhere'), /unknown node nowhere/],
  ['a boss\'s own epic weapon in an ordinary enemy\'s table', (d) => Object.assign(d['loot_tables.json'].lootTables[0].drops, { rarity: { ...d['loot_tables.json'].lootTables[0].drops.rarity, epic: 1 }, items: { ...d['loot_tables.json'].lootTables[0].drops.items, epic: [{ item: 'witchbane', weight: 1 }] } }), /witchbane is kept for seer/],
  ['a rarity rolled with no items to roll', (d) => (d['loot_tables.json'].lootTables[0].drops.rarity.legendary = 1), /rarity legendary has no items/],
  ['an item with an unknown rarity', (d) => (d['items.json'].items[0].rarity = 'shiny'), /unknown rarity shiny/],
  ['a spell missing a number its kind needs', (d) => delete d['abilities.json'].abilities.find((a) => a.kind === 'cast').tuning.castTime, /needs tuning.castTime/],
  ['an item spending more than its stat budget', (d) => (d['items.json'].items.find((i) => i.id === 'witchbane').stats = { strength: 20 }), /witchbane: spends 2\d\.\d stat points of its 5\.8/],
  ['gear without an item level', (d) => delete d['items.json'].items.find((i) => i.id === 'worn_longsword').itemLevel, /worn_longsword: gear needs an itemLevel/],
  ['an ability costing a resource no class has', (d) => (d['abilities.json'].abilities.find((a) => a.id === 'smite').cost = { rage: 10 }), /unknown resource rage/],
  ['an enemy of an unknown type', (d) => (d['enemies.json'].enemies[0].type = 'dragonkin'), /type must be one of/],
];
const selfTest = [];
for (const [what, breakIt, expect] of broken) {
  const copy = JSON.parse(JSON.stringify(raw));
  breakIt(copy);
  const errs = validateGameData(copy, { models: MODELS });
  if (!errs.some((e) => expect.test(e))) selfTest.push(`the check missed ${what} (got: ${errs.join('; ') || 'no errors'})`);
}
if (!findDuplicateKeys('{"a": 1, "b": {"c": 1, "c": 2}}', 'x').length) selfTest.push('the check missed a repeated key');

if (problems.length || selfTest.length) {
  for (const p of problems) console.error('DATA  ' + p);
  for (const p of selfTest) console.error('CHECK ' + p);
  process.exit(1);
}
console.log(`data: all ${Object.keys(raw).length} files valid; the checks caught all ${broken.length + 1} planted mistakes`);

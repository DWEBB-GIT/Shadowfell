// The game database: every JSON file in /data, loaded once, checked, and
// indexed by id. Gameplay code reads content from here (or from CONFIG,
// which takes its archetypes, abilities and enemies from here) and never
// from the files directly.
//
//   data/items.json        items, armour types, random-roll suffixes
//   data/archetypes.json   playable archetypes
//   data/abilities.json    player abilities and their tuning
//   data/enemies.json      enemy types (stats, behaviour, loot table)
//   data/rarities.json     item rarity tiers (junk to legendary) and colours
//   data/loot_tables.json  what enemies drop: a rarity roll, then an item
//   data/npcs.json         townsfolk (their shop and quests)
//   data/shops.json        vendor types and shop stock
//   data/quests.json       quests: giver, objectives, turn-in, reward
//   data/dialogue.json     what townsfolk say: greetings, topics, replies
//   data/world.json        regions, roads, shrines, locations, spawns, loot
//   data/scenery.json      props, clearings, lights
//   data/text.json         intro, documents, examine text
//   data/skills.json       skills learned from trainers (camping, fishing, cooking)
//   data/recipes.json      recipes for crafting skills (cooking)
//
// See CONTRIBUTING.md for how to add content.

import items from '../../data/items.json';
import archetypes from '../../data/archetypes.json';
import abilities from '../../data/abilities.json';
import enemies from '../../data/enemies.json';
import lootTables from '../../data/loot_tables.json';
import rarities from '../../data/rarities.json';
import npcs from '../../data/npcs.json';
import shops from '../../data/shops.json';
import quests from '../../data/quests.json';
import dialogue from '../../data/dialogue.json';
import world from '../../data/world.json';
import scenery from '../../data/scenery.json';
import text from '../../data/text.json';
import skills from '../../data/skills.json';
import factions from '../../data/factions.json';
import recipes from '../../data/recipes.json';
import { validateGameData, indexById } from './schema.js';

export const RAW = {
  'items.json': items,
  'archetypes.json': archetypes,
  'abilities.json': abilities,
  'enemies.json': enemies,
  'loot_tables.json': lootTables,
  'rarities.json': rarities,
  'npcs.json': npcs,
  'shops.json': shops,
  'quests.json': quests,
  'dialogue.json': dialogue,
  'world.json': world,
  'scenery.json': scenery,
  'text.json': text,
  'skills.json': skills,
  'factions.json': factions,
  'recipes.json': recipes,
};

// Problems found in the data (empty when it is sound). The game logs them at
// start-up; `npm test` fails on them before the game is ever opened.
export const DATA_ERRORS = validateGameData(RAW);

const byId = (list, where, pattern) => indexById(list, where, [], pattern);
// a record's id is its key in the maps below; the rest is the record
const strip = (map) => Object.fromEntries(Object.entries(map).map(([id, { id: _, ...rest }]) => [id, rest]));

export const DB = {
  items: strip(byId(items.items, 'items')),
  armourTypes: strip(byId(items.armourTypes, 'armourTypes')),
  suffixes: strip(byId(items.suffixes, 'suffixes')),
  archetypes: strip(byId(archetypes.archetypes, 'archetypes')),
  abilities: byId(abilities.abilities, 'abilities', /^[a-z][a-zA-Z0-9]*$/),
  globalCooldown: abilities.globalCooldown,
  spellQueueWindow: abilities.spellQueueWindow,
  castPushback: abilities.castPushback,
  maxPushbacks: abilities.maxPushbacks,
  enemies: strip(byId(enemies.enemies, 'enemies')),
  leashDistance: enemies.leashDistance,
  lootTables: byId(lootTables.lootTables, 'lootTables'),
  rarities: byId(rarities.rarities, 'rarities'), // in order, lowest first
  npcs: byId(npcs.npcs, 'npcs'),
  vendorTypes: byId(shops.vendorTypes, 'vendorTypes'),
  shops: byId(shops.shops, 'shops'),
  quests: byId(quests.quests, 'quests'),
  dialogues: byId(dialogue.dialogues, 'dialogues'),
  locations: byId(world.locations, 'locations'),
  skills: byId(skills.skills, 'skills'),
  factions: byId(factions.factions, 'factions'),
  recipes: byId(recipes.recipes, 'recipes'),
  standings: factions.standings,
  water: world.water || [],
  obscured: world.obscured || [],
  world,
  scenery,
  text,
};

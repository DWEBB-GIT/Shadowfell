# Working on Shadowfall

Shadowfall is data-driven. **Content lives in `/data` as JSON, and code lives in `/src`.** Adding a sword, a wolf, a shop or a quest step means editing data rather than code, unless the thing needs behaviour the engine does not have yet.

## The data files

| File | What it holds | Points at |
|---|---|---|
| `items.json` | Every item, plus `armourTypes` and the random-roll `suffixes` | models |
| `archetypes.json` | Playable archetypes: base attributes, per-level gains, armour types, defensive ability | armour types, abilities |
| `abilities.json` | Player abilities: name, targeting, description, and the `tuning` numbers each runs on; `globalCooldown` | items (the draught) |
| `enemies.json` | Enemy types: stats, behaviour (`ranged`, `circle`, `special`, `pack`), `lootTable`, `uniqueDrop`; `leashDistance` | loot tables, items, models |
| `loot_tables.json` | `always` materials (min to max) and a `gear` chance with weighted entries | items |
| `npcs.json` | Townsfolk: name, title, model, the shop they keep, their dialogue | shops, dialogue, models |
| `shops.json` | `vendorTypes` (what kinds of goods each type deals in) and `shops` (a vendor type and its stock) | items |
| `quests.json` | Quests: giver, turn-in npc, `requires`, `objectives` (kill, collect, examine), what the giver says, `reward` | npcs, enemy types, items, examine points, locations |
| `dialogue.json` | What townsfolk say: `greetings` (the last whose `when` holds), `topics`, and `nodes` with `replies` | nodes, quests |
| `world.json` | Bounds, regions, roads, player start, shrines, named `locations` (quest areas on the map), and where NPCs, enemies and loot are placed | npcs, enemy types, items, documents |
| `scenery.json` | Props (with colliders and examine points), clearings kept free of trees, lights | models, examine text |
| `text.json` | The intro, readable documents, and examine text | |

Engine tuning that is not content, such as the damage formula's constants, camera, fog, loot radius and shop sell fraction, stays in `src/config.js`.

## Rules

1. **Every record has an `id`.**
   - Ids are `lower_snake_case`; abilities are `camelCase` because saved spell bars use those names.
   - An id is unique within its file. Records live in lists such as `"items": [ { "id": ... } ]`, so a repeated id is caught rather than silently overwritten.
2. **Records refer to each other by id only.**
   - A loot table names item ids, a shop names item ids, an NPC names a shop id, and a spawn names an enemy type id.
   - Nothing is copied between files.
3. **Never rename or delete an id that has shipped.**
   - Saves store item ids, enemy spawn ids, placed loot ids, flags and ability ids.
   - To retire something, stop placing or selling it, and leave the record.
4. **No logic in data.**
   - Data says *what*: numbers, names, references, and simple conditions such as `{ "examined": "cart" }`.
   - Code says *how*. If content needs a new kind of behaviour, add it to the engine and give it a data field.
5. **Positions are `[x, z]` in metres**, rotations are in degrees, and north is −z.
6. **Every file has an `_about` line** saying what it is for. Keys starting with `_` are notes and are ignored.

## Checking your change

```
npm run validate    # checks /data on its own, in under a second
npm test            # validate, then the full in-browser acceptance suite
npm run build       # rebundle dist/shadowfall.js (data is bundled in)
```

`npm run validate` (`tests/validate-data.mjs`) fails on:
- a missing or repeated id;
- a reference to something that does not exist;
- a model with no file in `assets/models`;
- a position outside the world;
- a shop selling a kind of item its vendor type does not deal in, or selling a quest item;
- a quest objective naming something that does not exist, or needing more kills than the world has enemies;
- quests whose requirements loop back on themselves;
- a dialogue reply leading to a node that does not exist;
- a key repeated in the same object;
- a wrong type, such as a string where a number belongs.

The game runs the same checks (`src/data/schema.js`) when it starts and logs anything wrong to the console.

## Recipes

- **A new item:**
  1. Add a record to `items.json`.
  2. If it needs its own look, add a builder to `assets/blender/build_assets.py`, run `npm run assets`, and register the model in `src/assets/assets.js`.
  3. Sell it from a shop, or add it to a loot table.
- **A new enemy type:**
  1. Add a record to `enemies.json`, reusing behaviour blocks such as `ranged`, `circle`, `special` and `pack`.
  2. Add a loot table.
  3. Add spawns to `world.json`, and build a model.
- **A new shop:**
  1. Add a `shops.json` record, with a `vendorTypes` entry if it is a new kind of vendor.
  2. Point an NPC's `shop` at it.
  3. Place the NPC with an `npcSpawns` entry in `world.json`.
- **A new quest:**
  1. Add a `quests.json` record with a `giver` and `turnIn` npc, and `requires` for any quests that must be done first.
  2. Give it `objectives`: `kill` an enemy type (counted from every one defeated, since enemies do not return), `collect` an item (taken on hand-in unless `keep`), or `examine` a world point. Add a `location` so the minimap shows where to go.
  3. Write what the giver says: `offer`, `progress` and `complete`, plus the `summary` the quest log shows.
  4. The giver shows a gold ! when it can be taken, a grey ? while it is in hand, and a gold ? when it is ready.
- **New things for someone to say:** add `topics` and `nodes` to their `dialogue.json` record. A `when` such as `{ "quest": "missing_delivery", "status": "done" }` holds a line back until the story gets there.
- **A new place:**
  1. Add props to `scenery.json`, with examine text in `text.json`.
  2. Add spawns and placed loot to `world.json`. A new region is a `regions` entry.

## How it maps to Unity

Each file is a list of records with stable ids, which is how Unity ScriptableObject databases are usually built: one ScriptableObject class per file type, such as `ItemDefinition`, `EnemyDefinition`, `LootTable`, `ShopDefinition` and `QuestDefinition`. References become asset references resolved by id at import. A small editor importer can read these JSON files into assets, and `src/data/schema.js` is the checklist for its validation.

## Code layout

- `src/data/db.js` loads `/data`, runs the checks, and indexes records by id.
- `src/config.js` holds engine tuning, and exposes archetypes, enemies and ability tuning from the data under their long-standing names.
- `src/world/layout.js` exposes `world.json` and `scenery.json` to the world builder.
- Systems in `src/systems/` own their state and talk through the event bus. The HUD only displays state and asks systems to act.
- `src/systems/quests.js` is the quest log: status, objectives, accept, hand in, save. `src/systems/dialogue.js` is the conversation. `src/ui/questUI.js` draws both, the tracker and the ! and ? marks; `src/ui/minimap.js` draws the map.

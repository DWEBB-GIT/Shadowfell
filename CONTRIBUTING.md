# Working on Shadowfall

Shadowfall is data-driven. **Content lives in `/data` as JSON, and code lives in `/src`.** Adding a sword, a wolf, a shop or a quest step means editing data rather than code, unless the thing needs behaviour the engine does not have yet.

## The data files

| File | What it holds | Points at |
|---|---|---|
| `items.json` | Every item, plus `armourTypes` and the random-roll `suffixes`. Gear states its `itemLevel` and `statSplit`; its armour, damage, block and stats are worked out | models |
| `archetypes.json` | Playable classes: base attributes, per-level gains, armour types and weapons, resources (mana and the class bars: Resolve, Energy and combo points, Focus, Corruption), trait, spellbook, the six spells a new character starts with, starting gear | armour types, abilities, items |
| `abilities.json` | Player abilities: name, targeting, description, the `tuning` numbers each runs on, cost and gain, and what they do to a target (`applies`: slows, stuns, sleeps, curses); `globalCooldown` | items (the draught), abilities |
| `enemies.json` | Enemy types: `level` and `type` (which size health, hits, attack speed and armour), behaviour (`ranged`, `circle`, `special`, `pack`), `lootTable`, `uniqueDrop`; `leashDistance` | loot tables, items, models |
| `skills.json` | Learnable skills (Camping, Fishing): the `trainer` npc, `cost`, `maxRank`, the ability it `teaches` | npcs, abilities |
| `rarities.json` | Item rarity tiers, lowest first (junk, common, enhanced, rare, epic, legendary, quest): name and colour | |
| `loot_tables.json` | `always` items (min to max), and `drops`: `rolls` tries at `chance`, each rolling a rarity by weight, then an item from that rarity's list | items |
| `npcs.json` | Townsfolk: name, title, model, the shop they keep, their dialogue | shops, dialogue, models |
| `shops.json` | `vendorTypes` (what kinds of goods each type deals in) and `shops` (a vendor type and its stock) | items |
| `quests.json` | Quests: giver, turn-in npc, `requires`, `objectives` (kill, collect, examine), what the giver says, `reward` | npcs, enemy types, items, examine points, locations |
| `dialogue.json` | What townsfolk say: `greetings` (the last whose `when` holds), `topics`, and `nodes` with `replies` | nodes, quests |
| `world.json` | Bounds, regions, roads, player start, shrines, named `locations` (quest areas on the map), `water`, `obscured` areas, and where NPCs, enemies and loot are placed | npcs, enemy types, items, documents |
| `scenery.json` | Props (with colliders and examine points), clearings kept free of trees, lights | models, examine text |
| `text.json` | The intro, readable documents, and examine text | |

Engine tuning that is not content, such as the damage formula's constants, camera, fog, loot radius and shop sell fraction, stays in `src/config.js`. Growth by level (the armour constant, the level gap, item budgets, weapon damage and the enemy table) is in `src/data/scaling.js`, with the formulas that turn an item's level and an enemy's type into numbers. `docs/stats-and-damage.md` explains them.

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

## Editing quests

`npm run editor` starts a small local server; open the address it prints (http://localhost:5180/tools/quest-editor/). The quest editor lists every quest by giver, edits one at a time with dropdowns of real NPCs, enemies, items, examine points, map areas and factions, draws the quest chains, and runs the same checks as `npm run validate` as you type. **Save** (or Ctrl+S) writes `data/quests.json`; then rebuild and commit as usual. Quest ids lock once saved, because saves store them.

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
- a wrong type, such as a string where a number belongs;
- gear without an `itemLevel`, or more than 10% over its stat budget (it prints each green-or-better item's budget against what it spends);
- an enemy of an unknown `type`.

The game runs the same checks (`src/data/schema.js`) when it starts and logs anything wrong to the console.

## Recipes

- **A new weapon:** give it an `itemLevel`, a `rarity` and a `speed` (seconds between auto attack swings), and a `statSplit` if it is green or better. Its damage per swing is worked out: 0.45 × (item level + 4) damage a second (more on blue and up), times its speed, ±40%. A slow weapon has bigger swings but no stronger abilities, which use the weapon's damage over `abilityWeaponSeconds` (strike tuning).
- **A new item:**
  1. Add a record to `items.json`. Gear (weapons, armour, shields, jewellery) states its `itemLevel` (the level of where it drops), `slot`, `armourType` and `rarity`, and a `statSplit` of shares such as `{ "strength": 1, "stamina": 1 }`; the game works out its armour, weapon damage, block chance and stat points (white gear has none). A special item can state an exact `damage`, or a stat in `stats`, and `budgetException: true` if it is meant to be over budget.
  2. If it needs its own look, add a builder to `assets/blender/build_assets.py`, run `npm run assets`, and register the model in `src/assets/assets.js`.
  3. Give it a `rarity`. Sell it from a shop, or list it in a loot table under its rarity. Common weapons and armour may also be listed under `enhanced`, where they drop with a suffix. To keep an item for one boss, set `reservedFor: ["<loot table id>"]`; the check then refuses it in any other table or shop.
- **A new enemy type:**
  1. Add a record to `enemies.json` with a `level` and a `type`: `fodder`, `pack_beast`, `normal`, `skirmisher`, `armoured`, `elite`, `heavy` or `boss`. The type works out its health, hits, attack speed and armour from its level (`armourClass` changes the armour), and an elite's or heavy's `special` damage. Never size an enemy to the player's level. State a number to override the type's (a boss states its own hits and attack speed). Reuse behaviour blocks such as `ranged`, `circle`, `special` and `pack`.
  2. Add a loot table.
  3. Add spawns to `world.json`, and build a model.
- **A new spell:** add a record to `abilities.json` with a `kind` the spell engine knows (the list is at the top of `src/systems/spells.js`: cast, dot, instant, aoe, cleave, burst, charge, leap, guard, interrupt, control, buff, stealth, trap, purge, channel, shield), its `tuning`, a `cost` in mana or the class's bar, and an `applies` aura if it slows, stuns, sleeps or curses. Then list it in a class's `abilities` in `archetypes.json` (and in its `bar` if it is part of the base kit). A spell no class lists cannot be used. Stuns and sleeps never hold a boss: they fill its stagger bar (`control` in `src/config.js`).
- **A new class:** add an archetype (stats, armour, `resources`, `trait`, `abilities`, a six-spell `bar`, `startingGear`) and a class in `text.json` `title.classes` pointing at it. A trait with new behaviour needs code in `src/systems/spells.js`.
- **A new shop:**
  1. Add a `shops.json` record, with a `vendorTypes` entry if it is a new kind of vendor.
  2. Point an NPC's `shop` at it.
  3. Place the NPC with an `npcSpawns` entry in `world.json`.
- **A new quest:**
  1. Add a `quests.json` record with a `giver` and `turnIn` npc, and `requires` for any quests that must be done first.
  2. Give it `objectives`: `kill` an enemy type (counted from when the quest is taken, since most enemies respawn), `collect` an item (taken on hand-in unless `keep`), `examine` a world point, or `talk` to the turn-in npc (met at once: "go and speak to Bram"). Add a `location` so the minimap shows where to go.
  3. Write what the giver says: `offer`, `progress` and `complete`, plus the `summary` the quest log shows.
  4. The giver shows a gold ! when it can be taken, a grey ? while it is in hand, and a gold ? when it is ready.
  5. **A choice:** quests that share a `choice` name are one decision (the Ashby feud's three endings). Taking one locks the others; abandoning it opens them again. Give each a `setsFlag`, then let greetings, topics and npc spawns (`goneWhen` in `world.json`) react to the flag, so the world shows what the player chose.
- **A new spell:** add an `abilities.json` record with a `kind` and the spell engine (`src/systems/spells.js`) runs it with no new code. Kinds and the `tuning` numbers each needs (all need `cooldown`):
  - `cast` (target `enemy`): `castTime`, `damageMin`, `damageMax`, `projectileSpeed`
  - `dot` (target `enemy`): `duration`, `tickInterval`, `tickMultiplier` (× a weapon roll per tick)
  - `instant` (target `enemy`): `damageMin`, `damageMax`
  - `aoe` (target `self`): `radius`, `duration`, `tickInterval`, `damageMin`, `damageMax`
  - `cleave` (target `self`): `damageMultiplier`, `coneDegrees`, `range`, `maxTargets`, `windup`
  - `buff` (target `self`): `duration`, `damageBonus` (percent)
  - `burst` (target `self`, Shield Break): `damageMultiplier`, `radius`, `windup`, `stagger`, `knockback`; `interrupts: 1` stops ordinary enemy attacks
  - `charge` (target `enemy`, Lunge): `damageMultiplier`, `distance`, `duration`, `hitRadius`; dashes at the target, or the cursor with none

  `damageMin`-`damageMax` is a spell's own damage at level 1 (it grows ×(level + 4) ÷ 5), plus spell power; `school` (`physical`, `holy`, `shadow`) says whether armour or resistance reduces it. Add an icon to `abilityIcons()` in `src/ui/icons.js`. Every spell is on the global cooldown and appears in the spellbook.
- **New things for someone to say:** add `topics` and `nodes` to their `dialogue.json` record. A `when` such as `{ "quest": "missing_delivery", "status": "done" }` holds a line back until the story gets there.
- **An obscured (dark) area:** add an entry to `obscured` in `world.json`: `{ "id", "name", "position": [x, z], "radius", "text" }`. Without a torch (any item of kind `torch`, with a `light` radius, in the off hand) the Warden is pushed back at its edge and `text` shows in the log; with one, the dark thins and they can walk in. It shows black on the minimap. Put something worth finding inside with `placedLoot`, and a `clearings` entry in `scenery.json` so trees stay out.
- **Water and fish:** add an entry to `water` in `world.json`: `{ "id", "name", "position": [x, z], "radius", "fishTable" }`. The ground dips into a pond there, the water blocks walking, and it shows blue on the minimap. `fishTable` is an ordinary loot table (rarity weights and items per rarity); fish are items like any other and are never shown in the water. Add a `clearings` entry so trees stay out.
- **Bait:** an item with `bait: <percent>` adds that much to the catch chance while it is in the bags; one is used per strike.
- **A skinnable beast:** give the enemy type `skin: { "table": <loot table>, "rank": <Skinning rank needed> }`. With Skinning learned (Agna Holt teaches it) and a knife (an item with `skinningKnife: true`, and `skinningSkill` for a bonus) in the bags or tool pack, its body waits once looted and can be skinned for that table. The skill rises while the beast is under 10 ranks below yours, now and then up to 20, then never (`skinning` in `src/config.js`).
- **A learnable skill:** add a `skills.json` record with a `trainer`, `cost`, `maxRank` and the ability it `teaches`, and give that ability `skill: "<skill id>"` (and `requiresItem` if it needs a tool). The trainer then offers "Teach me ..." in dialogue, and the ability stays out of the spellbook until learned.
- **A new place:**
  1. Add props to `scenery.json`, with examine text in `text.json`.
  2. Add spawns and placed loot to `world.json`. A new region is a `regions` entry.

## How it maps to Unity

Each file is a list of records with stable ids, which is how Unity ScriptableObject databases are usually built: one ScriptableObject class per file type, such as `ItemDefinition`, `EnemyDefinition`, `LootTable`, `ShopDefinition` and `QuestDefinition`. References become asset references resolved by id at import. A small editor importer can read these JSON files into assets, and `src/data/schema.js` is the checklist for its validation.

## Code layout

- `src/data/db.js` loads `/data`, runs the checks, and indexes records by id.
- `src/config.js` holds engine tuning, and exposes archetypes, enemies (with their numbers worked out) and ability tuning from the data under their long-standing names.
- `src/data/scaling.js` holds growth by level and the item and enemy formulas; it has no imports, so `npm run validate` runs it in Node.
- `src/world/layout.js` exposes `world.json` and `scenery.json` to the world builder.
- Systems in `src/systems/` own their state and talk through the event bus. The HUD only displays state and asks systems to act.
- `src/systems/quests.js` is the quest log: status, objectives, accept, hand in, save. `src/systems/dialogue.js` is the conversation. `src/ui/questUI.js` draws both, the tracker and the ! and ? marks; `src/ui/minimap.js` draws the map.

## Godot

The game is being ported to Godot 4.5; see `docs/godot.md`. The Godot project shares `/data` and `assets/models` with the browser build, so content rules above apply to both. Models and icons are made by hand or taken from asset packs, never generated by code.

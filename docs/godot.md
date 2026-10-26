# Shadowfell in Godot

Shadowfell is moving from the browser build (JavaScript and Three.js, in `src/`) to **Godot 4.5**. The Godot project sits at the root of this repo (`project.godot`), next to the browser build, so both read the same content:

- `data/*.json`: items, enemies, quests, abilities, the world layout. Edit them by hand, with the quest editor (`npm run editor`), or ask Claude.
- `assets/models/*.glb`: the 3D models.

A change to the data shows up in both builds. The browser build stays playable at the Pages link until the Godot build catches up, so nothing is lost while the port runs.

## Setting up your machine

1. Install **Git**, **Node.js 20+**, **Godot 4.5** (the standard build, not .NET) and **Claude Code** (the desktop app is the easiest).
2. Clone the repo: `git clone https://github.com/DWEBB-GIT/Shadowfell.git`, then run `npm install` inside it.
3. Open Godot, choose **Import**, and pick `Shadowfell/project.godot`. The first open imports every model, which takes a minute.
4. Press **F5** (Run Project). Make a character on the title screen and play: the controls are the browser build's (WASD or the left stick, click to select, right click to attack or talk, 1-4 Q E for spells, Space to interact, Tab to cycle targets).
5. Open the same folder in Claude Code, and ask for changes there. Claude edits the files and you press F5 to see the result.

Folders holding a `.gdignore` file (the JavaScript code, tests and tools) are hidden from Godot on purpose.

## How the Godot project is laid out

The Godot code is a faithful port of the browser build: each file in `src/` has a matching GDScript file with the same systems, rules and numbers, so a fix or a feature can be carried across by reading the two side by side.

| Path | What it is | Browser build |
|---|---|---|
| `game/main.tscn`, `game/game.gd` | The game: starts every system, routes input, runs the loop, places the camera | `src/main.js` |
| `game/autoload/game_data.gd`, `game/core/db.gd` | Loads every data file; `DB` holds the tables and tuning | `src/data/db.js`, `src/config.js` |
| `game/core/` | Items and rolls, scaling, events, input (keys keep the browser's names), gamepad, the save store | `src/data/items.js`, `src/core/` |
| `game/entities/` | The player, enemies and the procedural animation rig | `src/entities/` |
| `game/systems/` | Combat, spells, resources, targeting, loot, quests, dialogue, shops, fishing, cooking, camp, death, reputation, titles, saves, key bindings, settings | `src/systems/` |
| `game/world/` | Terrain, layout, the world itself (woodland, buildings, lights, mist), ponds and dark places, collision | `src/world/` |
| `game/render/` | Generated effect textures, telegraph and cutaway shaders, sparkles | `src/render/` |
| `game/ui/` | The HUD and its windows: bags, character panel, spellbook, professions, talents, settings and key binding, cooking, shops, trainers, dialogue, the quest log and tracker, the minimap, names over heads, the title screen and character select, damage numbers. `ui.gd` holds the shared look; `canvas_2d.gd` lets the browser's canvas drawing (spell glyphs, minimap) be ported line for line; item icons and target portraits are snapshots of the real models (`icons.gd`) | `src/ui/` |
| `game/tests/run_tests.gd` | Headless checks: data, terrain heights against the browser build, then a short game (`npm run godot:test`) | |
| `game/tests/data_editor_check.gd` | Tests the Game Data editor on a copy of `data/`: files read back unchanged, a new sword saves and passes the checks | |
| `game/tests/quest_npc_editor_check.gd` | Tests the Quests, Quest chains, NPCs, Dialogue, Skills and Abilities tabs on a copy of `data/`: a new npc with a shop, a quest, a skill and a trained spell saves and passes the checks, broken data is caught | |
| `game/tests/trainer_spell_check.gd` | A class spell a trainer teaches: unknown until learned, locked below its level, costs its coins, kept in the save | |
| `game/tests/check_scripts.gd` | Compiles every script and lists any that fail | |
| `game/tests/perf_parts.gd`, `game/tests/perf_render.gd` | Frame cost: CPU time per system, and frame time with parts switched off in turn | |
| `game/tests/screenshot.gd` | Renders the game to a PNG without opening the editor; a fourth argument opens windows (`-- out.png 0 10 bags,character,quests`) | |

Saves live in Godot's user folder (`user://store`, which is IndexedDB on a web export), one file per key, in the same format as the browser build's saves.

### Matching the browser build's look

- Lights: three.js divides every light by pi and Godot does not, so intensities are scaled (`Tex.LIGHT_SCALE`, `Tex.OMNI_SCALE`, `Game.SUN_MATCH`). Side-by-side screenshots of both builds match within about 10%.
- The Compatibility renderer reads vertex colours as sRGB, so model colours (stored linear in .glb files) are converted once when a model loads, and the terrain stores its colours as sRGB.
- `diffuse_lambert` and `specular_disabled` render black in the Compatibility renderer, so materials keep the defaults.

## Editing game data in Godot

The **Game Data** screen (top bar, next to 2D, 3D and Script) edits the data files from inside the Godot editor. It is an editor plugin in `addons/shadowfell_data`, switched on in Project Settings > Plugins.

- **Items**: New item asks what it is (one-hand weapon, then sword; armour, then slot; potion, food...), its name and rarity. Then set the item level, swing speed, price and description, give each stat a share of its points (the screen shows the damage and stats it will have in game), set what it does when used, and choose its model and sprite. *Import model* copies a .glb into `assets/models`; *Choose sprite* copies a .png into `assets/icons` and the game shows it as the item's icon instead of a picture of the model.
- **Loot tables**, built the way WoW does it:
  - An enemy's **own table** holds only what is its own (a ghoul's bones, a boss's blade). Pick an enemy to choose its own table and skinning table.
  - **World drops** are level bands (levels 1 to 5, 6 to 10...) of the gear any mob of those levels might carry. Every enemy rolls the band its level falls in as well as its own table, picked by level, so nothing is assigned by hand. Beasts (and anything else with *World drops* off) roll no band.
  - A ghoul in a higher zone is a **level variant**: *Make a level variant* adds an entry that names the ghoul as its `base` and changes only its name, level and tables. *Up to level* gives a level range: each spawn rolls its level in it (fixed per spawn). Place its spawns in `world.json` (`enemySpawns`).
  - Each item shows its chance a kill.
  - **Quest drops**: an item on an enemy's own table that drops only while the player has the quest and still needs it (a consignment note on a bandit), at its own chance. The quest must ask for the item (a collect objective); the quest's objective on the Quests tab shows where it drops.
- **Quests** (grouped by who gives them), the browser quest editor's design: giver and hand-in npc, the quests it requires, a choice name (quests sharing one lock each other), what the giver says (summary, offer, progress, complete), objectives (kill an enemy, collect an item, examine a point, talk to the hand-in npc; count, tracker label, map area) and the reward (coins as a min-max range, experience, items from the item picker, reputation), and the flag it sets. It lists the quests it needs and unlocks and the dialogue lines that check it. *New quest*, *Follow-up quest* and *Duplicate*; a quest's id is made from its name and locked once saved.
- **Quest chains**: every quest as a box with arrows to the quests it unlocks, each chain on its own row. Drag from one quest to another to add a requirement; drag an arrow off to remove it.
- **NPCs**: name, title, level, model, tint, map icon, innkeeper and notice board; their plain greeting (*Give them a greeting* makes a dialogue for a new npc); the shop they keep (*New shop*), its vendor type and faction, and its stock, picked from the items that vendor type sells; the quests they give and take back (*New quest from...*); and where they stand (*Place in Brackenford* for a new npc, then move them with the World editor). *Trains* lists the skills and class spells they teach (add either there, or *New skill* / *New spell*) and their recipes.
- **Dialogue**: each npc's greetings (the last whose condition holds is said), topics on the first page, and nodes with replies that open another node or go back. A condition is a quest's status, a story flag or a place looked at.
- **Skills**: what a trainer teaches for coins (Camping, Fishing): its trainer, cost, top rank if it rises with use, and the abilities (tools) it teaches. *New ability for this skill* makes a spell the skill teaches.
- **Abilities**: class spells and skill tools. *New spell* asks its kind (cast, damage over time, cleave, buff...) and starts it with the numbers that kind needs; the spell engine runs it with no new code. Set its target, range, school, numbers, cost and gain; anything else (auras, follow-ups) is JSON under *Other fields*. Under *Classes*, tick a class to put it in its spellbook, then choose whether they know it from the start or a trainer teaches it from a level, for coins (`trained` in archetypes.json; a spell on the starting bar is always known).
- **Chests**: coins and items in each chest.

Nothing is written until **Save**; **Revert** throws changes away. The checks along the bottom are the rules `npm run validate` applies, so a problem shows before the build refuses it. An item's id is made from its name and locked once saved, because saves, shops and quests use it. `game/tests/data_editor_check.gd` and `game/tests/quest_npc_editor_check.gd` test the editor on a copy of `data/`.

The World editor (`world_editor.tscn`) keeps its own copy of `world.json` while it is open: after placing an npc from the NPCs tab, open (or reopen) the World editor scene to move them.

## Art: made by hand, not by code

Models and icons are real files, never generated by code (Dan, 2026-10-19):

- **Free asset packs first**: KayKit, Quaternius and Kenney are low-poly, free and fit the retro look. They come as .glb files that Godot imports directly.
- **Mixamo** for character rigs and animations.
- **Blender, by hand** for unique pieces, saved as .glb in `assets/models`.
- **Icons** for items and spells are image files (PNG) in `assets/icons`.

`assets/blender/build_assets.py`, the script that makes today's placeholder models, is retired once real assets replace them. Models without a .glb yet (the town board, the waymarker, the well) show as grey boxes, so missing art is easy to spot.

## Exporting for the web

`export_presets.cfg` has a **Web** preset: single-threaded, so it runs on GitHub Pages, which cannot send the headers that threads need. Install Godot 4.5's export templates (Editor > Manage Export Templates), then run:

```
godot --headless --path . --export-release "Web" build/web/index.html
```

Serve the folder from any web server; opening the file directly won't work. The build is about 40 MB, most of which is the engine itself (`index.wasm`), and the game data is about 2 MB. Pages compresses it when it serves it. `game/tests/audio_check.gd` renders every sound and prints how long each took and how loud it peaks.

## Performance: simulate everything, draw what you see

The world is built to work as a shared (later multiplayer) world: every
system (enemies, respawns, quests, the clock) runs for the whole map no
matter where the camera is. Only drawing is local to each screen:

- **Loading screen.** `Game.load_world()` runs behind `LoadingScreen` when a
  character enters the world. It synthesises every sound, draws each model
  and effect once off-screen (so the GPU compiles their shaders up front)
  and paints the portraits, then fades out. Nothing hitches the first time
  you swing, cast or meet an enemy.
- **Streaming the world.** The whole world (5 x 7.7 km) is one baked file,
  `data/terrain/world.bin`: 128 m tiles of heights, walkability, surface and
  zone, each compressed and only unpacked when something asks about it
  (`Terrain`). `Land` builds 64 m chunks of ground, trees, rocks and grass
  within 112 m of the camera, a few milliseconds per frame, and frees them
  past 176 m. Trees are placed the same way every time from the chunk's
  position, and their collision is registered per chunk on demand, so the
  game never depends on what one screen happens to draw (safe for
  multiplayer).
- **Draw distance.** The camera's far plane sits just past the fog; grass
  stops at 36 m (`visibility_range_end`), lamps fade out from 40 m, and the
  sun's shadows reach 40 m.
- **Animation.** Idle enemies more than 45 m away skip skeleton updates
  (their logic still runs).
- **UI.** The minimap and action bar redraw only when something changes.

To measure: `game/tests/perf_parts.gd` (CPU per system) and
`game/tests/perf_render.gd` (frame time and triangles).

## The world map and how it is built

Dan's painted map is the master. `data/world_map.json` holds it traced
(`world`: coast, zones, settlements, routes, landmarks; `terrain`: mountains,
forests, rivers; `act1`: Act 1's regions, valleys, POIs and story notes).
`tools/world/bake_world.py` turns it into `data/terrain/world.bin` and
`data/terrain/water.json` (rivers and lakes); run it again after changing
the map (`python3 tools/world/bake_world.py`, needs numpy and Pillow). It
prints which places can't be reached on foot; only boat-only places and
mountain landmarks should be listed.

- High ground, the sea and rivers can't be walked; roads, tracks, fords and
  clearings around every settlement and POI always can.
- `WorldMap` answers which region and valley you are in; `Discovery` puts a
  marker on each POI, discovers it when you come within 30 m (a banner and
  some XP) and runs the boat ferries (Space at a jetty).
- M opens the world map (`WorldMapUI`): zones, roads, boats, the places
  you've found and you.
- Act 1 sits in the world at `world.act1Offset`; positions in
  `data/world.json` are world positions.
- `game/tests/world_check.gd` checks the tiles, regions, chunk cost,
  discovery, boats and saves.

## Port plan

Each step is its own pull request, and the browser build keeps working throughout.

1. **Done: world and walking.** The project shares the data and models, the world is built from data, and there's a player with WASD movement and the isometric camera.
2. **Game core and every system** (2026-10-21): combat, targeting, spells and class resources, enemies and telegraphs, loot, chests, quests, dialogue, shops, fishing, cooking, camp, death, reputation, titles, saves and key bindings, with a working HUD (bars, spell bar, cast and swing bars, target frame, log, damage numbers) and a plain title screen.
3. **Done: full UI** (2026-10-21): bags and character panel, spellbook, quest log and dialogue windows, shops and trainers, the minimap, settings and key binding, the full title screen and character select, item and spell icons, names over heads.
4. **Done: audio and a web export check** (2026-10-21): every sound effect and the ambience (wind, the rumble near elites, bells, crows, creaks) are synthesised by the same recipes as the browser build (`game/systems/audio.gd`), with the master, effects and ambience sliders. The fonts are bundled (`game/fonts`, DejaVu), because the web has no system fonts. The web export loads, makes a character and plays in headless Chromium.
5. **Art pass**: swap placeholder models for asset packs, Mixamo characters and PNG icons.
6. **Hand-placed world**: move world layout from `world.json` into Godot scenes, so you can place things in the editor instead of typing positions.
7. **Web export**: publish the Godot build to the Pages link and retire the browser build.
8. **Clean-up**: a refactor pass to keep the code clean and fast, once the port is finished.

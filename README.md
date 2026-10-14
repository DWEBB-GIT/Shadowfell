# Shadowfall: The Fallen Road (build 2)

A small dark fantasy action RPG prototype built to the *Shadowfall Game Design & Build Scope v0.1*. One region, one character, four undead, one investigation, and a save that survives closing the browser.

## Launch

1. Open `index.html` in Chrome or Edge (double-click it, or drag it into the browser window).
2. Choose **Begin**, or **Continue** if you have a save.

No install, web server or internet connection is needed. Three.js and every Blender model are bundled into `dist/shadowfall.js`, so the game also runs offline.

The project is a git repository (branch `main`). `dist/` is committed so a fresh checkout runs straight away; run `npm install` and `npm run build` after changing anything in `src/`.

## New in build 2

- **Ground telegraphs, after Final Fantasy XIV.** The Gravebound Brute paints its attacks on the ground before they land: an amber cone for its ordinary cleave and a large orange cone for **Grave Slam** (24 damage, 1.4 s wind-up). The cone fills as the wind-up runs, a cast bar shows under its health bar, and anyone still inside when it fills is hit. The area is fixed when the wind-up starts, so walk out or Brace. Shield Break interrupts the cleave but not the slam.
- **Global cooldown, as in classic WoW.** Shield Break and the new **Lunge** (a 5 m charge that strikes on arrival, 1.5× damage, 8 s cooldown) share a 1.5 s GCD. Strike, Brace and draughts stay off it. The spell bar shows each cooldown as a sweep, and the GCD as a second sweep.
- **Diablo-style spell bar** along the bottom of the screen, with the experience bar above it, the character and save buttons, coins, and four bag slots.
- **WoW bags.** The backpack (16 slots) sits in the right-most bag slot; three more slots take bags. A Traveller's Satchel (8 slots) lies in the western ruins. Click a bag slot to open or close that bag; each bag window also has its own ×, and B opens or closes them all. The bags, the character panel and the spellbook are separate windows, and none of them pause the game.
- **Editable spell bar.** Each of the seven slots has a fixed key (1, 2/Q, 3, 4, left click, right click, Space). Drag spells along the bar to rearrange them, or drag one off the bar to remove it. The spellbook (P) lists every spell to drag back on, a healing draught can be dragged from the bags onto the bar, and clicking a slot uses it. The layout is saved.
- **Drag and drop.** Drag an item from a bag onto the character panel to equip it, and back to unequip. Right-click equips or uses. Drag an item out of the windows onto the world to drop it on the ground, RuneScape style; it stays there (and in your save) until you pick it up.
- **More to wear.** Seven equipment slots. A dented watch helm (+8 maximum health) lies among the rocks near the watch post, and shows on the Warden when worn.
- **Gamepad support** (Xbox or PlayStation pads in Chrome or Edge), including the bags and character panel.
- **Fog and light.** Linear view-distance fog swallows the road ahead, low mist drifts over the ground, the light is a warm dusk, the Warden carries a glow, and braziers burn at the watch post.
- **Saves carry over.** A build 1 save is upgraded on load: its items go into the backpack and its weapon into the main hand.

## Stats and damage

The design and the comparison with RuneScape, Skyrim, Diablo and Lost Ark are in [docs/stats-and-damage.md](docs/stats-and-damage.md). In short:

- **Four attributes:** Might, Finesse, Intellect and Vitality. Each archetype has a main attribute that adds to its damage; the Warden's is Might. Vitality gives health.
- **Derived combat stats:**
  - weapon damage ranges;
  - crit chance (5% plus Finesse) at 150% damage;
  - armour, a capped percentage reduction that weakens against higher-level attackers;
  - shield block: block chance plus block rating, and each block stops 30% of the hit;
  - haste, from gear only, which shortens swings, windups and the global cooldown.
- **Armour types:** cloth, leather, mail and plate. Each archetype can only wear some types; the Warden can wear all of them and use shields, and starts with a battered kite shield.
- **No hit rolls and no dodge chance.** Avoiding damage comes from telegraphs and the defensive button.
- **One formula for every hit:** base × ability multiplier, then crit, then armour, then block.
- **Damage numbers** float up for hits dealt (pale), hits taken (red) and heals (green). Crits are larger, amber and marked "!", and blocks read "Block". They stay small and muted, as the design asks.
- **Enemy health:** the target frame shows the health of the enemy you are locked on to, aiming at or fighting. Enemies with mana also get a blue bar there and over their heads.
- **Character panel:** shows every stat. Item tooltips show weapon ranges, armour type and stat bonuses.
- **Level-up:** a card lists each stat that rose, old value to new, and the character panel marks those stats with a green "+n".

All numbers are in `src/config.js` (`stats`, `archetypes` and the enemies) and in the item definitions.

## Items and Mara's forge

- **Item database.** Every item is defined once in `src/data/items.json`: name, kind, slot, armour type, quality, damage, stats, use effect, bag size, stack size, buy price, model and icon. The game checks the file at startup and logs any malformed entry. Adding an item is a new entry there, plus a Blender model if it needs a new look.
- **Mara Venn's forge** stands beside the watch post: a forge, an anvil and an awning, with Mara hammering at her anvil until you come close. Press E (A on a pad) to talk to her. Her shop opens on the left with your bags on the right.
  - Click an item to buy it (A on a pad). Merchants' stock is in `src/data/merchants.json`.
  - Right-click anything in your bags (or drag it onto her window, or Y on a pad) to sell it. Merchants pay a quarter of the price, as in WoW, and tooltips show what an item sells for.
  - Anything sold can be bought back for what it fetched until you leave the game.
  - Quest items cannot be sold or dropped.
  - Walking away closes the shop.
- **The manifest.** Once you have the manifest, the objective says to return to Mara. Hand it over in her shop for 20 coins and 50 experience; that closes the cart storyline, and she points you north to the Blackwood.

## Controls

One scheme for keyboard and mouse and for a gamepad. The camera is fixed (the scenes are composed for that one isometric angle) and movement is direct.

**Targeting.** By default it is a *soft lock*: Strike, Lunge and any other targeted ability go to the enemy nearest where you aim (the cursor, or the right stick) that is in range and roughly in that direction. A faint gold ring shows who your next blow will go to, so you never have to select anything. Press **Tab** (or **R3**) for a *hard lock* on the enemy you are aiming at, or the nearest one: a red ring and a frame at the top of the screen mark it, the Warden keeps facing it as you move, and every targeted ability goes to it wherever the cursor is. Press Tab or R3 again (or Esc) to let go; a lock also ends when the enemy dies or is far away. Ranged and cast spells, when they arrive, use the same rule with their own range; ground-targeted spells land at the cursor or stick point.

**No dodge, no sprint.** Space is a single defensive button on a 7 s cooldown, and the slot belongs to the archetype. The Warden's is **Brace**: raise the shield and the next blow within 2.5 s, even a Grave Slam, is turned aside. It is off the global cooldown.

**Looting.** Defeated enemies give experience at once, but their coins stay on the body until you loot it. Click a body or anything lying on the ground (within a few metres) to loot it, or press E / A when the prompt shows. Either way it also loots every other body and dropped item within 5 m, so after a fight one click picks up the lot; the prompt says how many ("Loot the Ashen Ghoul (and 2 more nearby)"). Things placed in the world, such as the manifest, are still taken one at a time. Looted bodies sink away; unlooted ones are kept in your save.

| Keyboard and mouse | Gamepad | Action |
|---|---|---|
| WASD | Left stick | Move |
| Mouse | Right stick | Aim (with no stick input, you aim the way you face) |
| Tab | R3 (stick click) | Hard lock on, or let go |
| Left click | X or RT | Strike (spell-bar slot 5); a click on a body or a drop loots it instead |
| Right click | Y | Shield Break (slot 6) |
| Space | B | Brace, the defensive slot (slot 7) |
| 1 | RB | Lunge (slot 1) |
| 2 or Q | LB | Healing draught (slot 2) |
| 3 · 4 | LT · D-pad left | Spell-bar slots 3 and 4 (empty to start) |
| E | A | Interact, examine, loot everything nearby |
| B (or I) | Start | Bags |
| C | View | Character panel |
| P | D-pad up | Spellbook |
| K | D-pad down | Save |
| Esc | B (in a window) | Close windows, then let go of the lock |
| M | | Sound on or off |

The spell-bar rows above are the default layout; keys belong to slots, so moving a spell moves its key. Clicking open ground is always the basic attack; it never moves the Warden.

**Windows on a gamepad:** while a window is open the pad drives it (the world keeps running). The d-pad or left stick moves a highlight. A picks an item or spell up and puts it down (to move, swap, equip, unequip, or place a spell on the bar), X equips or uses an item, Y drops an item on the ground or removes a spell from the bar, LB/RB jump between the bags, character panel, spellbook and spell bar, and B cancels or closes.

## What is in the region

- **The road** runs north from the road's end, past the shrine and the cart, to the ruined watch post.
- **The roadside shrine** (east of the road, candles lit) restores health and becomes your respawn point.
- **The abandoned cart** (west of the road, missing a wheel) holds the manifest and some spilled grave-iron. Reading the manifest completes the investigation.
- **Old graves** in the western woods, a **healing draught** among the eastern rocks, a **purse** by the ruined wall near the watch post, a **Traveller's Satchel** in the western ruins, and a **dented helm** among the rocks east of the watch post.
- **Hallow Cut**, the fresh timber graves hung with bells north-east of the road, is the Gravebound Brute's ground. Watch its telegraphs. It drops Watchman's Edge (23 damage against the worn longsword's 18), which you equip by dragging it onto the character panel.

Three Ashen Ghouls and the Brute are placed so they are not all visible from the start, and one is off the road.

## Balance (from section 9.7)

Every number lives in `src/config.js`. At average rolls: player 100 HP, strike 18 (16–20), Shield Break 2× strike (36), ghoul 48 HP / 8 dmg after armour / 1.35 s, brute 96 HP with 10 armour / 13 dmg after armour / 1.05 s, draught +42, ghoul 28 XP, brute 65 XP, level 2 at 100 XP (+2 Might and +2 Vitality: +12 max HP and +2 strike, then 160, 220 … XP per level), death costs 20% of coins capped at 5. Build 2 adds a 1.5 s GCD, Lunge 1.5× strike with an 8 s cooldown, Grave Slam 24 damage with a 1.4 s wind-up and 7 s cooldown, a 1 s cooldown between draughts, and fog from 14 m to 40 m. Brace has a 7 s cooldown and a 2.5 s window; area looting reaches 5 m (`loot` and `targeting` in config).

## Saving

- K saves to the browser's local storage and confirms only after the data reads back correctly.
- The game also autosaves when the tab is closed, refreshed or hidden.
- On launch the save is validated. If it is unreadable the game starts fresh, says so on the title screen, copies the bad save to `shadowfall.save.unreadable`, and does not autosave over it until you press K.
- Saves live in the browser you play in, so Chrome and Edge keep separate saves.

## Project layout

```
index.html, style.css     page and HUD styling
dist/shadowfall.js        the bundled game (what index.html loads)
src/
  main.js                 initialisation, main loop, input routing, camera
  config.js               all tunable numbers
  core/                   events (pub/sub), keyboard/mouse input, gamepad
  assets/                 loads the embedded Blender .glb files (+ procedural fallback)
  render/textures.js      small painted canvas textures
  world/                  layout data, terrain, collision, world builder
  entities/               player, enemy, procedural rig animation
  systems/                combat, telegraphs, enemies, loot, interaction,
                          targeting, action bar, stats (the damage formula),
                          inventory (bags/equipment), progression,
                          world state, save, effects, audio
  ui/hud.js               HUD, spell bar, modals (reads state, requests actions)
  ui/itemUI.js            bags, character panel, drag and drop, pad menus
  ui/icons.js             item icons rendered from the Blender models
  data/                   item definitions and all written text
assets/
  blender/build_assets.py Blender script that builds every model
  models/*.glb            exported models used by the game
  fbx/*.fbx               the same models as FBX, for Unity
docs/                     design notes (stats and damage)
tests/                    automated acceptance test (Chromium), latest results,
                          and screens.mjs for reference screenshots
```

Systems own their own state and talk through the event bus; the HUD never decides outcomes. Positions in `src/world/layout.js` and items in `src/data/items.js` are plain data with stable ids, which keeps saves meaningful across layout tweaks and should port directly to Unity ScriptableObjects or JSON.

## Rebuilding

```
npm install
npm run build        # rebundle dist/shadowfall.js after editing src/
npm test             # run the acceptance checklist in headless Chromium
node tests/acceptance.mjs gamepad telegraphs   # run only some sections
npm run assets       # rebuild the models (Blender 4.2 or later on PATH; tested with 5.2)
```

`npm run assets` can also be run as `python assets/blender/build_assets.py` with the `bpy` module installed (`pip install bpy`, Python 3.13). After rebuilding models, run `npm run build` to embed them.

## Notes for a move to Unity

- `assets/fbx/` holds every model with the same part hierarchy. Characters are split into `Torso`, `Head`, `Arm_L`, `Arm_R`, `Leg_L`, `Leg_R` and `Weapon`, each pivoting at its joint, so they can be animated in Unity directly or re-rigged later. Colour is stored as vertex colour, so use a vertex-colour shader (or bake to a texture).
- The ground telegraphs are a sector mesh with a small shader whose `uProgress` uniform fills it (`src/systems/telegraphs.js`); in Unity this maps to a decal or projector with the same parameter. Hit tests use the locked shape, not the mesh.
- Inventory locations are plain strings (`b:<bag>:<slot>`, `e:<slot>`, `s:<bag slot>`), shared by the mouse UI, gamepad UI, saves and tests.
- `src/config.js`, `src/world/layout.js`, `src/data/items.js` and `src/data/text.js` are the design data. The system split in `src/systems/` maps one-to-one onto MonoBehaviours or services.

## Known limits of this build

- Only the Brute uses ground telegraphs; the ghouls keep their raised-arm wind-up.
- Bags cannot be re-ordered between bag slots while they hold items (as in WoW, empty a bag before moving it).
- Enemies use simple circle collision and do not path around large obstacles.
- The watch post is a landmark only and cannot be entered (as the design specifies).
- Animation is procedural, not keyframed.
- There are no ranged or ground-targeted spells yet; targeting already supports both (`Targeting.aimFor` with `'enemy'` or `'ground'`).
- No enemy in this region has mana yet; the HUD shows it for any enemy whose config gives it some.
- Mara Venn, dialogue and a reward for the manifest are outside this build's scope.

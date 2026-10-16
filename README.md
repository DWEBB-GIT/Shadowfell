# Shadowfall: The Fallen Road and the Blackwood (build 2)

A small dark fantasy action RPG prototype built to the *Shadowfall Game Design & Build Scope v0.1*. One region, one character, four undead, one investigation, and a save that survives closing the browser.

## Launch

1. Open `index.html` in Chrome or Edge (double-click it, or drag it into the browser window).
2. Choose **New character**, or **Continue** to play your last character.

### Title screen and characters (alpha)

- **Title screen:** Continue (names your last character), Characters, New character and Controls.
- **Character creation:** pick a class (the Warden for now; the Ranger and Occultist are shown as coming later), type a name or roll one with the dice (gamepad Y), then **Create and enter**. Names are one or two words of letters and must be unique.
- **Character select:** your characters with their level, class and where they stand, latest first. Enter world (or double-click), Create new, or Delete (asks first, and removes that save). Up to 10 characters.
- **Saves:** each character has its own save in the browser. The first character keeps the old save key, so a save from before this build shows up as a character called Warden. **Settings → Save and return to characters** logs out.
- The keyboard (arrows, Enter, Esc, Del) and the gamepad (D-pad or stick, A, B, Y) drive every screen. Title text, classes and the name lists are in `data/text.json` under `title`.

No install, web server or internet connection is needed. Three.js and every Blender model are bundled into `dist/shadowfall.js`, so the game also runs offline.

The project is a git repository (branch `main`). `dist/` is committed so a fresh checkout runs straight away; run `npm install` and `npm run build` after changing anything in `src/`.

## New in build 2

- **Ground telegraphs, after Final Fantasy XIV.** The Gravebound Brute paints its attacks on the ground before they land: an amber cone for its ordinary cleave and a large orange cone for **Grave Slam** (31 damage, 1.4 s wind-up). The cone fills as the wind-up runs, a cast bar shows under its health bar, and anyone still inside when it fills is hit. The area is fixed when the wind-up starts, so walk out or Brace. Shield Break interrupts the cleave but not the slam.
- **Global cooldown, as in classic WoW.** Shield Break and the new **Lunge** (a 5 m charge that strikes on arrival, 1.5× damage, 8 s cooldown) share a 1.5 s GCD. Strike, Brace and draughts stay off it. The spell bar shows each cooldown as a sweep, and the GCD as a second sweep.
- **Diablo-style spell bar** along the bottom of the screen, with the experience bar above it, the character and save buttons, coins, and four bag slots.
- **WoW bags.** The backpack (16 slots) sits in the right-most bag slot; three more slots take bags. A Traveller's Satchel (8 slots) lies in the western ruins. Click a bag slot to open or close that bag; each bag window also has its own ×, and B opens or closes them all. The bags, the character panel and the spellbook are separate windows, and none of them pause the game.
- **Editable spell bar.** Each of the seven slots has a fixed key (1, 2/Q, 3, 4, left click, right click, Space). Drag spells along the bar to rearrange them, or drag one off the bar to remove it. The spellbook (P) lists every spell to drag back on, a healing draught can be dragged from the bags onto the bar, and clicking a slot uses it. The layout is saved.
- **Drag and drop.** Drag an item from a bag onto the character panel to equip it, and back to unequip. Right-click equips or uses. Drag an item out of the windows onto the world to drop it on the ground, RuneScape style; it stays there (and in your save) until you pick it up.
- **More to wear.** Seven equipment slots. A dented watch helm (+8 maximum health) lies among the rocks near the watch post, and shows on the Warden when worn.
- **Gamepad support** (Xbox or PlayStation pads in Chrome or Edge), including the bags and character panel.
- **Fog and light.** Linear view-distance fog swallows the road ahead, low mist drifts over the ground, the light is a warm dusk, the Warden carries a glow, and braziers burn at the watch post.
- **Saves carry over.** A build 1 save is upgraded on load: its items go into the backpack and its weapon into the main hand.

## Playtest batch, 2026-10-16 (Dan's list)

- **Townsfolk.** A conversation groups its choices under Quests, Ask about and Services. Each kind has its own badge: speech, goods (Browse goods), training (Train) and the inn (Make this inn your home). **Train** opens a trainer window like the shop. It lists every skill and recipe that person teaches, with what it needs, its cost and Learn. The shop and the trainer window both have **Back** to the conversation.
- **Professions (U).** Professions have their own window with your rank in each, and their abilities (Fishing, Cooking, Set Camp) to drag onto the bar. The spellbook (P) now keeps to spells. There is also a Professions button with the menu buttons.
- **Bottom right.** The menu buttons sit in one row with the bag slots, and your money is in the corner. On a narrow screen the spell bar moves left to stay clear of them.
- **On screen.** Damage you take shows as "-n". The selected enemy's bar shows its health in numbers. Your name shows over your character, and Settings (O) can turn it off.
- Bows, signposts, cooking, Well Fed and fishing are under their own headings below.

## Dual wielding

- One-handed swords and daggers (the arming sword and rusty dirk from Mara, the militia sword and ghoulbone knife as drops) go in either hand. Drag one onto the off hand to dual wield.
- Each hand swings on its own timer at its own weapon's speed, with its own animation. The off hand opens half a swing later and never lands within 0.2 s of the main hand, so the blows alternate.
- Off-hand blows do half damage and build half the Resolve. Two swing bars show while dual wielding, and the character panel shows both hands.

## Brackenford, the Ford Inn and Cooking

- **Brackenford** is a small town at the south end of the Fallen Road, a short walk south of where you start: three cottages, a well, lamp posts and the **Ford Inn**.
- **Indoors.** Walk in through the inn's west door. Its walls are solid; inside, the roof hides, the front wall fades to a ghost, and the camera comes in about a fifth closer. All of it eases back as you step out.
- **Hester Vale**, the innkeeper, sells food, teaches Cooking (10 coins) and its recipes, and can make the inn your home: if you fall, you wake by her hearth. Standing inside the inn with no enemy near builds rested experience, as by your camp fire.
- **Cooking.** Learn it and you know Grilled Perch and Roast Dace. Hester teaches Hound Steak (Cooking 10), Traveller's Stew (20, hound meat and perch) and Smoked Eel (30). Cook at the inn hearth (E there opens the Cooking window) or by your camp: a 2.5 s cast each, Cook or Cook all, and moving stops it. Recipes are orange, yellow, green or grey (WoW): orange always raises the skill, yellow usually, green now and then, grey never.
- **Food.** Use a dish to sit and eat: it heals over 15 seconds, out of a fight only, and stops if you move or are hit. Eat for 10 seconds (even at full health) to become **Well Fed**: +2 Stamina for 15 minutes. Recipes live in `data/recipes.json`.
- **Signposts.** Four posts along the road (outside Brackenford, by the mere turning, at the fork for the watch post and the Blackwood, and inside the Blackwood). Hover over one to see where its arms point, with distance and direction, or press E (or click it) to read it on screen until you walk on. They live in `data/world.json` `signposts`.
- **Fishing.** Each cast runs a 20-second fishing bar. Whether anything bites is rolled when you cast, and the chance rises with your Fishing skill: your rank, plus your best rod (Tam's yew rod +10) and bait (cut bait +5, one used per cast). If the bar runs out without a bite, nothing was biting. The cursor turns into a hook over your bob.

## Combat feel (WoW)

- Auto attack opens with an instant blow the moment you reach the target, then swings on the weapon's timer. The swing bar fills as each blow lands.
- No animation lock: you move at full speed while swinging, shooting and using abilities, and a swing on its way never eats a key press. Abilities pressed in the last 0.4 s of the global cooldown are queued.
- Casts are broken by moving, and each hit while casting pushes the cast back 0.5 s (at most twice).
- **Bows:** put a bow in the ranged slot (Mara sells a hunting bow). Auto Shot fires at targets beyond melee reach on the bow's own timer while you stand still; arrows fly and hit on arrival. In melee reach the sword takes over.
- **Arrows and quivers:** each shot uses an arrow (sold by the hundred: rough from Mara or Tam, barbed from Tam, which hit harder). Tam's leather quiver goes in a bag slot, holds only arrows and makes Auto Shot 10% faster.
- **Bow abilities:** Quick Shot (instant arrow, 120% of a bow shot) and Venom Arrow (instant poison, 5 ticks over 15 s). Both use an arrow and appear on keys 6 and 7 when you first equip a bow.

## Mana and Resolve

- **Mana** pays for spells. The Warden has 100 plus 10 per point of Intellect (110 at the start). It refills at 1.5 a second in a fight and 10 a second out of one. A cast pays when it finishes, so an interrupted cast costs nothing.
- **Resolve** is the Warden's class gauge (0 to 100), shown under the mana bar. Each landed weapon swing gives 12, each hit you take 6, and a block 10 more. It fades at 8 a second once you have been out of the fight for 6 seconds.
- **Costs:** Shield Break 25 Resolve, Rend 20, Cleave 30; Hallowed Bolt 20 mana, Smite 15, Hallowed Ground 30, Rebuke 10. Lunge is free and gives 15 Resolve, and Battle Cry gives 25, so both open a fight. Brace, the draught, camp and fishing are free.
- A slot you can't afford is dimmed, and its tooltip shows the cost. Trying it says "Not enough mana" or "Not enough Resolve".
- Each class's mana and gauge numbers live in `data/archetypes.json` (`resources`), and ability costs in `data/abilities.json` (`cost`, `gain`). A later class gets its own gauge by giving it a different `gauge` block.

## Swing timer, layout and key bindings

- **Swing timer.** Time between swings = weapon speed ÷ (1 + haste), on its own clock. A bar where the cast bar sits fills up to the moment your blow lands, with the weapon's name and the seconds left. The blow lands at the swing's impact frame and only if the target is still in reach; haste shortens the gap between swings, not the swing itself. Details in `docs/stats-and-damage.md` (The swing timer).
- **Layout.** The spell bar and experience bar sit in the middle of the bottom edge. Coins, the menu and the bag slots are stacked on the far right.
- **Menu.** Five buttons: Character (C), Spells (P), Talents (N, an empty placeholder), Quest Log (L) and Settings (O). Skills moved into the Spells window header and Save into Settings (K still saves).
- **Key bindings.** Settings lists every action with its key; click one and press a new key (Backspace clears it, Esc cancels). A key taken from another action moves over. **Quick bind** lets you hover a spell or utility slot and press a key to bind it; Esc ends it. Bindings are saved in the browser and the bar labels and tooltips follow them.

## Armour, item budgets and enemy types

Dan approved this design on 15 October; [docs/stats-and-damage.md](docs/stats-and-damage.md) has the formulas and tables.

- **One growth line.** Everything that grows with level grows with (level + 4): the armour constant, item armour, item stat budgets, weapon damage, player spells, and enemy health and hits. The constants and formulas are in `src/data/scaling.js`.
- **Armour by your own level.** Damage reduction = armour ÷ (armour + 400 + 100 × your level), capped at 75%, so the character panel's percentage holds against every enemy. Armour numbers are ten times what they were: the travelling clothes have 30, and the Warden starts at 130 (21%).
- **Level gaps.** Every hit is ×1.2 for each level the attacker is above its target, and ÷1.2 for each level below, with at least 1 damage.
- **Items are worked out.** Gear states its item level, slot, armour type, rarity and a stat split; the game works out armour (cloth 3, leather 6, mail 9, plate 12 per slot weight), weapon damage (0.45 × (item level + 4) a second, ±40% a swing), a shield's armour and 10% block, and the stat points (0.4 × slot weight × (item level + 4), ×1 green, ×1.3 blue, ×1.6 purple; white has none). Tooltips show the item level. `npm run validate` prints each item's budget and refuses one more than 10% over. Block rating is folded into block chance, and suffixes on green drops spend the green budget.
- **Enemies by level and type.** No world scaling: each enemy's health, hits, attack speed and armour come from its level and type (fodder, pack beast, normal, skirmisher, armoured, elite, heavy, boss), sized against a par character of its level. Each spawn point's enemy has its own health within ±10%. The ghoul is 18 health and hits for 6; the brute 50 (45 at Hallow Cut) with 140 armour, hits of 9 and a 31 Grave Slam; the archer shoots for 12.
- **Spells** follow the weapons: Hallowed Bolt 3–4, Smite 1–3, Hallowed Ground 1 a second and Rebuke 1 at level 1, ×(level + 4) ÷ 5, plus 0.25 spell power per Intellect.

## Utility bar and camera (Dan's list, part 4)

- **Utility bar.** Four more slots after the combat bar, on keys 6–9 (gamepad: hold D-pad left and press X, Y, A or B, like FFXIV's cross hotbar). They take non-combat skills (Fishing and Set Camp land there when learned) and items dragged from the bags, WoW style: the torch lights on one press and goes away on the next, swapping your shield back in. Old six-slot bars move Fishing and Set Camp across.
- **Camera.** It stays fixed. Ground telegraphs, click targeting and gamepad aiming all read best from one known angle, as in Diablo IV and Lost Ark. Mouse-wheel zoom is the recommended next step; 90° snap turns are the safe option if turning is ever wanted.

## The world (Dan's list, part 3)

- **Respawns.** Every enemy type has `respawn` (seconds) in `data/enemies.json`: ghouls 90, hounds 75, archers 120, the brute 300, the seer 0 (never). A killed enemy comes back at its spawn point when its time is up (an unlooted body goes then), so you can grind for experience. Timers run on play time and are saved.
- **Names** float over townsfolk (green, with their title) and enemies (red, until their health bar shows). **Settings** (O, or the ☰ button) can hide names over characters and names of items on the ground.
- **Running** is the default: 6.5 m/s (was a 5 m/s walk), with a quicker stride.
- **Chests** (`chests` in `data/world.json`): the Traveller's chest by the cart (open), the Watch-post coffer at the watch post (locked: the Watch-post key, lying by the graves, or Lockpicking 1) and the Poacher's cache in the Blackwood (Lockpicking 3 only). Old Tam teaches **Lockpicking** and sells lockpicks; every lock picked raises the skill. Open with E or a click; contents go to your bags, silver to your purse.
- **Sparkles.** Gold motes rise from unopened chests, quest items in the world (the manifest) and places still to examine.
- **Reputation** (`data/factions.json`): the Road Wardens and the Folk of the Mere. Quests (`reward.reputation`) and kills in their area (`reputation` per enemy type) raise it; standings run Hostile, Neutral, Friendly (1000), Honored (3000), Revered (6000), Exalted (12000). A faction's vendors (`faction` on a shop) take 5/10/15/20% off from Friendly up. The character window lists each faction's standing. Gated items and areas can read the standing later.

## Money, durability and gear (Dan's list, part 2)

- **Gold and silver.** The purse holds silver and shows it as gold and silver with coin icons (100 silver = 1 gold, converted automatically: 1 gold less 1 silver is 99 silver). Prices in the data are in silver. `src/ui/money.js` formats it everywhere: bags, shop, quest rewards, tooltips ("Sell for 3 (coin)") and the log.
- **Durability.** Weapons, armour and shields start at 100%. Dying takes 10% off everything worn (`CONFIG.durability`). At 0% an item is broken: its icon turns red, it gives no stats, and a broken weapon swings like bare hands. Smiths (vendor types with `repairs` in `data/shops.json`, so Mara) have a **Repair all** button; mending costs half the item's price for the missing share.
- **Character panel** has every WoW slot: head, neck, shoulders, back, chest, wrists, hands, waist, legs, feet, two rings, two trinkets, main hand and off hand. Items say `slot: "finger"` or `"trinket"` to go in either of a pair; kind `jewellery` covers rings, necks and trinkets. No items use the new slots yet (they need models).
- **Rebalance.** Weapon damage is about an eighth of what it was (the worn longsword is 3–7 at 2.2 s), power adds 0.25 per point of Strength, starting armour is 5 and the kite shield blocks 5%. Enemy health is 45% of what it was and enemy damage 70%, so a ghoul (22 health) takes three swings. Old saves keep their rolled names; rolled damage from before the change falls back to the item's own.
- **Ground loot** shows its name in its rarity colour above it.

## Combat and targeting fixes (Dan's list, part 1)

- Engaging a target waits one full weapon swing before the first hit (2.2 s with the longsword). Casting a spell stops swings, and the swing timer restarts when the cast ends.
- **Brace** is a spell now (kind `guard`, still on Space, off the global cooldown). **Rebuke** (key 5, kind `interrupt`, 10 m, 10 s cooldown) breaks an enemy cast and locks it out for 3 s. Each enemy attack has `interruptible` in `data/enemies.json`: archer shots and Grasping Dark can be interrupted, Grave Slam cannot.
- Red errors mid screen: "You have no target.", "Out of range", "You need to be closer to interact with that target.". Abilities with `target: ground` or `self` need no target.
- Cursors: a sword over enemies, a speech bubble over NPCs (grey when out of reach), a bag over loot. Left and right click do the same thing on friendly NPCs.
- The swing animation now chops down instead of up.

## Stats and damage

The design and the comparison with RuneScape, Skyrim, Diablo and Lost Ark are in [docs/stats-and-damage.md](docs/stats-and-damage.md). In short:

- **Four attributes:** Stamina, Strength, Agility and Intellect (renamed from Vitality, Might and Finesse). Each archetype has a main attribute that adds to its damage; the Warden's is Strength. Stamina gives health. The character panel lists them, then Haste, Armour, Block and Crit.
- **Derived combat stats:**
  - weapon damage ranges;
  - crit chance (5% plus Agility, converted by level) at 150% damage;
  - armour, a capped percentage reduction by your own level; higher-level attackers hit harder through the level gap instead;
  - shield block: the shield's own block chance plus block chance from gear, and each block stops 30% of the hit;
  - haste, from gear only, which shortens swings, windups and the global cooldown.
- **Armour types:** cloth, leather, mail and plate. Each archetype can only wear some types; the Warden can wear all of them and use shields, and starts with a battered kite shield.
- **No hit rolls and no dodge chance.** Avoiding damage comes from telegraphs and the defensive button.
- **One formula for every hit:** base × ability multiplier × level gap, then crit, then armour, then block.
- **Damage numbers** float up for hits dealt (pale), hits taken (red) and heals (green). Crits are larger, amber and marked "!", and blocks read "Block". They stay small and muted, as the design asks.
- **Enemy health:** the target frame shows the health of the enemy you are locked on to, aiming at or fighting. Enemies with mana also get a blue bar there and over their heads.
- **Character panel:** shows every stat. Item tooltips show weapon ranges, armour type and stat bonuses.
- **Level-up:** a card lists each stat that rose, old value to new, and the character panel marks those stats with a green "+n".

All numbers are in `src/config.js` (`stats`, `archetypes` and the enemies) and in the item definitions.

## Game data

All content lives in `data/`, one JSON file per part of the game: items, item rarities, archetypes, abilities, enemies, loot tables, NPCs, shops (vendor types and stock), quests, world placements, scenery and text. Records refer to each other only by id. `npm run validate` checks every reference, id, model and position, and `npm test` runs that check first. [CONTRIBUTING.md](CONTRIBUTING.md) explains the layout and how to add content.

## Items and Mara's forge

- **Item database.** Every item is defined once in `data/items.json`: name, kind, slot, armour type, quality, damage, stats, use effect, bag size, stack size, buy price, model and icon. The game checks the file at startup and logs any malformed entry. Adding an item is a new entry there, plus a Blender model if it needs a new look.
- **Mara Venn's forge** stands beside the watch post: a forge, an anvil and an awning, with Mara hammering at her anvil until you come close. Press E (A on a pad) to talk to her. Her shop opens on the left with your bags on the right.
  - Click an item to buy it (A on a pad). Shops and their stock are in `data/shops.json`; Mara herself is in `data/npcs.json`.
  - Right-click anything in your bags (or drag it onto her window, or Y on a pad) to sell it. Merchants pay a quarter of the price, as in WoW, and tooltips show what an item sells for.
  - Anything sold can be bought back for what it fetched until you leave the game.
  - Quest items cannot be sold or dropped.
  - Walking away closes the shop.
- **The manifest.** Once you have the manifest, the tracker says to return to Mara, and she shows a gold ?. Talk to her and hand it over for 20 coins and 50 experience; she then has two new quests (a gold !), and a third once both are done.
- **Quests and talking.** Talking to someone opens a WoW-style conversation: their quests first, then things to ask, their wares, and Goodbye. The quest log is on L (D-pad right on a pad); up to four tracked quests show under the minimap.
- **The minimap.** Top right, north up. The arrow is you; ! and ? mark quest givers, dashed circles mark where open objectives point, and blue diamonds are shrines. + and − zoom.

## The Blackwood (second region)

A forest track leaves the Fallen Road below the watch post, passes west of Mara's forge and runs north into the **Blackwood**. The HUD names the region you are in. Under the black pines the fog closes in and the light dims. The Blackwood is meant for a Warden of level 3 or so.

- **A shrine at the forest edge** heals you and becomes your respawn point, so a death deep in the wood does not send you back down the road.
- **Barrow Hounds** (level 3) are fast and hunt as a pack: wake one and every hound near it comes too. They drop pelts that Mara buys.
- **Hollow Archers** (level 3) keep their distance and paint their aim on the ground as a line. When it fills, the arrow flies down it, so step off the line. Your shield can block an arrow, and Brace stops it. Archers back away if you close in, and a Shield Break interrupts the shot.
- **The Blackwood Seer** (level 5, elite) has mana, shown as a blue bar under her health.
  - Rot Bolt is a line like the archers' arrows.
  - **Grasping Dark** is a circle under your feet. It cannot be blocked, only Braced or walked out of.
  - When her mana runs dry she closes in with her staff.
- **Places:** the hound den, the archers' broken camp, and the ring of standing stones where Mara's missing iron ended up. Each can be examined.

## Gear drops and random stat rolls

- **Rarity.** Every item has a rarity from `data/rarities.json`, which sets the colour of its name, its bag-slot border, its loot line in the log and its glint on the ground:

  | Rarity | Colour | What it is |
  |---|---|---|
  | Junk | Grey | Vendor trash (cracked bones, bent arrowheads) |
  | Common | White | Plain weapons and armour, no magical properties |
  | Enhanced | Green | Gear with a magical property, such as a bonus stat |
  | Rare | Blue | A very low drop chance, or from bosses and quest chains (Helm of the Old Watch) |
  | Epic | Purple | The best gear, kept for bosses (Witchbane, the seer's blade) |
  | Legendary | Orange | Reserved for a handful of items; none yet |

- **Drop tables, rarity first.** Every enemy type names a loot table in `data/loot_tables.json`. A kill drops the table's `always` items (a hound's meat, and often its pelt), then has a chance to drop something: it rolls a rarity by weight, then an item from that rarity's list. A ghoul, for example, drops junk 22.5% of the time, common gear 14%, enhanced 7% and rare 1.4%. The Blackwood Seer always drops enhanced gear or better, and Witchbane 15% of the time. An item can be `reservedFor` one table (a boss's weapon), and the data check stops it appearing anywhere else. Drops lie beside the body and are looted with it in one go.
- **Rolled gear.** Gear that drops rolls a little, as in Diablo:
  - armour, block and other stats move up to 20% either side of the database value;
  - weapon damage moves up to 12%;
  - common gear that drops at the Enhanced rarity gains a WoW-style suffix such as *of the Bear* (Strength and Stamina), *of Swiftness* (haste) or *of Vigour*, which spends the green stat budget of the item's level and slot: that is its magical property. It shows green and sells for a little more.
- **Where the rolls live.** Each item keeps only its differences from the database, so a later balance change still reaches items already in your bags. Rolls survive dropping, selling, buying back and saving, and the save check rejects impossible rolls.
- **Items placed in the world** (the helm, the sabatons in the archers' camp) and items bought from Mara do not roll.

## Death, camps, the dark and fishing

- **Death.** When you fall, release your spirit. It rises, grey and fast, at your camp or the last shrine you rested at. Enemies ignore a spirit. Walk back to your body (marked ✝ on the minimap) and rise there at half health with nothing lost, or return to life where you rose and lose a few coins.
- **The dead remember.** The enemy that killed you wears a skull, over its head and on the minimap (☠). You deal it 25% more damage, and killing it pays half its experience again as revenge.
- **Old Tam**, the fisher by the Stillwater Mere west of the road, teaches Camping (10 coins) and Fishing (5 coins), and sells rods and torches.
- **Set Camp.** A 3 second cast, standing still, with no enemies near. The camp (▲ on the minimap) becomes where your spirit rises. Resting by its fire builds rested experience (the pale band on the experience bar), which doubles kill experience until spent.
- **Torches and the dark.** Some places are too dark to enter. Equip a torch in the off hand (it replaces the shield, so no block) to walk in. The Barrow Hollow, west of the hound den in the Blackwood, holds a strongbox and a purse.
- **Fishing.** With the skill and a rod in your bags, use Fishing (it goes on your bar when learned) facing the water (it casts towards your cursor if that is on the water). The Warden puts his sword away and holds the rod out, with the line running to the bob. Wait for the bob to dip, then strike: click the bob, or press E / A. Too soon, or too late, and the fish is gone. Each catch raises the skill, and higher skill (and bait, later) catches more often.

## Controls

One scheme for keyboard and mouse and for a gamepad. The camera is fixed (the scenes are composed for that one isometric angle) and movement is direct.

**Targeting and auto attack (WoW style).** Left-click anyone to select them: a yellow ring and the frame at the top of the screen (with their portrait and level) mark them. Left-clicking the ground lets go; right-clicking the ground does not. Hovering over anyone shows who they are in the bottom-right corner, where every tooltip now shows. Right-click an enemy (or **RT** on a pad), or use any ability on it, to **engage** it (the ring turns red): the Warden then auto attacks, swinging each time his weapon is ready while the target is in reach and in front of him, until it falls, you pick another target, or you clear it (Esc). Auto attack is not a spell and is not on the bar. Swing time is the weapon's **speed** (the worn longsword swings every 2.2 s), shortened by haste; each swing hits for the weapon's damage plus Strength. Engaging an enemy out of reach, or using a spell on one, says "Out of range" in red mid-screen. Right-clicking does not turn the Warden: on the move he faces where he walks (and holds his swing if the target is behind him); standing still he turns to it. The frame says "Attacking", or "Out of reach" until you close in. **Tab** (or **R3**) picks the enemy you are aiming at, then cycles through the others nearby. Abilities on the spell bar go to your target; with nothing selected they go to the enemy nearest your aim, which a faint gold ring shows. Left-clicking a townsperson selects them; right-clicking talks to them. Esc clears the target.

**Weight.** A landed swing, a crit or a heavy blow kicks the camera and knocks the enemy back a little; crits shake harder and land with a deeper crunch. Nothing pauses: the action stays fluid. The numbers are in `impact` in `src/config.js`.

**No dodge, no sprint.** Space is a single defensive button on a 7 s cooldown, and the slot belongs to the archetype. The Warden's is **Brace**: raise the shield and the next blow within 2.5 s, even a Grave Slam, is turned aside. It is off the global cooldown.

**Looting.** Defeated enemies give experience at once, but their coins stay on the body until you loot it. Click (either button) a body or anything lying on the ground (within a few metres) to loot it, or press E / A when the prompt shows. Either way it also loots every other body and dropped item within 5 m, so after a fight one click picks up the lot; the prompt says how many ("Loot the Ashen Ghoul (and 2 more nearby)"). Things placed in the world, such as the manifest, are still taken one at a time. Looted bodies sink away; unlooted ones are kept in your save.

| Keyboard and mouse | Gamepad | Action |
|---|---|---|
| WASD or arrow keys | Left stick | Move |
| Mouse | Right stick | Aim (with no stick input, you aim the way you face) |
| Tab | R3 (stick click) | Next target |
| Left click | | Select an enemy or townsperson; loot a body or drop |
| Right click | RT | Engage an enemy (auto attack); talk to a townsperson; loot |
| 1 | X | Lunge (slot 1) |
| 2 | Y | Shield Break (slot 2) |
| 3 or Q | RB | Healing draught (slot 3) |
| 4 | LB | Hallowed Bolt (slot 4) |
| 5 | LT | Spell-bar slot 5 (Rend by default) |
| Space | B | Brace, the defensive slot |
| E | A | Interact, examine, loot everything nearby |
| B (or I) | Start | Bags |
| C | View | Character panel |
| P | D-pad up | Spellbook |
| N | | Talents (placeholder for now) |
| L | | Quest log |
| O | | Settings (key bindings, nameplates, save) |
| U | | Skills (RuneScape style: each skill and its level; also a button in the Spells window) |
| K | D-pad down | Save |
| Esc | B (in a window) | Close windows, then clear the target |
| M | | Sound on or off |

Every keyboard key above except WASD, the arrow keys, Esc and M can be changed in Settings (O).

**Example spells.** The Warden has six example spells, all on the global cooldown and all going to your target (or the enemy nearest your aim) as above. Hallowed Bolt starts on key 4; drag the rest from the spellbook (P) onto the bar.

| Spell | Kind | What it does |
|---|---|---|
| Hallowed Bolt | Ranged cast | 1.6 s cast with a cast bar (moving interrupts it), then a holy bolt hits a target up to 20 m away |
| Rend | Bleed | Your target bleeds 5 times over 10 s; shown on the target frame; using it again refreshes it |
| Smite | Instant | Instant holy damage on a target up to 12 m away; 6 s cooldown |
| Hallowed Ground | Local AoE | Consecrates the ground around you: enemies in it burn every second for 6 s; 15 s cooldown |
| Cleave | Cleave | A wide swing hitting up to 4 enemies in front of you; 5 s cooldown |
| Battle Cry | Self buff | +20% to all your damage for 15 s, shown under your health bar; 45 s cooldown |

The spell-bar rows above are the default layout; keys belong to slots, so moving a spell moves its key. Clicks never move the Warden, and a click on open ground does nothing, so no swing is wasted.

**Windows on a gamepad:** while a window is open the pad drives it (the world keeps running). The d-pad or left stick moves a highlight. A picks an item or spell up and puts it down (to move, swap, equip, unequip, or place a spell on the bar), X equips or uses an item, Y drops an item on the ground or removes a spell from the bar, LB/RB jump between the bags, character panel, spellbook and spell bar, and B cancels or closes.

## What is on the Fallen Road

- **The road** runs north from the road's end, past the shrine and the cart, to the ruined watch post.
- **The roadside shrine** (east of the road, candles lit) restores health and becomes your respawn point.
- **The abandoned cart** (west of the road, missing a wheel) holds the manifest and some spilled grave-iron. Reading the manifest completes the investigation.
- **Old graves** in the western woods, a **healing draught** among the eastern rocks, a **purse** by the ruined wall near the watch post, a **Traveller's Satchel** in the western ruins, and a **dented helm** among the rocks east of the watch post.
- **Hallow Cut**, the fresh timber graves hung with bells north-east of the road, is the Gravebound Brute's ground. Watch its telegraphs. It drops Watchman's Edge (23 damage against the worn longsword's 18), which you equip by dragging it onto the character panel.

Three Ashen Ghouls and the Brute are placed so they are not all visible from the start, and one is off the road.

## Balance (from section 9.7)

Every number lives in `src/config.js`, `src/data/scaling.js` and the data files. At average rolls: player 100 HP and 130 armour (21%), auto attack 9 (7–11) every 2.2 s with the worn longsword, Shield Break 5, ghoul 18 HP / 5 dmg after armour / 1.35 s, brute 50 HP with 140 armour / 9 dmg (×1.44 two levels up) / 1.2 s, draught +42, ghoul 28 XP, brute 65 XP, level 2 at 100 XP (+2 Strength and +2 Stamina: +12 max HP and more damage, then 160, 220 … XP per level), death costs 20% of coins capped at 5. Build 2 adds a 1.5 s GCD, Lunge 1.5× strike with an 8 s cooldown, Grave Slam 31 damage with a 1.4 s wind-up and 7 s cooldown, a 1 s cooldown between draughts, and fog from 14 m to 40 m. Brace has a 7 s cooldown and a 2.5 s window; area looting reaches 5 m (`loot` and `targeting` in config).

## Saving

- K saves to the browser's local storage and confirms only after the data reads back correctly.
- The game also autosaves when the tab is closed, refreshed or hidden.
- On launch the save is validated. If it is unreadable the game starts fresh, says so on the title screen, copies the bad save to `shadowfall.save.unreadable`, and does not autosave over it until you press K.
- Saves live in the browser you play in, so Chrome and Edge keep separate saves.

## Project layout

```
index.html, style.css     page and HUD styling
dist/shadowfall.js        the bundled game (what index.html loads)
data/                     ALL game content as JSON, one file per domain: items,
                          archetypes, abilities, enemies, loot tables, npcs,
                          shops, quests, world, scenery, text (see CONTRIBUTING.md)
src/
  main.js                 initialisation, main loop, input routing, camera
  config.js               engine tuning (formula constants, camera, fog, ...)
  core/                   events (pub/sub), keyboard/mouse input, gamepad
  assets/                 loads the embedded Blender .glb files (+ procedural fallback)
  render/textures.js      small painted canvas textures
  world/                  layout data, terrain, collision, world builder
  entities/               player, enemy, procedural rig animation
  systems/                combat, telegraphs, enemies, loot, interaction,
                          targeting, action bar, spells (the spell engine),
                          stats (the damage formula),
                          inventory (bags/equipment), progression,
                          world state, save, effects, audio
  ui/hud.js               HUD, spell bar, modals (reads state, requests actions)
  ui/itemUI.js            bags, character panel, drag and drop, pad menus
  ui/icons.js             item icons rendered from the Blender models
  data/                   db.js loads /data; schema.js checks it; items.js holds
                          the item rules (rolls, prices); text.js the writing
assets/
  blender/build_assets.py Blender script that builds every model
  models/*.glb            exported models used by the game
  fbx/*.fbx               the same models as FBX, for Unity
docs/                     design notes (stats and damage)
tests/                    automated acceptance test (Chromium), latest results,
                          and screens.mjs for reference screenshots
```

Systems own their own state and talk through the event bus; the HUD never decides outcomes. Everything in `data/` is plain data with stable ids, checked by `npm run validate`, which keeps saves meaningful across layout tweaks and should port directly to Unity ScriptableObjects or JSON.

## Rebuilding

```
npm install
npm run build        # rebundle dist/shadowfall.js after editing src/
npm run validate     # check every file in data/ (ids, references, models, positions)
npm test             # validate, then run the acceptance checklist in headless Chromium
node tests/acceptance.mjs gamepad telegraphs   # run only some sections
npm run assets       # rebuild the models (Blender 4.2 or later on PATH; tested with 5.2)
```

`npm run assets` can also be run as `python assets/blender/build_assets.py` with the `bpy` module installed (`pip install bpy`, Python 3.13). After rebuilding models, run `npm run build` to embed them.

## Notes for a move to Unity

- `assets/fbx/` holds every model with the same part hierarchy. Characters are split into `Torso`, `Head`, `Arm_L`, `Arm_R`, `Leg_L`, `Leg_R` and `Weapon`, each pivoting at its joint, so they can be animated in Unity directly or re-rigged later. Colour is stored as vertex colour, so use a vertex-colour shader (or bake to a texture).
- The ground telegraphs are a sector mesh with a small shader whose `uProgress` uniform fills it (`src/systems/telegraphs.js`); in Unity this maps to a decal or projector with the same parameter. Hit tests use the locked shape, not the mesh.
- Inventory locations are plain strings (`b:<bag>:<slot>`, `e:<slot>`, `s:<bag slot>`), shared by the mouse UI, gamepad UI, saves and tests.
- `data/*.json` is the design data (see CONTRIBUTING.md for how it maps to ScriptableObjects), and `src/config.js` the engine tuning. The system split in `src/systems/` maps one-to-one onto MonoBehaviours or services.

## Known limits of this build

- Ghouls and hounds keep a plain wind-up; the Brute, the archers and the seer use ground telegraphs.
- Bags cannot be re-ordered between bag slots while they hold items (as in WoW, empty a bag before moving it).
- Enemies use simple circle collision and do not path around large obstacles.
- The watch post is a landmark only and cannot be entered (as the design specifies).
- Animation is procedural, not keyframed.
- The Warden has no mana or rage yet, so spells cost nothing but their cooldowns. Ground-targeted spells (placed at the cursor) are not built yet.
- The Blackwood joins the Fallen Road as one continuous map rather than a separate zone with a loading step; the region name, fog and light change as you cross.
- Mara Venn, dialogue and a reward for the manifest are outside this build's scope.

# Thornford Reach: village life and the level 1–5 story

**World placement update, 1 November 2026:** The opening now connects to 34 authored onward hubs and 109 regional/return quest prototypes. The new map has 134 quests. Terrain routes, level districts, public return areas and seven sealed dungeon approaches are placed. Full private dungeons and measured 60-hour progression remain future work. See the [world review](world-layout-review.md). Earlier future-content wording below refers to the fuller designs, not the absence of this first placement pass.

Current build, 31 October 2026. This guide supersedes the original four-quest prototype. The [Quiet Levy chapter guide](quiet-levy.md) covers the new narrative, twelve additions and two physical puzzles.

## Start playing

Stop and restart the game after Godot reloads the project. Select **New map** and create a fresh character to begin at Thornford, **X −450, Z −203**. Existing characters retain their saved position, inventory and quest progress. Mayor Alder opens the new story from the town hall at the south end of Council Lane. Existing characters can pick up available local quests without resetting their saves.

The continent remains **2,048 × 3,072 m**. The built starting region concentrates activity into connected village, farm, woodland and haunted districts. The scale decision is based on travel time and readable local views, rather than matching an unverified kilometre figure for another MMO. Willow Lane takes about 12 seconds to run; Orchard Lane about 19; the Mourning Road about 21. The entire 317 m Lantern Road takes about 57 seconds before stops, fights or exploration. Characters move at 5.6 m/s.

## Main story and independent local stories

| Stage | Recommended level | Main story |
| --- | --- | --- |
| Holt Orchard and Meadow | 1–2 | **An Honest Day’s Work:** help with young boars, then report to Mayor Alder |
| Lantern Road | 2–3 | **Where the Lanterns Went Out:** investigate the missing watch and fight road revenants |
| Old Watch and Dawnstone | 3–4 | **The Silent Watch:** defeat the Bellkeeper and visit the shrine |
| The Nameless Yard | 4–5 | **The Names They Left Behind:** investigate the erased family names and lay gravewalkers to rest |
| Bell Crypt | 5 | **What the Bell Remembers:** defeat the keeper and restore the village's burial records |

Levels are recommendations, not hard quest locks. The quest system enforces the main chapter prerequisites. Optional stories do not block that chain. The crypt is currently a world encounter and exterior, not an instanced dungeon interior.

| Local story | Resident and place | Activity |
| --- | --- | --- |
| Three Paces Over the Line | Mayor Alder; orchard boundary | Resolve Heda and Osric's fence dispute using the old boundary stone |
| One Pig Too Many | Heda Holt; farmyard | Stop Briarjaw, the lone wolf killing her pigs |
| A Word Across the Water | Heda → Tobin | Deliver a request to trade orchard apples for reeds |
| Lost in the Rushes | Elsie; Miller's Pool | Recover a pouch holding her mother's brass brooch |
| Supper at the Lantern | Elsie; safe fishing ponds | Catch three perch for the inn |
| Something for the Road | Elsie; Briarwood | Gather ditchbell flowers |
| The Way Through Briarwood | Scout Fen; Wolf Hollow | Clear wolves and survey the western loop |
| The House That Kept a Light | Morrow; Widow's Mirror | A quiet local remembrance story, separate from the watch mystery |

The district now contains **25 quests: five main and twenty optional**. The original thirteen retain their IDs, objectives and rewards; the five main chapters now tell the Quiet Levy story. Twelve new optional quests add 220 quest XP and 68 coins, bringing total quest XP to 3,900 before combat, discovery, professions and rested gains. Future additions need an explicit XP budget. Current IDs and saved outcomes are preserved.

Heda acknowledges saving her remaining pigs. Osric acknowledges the boundary settlement. These are persistent quest flags and dialogue reactions; they do not imply a full daily schedule or simulated village economy. The woodcutter works with a held axe, Iren works at his anvil, and Tobin fishes at his landing.

## Places, services and enemies

- **Thornford:** compact street, working smithy, chapel, watch house, protected watchmen and an accessible town hall with Mayor Alder inside.
- **Lantern Inn:** enter through the western doorway. The roof/front fade while inside, revealing a hearth, tables, counter and beds. Elsie sells provisions, rents a bed for two silver, and can bind your home. Rest restores health, wounds and rested experience through the existing inn systems. Mira teaches rogues inside.
- **Holt Farm:** Heda's orchard, pigpen, three protected surviving pigs, Osric's woodlot, level-one young boars in the meadow and the separate level-two Briarjaw encounter farther east.
- **Willow Pond and Miller's Pool:** safe beginner fishing with landings, shore stones, plants and lily pads. Tobin teaches Fishing and sells rods at Willow Pond. Three successful casts can supply Elsie's supper quest. A rod costs ten silver and beginner training five; the first hunt pays enough for both.
- **Briarwood:** ranger training with Fen, a camp and level-two wolves beyond the safe approach.
- **Lantern Road and Old Watch:** level-two revenants, level-two sentries and the level-three Bellkeeper with his existing avoidable slam.
- **Mourning Hollow:** a small, shuttered hamlet under dead trees. Morrow runs the apothecary and teaches occultists. Cooler fog, reduced sun and haunted ground create a separate atmosphere from the village.
- **Nameless Yard and Bell Crypt:** headstones, fences, dead woodland, level-four gravewalkers/archers and a level-five keeper.
- **Widow's Mirror:** an optional haunted fishing pool requiring **Fishing rank 8**, distinct from character level 8.

Class trainers have specific locations: Rowan teaches wardens at the watch house; Mira teaches rogues at the inn; Fen teaches rangers at his camp; Lyra teaches paladins by the chapel; Morrow teaches occultists at the apothecary. Beginner Mining is with Iren, Cooking with Elsie, Fishing with Tobin and Herbalism/Alchemy with Morrow. The distant existing Agna spawn is retained. Higher profession rank trials still need the local-ladder work identified in the quest design audit; the tested beginner fishing loop is complete.

## Player and grass readability

The fixed elevated camera retains its pitch while zooming. Default zoom is now 0.98, framing about **39 m across at 16:9**, with a closer 0.5 minimum (about 18 m from the player, for a close look) and 1.3 maximum. There is no look-ahead control. A 1.2 visual scale makes the player and attached gear clearer; collision radius, movement and combat distances retain their original values. Together these changes make the figure roughly one third larger on screen. The 720p integration check measures a 48.6 pixel character-height projection. The paper doll compensates for this scale to avoid cropping.

Grass now uses a short original five-leaf clump, approximately 18–23 cm before instance variation, with gentle wind. Placed Common/Wispy grass is replaced while preserving placement and rotation; `sourceModel` and `sourceScale` retain the old values. Streamed grass uses the same small shape. Source pack files remain unchanged. Boars use original Godot-native body/snout/tusk geometry rather than a recoloured wolf.

## Edit the world

Open **World → New map → Open the world**. The scene tree contains Props, NPCs, Enemies, Loot, Chests, Shrines, Signposts, **Houses**, **Buildings** and **Ponds**. Select entries there to move them; Ctrl+D copies a template. Houses also turn with the rotation gizmo, with width/depth controls in the placement Inspector. Ponds have a radius control. Enterable building placements move as a whole; their component scenes define the interior layout. Save the world with Ctrl+S. Sculpting still edits the terrain and walkability directly.

Game Data edits the canonical NPC, dialogue, enemy, quest, item and shop tables. The new narrative records use `nr_` IDs, village expansion records use `vr_` IDs, and earlier Reach content uses `tf_` IDs. Preserve saved IDs. World mechanisms appear in the **Puzzles** scene-tree group; move them as a whole. The placement Inspector edits their name, instruction and answer, and Game Data offers a **Solve a world mechanism** objective type. Detailed controls, state labels and feedback remain editable under Metadata → record.

- `data/terrain/new_map/spawns.json`: world placements, roads, buildings, water, region names and trainer overrides.
- `data/terrain/new_map/scenery.json`: props, nature, lamps and motes.
- `data/terrain/new_map/sculpt.json`, `world.bin`: sculpt layer and packed terrain.
- `assets/scenery/`: native grass, dock, lilies, town-hall parts, work axe and chopping block.
- `assets/models/characters/thorn_boar.tscn`: original boar model.
- `game/core/db.gd`: camera, fog and player readability settings.

`tools/world/expand_reach.py` is a construction recipe requiring an explicit separate output directory. It owns generated `vr_` records and must not be rerun over subsequent hand edits without review. The existing continent, prior source assets and unowned placements are retained. Changed originals are backed up in the chat workspace's `village-expansion/backup`.

## Verification

`reach_village_check.gd` checks real fish bites/catches and recipient hand-ins, earned coins paying for training and a rod, main chapter progression, all local quest outcomes, protected pigs/guards, NPC tools/work, inn doors and rest, town-hall cutaway, readable player size, short grass, installed models, chest rewards and valid saves. Rendered captures cover the village, inn, hall, both safe ponds, farmyard, woodlot, meadow, haunted hamlet, graveyard and crypt.

`thornford_check.gd` checks every authored road centre at one-metre intervals, spawn walkability, combat/quest events, class training and saving. Editor checks verify no unintended changes on opening, precise transforms, native buildings/pond previews, tint, advanced abilities and save/reload. Terrain checks cover sculpting, undo and tile round trips. Control and minimap checks cover the shared camera changes and original map.

The final village integration check reports zero failed assertions; controls pass and the original-map live minimap check reports zero failures. Godot still emits resource/RID cleanup warnings at test shutdown, plus null-material messages during rendered world teardown. Those remain unresolved; passing gameplay assertions do not imply a clean engine shutdown.

These are functional and rendered checks, not a claim that every class/encounter is fully balanced. Advanced profession tiers, multiplayer, daily NPC schedules and mechanics such as escorts or ordered puzzles are separate future work. The design plan distinguishes those from content already built.

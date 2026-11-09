# A Reputation Earned — the playable level 1–10 introduction

Implemented in the active `new_map` world. Open the project in Godot, press F5 and create a fresh character to experience the intended ability progression. The normal character screen and Continue flow remain in use. Existing characters retain their learned abilities, equipped bars, possessions and finished quests.

## Journey

| Recommended levels | Place | What the player does |
| --- | --- | --- |
| 1–2 | Thornford and Holt Fields | Carry Elsie’s broken hinge to Iren, earn a belt, work for Hobb’s supper, meet Heda and protect her orchard. Learn cooking through a useful meal. |
| 2–4 | Lantern Road and Old Watch | Investigate Rowan’s missing patrol, help injured Dunn and courier Paige, recover family letters, then confront the Bellkeeper. |
| 4–5 | Mourning Hollow and Nameless Yard | Meet Morrow and gravekeeper Benn. Uncover a contract using dead people’s names, copy the family stones with permission and recover their seals. |
| 5–7 | Lantern Crossing, eastern route | Help Ada repair the crossing, hear Beren and Kit’s accounts, recover a paid toll bill and feed stranded drivers at Anwen’s Bent Nail. |
| 5–8 | Mossreed Landing, alternative western route | Help Celia and the ferrymen, bring wick to undead lamplighter Hale, adjust the sluice, meet his daughter Tess and recover a paid ferry receipt. |
| 7–9 | Lamplighter’s Rest and the miners’ camp | Sergeant Sella joins the accounts. Supply Edda’s camp, open the quarry lane and recover settled wage tags. |
| 9–10 | Blackpick Approach and Rillbank Quays | Defeat Bailiff Corven, recover the original accounts and carry Edda’s signed testimony to Rillbank. |

Either middle route reaches the shared finale. Players can visit the other community later. The initial letter is a choice, while the communities themselves remain accessible.

The main thread is the Quiet Levy. A winter grain contract became a claim on the living and the dead. The player starts as someone useful, earns witnesses and becomes credible enough to carry an inquiry to Rillbank. The theme is responsibility and the abuse of ordinary agreements. Humour comes from residents’ work, strained marriages, missing tools and bills which refuse to stay paid.

## Local lives and optional stories

Nine additional residents include a courier who stayed for an injured watchman, a retired seamstress, a gravekeeper, a cartwright, a stable hand, an undead lamplighter and his living daughter, a sergeant and a mine forewoman. They have conversations about their trades and relationships. Applicable residents keep the existing daily routine system; essential route contact Sella remains at her post.

Keep the existing fishing lesson, pig-raiding wolf, water gauge, reed messenger and lost brooch. Added local threads include taking soup to Della and Benn, recovering Della’s sewing tin, Celia’s locket and two exclusive resolutions to the neighbours’ fence dispute. The villagers remember which settlement was chosen. Local stories do not gate the main journey.

There are 29 added quests, including the Wizard’s calling and practical lesson, alongside substantial revisions to existing quests. A single main route contains 27 or 28 steps. Kill, collect, delivery, witness conversation, discovery and puzzle objectives all use the playable quest systems.

## Gradual class learning

Every fresh class starts with one core ability. More arrive automatically through level 8, fill free action bar slots outside combat and remain available in the spellbook. Trainer alternatives begin later. Existing saved abilities are retained.

| Class | Core abilities by unlock level |
| --- | --- |
| Warrior | Heavy Strike 1, Crushing Blow 2, Rend 3, Lunge 4, Cleave 5, Berserk 8 |
| Rogue | Quick Strike 1, Shadow 2, Poisoned Blade 3, Guile 4, Assassinate 5, Death Venom 8 |
| Ranger | Quick Shot 1, Long Shot 2, Tar Trap 3, Disengage 4, Flaming Arrow 6, Triple Shot 8 |
| Occultist | Blight Bolt 1, Rot 2, Soul Ward 3, Hex of Withering 4, Siphon Life 5, Purge 8 |
| Paladin | Holy Strike 1, Light Shield 2, Mending Prayer 3, Light’s Hammer 4, Bring to Kneel 6, Divine Storm 8 |
| Wizard | Firebolt 1, Frost Lance 2, Arcane Ward 3, Frost Ring 4, Blink 6, Stormfield 8 |

Class lessons at level 5 practise the actual resource mechanics and award appropriate weapons. Wizard now has core spell enhancements/forks and two key passives, allowing its level 10 build choices to function alongside the other classes.

## World and editing

Eight new connecting lanes include the Gravekeeper’s Walk. The terrain has soft road cuttings and open walking corridors. The eastern lane goes around Willow Pond. Surrounding hills and other continent edits remain. Existing large trees have been thinned around the new interactions and paths. Small ground cover, work props, carts, supply caches, signposts, camp shelters and 26 warm lights reinforce the places residents describe. Mossreed’s sluice has a nearby fishing pool. Haunted areas retain cool fog with higher night visibility and warm pools of light.

The new content is editable through Game Data and World. Quests expose main-story status, chapter and actual NPC visits. Ability forms expose core unlock level. Witness targets remain independent of the final hand-in NPC. The placement manifest records the final NPC, clue, pickup and encounter coordinates. Quill’s development gear shop is retained at the original authoring settlement, at 267, −155, away from the starter square.

The eight-dungeon cap is unchanged. Blackpick’s outdoor approach has encounters and story content. Its private dungeon instance remains unbuilt and is marked sealed. Modular building art and final bespoke puzzle art remain later work.

## Quest handoffs — 9 November 2026

Successful hand-ins now immediately open an actionable follow-up from the same NPC. If the next step is with another resident, the conversation shows who to speak to and follows that quest giver in the tracker, minimap and world map. The offered quest stays unaccepted until the player speaks to its giver and chooses Accept. This lead survives save/load, and accepting it keeps it visible even with ten quests already tracked. The older quest stays in the journal.

Hobb’s Hungry Work hand-in immediately opens A Meal Earned. Returning the meat, firewood and garlic directs the player to Heda’s A Watchman’s Word when the farm work is done. If the parallel farm tasks remain unfinished, the handoff directs the player through the missing task first. Optional fishing stays available as another choice. The crossing/ferry decision and all level, class and prerequisite gates remain in force.

The introduction tests now use the actual dialogue completion buttons. Both routes passed 1,369 checks. The focused follow-up suite passed 85 checks, covering both cook/farm completion orders, saved leads, full trackers, failed hand-ins and regional choices. Native Forward+ rendering also verified that the next-offer and onward-handoff windows settle into visible panels. The existing quest-log check, script scan and data validation passed. Earlier completion records do not replay their reward windows; existing progress is retained.

To author another chain, link the next quest’s prerequisites to the previous quest and place its giver in the world. The hand-in flow derives follow-ups from those dependencies. No additional popup script is required for each quest.

## Pacing and verification

The global level 50 curve is unchanged. The design target for 1–10 is about two hours. Required quest rewards and required kills alone reach level 10 on either route; optional stories, class practice and exploration provide a margin. Running both alternative chapters will naturally overlevel some content.

Automated trials use isolated characters, actual quest acceptance and hand-ins, physical gathering nodes, witness conversations, nearby puzzle controls, saved conversation progress and normal combat updates. All six classes are checked against a first boar using starter equipment and only the first class ability. These are controlled simulations, not a timed two-hour human playthrough. Human route timing, later group balance and listening through a working audio device remain follow-up checks.

Regression coverage includes script/data validation, editor round-trips, class mechanics, trainers, profession lessons, build choices, the unchanged 1–50 experience curve and Continue using a copy of an existing character. Native Forward+ captures review the normal camera, local fog, night visibility and world dressing. The project still reports existing material/resource cleanup warnings when the process exits.

Final verification on 7 November 2026 passed 1,259 intro assertions and 665 class-kit assertions. Both required routes ended at level 10, with 2,096 and 2,390 XP toward level 11 respectively. The controlled first-boar trials took approximately 4–12 seconds and left every class with at least 85% health. Script loading reported zero failures and data validation reported zero problems. Data and NPC/quest editor round-trips, authoring, trainers, starter professions, builds, progression scaling and copied-character Continue checks passed.

## Research references

- [Blizzard’s Elwynn Forest 1–5 guide](https://worldofwarcraft.blizzard.com/en-us/news/20147001/new-player-guide-human-starting-zone-elwynn-forest-1-5) informed the sheltered village, short first errands and gradual move toward a larger community.
- [Blizzard’s WoW Classic primer](https://worldofwarcraft.blizzard.com/en-us/news/23090134) informed class learning and useful town services.
- [Deathknell](https://warcraft.wiki.gg/wiki/Deathknell) informed an undead community with domestic problems, guards and nearby dangers. Mythkeep uses original people, dialogue and plot.
- [FFXIV’s official starter guide](https://starter-guide.finalfantasyxiv.com/en_US) and [game manual](https://eu.finalfantasyxiv.com/game_manual/view/) informed clear main-story guidance and practical class lessons.
- [RuneScape’s Cook’s Assistant](https://runescape.wiki/w/Cook%27s_Assistant) informed ordinary ingredients and a memorable local employer. [Jagex’s early-game rebalance notes](https://runescape.wiki/w/Update%3APatch_Notes%3A_Early-Game_Rebalance) reinforced avoiding special versions of everyday materials and unnecessary quest friction.
- [Kingdom Come: Deliverance II — Legacy of the Forge](https://www.deepsilver.com/games/kingdom-come-deliverance-ii/legacy-of-the-forge) informed the emphasis on trades, reputation and residents’ work. Mythkeep’s opening combat remains forgiving.

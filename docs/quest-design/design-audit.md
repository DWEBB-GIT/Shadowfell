# Shadowfell quest design audit

Audited 31 October 2026. Read-only inspection of `C:/Dev/Shadowfell/Shadowfell`; no game files changed. This is the preliminary inventory and gap analysis. Research subsequently arrived and informed `shadowfell-zone-quest-plan.md` and `shadowfell-quest-catalogue.json`.

## Canonical state

Use `data/quests/quests.json`, `data/npcs/npcs.json`, `data/quests/dialogue.json`, `data/terrain/new_map/spawns.json`, `game/systems/quests.gd`, `game/systems/skills.gd`, and `game/core/db.gd` as current evidence. At initial inspection, `docs/thornford-playable-slice.md` still described the earlier four-quest slice. The production team subsequently updated it to redirect to `docs/reach-progression.md`, the current thirteen-quest guide; the documentation-lag finding is historical. Legacy quest records remain in the shared table; do not count them as Thornford's built content merely because they exist.

Thornford has **13 map:new quests: five main and eight optional**. Existing IDs and save progress must be preserved.

| Existing ID | Zone; stated level | Role and objectives | Prerequisite | Coins / XP |
|---|---|---|---|---|
| vr_first_hunt | Holt Meadow; 1-2 | Main: kill 3 young boars, examine meadow | None; auto-accepted | 25 / 260 |
| tf_lanterns | Lantern Road; 2-3 | Main: examine lantern, kill 3 revenants | vr_first_hunt | 25 / 400; 2 draughts |
| tf_bell | Old Watch/Dawnstone; 3-4 | Main: examine ruins, kill Bellkeeper, examine shrine | tf_lanterns | 40 / 550; iron shield |
| vr_names | Nameless Yard; 4-5 | Main: examine stones, kill 3 gravewalkers | tf_bell | 35 / 650; 2 draughts |
| vr_crypt | Bell Crypt; 5 | Main: examine crypt, kill Keeper of the Lost Names | vr_names | 55 / 650; 2 strong draughts |
| tf_briar | Briarwood/Wolf Hollow; 2-3 | Optional local combat/exploration: kill 3 wolves, examine hollow | vr_first_hunt | 20 / 400; tool pack |
| tf_herbs | Briarwood route; level unspecified | Optional gathering: collect 3 ditchbell; marked pickups need no training | None | 10 / 100; draught |
| vr_perch | Willow Pond or Miller's Pool; 1-3 | Optional fishing: deliver 3 Gloomwater perch to Elsie | None | 16 / 120 |
| vr_hollow_story | Mourning Hollow/Widow's Mirror; 3-5 | Independent remembrance: visit pool, return to Morrow | None | 12 / 140 |
| vr_fence_dispute | Orchard boundary; 1-3 | Independent civic evidence: read stone, report to Mayor | None | 10 / 100; boundary flag |
| vr_pig_wolf | Briarjaw's Run; 2 | Independent farm bounty: kill Briarjaw | None | 16 / 150; pigs-safe flag |
| vr_reed_message | Farm to Willow Pond; 1-3 | Independent trade message: accept from Heda, hand in to Tobin | None | 8 / 70 |
| vr_lost_brooch | Miller's Pool; 1-3 | Personal retrieval: recover quest pickup, return to Elsie | None | 12 / 90 |

The main chain is vr_first_hunt -> tf_lanterns -> tf_bell -> vr_names -> vr_crypt. Fen is optional and shares only the first main prerequisite. Do not propose the boundary dispute, pig-killing wolf, reed trade, brooch, perch supper, ditchbell, wolf hollow, or remembrance as new ideas.

## People and ownership

Eleven tf_/vr_ residents: Mayor Alder (4 quests), Rowan (2), Elsie (3), Fen (1), Heda (2), Morrow (1), Iren the smith (no quests), Osric the woodcutter (no quests), Tobin the angler (recipient, no offered quest), Mira the rogue trainer (no quests), Lyra the paladin trainer (no quests). Agna also has an older-map spawn far east at about (267,-168), approximately 717 m from Thornford: not a compact local town service.

NPC concerns already present: civic records and boundaries, missing watch, inn trade and personal keepsake, orchard/livestock, woodcutting rights, apothecary remembrance, fishing and reed exchange. Most local dialogues currently contain one greeting and empty topics/nodes. Heda reacts to pigs-safe and Osric to boundary-settled. Others have little post-quest recognition. Planned work should give Iren, Osric, Tobin, Mira, and Lyra independent personal/work concerns without turning each into a main-plot informant. New ordinary residents can support livelihoods missing from the settlement, but should have a visible workplace and reason to need help.

## Geography and pacing evidence

Start (-450,-203), town hall (-453,-165), Willow Pond (-395,-172), mill pool (-523,-217), orchard (-350,-270), meadow (-332,-309), Briarwood camp (-575,-275), wolf hollow (-555,-360), fallen lantern (-465,-300), watch (-450,-425), Dawnstone (-415,-485), Mourning Hollow (-310,-382), graveyard (-343,-456), crypt (-313,-486), Widow's Mirror (-297,-404). Coordinates are x/z metres; quoted positions are landmarks, not validated new placement sites.

Current built district is a compact part of the 2048 x 3072 m world. Most local trips are tens to a few hundred metres. Town -> camp straight line about 143 m (~26 s at 5.6 m/s before obstacles); town -> watch 222 m (~40 s); town -> Mourning Hollow 227 m (~41 s). Do not scale every errand to the whole continent. Main path and west/east loops already support several activities per outward journey, but repeated Mayor/Rowan returns risk excessive retracing. Future design should batch nearby optional work and allow recipient hand-ins where narratively sensible.

Safety: Thornford guarded watchmen are level 12; farm pigs are lawful livestock. Do not use killing domestic animals as an ordinary gathering tutorial. There are marked flowers west, optional watch treasure, fishing at Willow/Mill level 1, and Widow's Mirror fishing level 8. The latter is a profession skill requirement, not character level 8. An apothecary, chapel, inn, smithy, town hall, farm and woodcutting workplace exist; Bell Crypt is currently a world POI/boss placement, not evidence of an instanced multi-room dungeon system.

Camera direction stays fixed isometric with no look-ahead. Design must be legible through foreground-safe objects, nearby signposts, landmarks, quest text, and map support. No quest should depend on looking ahead with a moving camera or seeing across the entire map.

## Progression and reward audit

Godot canonical character XP costs are 280 + 200*(level-1) per level, unlike the old web `src/config.js` values. Cumulative thresholds: L2 280, L3 760, L4 1440, L5 2320, L6 3400, L7 4680. Main quest rewards total 2,510 XP / 180 coins; optional rewards total 1,170 XP / 104 coins; all current quest rewards total 3,680 XP / 284 coins before combat, profession, rested, or other gains. Completing every current quest already guarantees at least level 6. Adding many full-XP side quests without an explicit policy would over-level this nominal 1-5 region.

Enemy kill XP changes with relative level and rested state, so exact level arrival needs simulation or human route playtesting. Main-only travel should be checked before crypt: the listed L5 quest is not itself level-gated and a sparse route may still be level 4 at its acceptance. Fen's optional 400 XP is much larger than most short local side quests and includes the tool pack; this may influence route choice and inventory access. Do not silently require optional stories to fix mandatory progression. No shield reward is equally useful to all classes; future major rewards should review class parity and item value. Existing rewards/progress are not to be reset.

Profession trainer overrides map combat teachers to local residents and Mining to Iren, Fishing/Camping/Lockpicking to Tobin, Cooking to Elsie, Herbalism/Alchemy to Morrow. Skinning's Agna remains distant. **Potential progression gap:** apprentice rank gates still require legacy quest IDs (`tam_blackpool`, `briony_bloodroot`, `briony_fever`) with legacy giver/turn-in NPC IDs and legacy locations. Trainer overrides alone do not demonstrably remap those quest offerings; plan local accessible rank trials or explicitly verify migration before claiming professions have a complete local ladder. Recipes/tools/nodes also need supply checks. Ditchbell pickups are not proof of a working Herbalism learning loop. Buying crafted goods can satisfy collect objectives; do not claim an item was personally crafted unless a new action-tracking system enforces it.

## Engine capabilities and honest design limits

Current quest status supports map filter, prerequisite quest completion, mutually exclusive `choice`, profession `skillReq`, accepted/done persistence, kill counts after acceptance, inventory collection (consumed unless keep), persistent examined points, one `setsFlag` per completed quest, item/coin/XP/reputation/infamy rewards. Dialogue conditions support quest status, flags, examined point, and minimum character level. Normal quest offering does **not** check the quest's display `level`, so level labels are guidance, not enforcement.

A `talk` objective is ready immediately on acceptance and the UI routes hand-in to `turnIn`; it does not track visiting named intermediate NPCs or actually selecting dialogue. Use recipient hand-in for messages. A multi-person interview needs separate quests or new conversation-event tracking. Examine state can predate acceptance; objectives are unordered within a quest. Multi-stage investigations should use small prerequisite-linked steps if ordering matters. Choice locks when an alternative is accepted; it can be abandoned before completion, so do not promise an irreversible moral choice at acceptance. Static flags and reactive greetings can acknowledge outcomes; relocated fences, repaired mills, restored populations, schedules, or economy simulation require explicit world support and verification. Do not claim NPC life simulation merely from a line of completion text.

Existing gathering, fishing, crafting, shops/repairs, inn/home, training, law/guarded livestock and optional pickups can support content additions. These still need new canonical items/POIs/dialogue/spawns where specified. Escorts, defended wagons, timers/races, multi-step conversation tracking, ordered interactable puzzles, shared multiplayer credit, large dynamic events, permanent building restoration, controllable vehicles, and instanced dungeons should be separately marked as mechanic work until proven implemented. A data-only examine proxy should never be presented as the real mechanic.

## Main design gaps to resolve after research

1. Broaden action and emotional rhythm beyond repeated kill+examine encounters; use civic judgement, evidence, learning, discovery, modest trade, production and optional challenge without repeating built plots.
2. Give underused working residents motivations and visible consequences through dialogue; allow optional places to have stories that remain independent of the watch and stolen names.
3. Establish a repeatable but finite XP/economy budget for adding side content; keep main-only route viable and completionist route appropriately rewarded.
4. Provide complete local profession teaching/supply/rank progression; distinguish character and profession requirements.
5. Separate small current-region additions from concept-only river towns, haunted woods, snowy citadel, volcano, oasis and coast. Concept map geography is not built traversable content.
6. Balance authored complexity against engine limits. Each proposed quest needs zone, level, role, objective types, prerequisites, motivated owner, reward, outcome, implementation status, and concrete data/mechanic dependencies.
7. Refresh stale slice documentation only when implementation is explicitly authorized; this audit remains read-only.

Status: inventory complete; research consumed and final original planning delivered in the accompanying report/catalogue. The production team confirmed the five main/eight optional stories, actual catches, work tools, guards/pigs, interiors and saves pass; this audit's unimplemented-feature distinctions still apply. No game edits were made by this design task.

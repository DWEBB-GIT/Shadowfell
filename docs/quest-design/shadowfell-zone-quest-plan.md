# Shadowfell: zone and quest plan

**World placement update, 1 November 2026:** The opening now connects to 34 authored onward hubs and 109 regional/return quest prototypes. The new map has 134 quests. Terrain routes, level districts, public return areas and seven sealed dungeon approaches are placed. Full private dungeons and measured 60-hour progression remain future work. See the [world review](../world-layout-review.md). Earlier future-content wording below refers to the fuller designs, not the absence of this first placement pass.

Revised 1 November 2026. **Level cap 50. Target journeys: 45 / 60 / 80 hours.** This supersedes the earlier level-6–15 future-zone ladder. Snow and desert are end-level regions.

The opening chapter has **25 quests: five main and twenty optional**. The regional placement pass adds 109 prototypes, recorded separately in the current catalogue and world review. The Quiet Levy rewrite and twelve additions are installed; see [the chapter guide](../quiet-levy.md). The catalogue has 28 research-led design seeds: eight now have implemented `nr_` adaptations, ten further local ideas need new mechanics, and ten cover future regions. Future proposals below are representative stories, not complete regional content or a promise of a finished 60-hour game.

## The level-50 journey

Starting at level 1 gives **49 level-ups**, with no level-50-to-51 interval. Baseline play includes quest dialogue/actions, ordinary travel, encounters, occasional crafting and naturally encountered dungeons. The clock runs to first reaching 50. Offline/AFK time and post-cap map completion are separate.

| Phase | Arrival levels / level-ups | Minutes per level-up | Baseline time | Cumulative time |
|---|---|---|---|---|
| The Hook | 2–10 / 9 | 5, 8, 10, 12, 14, 16, 17, 18, 20 | 2 h | 2 h |
| The Groove | 11–40 / 30 | 30, 45, 55, 65, 70; then 25 at 75 | 35 h 40 m | 37 h 40 m |
| The Prestige | 41–50 / 10 | 100, 115, 125, 130, 135, 140, 145, 150, 150, 150 | 22 h 20 m | **60 h** |

This stays within the requested baseline ranges of 5–20, 30–75 and 90–150 minutes. A straight linear ramp from the low to high edge of all three ranges instead gives 2,887.5 minutes (48 h 07 m 30 s). To retain a 60-hour total without widening those limits, most mid-game levels must be near 75 minutes. This chosen curve makes that tradeoff explicit. It averages **73.47 minutes per level-up**, or 0.817 level-ups/hour, over the whole journey; “roughly a level an hour” is a broad feel, not the exact arithmetic.

Efficient routes use 75% of each baseline time: **45 hours**. Explorer routes use 4/3: **80 hours**. These are comparison envelopes, not player-specific XP multipliers. All players face the same XP thresholds. Speed comes from routing, combat uptime, fast travel, group coordination and reading choices. Explorer time comes from slower routes, lore, experimentation and additional optional play. An explorer who gains more XP from clearing everything can reach 50 before finishing every map: never force an 80-hour minimum or penalize reading/exploration to make a chart true.

The complete 49-row [pacing model](level-50-pacing.json) and [CSV](level-50-pacing.csv) specify every transition. The [editable workbook](Shadowfell-level-50-pacing.xlsx) provides the same model with formula-driven totals and profile comparisons.

## World identity and dungeon layer

The [world scope/name review](world-scope-and-names.md) compares our planned geography with official RuneScape, LOTRO, Conquer and Lost Ark examples. Nine macro-regions and 35 hubs are a sufficient initial design scope; complete their content before adding more regions. Region names now distinguish Rillbank Vale from its port, Brinewatch Strand from its harbor, Frostward Marches from its settlements, and Sunscar Basin from the Sable Well oasis. [Stable naming records](world-names.json) preserve IDs and earlier design aliases.

The [instance plan](instanced-dungeons.md) adds seven approved dungeon-layout blueprints (absolute maximum eight). They sit near the middle/top of local bands, with named loot, resident concerns and wider plot evidence. The 60-hour target is unchanged: dungeon play substitutes within its existing budget. Private contexts, solo/party modes, checkpoints, scoped objectives and receipt-backed loot are implementation work, not features already delivered by a map marker.

## Smaller questing hubs within regions

The region-wide 8–22 assignments are superseded by [named questing hubs and return areas](quest-hubs.md). Player-facing ranges now describe settlements, work bases and dangerous pockets. Rillbank/Mirefen have 5–10 entry hubs, 10–13 and 13–16 work hubs, then 16–19 and 19–22 upper hubs; the player moves repeatedly within the larger geography. The region itself is not one fourteen-level quest hub.

The proposed area sequence is **1–5, 5–10, 10–16, 16–22, 22–28, 25–30, 28–35, 30–40, 40–46, 45–50, 48–50, then level-50 endgame**. Overlap permits route choice and revisits. Long bands contain several forward bases: a single 30–40 camp would still hold 12½ hours of the target journey. Snow and desert both remain end-level regions, with smaller 40–42, 42–44, 44–46, 45–47, 47–48 and 48–50 bases.

### One budget per earning interval

| Earning interval | Baseline time | Hub chains: choose or mix |
|---|---|---|
| 1→5 | 0 h 35 m | Thornford village |
| 5→10 | 1 h 25 m | Lantern Crossing **or** Mossreed Landing |
| 10→16 | 5 h 40 m | Rillbank Quays → Millward **or** Reedward Cooperative → Pumpstead |
| 16→22 | 7 h 30 m | Willow Ferry → Tollhouse Rise **or** Stiltmarket → Causeway Watch |
| 22→28 | 7 h 30 m | Greyroot Refuge → Scribes’ Hollow **or** Brinewatch Docks → Saltmere Outpost |
| 28→35 | 8 h 45 m | Highmere Market → Quarryend **or** Cinder Gate → Ashworks |
| 35→40 | 6 h 15 m | Windscar Redoubt → Heatherpass Relay **or** Redkiln Camp → Ember Relay |
| 40→46 | 12 h 25 m | Frostgate → Rimepass → Hearthwatch **or** Sable Well → Duneshade Rest → Dune Watch |
| 46→48 | 4 h 55 m | Whitebough Hospice → Last Beacon **or** Saltroad Caravanserai → Glassroad Station |
| 48→50 | 5 h 00 m | Rimewatch Gate **or** Sunseal Court |

The intervals total **3,600 minutes and 49 gains** once. 25–30, 30–40 and 45–50 are overlapping local-area choices, not additional required time. The 45/60/80-hour envelopes and existing XP prices are retained. An efficient route need not clear every hub; a completionist can finish more stories after reaching the cap.

### Later returns and fixed danger

The [hub plan](quest-hubs.md) includes Sealhouse Cellars and the Drowned Pumphouse at 25–30, Stormwatch Point at 30–35, Deep Crucible at 38–42, a separate Bell Wing at 48–50, and three deferred level-50 endgame pockets for later production. These locations can be seen or mentioned on the first regional visit, then revisited with stronger equipment and a relevant local story. Existing safe settlements and low-level encounters do not scale up when the player returns.

**50+ means post-cap content only:** all normal and elite enemies there are level 50. Distinguish elites by encounter tuning and an elite flag, not level 51–53. The finale awards level 50 once; endgame play is outside the first-arrival hour budget.

### Story continuity, services and scope

Equivalent regional chapters should produce the same onward evidence/outcome, so choosing marsh instead of river or coast instead of woodland does not break the main story. `qp_honest_copy` accepts the planned river **or** marsh evidence outcome. Do not put both route IDs into the current all-required `requires` list. OR/outcome gates and single-claim shared chapter rewards remain planned engine work.

Preserve progress when switching routes. Main settlements provide inns and training; forward bases provide practical repairs, supplies, rest and local hand-ins. Keep travelled distances compact and purposeful. Hub residents still have livelihoods and independent local problems; not every quest points to Rook.

The structured [hub records](quest-hubs.json) are an authoring plan, not placed NPCs, terrain or additional quests. Current Thornford remains the level-1–5/6 prototype; the onward settlements and return pockets require building. Start with a complete 5–10 branch before spreading empty markers across all later regions.

## Future quest placements

| Quest | Region | Recommended level | Type |
|---|---|---|---|
| A Seal Without a Sender | Rillbank | 13–16 | Main investigation |
| The Ferry’s Third Passenger | Rillbank | 16–18 | Cargo investigation and negotiation |
| A Path Borrowed from Tomorrow | Paleweald | 22–25 | Spatial knowledge puzzle |
| The Last Honest Copy | Paleweald | 25–28 | Main document investigation |
| The Heat Ledger | Frostward Marches | 44–46 | Civic evidence and allocation |
| The Rope School | Frostward Marches | 46–47 | Training and execution |
| The Forge Between Eruptions | Cinder Reach | 38–42 | Crafting and protective combat |
| Water Has a Name Here | Sunscar Basin | 48–50 | Water audit and policy negotiation |
| Shade Is a Trade | Sunscar Basin | 45–47 | Capped favor chain and carrying challenge |
| The Seamark at Low Water | Brinewatch Strand | 30–35 | Navigation and harbor work |

The two future main seeds describe the Rillbank and Paleweald versions of shared act outcomes. Mirefen and Brinewatch need their own equivalent chapters. These ten seeds are **not the whole level-11–50 main questline**, and the new regional briefs are not extra completed quest designs. Both frontier routes and both final routes need complete chains and a shared earned conclusion. No optional seed becomes a prerequisite of the existing five chapters.

## XP and content budgets

The runtime cap is now 50. Existing XP costs remain `280 + 200 × (current level − 1)` for the next level. They sum to **248,920 XP** across 1→50. This is a diagnostic of the current placeholder curve, **not evidence the present rewards deliver 60 hours**. Each model row divides that cost by its target minutes to show the XP/minute that route would need. Route-bracket budgets sum each interval once; paired regions share those opportunities rather than adding both to the required journey. Changing XP prices later requires measured encounter/quest rates and a save policy; no mass reward or cost retune is hidden in this planning revision.

The current 25 quests pay **3,900 XP** (2,510 main, 1,390 optional). Current thresholds require 9,720 XP to reach 10, leaving 5,820 XP beyond existing quest payouts before accounting for kills, discoveries, rested gains or new content. That difference is not a prescription to add 5,820 more quest XP: budget those other sources first. Early rewards and existing completion remain intact.

Assign each bracket its required XP from the 49-transition model, then build each alternative region a reachable story/encounter route that can meet the same exit level without mandatory dungeon queues, profession grinding, rare drops or every side quest. Optional content supplies alternative ways to replace some encounters or take a different route. Dungeon and crafting XP must be included once rather than added on top of an already complete budget. Track rested/inspiration, party sharing, repeat clears, grey enemies and profession XP explicitly when testing actual routes.

Future quest payouts are now **unbudgeted** in the structured catalogue. The old 40–280 XP and 10–18 coin figures were starter-tier placeholders; they are not silently carried into level-50 regions. Their old values remain labelled historical for traceability. Define regional reward anchors after XP/minute, gearing and local prices are tested. A main chapter's listed reward is paid once, not again at every internal step. Failure/retry never duplicates payout.

For estimating authoring scope, one possible baseline time mix is 48 hours in quest loops, 6 in dungeons, 3 in professions and 3 in free exploration. A quest loop already includes its combat, travel, dialogue and puzzle actions: do not count those minutes again. Forty-eight hours at 12 minutes per completed loop implies about **240 baseline quest completions**; at 16 minutes it implies 180. Those are workload estimates to replace with measured durations, not a rule to pad the game with counters. A larger optional pool supports route choice and completionists. The ten future proposals are seeds, far short of this content requirement.

## Milestones and production gates

- **Hook:** short feedback loops, early class choices and useful training; a first group/dungeon introduction around 10 with a solo route available. The exact training/talent unlocks still require a class-by-class pass.
- **Groove:** region changes, build synergies and optional dungeons. Plan earned mount access around 20 and useful fast-travel links, then budget their effect on travel time. Mounts and these new dungeons are future features, not current build claims.
- **Prestige:** meaningful chapters and build milestones between longer XP bars; final training/capstones and endgame gear previews across 41–50. Scope each class's actual abilities before claiming they are implemented. No filler grind to fill the longer intervals.
- **Measurement:** compare fresh-character efficient, baseline and explorer routes. Log cumulative XP by source and elapsed active minutes at every level and regional exit. Use a separate journey clock: the current simulation clock pauses for blocking UI and clamps long frames, so it cannot measure a journey that includes reading and menus. First test 1–10, then one middle region and one end-level region; tune the local source of a discrepancy rather than applying a global multiplier on guesswork.
- **Acceptance:** complete primary progression with optional professions/dungeons omitted, test alternative regional routes, and verify level 50 stops further character XP while quests can still reward currency/items. Old saves remain readable. Publish 45/60/80 as measured expectations only after representative human playthroughs support them.

## Verification

The earlier cap revision’s isolated level-cap/save-compatibility test reports zero failed assertions, the existing starter checks pass, and the script check reports zero failures. The workbook's 45/60/80-hour totals, representative edited-input recalculation, error scan, native chart export and readable sheet views were checked. These verify implementation and arithmetic, not a measured 60-hour playthrough. Existing engine cleanup warnings still occur at test shutdown.

The hub revision changes planning documents only. Its audit checks all core route combinations, hub-chain coverage, preserved level timings and identical 45/60/80-hour totals. Return areas are optional and level-50 endgame has no additional character-level interval.

## Original research-led designs

The cards retain their source-pattern links, motivations and interaction requirements. Eight local cards are flagged as implemented adaptations. Future regional main cards describe one version of an alternative act outcome, not a compulsory visit to every region. Future cards have revised level bands and retired early-tier payouts. Proposed `qp_` keys remain planning identifiers; production `nr_`, `vr_` and `tf_` IDs remain stable. [The original comparative report](game-quest-research.md) contains source access limitations and distinguishes source mechanics from original Shadowfell adaptations.

## Detailed proposal catalogue

Levels and durations are targets to test. “Engine-ready” means current quest primitives support the described player actions; the content still needs authoring and validation. “New interaction mechanics required” means the described action cannot be completed honestly by an examine marker. Future entries also need their entire place and residents. All stated rewards are whole-entry totals and original budget proposals.


### qp_gauge — A Gauge Worth Trusting

**Implemented adaptation:** `nr_gauge`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Thornford smithy; character 1–2; no profession requirement.** simple; Evidence and salvage; leading verb **compare**; role **profession**. Target 3–5 minutes. **Original first-batch seed.** 

**Owner:** Iren Holt (tf_iren). Iren refuses to sell tools checked against an unreliable borrowed gauge; her professional reputation matters.

**Prerequisites:** None; optional local work.

1. Accept Iren’s request; examine the stamped master measure beside her anvil and the split witness mark on a discarded gauge near the smithy.
2. Recover one rejected gauge from a quest-bound pickup; hand it to Iren. The two examines and collect can occur in any order.
3. Iren explains how the witness mark proves the gauge slipped. The player has gathered evidence, not straightened or tested a tool.

**Budget:** 20 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Iren gains a completion-conditioned greeting about checking her own work; no physical repair or discount is promised.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: Two new POIs, one quest-bound pickup/item, one completion flag and reactive greeting; verify forge access remains clear.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [RuneScape: Cook's Assistant](https://runescape.wiki/w/Cook%27s_Assistant). S01, deliberately reduced to an honest evidence-and-salvage slice.

### qp_timber — The Dry Stack

**Implemented adaptation:** `nr_timber`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Orchard timber trail → smithy; character 1–2; no profession requirement.** simple; Work delivery; leading verb **supply**; role **local**. Target 3–5 minutes. **Original first-batch seed.** 

**Owner:** Osric Moss (vr_osric); recipient Iren Holt. Osric wants his carefully seasoned handle wood used before damp splits it, and wants Iren to trust his grading.

**Prerequisites:** None; optional local work.

1. Accept from Osric; collect two tagged dry handle billets from his existing work stack through quest-bound pickups.
2. Carry both to Iren at the smithy; the collect hand-in consumes them. The player does not chop live trees or repair the disputed fence.

**Budget:** 0 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Iren’s completion text recognizes Osric’s good wood; Osric has a quest-conditioned greeting. The old boundary outcome is untouched.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: New billet item and two nearby pickups; giver vr_osric / turnIn tf_iren; dialogue conditions; no holding animation or carrying penalty.

**Pattern:** [RuneScape: One Small Favour](https://runescape.wiki/w/One_Small_Favour); [RuneScape: Cook's Assistant](https://runescape.wiki/w/Cook%27s_Assistant). Original extension of S06’s workmanship theme, without its repair mechanic.

### qp_water_notes — Two Waters, One Notebook

**Implemented adaptation:** `nr_water_notes`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Willow Pond and Miller’s Pool; character 1–3; fishing 1.** simple; Fishing survey; leading verb **sample**; role **profession**. Target 4–7 minutes. **Original first-batch seed.** 

**Owner:** Tobin Reed (vr_tobin). Tobin is writing a beginner’s notebook and needs a second observer, not a larger supper order.

**Prerequisites:** None; optional local work.

1. Accept with Fishing 1; examine Tobin’s bank-depth marker at Willow Pond and the mill-pool reed marker.
2. Supply one silver_dace and one gloomwater_perch, then hand in to Tobin. Either fish may come from either water or existing bags; the journal says supply rather than prove where caught.

**Budget:** 20 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Tobin’s greeting mentions the completed notes; completion text gives a practical fishing hint. No catch-location validation is claimed.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: skillReq fishing 1; two POIs; existing fish items/table; verify dace availability and costs with the existing tackle shop. Do not add a large random rare-fish gate.

**Pattern:** [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml); [RuneScape: Cook's Assistant](https://runescape.wiki/w/Cook%27s_Assistant). S09/S10 technique-and-observation theme; actual release/drift mechanics reserved below.

### qp_reverse_route — The Route on the Reverse

**Implemented adaptation:** `nr_reverse_route`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Thornford ↔ Briarwood safe edge; character 2–3; no profession requirement.** simple; Landmark navigation; leading verb **orient**; role **exploration**. Target 4–7 minutes. **Original first-batch seed.** 

**Owner:** Mira Vale (vr_rogue). Mira trains rogues, but her personal concern is making sure apprentices can find home when a pursuit goes badly.

**Prerequisites:** vr_first_hunt

1. Read Mira’s three descriptive directions in the offer and journal; examine a split stump, bridge-side stone and shelter-door mark on a safe edge route.
2. Return to Mira; no ordered input, hidden orientation state or correct-answer selection is required. All three landmarks count in any order.

**Budget:** 20 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Mira acknowledges reliable route knowledge. The route already exists: no new shortcut, skill or map overlay is unlocked.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: Three legible new POIs near existing paths; optional ordinary map markers; manually useful clues with full marker accessibility.

**Pattern:** [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/); [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml). S13, data-only landmark route rather than a map-rotation puzzle.

### qp_bedding — No One Turned Away

**Implemented adaptation:** `nr_bedding`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Thornford chapel / smithy / timber trail; character 1–3; no profession requirement.** simple; Community provisioning; leading verb **provision**; role **local**. Target 3–5 minutes. **Original first-batch seed.** 

**Owner:** Sister Lyra (vr_lyra). Lyra has promised shelter to seasonal workers regardless of faith and is embarrassed that the chapel has empty bed frames.

**Prerequisites:** None; optional local work.

1. Accept Lyra’s request for two donated bedding rolls; recover one clearly labelled donation beside Iren’s smithy and one at Osric’s work shelter.
2. Return both rolls to Lyra. Donations are voluntary, marked quest pickups; there is no stealing from homes or defeating townsfolk.

**Budget:** 0 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Lyra thanks the workers by name in her completion greeting. No guest simulation, restored building or bed service is asserted.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: New bedding item and two quest-bound pickups; Lyra reactive dialogue; donor permission stated in pickup/offer text.

**Pattern:** [RuneScape: Cook's Assistant](https://runescape.wiki/w/Cook%27s_Assistant); [RuneScape: One Small Favour](https://runescape.wiki/w/One_Small_Favour). Original pastoral-work story using local interdependence.

### qp_shelter_tracks — A Shelter, Not a Lair

**Implemented adaptation:** `nr_shelter_tracks`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Briarwood camp and safe woodland edge; character 2–3; no profession requirement.** simple; Evidence-led exploration; leading verb **trace**; role **exploration**. Target 4–7 minutes. **Original first-batch seed.** 

**Owner:** Scout Fen (tf_scout). Fen wants to avoid sending hunters after every shape in the woods: a traveling brush maker has a right to shelter there.

**Prerequisites:** vr_first_hunt

1. Examine a boot print, bristle sack impression and dry shelter hearth at three fixed POIs.
2. Return to Fen; each note supplies part of a benign explanation. This is an authored trail with unordered examine credit, not a system that grades deductions.

**Budget:** 20 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Fen’s greeting distinguishes shelter signs from wolf spoor. Brush maker remains off-stage; no missing-person escort or spawned survivor is implied.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: Three POIs outside mandatory wolf aggro; clue texts; completion greeting; keep tf_briar independent.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/). S11, honest tracking vignette.

### qp_bottle_labels — The Label Facing In

**Implemented adaptation:** `nr_bottle_labels`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Mourning Hollow apothecary; character 3–5; no profession requirement.** simple; Workplace diagnosis; leading verb **document**; role **local**. Target 3–6 minutes. **Original first-batch seed.** 

**Owner:** Morrow Finch (vr_morrow). Morrow has been refunding harmless spoiled mixtures and wants to find a storage mistake before blaming the supplier.

**Prerequisites:** None; optional local work.

1. Examine the supplier’s storage card outside the apothecary; recover two labelled spoiled-sample bottles from quest-bound shelf-side pickups.
2. Hand the samples to Morrow; the completion explains that the inward label hid a cold-storage warning. The player records evidence; Morrow diagnoses it.

**Budget:** 20 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Morrow admits the mistake in a new greeting. No safe-slate experiment, bottle-temperature model or actual shelf rearrangement is implemented by this slice.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: New sample item/two pickups, readable warning POI, dialogue and flag; verify reachability without claiming entry to a non-enterable shell.

**Pattern:** [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml); [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery). S17, paperwork-and-samples precursor; experimental sequel is separate.

### qp_pollinator_notes — The Orchard’s Small Tenants

**Implemented adaptation:** `nr_pollinator_notes`. Read [the current chapter guide](../quiet-levy.md) for actual actions; the original design seed below is retained for context.

**Holt Orchard; character 1–3; no profession requirement.** simple; Ecology survey; leading verb **observe**; role **local**. Target 3–6 minutes. **Original first-batch seed.** 

**Owner:** Heda Holt (vr_heda). Heda needs fruit to set and suspects poor pollination, not another monster at her pigs.

**Prerequisites:** None; optional local work.

1. Examine two orchard-row blossom markers and one blocked pollinator nook; the notes compare shaded and sunny rows.
2. Recover one abandoned loose mesh roll beside the nook and return it to Heda. The mesh is already detached: picking it up does not free creatures, reopen nests or change pollination.

**Budget:** 20 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Heda thanks the player for locating the problem and says she will do the work. Only a reactive greeting changes; a bee/blossom restoration is reserved for later world-state work.

**Readiness:** Implemented adaptation; see production quest and current guide. Original dependencies: Three POIs, one ordinary quest pickup/item, completion greeting; no protected livestock targets or bee simulation.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html). S07, survey slice; active nest repair deliberately deferred.

### qp_chairs — An Empty Chair

**Lantern Inn; character 1–3; no profession requirement.** moderate; Social spatial puzzle; leading verb **arrange**; role **local**. Target 6–10 minutes. 

**Owner:** Elsie Reed (tf_elsie). Elsie wants a hard-of-hearing visiting buyer and a courier with a short stop to feel equally welcome.

**Prerequisites:** None; optional local work.

1. Ask three proposed guests about practical needs; retain their answers as journal clues.
2. Assign each guest to a marked seat; press a clear test/confirm prompt; guests explain mismatches and can be reseated.
3. Confirm one arrangement meeting the buyer’s hearing needs and courier’s exit access; report to Elsie.

**Budget:** 0 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Seating and guest comments persist for this visit; inn services remain available during retries.

**Readiness:** New interaction mechanics required; not implemented. Conversation-event objective tracking; guest spawn/lifecycle; seat assignment UI; saved arrangement; rule evaluator; reversible test feedback and navigation around furniture. Examine props cannot seat NPCs.

**Pattern:** [WoW: Welcome to the Machine](https://warcraft.wiki.gg/wiki/Welcome_to_the_Machine); [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery). S02.

### qp_chalk — Whoever Holds the Chalk

**Thornford town hall; character 2–3; no profession requirement.** moderate; Civic role reversal; leading verb **assign**; role **local**. Target 7–10 minutes. 

**Owner:** Mayor Alder (vr_mayor). Alder needs to attend a sick relative and wants ordinary residents to share decisions rather than wait for orders.

**Prerequisites:** None; optional local work.

1. Hear three volunteers’ constraints and read three small job descriptions: indoor sorting, short delivery and daytime sign painting.
2. Assign one volunteer per job on a three-slot board; confirm; observe one short follow-up.
3. Correct a mismatch or accept another valid arrangement; close the shift with Alder.

**Budget:** 0 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Board assignments and two follow-up lines reflect the choice; no permanent town labor economy is simulated.

**Readiness:** New interaction mechanics required; not implemented. Dialogue-event tracking; assignment board and constraint evaluator; staged volunteer tasks, saved choices and fail-forward correction. Do not represent this as three talk objectives.

**Pattern:** [WoW: Welcome to the Machine](https://warcraft.wiki.gg/wiki/Welcome_to_the_Machine); [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml). S03.

### qp_fair_ring — A Fair Ring

**Thornford market nook; character 2–4; no profession requirement.** moderate; Civic investigation and choice; leading verb **verify**; role **local**. Target 8–12 minutes. 

**Owner:** Nessa Bale (proposed scale mender). Nessa’s livelihood depends on honest calibration; she resents being blamed for a trader’s damaged pan and a customer’s false claim.

**Prerequisites:** None; optional local work.

1. Gather a stamped test weight and inspect two receipts; interview trader and customer with separately recorded answers.
2. Place the test weight in each pan to distinguish a bent suspension from deliberate short measure.
3. Present supported findings; choose public correction or quiet restitution after seeing both costs; complete the same core work for either ending.

**Budget:** 0 XP, 6 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** One bounded customer/trader greeting differs; Nessa keeps her calibration stall. Equal rewards prevent the louder outcome becoming the optimal farm.

**Readiness:** New interaction mechanics required; not implemented. New working NPC/stall; physical test interaction; evidence inventory/journal; dialogue-event and conclusion validation; saved choice committed on resolution. Existing choice acceptance alone does not enforce informed commitment.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html); [RuneScape: Hazeel Cult](https://runescape.wiki/w/Hazeel_Cult). S04.

### qp_nails — Not One Nail Wasted

**Timber work shelter and field stile; character 2–3; no profession requirement.** moderate; Salvage and repair; leading verb **dismantle**; role **profession**. Target 7–10 minutes. 

**Owner:** Osric Moss (vr_osric). Osric wants to teach an apprentice thrift and leave a usable footpath, without cutting another sound tree.

**Prerequisites:** qp_timber

1. Read the old bench’s joint marks; remove braces before the load-bearing rail.
2. Straighten reusable fittings at a work surface; use them to brace a designated field stile.
3. Test the stile and show the result to Osric; bent spare nails can be replaced for free.

**Budget:** 0 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** A single stile gains a saved repaired appearance and safe passage; the orchard boundary is untouched.

**Readiness:** New interaction mechanics required; not implemented. Ordered dismantling states; tool/workstation action; replaceable material handling; repair validation; collision/appearance swap; saving and interruption recovery. A collect objective supplies nails but does not perform repair.

**Pattern:** [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html); [RuneScape: Cook's Assistant](https://runescape.wiki/w/Cook%27s_Assistant). S06.

### qp_release — A Clean Release

**Willow Pond; character 2–3; fishing 1.** moderate; Fishing technique; leading verb **release**; role **profession**. Target 6–9 minutes. 

**Owner:** Tobin Reed (vr_tobin). Tobin wants children to inherit healthy water and dislikes seeing inexperienced anglers throw injured fish back.

**Prerequisites:** qp_water_notes

1. Practice unhooking on Tobin’s reusable float; see clear success and retry feedback.
2. Catch a common fish after accepting; retain a live-catch instance; choose the wet-bank release action.
3. Tobin acknowledges the released fish; keeping it remains possible but does not complete the release objective.

**Budget:** 0 XP, 4 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** Release animation and catch record acknowledge one successful lesson; no statistical ecology bonus or new perk.

**Readiness:** New interaction mechanics required; not implemented. Catch-instance/provenance state; unhook interaction and visual equivalent; release action, objective event, inventory reconciliation; expiry/retry if leaving water. Existing collect and examine objectives cannot prove release.

**Pattern:** [Lost Ark: Lullaby Island](https://www.icy-veins.com/lost-ark/lullaby-island-guide); [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml). S09.

### qp_no_sword — No Sword Drawn

**Lantern Road side shelter; character 3–4; no profession requirement.** moderate; Safe-passage rescue; leading verb **guide**; role **local**. Target 8–12 minutes. 

**Owner:** Captain Rowan (tf_rowan). Rowan wants a civilian home without treating every road problem as an order to kill.

**Prerequisites:** tf_lanterns

1. Meet a proposed stranded basket maker at a side shelter; observe a short, telegraphed patrol loop.
2. Place two available decoys and guide the civilian through the opening, or clear a capped group of threats.
3. Reach a safe point together; report success to Rowan. Both approaches award the same reward.

**Budget:** 0 XP, 6 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** The basket maker appears in town for this saved outcome and comments on the chosen approach; the main watch chain is unchanged.

**Readiness:** New interaction mechanics required; not implemented. Escort pathfinding/leash and safe restart; real patrol schedule; sound-decoy aggro behavior; civilian arrival objective; combat alternative credit and saved actor state. Examination is not an escort.

**Pattern:** [LOTRO: Web-cutter](https://lotroquesting.blogspot.com/2014/05/the-shire-eriador-a.html); [LOTRO: spoiled-pie deliveries](https://lotro.fandom.com/wiki/No_Place_for_Spoiled_Pies_%28spoiler%29). S14.

### qp_hinge — Hold the Hinge

**Old Watch outer shelter; character 3–5; no profession requirement.** moderate; Protective combat and repair; leading verb **protect**; role **profession**. Target 8–12 minutes. 

**Owner:** Iren Holt (tf_iren). Iren promised the carters a storm shelter and wants her hardware fitted safely rather than abandoned at the ruins.

**Prerequisites:** tf_bell

1. Carry a replacement hinge to a designated outer shelter separate from the Bellkeeper arena.
2. Fit the hinge through a real station action; protect the fitting zone against two capped waves and reset its brace between them.
3. Close and reopen the gate once to test it; report to Iren.

**Budget:** 20 XP, 6 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** The shelter gate has a saved working state; no permanent suppression of ambient undead is claimed.

**Readiness:** New interaction mechanics required; not implemented. Quest encounter controller; bounded wave spawns/XP; interactive brace and fitting progress; interruption checkpoint; gate animation/collision and escape guarantee. No ordinary kill counter is passed off as defense.

**Pattern:** [WoW: Peacebloom vs. Ghouls](https://www.wowhead.com/guide/peacebloom-vs-ghouls-the-strategy-guide-450); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html). S15.

### qp_cold_slate — The Bottle That Froze Warm

**Mourning Hollow apothecary; character 3–5; alchemy 1.** moderate; Controlled experiment; leading verb **test**; role **profession**. Target 8–12 minutes. 

**Owner:** Morrow Finch (vr_morrow). Morrow wants the apprentice to understand how storage changes a mixture, and to stop refunding another spoiled batch.

**Prerequisites:** qp_bottle_labels

1. Place tiny labelled samples on a safe slate; test warm, shaded and charm-adjacent positions.
2. Compare visible residue rather than color alone; choose an evidence-supported storage shelf.
3. Prepare one replacement practice dose using the known correct conditions; wrong tests explain themselves and consume no scarce materials.

**Budget:** 20 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** One shelf arrangement and Morrow’s instruction persist; this does not unlock Apprentice by itself.

**Readiness:** New interaction mechanics required; not implemented. Sample/temperature trial UI; controllable experiment state and evaluation; actual station action event, saved shelf state, free reset. Ordinary collected tonics cannot prove personal brewing.

**Pattern:** [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml); [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery). S17 full interaction, following the reduced first slice.

### qp_wall_visitor — The Visitor in the Wall

**Mourning Hollow cottage; character 3–5; no profession requirement.** moderate; Sensory investigation and rescue; leading verb **listen**; role **local**. Target 7–11 minutes. 

**Owner:** Della Wren (proposed basket weaver). Della needs sleep before her market journey and fears damaging her rented wall more than any ghost.

**Prerequisites:** None; optional local work.

1. Trace three wall panels with a listening cup; match sound with a visible pulse and text vibration clue.
2. Open the panel matching the moving signal; calmly release a trapped dusk-marten.
3. Refit the panel and reassure Della; wrong panels can be closed without a fine.

**Budget:** 20 XP, 5 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** The animal exits and the cottage sound stops in the saved quest state; Della resumes weaving. No connection to stolen names.

**Readiness:** New interaction mechanics required; not implemented. New local NPC and accessible cottage space; spatial listening/visual clue sampling; panel open/close state; animal release and escape; repair state and saved sound suppression.

**Pattern:** [Lost Ark: Lullaby Island](https://www.icy-veins.com/lost-ark/lullaby-island-guide); [LOTRO: Web-cutter](https://lotroquesting.blogspot.com/2014/05/the-shire-eriador-a.html). S18.

### qp_outward_door — A Door That Opens Outward

**Bell Crypt proposed side alcove; character 5–6; no profession requirement.** advanced; Spatial escape puzzle; leading verb **unlatch**; role **exploration**. Target 10–16 minutes. 

**Owner:** Lyra (giver); a proposed stoneworker’s old instruction plaque. Lyra wants the old public refuge usable for emergencies; the side-room latch is unsafe.

**Prerequisites:** vr_crypt

1. Voluntarily enter a clearly marked optional trial alcove; checkpoint at the open exit.
2. Read hinge wear and move a counterweight; use either a replaceable manual brace or a controlled summoned revenant weight to hold a plate.
3. Open the outward door and leave; an always-available reset returns the player to the checkpoint.

**Budget:** 20 XP, 6 coins, no item/stat reward. One-time; no repeat XP; all phases share this budget. **Aftermath:** The alcove can be revisited; its safe exit persists. No main crypt path, existing boss or unique story item is required again.

**Readiness:** New interaction mechanics required; not implemented. New side geometry; interactable counterweights/plates and door state machine; two solution evaluators; reset/unstuck button; save/load during trial and combat-proxy lifecycle. A POI examine cannot implement a puzzle room.

**Pattern:** [RuneScape: Broken Home](https://www.runehq.com/quest/broken-home); [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/). S21.

### qp_seal_sender — A Seal Without a Sender

**Planned hub/pocket:** Millward.

**FUTURE — Future river farming town: Rillbank (working name); character 13–16; no profession requirement.** moderate; Main investigation; leading verb **authenticate**; role **main**. Target 10–15 minutes. 

**Owner:** Jory Pell (proposed river records clerk). Jory wants a forged freight seal cleared from his family’s trading record; the player separately wants the source of the crypt’s seals.

**Prerequisites:** vr_crypt; Future river chapter arrival; placeholder trigger, not an existing quest ID

1. Compare the restored burial-seal impression from the Mayor’s records with a river toll stamp and a dated mold receipt.
2. Recover one abandoned freight ledger at a riverside store; return evidence to Jory.
3. Jory establishes that genuine blank seals left for an upland copying house; obtain a documented lead rather than name a villain.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** The river freight issue is closed and the next main chapter points toward an upland archive. No local fishing/farm quest gates that lead.

**Readiness:** Future zone/content required; existing quest primitives sufficient for stated actions. New river geography, clerk/dialogue/items/POIs; three unordered examines and collect; no personal-identity test or document comparison puzzle claimed. Complete a prerequisite-linked step if clue reveal order matters.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/). Original main bridge derived from evidence/provenance patterns.

### qp_ferry — The Ferry’s Third Passenger

**Planned hub/pocket:** Willow Ferry.

**FUTURE — Future Rillbank ferry and market; character 16–18; no profession requirement.** moderate; Cargo investigation and negotiation; leading verb **weigh**; role **local**. Target 10–15 minutes. 

**Owner:** Bessa Quill (proposed ferry operator). Bessa is liable for overloads, while a grower is trying to save vulnerable seedlings rather than evade a villain’s tax.

**Prerequisites:** None; optional local work.

1. Compare a manifest with the ferry waterline; operate a cargo scale to locate an undeclared crate.
2. Hear the grower and inspector; choose licensed carriage, a shore nursery, or return with a refund.
3. Load the agreed cargo and validate the safe waterline before departure.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** One market seedling stock or shore nursery variant changes; no choice removes ferry access.

**Readiness:** Future zone and new interaction mechanics required; not built. Ferry scene; weight/loading UI and evaluator; recorded interviews; choice and saved stall variants. Real travel vehicle simulation is optional; scene transition ferry can suffice.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [RuneScape: Hazeel Cult](https://runescape.wiki/w/Hazeel_Cult); [LOTRO: spoiled-pie deliveries](https://lotro.fandom.com/wiki/No_Place_for_Spoiled_Pies_%28spoiler%29). S22.

### qp_weather_path — A Path Borrowed from Tomorrow

**Planned hub/pocket:** Greyroot Refuge.

**FUTURE — Future haunted woods: Paleweald (working name); character 22–25; no profession requirement.** advanced; Spatial knowledge puzzle; leading verb **reveal**; role **exploration**. Target 12–18 minutes. 

**Owner:** Cairn Vale (proposed surveyor; no relation to Mira). The surveyor wants a safe route for mushroom gatherers and dislikes selling maps that only work in dry weather.

**Prerequisites:** None; optional local work.

1. Use three nearby mist, warmth and lamplight devices on a weather-stained route sheet.
2. Combine each revealed symbol with a distinct real landmark; select and traverse the safe local branch.
3. Mark the stable route for the surveyor; mistakes return to the nearest safe marker without a long trek.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** A saved shortcut marker becomes usable; no scheduled weather waiting or link to the crypt conspiracy.

**Readiness:** Future zone and new interaction mechanics required; not built. Weather-reveal item UI; controllable device conditions; route-knowledge validation, bounded traversal/reset, shortcut world state and save handling.

**Pattern:** [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/); [RuneScape: Broken Home](https://www.runehq.com/quest/broken-home). S23.

### qp_honest_copy — The Last Honest Copy

**Planned hub/pocket:** Scribes’ Hollow.

**FUTURE — Future Paleweald upland archive; character 25–28; no profession requirement.** moderate; Main document investigation; leading verb **reconstruct**; role **main**. Target 12–18 minutes. 

**Owner:** Talla Sorn (proposed archivist). Talla wants to protect the archive’s record of public debts after discovering pages selectively copied for a private patron.

**Prerequisites:** Relief accounts authenticated through Rillbank **or** Mirefen. This shared-outcome gate requires implementation. Ordinary archive access is not a profession gate.

1. Examine the public index, surviving copy and printer’s discarded proof at three reachable archive POIs.
2. Recover an unaltered routing slip from a deserted annex guarded by two authored sentries; the goal is the document, not a kill quota.
3. Return to Talla; she identifies the patron’s contracted copying office and preserves a public copy before handing on the lead.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** Closes the first investigation of how names were selected; leaves a discrete future copying-office chapter hook, not proof every haunted creature serves it.

**Readiness:** Future zone/content required; existing quest primitives sufficient for stated actions. Archive/annex geometry, items, sentries and readable POIs; no multi-clue selection grading. Delivery/examine order can be separate prerequisite-linked steps sharing the budget.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html). Original main bridge; civic records meet physical evidence.

### qp_heat — The Heat Ledger

**Planned hub/pocket:** Hearthwatch.

**FUTURE — Future snowy citadel: Frostward (working name); character 44–46; no profession requirement.** advanced; Civic evidence and allocation; leading verb **allocate**; role **local**. Target 12–18 minutes. 

**Owner:** Enna Slate (proposed district stoker). Enna is blamed for cold homes despite equal fuel shares; she wants a policy that accounts for insulation and vulnerability.

**Prerequisites:** None; optional local work.

1. Trace two fuel receipts and inspect heat loss and occupancy in three homes.
2. Allocate a fixed fuel budget on a board, then select one shared insulation repair with an explicit material cost.
3. Run a visual warmth test; revise until minimum shelter needs are met and ratify one of multiple workable policies.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** Only this district’s fuel board, one repaired wall and residents’ comments change. No continent economy or real-time winter wait.

**Readiness:** Future zone and new interaction mechanics required; not built. New district, home access; heat/occupancy evidence; budget UI and evaluator; repair state; saved policy and readable costs.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [WoW: Welcome to the Machine](https://warcraft.wiki.gg/wiki/Welcome_to_the_Machine). S24.

### qp_rope_school — The Rope School

**Planned hub/pocket:** Whitebough Hospice.

**FUTURE — Future Frostward courier yard; character 46–47; no profession requirement.** moderate; Training and execution; leading verb **practice**; role **profession**. Target 8–12 minutes. 

**Owner:** Orris Fenlow (proposed mountain courier). Orris wants apprentices to inspect knots before carrying another person’s letters across ice.

**Prerequisites:** None; optional local work.

1. Answer three local safety questions using a nearby illustrated practice board.
2. Rig two fixed practice anchors through knot interactions and cross a short safe yard course.
3. Teach the final knot to a proposed apprentice; mastery time is an optional cosmetic stamp, never required for story closure.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** Courier comments and a non-stat practice stamp acknowledge the lesson; no class ability or live rescue unlocked.

**Readiness:** Future zone and new interaction mechanics required; not built. Knot interaction/evaluator; anchors and short traversal control; recorded teach-back; checkpoint and optional timer. No rope physics needed if using authored fixed traversal states.

**Pattern:** [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml). Original knowledge-then-execution training adaptation.

### qp_forge_cycle — The Forge Between Eruptions

**Planned hub/pocket:** Deep Crucible.

**FUTURE — Future volcanic frontier: Cinder Reach (working name); character 38–42; mining 20.** advanced; Crafting and protective combat; leading verb **forge**; role **profession**. Target 14–20 minutes. 

**Owner:** Harn Voss (proposed rescue smith). Harn needs a winch to recover trapped workers and will abandon the ore contract to get them home.

**Prerequisites:** None; optional local work.

1. Read tremor/heat cues; open two cooling channels in the locally signalled safe order.
2. Forge the winch at a controlled station using common supplied metal; checkpoint the completed winch.
3. Protect its operation during two capped assaults; pull the workers to safety through a final explicit winch action.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** A rescued work camp opens ordinary repair/trade access; no permanent mining bonus or required main-chapter unlock.

**Readiness:** Future zone and new interaction mechanics required; not built. Thermal cycle and visual cues; channel sequence state; crafting provenance event; checkpointed winch interaction; waves and rescue actor outcomes; no severe real-time fail timer. Mining 20 is a planned profession requirement, not a claim Smithing exists.

**Pattern:** [WoW: Peacebloom vs. Ghouls](https://www.wowhead.com/guide/peacebloom-vs-ghouls-the-strategy-guide-450); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html); [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml). S25.

### qp_water_names — Water Has a Name Here

**Planned hub/pocket:** Sunseal Court.

**FUTURE — Future desert oasis: Sable Well (working name); character 48–50; no profession requirement.** advanced; Water audit and policy negotiation; leading verb **negotiate**; role **local**. Target 14–20 minutes. 

**Owner:** Ruma Ness (proposed cistern keeper). Ruma wants honest rationing that keeps households, traveling drovers and market gardens viable after a leak is fixed.

**Prerequisites:** None; optional local work.

1. Measure three cistern draw points; interview the household, drover and garden delegates.
2. Locate and actually isolate a hidden leaking pipe; recompute the remaining genuine shortage.
3. Choose and fund a transparent feasible policy: rationing, shared transport or a short new channel; demonstrate one agreed allocation.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** One saved local service-cost/stock variant and three comments reflect the policy; every policy preserves basic water access.

**Readiness:** Future zone and new interaction mechanics required; not built. Flow measurement and valve state; interview tracking; constraint/cost UI; repair validation; saved service variants. Existing shops require new conditional-price/stock support if that consequence is retained.

**Pattern:** [RuneScape: Murder Mystery](https://runescape.wiki/w/Murder_Mystery); [RuneScape: Hazeel Cult](https://runescape.wiki/w/Hazeel_Cult); [WoW: Welcome to the Machine](https://warcraft.wiki.gg/wiki/Welcome_to_the_Machine). S26, oasis separated from coast.

### qp_shade — Shade Is a Trade

**Planned hub/pocket:** Saltroad Caravanserai.

**FUTURE — Future Sable Well covered market; character 45–47; no profession requirement.** moderate; Capped favor chain and carrying challenge; leading verb **barter**; role **local**. Target 9–13 minutes. 

**Owner:** Sefi Marr (proposed awning stitcher). Sefi’s apprentice keeps working in the sun; she needs help coordinating supplies, not a hero to investigate a cult.

**Prerequisites:** None; optional local work.

1. Arrange a three-leg trade: cord to a potter, insulated jar to a dye seller, then dye to Sefi; each leg has one nearby recipient.
2. Carry a fresh dye batch along a short shaded route using a clearly displayed heat meter; replace it freely if it spoils.
3. Assist a real awning-fastening interaction, ending the chain at the apprentice’s stall.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** One awning state and apprentice work pose change; no additional hidden favors are appended.

**Readiness:** Future zone and new interaction mechanics required; not built. Three recipient-linked deliveries can use existing quests; fragile batch/heat meter, free replacement and fastening action need new mechanics; shared total reward across legs.

**Pattern:** [RuneScape: One Small Favour](https://runescape.wiki/w/One_Small_Favour); [LOTRO: spoiled-pie deliveries](https://lotro.fandom.com/wiki/No_Place_for_Spoiled_Pies_%28spoiler%29). Original capped interdependence/carrying-rule adaptation.

### qp_seamark — The Seamark at Low Water

**Planned hub/pocket:** Stormwatch Point.

**FUTURE — Future coast: Brinewatch (working name); character 30–35; no profession requirement.** advanced; Navigation and harbor work; leading verb **align**; role **exploration**. Target 12–18 minutes. 

**Owner:** Elva Keel (proposed harbor pilot). Elva wants a shallow-water approach safe for small fishing boats while the merchants fund only the deep channel.

**Prerequisites:** None; optional local work.

1. Read three high/low-water marks around a short harbor loop; use a local tide model rather than wait for a real clock.
2. Align two seamark vanes to a visible shoreline bearing and test the route with a model float.
3. Secure one real mooring line at the chosen landing; show the pilot the corrected approach.

**Budget:** XP and coins await this region’s level-50 budget; prior low-tier amounts are retired. **Aftermath:** Local seamarks and a small-boat landing scene persist; no new playable sailing system or time-of-day gate.

**Readiness:** Future zone and new interaction mechanics required; not built. New harbor; controllable tide-model puzzle; alignment and route evaluation; mooring interaction; saved prop/landing state. Existing fishing water cannot supply these interactions.

**Pattern:** [Lost Ark: The Book of Time](https://exputer.com/guides/tower-of-thanks-lost-ark/); [Conquer Online: Ape City quest table](https://co.99.com/guide/mission/ape_city.shtml); [LOTRO: Gathering Jam / A Formal Complaint](https://lotrolevelling.blogspot.com/2013/04/evendim-part-1-30-36.html). Original coast-specific landscape-and-work adaptation.

## Approved seven-dungeon scope

Build Blackpick Mine (8–10), Silkburrow Caverns (19–21), Yewbound Catacombs (26–28), Deep Crucible (38–40), Coldhearth Sanctuary (44–46), Graveshroud Hollow (48–49) and The Unwritten Court (49–50). Seven layouts are approved; eight is an absolute ceiling, not an instruction to add one. Rootlock’s flood/cooperative work and Quarryend’s wages/rescues remain outdoor chapters. The late Thornford cave is separate from the low-level exterior crypt.

The [mechanics curriculum](dungeon-mechanics.md) teaches telegraphs, threat and taunts, stuns/roots, interrupts, web rescues, sight breaks, add priorities, environmental hazards and coordination. Class-training coverage and encounter systems are future implementation tasks. Outdoor encounters at roughly 12–16, 30–35 and 41–43 rehearse these tools between dungeons without adding instances. Regional alternatives retain story and gear parity. The 60-hour model and existing 25 runtime quests remain unchanged.

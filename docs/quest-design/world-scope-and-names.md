# World scope and naming review

**World placement update, 1 November 2026:** The opening now connects to 34 authored onward hubs and 109 regional/return quest prototypes. The new map has 134 quests. Terrain routes, level districts, public return areas and seven sealed dungeon approaches are placed. Full private dungeons and measured 60-hour progression remain future work. See the [world review](../world-layout-review.md). Earlier future-content wording below refers to the fuller designs, not the absence of this first placement pass.

Reviewed 1 November 2026. This updates design labels and future content. Stable region/hub IDs remain intact. Existing current-map names and canonical saved quests are preserved.

## Do we have enough zones?

**For the planned first 1–50 campaign, yes: nine macro-regions and 35 hub bases provide enough geographic variety to author the target journey.** This is a design judgment, not a claim the planned world already contains 60 hours of play. The existing opening is the playable prototype. Finish connected hubs, regional routes and instances before increasing the region count.

The useful comparison is the work a place supports: distinct hubs, routes, dangers, services, quests and later returns. Counting a continent, a town district and an instance as the same kind of “zone” gives a misleading comparison. The planned river, fen, haunted wood, coast, upland, volcanic, snowy and desert regions already provide substantial changes of scenery and activity.

| Reference | What the official source establishes | Lesson for Shadowfell |
|---|---|---|
| RuneScape | Jagex presents the world through skills, quests, towns, dungeons and other points of interest. [Official game guide](https://www.runescape.com/game-info). | Build multiple reasons to return to a place. Its multi-skill structure is not a direct zone-count or character-level comparison with our 1–50 model. |
| LOTRO | The 2022 Before the Shadow announcement describes two regions, Swanfleet and Cardolan, with questing from levels 1–32 and higher-level instance content. [Official announcement](https://www.lotro.com/news/lotro-before-the-shadow-announcement-en?locale=en_US). | A region can contain many local chapters and later activities. This example does not mean two regions would automatically deliver our playtime target. |
| Conquer Online | The publisher’s atlas groups named cities with their plains, forest, canyons, desert, islands and special locations, including multi-floor Frozen Grotto entries. [Official atlas](https://co.99.com/guide/atlas/atlas.shtml). | Memorable settlement anchors and recognizable surrounding terrain can carry many encounters without dozens of unrelated macro-regions. |
| Lost Ark | The 2023 Elgacia announcement names a city, garden and mountain within one continent, and connects its story to the Kayangel group dungeon. [Official announcement](https://www.playlostark.com/en-us/news/articles/elgacia-arrives). | Give a regional chapter a distinct instanced payoff, with local identity and useful rewards. This is a structural example, not a current endgame-progression comparison. |

No exhaustive current-world counts are asserted. These official examples support structural comparisons; our judgment about nine regions depends on our own 35 hubs, route choices, content durations and production scope. Earlier estimates of 180–240 baseline quest completions still need measured durations. Naming places does not produce those quests.

## Region identities

| Display name | Biome and use | Decision | Reason |
|---|---|---|---|
| Thornford Reach | Temperate farms, hedges and a wooded road | Keep | Thorn and ford suggest hedged country and a river crossing; Reach names the district. |
| Rillbank Vale | River valley, mills and freight landings | Refine | Keep Rillbank as the town; Vale makes the wider geography distinct from its quays. |
| Mirefen | Wetland, peat, reeds and raised paths | Keep | The name already signals wet ground; the hubs show how people work around it. |
| Paleweald | Haunted woodland and sheltered archive settlements | Keep | Pale suggests the drained woodland palette; the woodland name fits roots, trees and old tracks. |
| Brinewatch Strand | Salt coast, cliffs, beaches and working harbors | Refine | Brine suggests the sea; Strand describes the wider shoreline while Brinewatch remains the port. |
| Highmere Downs | Rolling uplands, grazing, quarries and small high waters | Keep | Highmere and Downs suit inhabited upland country rather than a second volcanic frontier. |
| Cinder Reach | Ash country, lava-cut rock and industrial work camps | Keep | Cinder immediately suggests heat and ash. The human settlements add their own identities. |
| Frostward Marches | Snowbound borderlands, passes and sheltered settlements | Refine | Frost cues the climate; Marches suggests a frontier of watch posts and supply roads. |
| Sunscar Basin | Sun-baked desert, salt roads, dunes and oasis settlements | Rename region | Sunscar suggests heat and weathered ground. Sable Well becomes the oasis town, not the name of an entire desert. |

Rillbank and Brinewatch remain settlement names inside the Vale and Strand. Sable Well is an oasis settlement in Sunscar Basin. Players can therefore understand “travel to Sunscar Basin, then find Sable Well” without confusing a whole desert with one well.

## Selected local refinements

| Earlier design name | Display name | Reason |
|---|---|---|
| North Ferry | Willow Ferry | A river landmark is more memorable than a direction. |
| Scribes’ Rest | Scribes’ Hollow | Keeps the archive identity while giving the settlement woodland geography. |
| High Pass Relay | Heatherpass Relay | Heather ties this pass to the uplands rather than any generic high road. |
| Furnace Camp | Redkiln Camp | A distinctive working name for the hot inner frontier. |
| Lantern Pass | Rimepass | The cold pass gains an immediate climate cue and avoids confusion with Lantern Crossing. |
| Wellward | Sable Well | Retains the established oasis name as a settlement inside Sunscar Basin. |
| Caravan Rest | Duneshade Rest | A desert rest stop with an understandable reason to exist. |
| Glass Road Station | Glassroad Station | A compact proper name for the desert approach. |
| North Ledger Gate | Rimewatch Gate | The northern final approach gets a geographical name; the institution is described in its story. |

Most hub names already do useful work: Mossreed Landing, Stiltmarket, Quarryend, Ashworks, Frostgate and Saltroad Caravanserai suggest terrain or local life. Keep them. A name such as Scribes’ Hollow can signal the settlement’s purpose and geography without naming a biome literally. Naming should remain short enough for map labels and easy to distinguish from another place in the same region.

Use environmental reinforcement: wet timber and raised paths in Mirefen, cliff silhouettes and salt-stained masonry in Brinewatch, heather and drystone walls in Highmere, ash and hot workings in Cinder Reach, and protected water/shade in Sunscar. The name, palette, silhouette, ambient sound and resident work should agree. Exact scene/asset work remains a later build task.

## Instance production scope

The [dungeon plan](instanced-dungeons.md) adds **seven approved dungeon layouts (maximum eight)** as blueprints. They deepen existing places rather than requiring new macro-regions. Pilot The Siltwheel first, including real private-run isolation, return travel, checkpoint death and reward persistence. Then build Rootlock Sluice and one regional story payoff before committing to the whole roster.

This review does not implement multiplayer or private dungeon scenes. Current code constructs one overworld; those runtime systems remain required. All seven active designs have entry/level placement, local story, wider thread, encounter features and loot direction so the next implementation is concrete and reviewable.

The approved build has seven layouts, with an absolute maximum of eight. Seven former designs remain [unscheduled references](deferred-dungeons.md). Reuse the finale for level-50 play; no additional post-cap layout is scheduled.

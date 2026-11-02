# World layout and playable-hub review

Updated 1 November 2026. This is the authored regional prototype following the seven-dungeon design revision. [Placement records](quest-design/world-placement.json), [quest hubs](quest-design/quest-hubs.json), [dungeon plan](quest-design/instanced-dungeons.md).

## Scale and camera decision

Keep the existing **2,048 × 3,072 metre** island. About 4.81 km² is above sea level; the initial survey found 69.1% of that land walkable. At 5.6 m/s the full north–south extent is roughly nine minutes of uninterrupted running. Shrinking all terrain, props and settlements together would also compress doorways, combat spacing and existing authored content.

Keep the accepted fixed camera, approximately 39 metres across at its default zoom, with zero look-ahead, the existing player readability scale and short grass. Default fog remains 58–122 metres; haunted surfaces use the closer existing gloom treatment. Terrain chunks draw around a 112-metre radius. The new placements use compact settlements and nearby work sites rather than relying on seeing the horizon.

Primary onward road legs have a median of **282 metres** (about 50 seconds running) and a maximum of **594 metres** (about 106 seconds). Optional links between alternate regions are longer. These are geometric lower bounds, excluding combat, dialogue, detours and stops. Typical new work sites are around 40–80 metres from their hub. Do not call these figures measured quest durations.

The revised layout follows the saved terrain: Rillbank follows the middle river, Mirefen occupies the lower western wet ground, Brinewatch uses the southwest coast, Paleweald uses the existing eastern haunted area, Highmere occupies the northern uplands, Cinder uses the southern volcanic terrain, and snow/desert remain end-level alternatives. Existing Thornford subregions take priority over broad region rectangles.

## Installed content

- Nine named macro-regions and 35 hub bases, including the existing Thornford opening.
- 34 new hub clusters with named residents, local provisions, rest points and compact work areas. Larger settlements have enterable rest houses; smaller posts use a quartermaster and campfire. House materials and vegetation vary by biome.
- 109 new quest prototypes: 68 regional story jobs, 34 independent local stories and seven optional return patrols. Together with the 25 opening quests, the new map has **134 quests**. Legacy-map quests remain intact.
- 114 placed NPCs and 258 enemy spawns across the map. Normal regional opposition, separate higher-level return areas and public level-50 normal/elite patrols are explicitly placed. No outdoor enemy is raised above 50 for post-cap difficulty.
- Five additional fishable ponds, signed routes, roadside landmarks, region labels and individual hub brackets on the zoomed map.
- **Seven planned dungeon layouts, maximum eight.** Eight entrance markers represent seven layouts because the Court has two alternative approaches. All dungeon approaches are sealed; private instances are not implemented.

The regional quests use real NPCs, examinable notices, enemies, physical recoverable items, working dial puzzles and saved progress. Shared `requiresAny` milestones allow switching between paired regions without completing both. Quest checks now honour minimum levels. Data remains in the existing Godot editor files. The quest validator caches shared dependency checks; the editor recognises authored POIs as examine targets.

## What this review does not certify

This is a world and content foundation, not a finished 60-hour MMORPG. The new regional jobs deliberately reuse a small number of mechanics. Many work/record loops still need bespoke objectives, authored choices and distinct consequences before a full route will feel varied enough. The 28 earlier research seeds retain their own implementation status; a nearby simple prototype does not implement a seed's missing advanced mechanic.

XP and equipment are initial regional budgets, not a measured 45–80-hour balance pass. Full class training beyond the opening, party threat/taunts, mandatory utility coverage, actual dungeon instances, multiplayer authority and the final Court encounter still require implementation. The regional story reaches preparations for the Court and does not falsely mark its defeat complete.

Broad rectangular region boundaries and modular settlement buildings are suitable for this placement pass. Organic borders, distinctive landmark architecture, richer NPC routines, enemy ecology and encounter variety need further authored passes. Avoid treating every hub as another identical village.

The terrain surface pass is now installed: paint blends independently of triangles, road verges soften, terrain lighting uses smooth shared normals and steep detail uses triplanar mapping. Sculpt/undo and unchanged editor saves pass. Terrain shape and collision were preserved. See [terrain surface blending](terrain-surfaces.md).

Automated content, spawn, road, quest, puzzle, save and authoring round-trip checks pass. Representative regions were visually reviewed in Godot. Existing shutdown material/resource warnings remain. Human route pacing and sustained frame-rate testing are still outstanding.

## Hub coordinates

Coordinates are Godot world X, Z in metres, with north toward negative Z. Individual hub brackets determine the stay; macro-region spans describe geography.

| Hub | Region ID | Levels | X, Z |
|---|---|---|---|
| Thornford village | thornford | 1–5 | -450, -207 |
| Lantern Crossing | rillbank | 5–10 | -208, -176 |
| Mossreed Landing | mirefen | 5–10 | -540, -60 |
| Rillbank Quays | rillbank | 10–13 | -80, -240 |
| Millward | rillbank | 13–16 | -92, -380 |
| Reedward Cooperative | mirefen | 10–13 | -612, 128 |
| Pumpstead | mirefen | 13–16 | -512, 224 |
| Willow Ferry | rillbank | 16–19 | 20, -476 |
| Tollhouse Rise | rillbank | 19–22 | 100, -580 |
| Stiltmarket | mirefen | 16–19 | -380, 44 |
| Causeway Watch | mirefen | 19–22 | -292, 28 |
| Greyroot Refuge | paleweald | 22–25 | 412, -556 |
| Scribes’ Hollow | paleweald | 25–28 | 524, -396 |
| Brinewatch Docks | brinewatch | 22–25 | -692, 68 |
| Saltmere Outpost | brinewatch | 25–28 | -580, 296 |
| Highmere Market | highmere | 28–31 | 280, -820 |
| Quarryend | highmere | 31–35 | 48, -940 |
| Cinder Gate | cinder | 28–31 | -380, 248 |
| Ashworks | cinder | 31–35 | -128, 420 |
| Windscar Redoubt | highmere | 35–38 | -160, -1132 |
| Heatherpass Relay | highmere | 38–40 | 152, -1112 |
| Redkiln Camp | cinder | 35–38 | 104, 492 |
| Ember Relay | cinder | 38–40 | 220, 708 |
| Frostgate | frostward | 40–42 | -172, -1388 |
| Rimepass | frostward | 42–44 | 96, -1404 |
| Hearthwatch | frostward | 44–46 | 260, -1392 |
| Sable Well | sable | 40–42 | -112, 1140 |
| Duneshade Rest | sable | 42–44 | -292, 968 |
| Dune Watch | sable | 44–46 | 60, 908 |
| Whitebough Hospice | frostward | 45–47 | 620, -1208 |
| Last Beacon | frostward | 47–48 | 516, -1412 |
| Saltroad Caravanserai | sable | 45–47 | 228, 1052 |
| Glassroad Station | sable | 47–48 | 412, 1208 |
| Rimewatch Gate | frostward | 48–50 | 664, -1288 |
| Sunseal Court | sable | 48–50 | 692, 1348 |

## Higher-level returns

These occupy separate signed outer areas. Earlier towns and beginner enemies retain their original levels. Public patrol areas do not add private dungeon layouts.

| Area | Levels | X, Z | Scope |
|---|---|---|---|
| Sealhouse Cellars | 25–30 | [44.0, -188.0] | Public outdoor area; separate private designs remain unscheduled |
| Drowned Pumphouse | 25–30 | [-452.0, 344.0] | Public outdoor area; separate private designs remain unscheduled |
| Stormwatch Point | 30–35 | [-508.0, 412.0] | Public outdoor area; separate private designs remain unscheduled |
| Deep Crucible | 40–42 | [-20.0, 504.0] | Public outdoor area; separate private designs remain unscheduled |
| Sealed Bell Wing | 48–50 | [-305, -486] | Sealed private approach |
| Rook Audit House | 50–50 | [32.0, -328.0] | Public outdoor area; separate private designs remain unscheduled |
| Whitefall Vaults | 50–50 | [312.0, -1268.0] | Public outdoor area; separate private designs remain unscheduled |
| Sunken Cistern | 50–50 | [132.0, 1024.0] | Public outdoor area; separate private designs remain unscheduled |

## Seven dungeon locations

The recommended levels and mechanic lessons are in the [dungeon curriculum](quest-design/dungeon-mechanics.md). Coordinates locate the exterior approach, not a playable instance scene.

| Dungeon | Recommended | Approach coordinates |
|---|---|---|
| Blackpick Mine | 8–10 | lantern_crossing: -175, -204 |
| Silkburrow Caverns | 19–21 | tollhouse_rise: 133, -608 |
| Yewbound Catacombs | 26–28 | scribes_rest: 557, -424 |
| Deep Crucible | 38–40 | ember_relay: 253, 680 |
| Coldhearth Sanctuary | 44–46 | hearthwatch: 293, -1420 |
| Graveshroud Hollow | 48–49 | thornford: -305, -486 |
| The Unwritten Court | 49–50 | north_ledger_gate: 697, -1316; sunseal_court: 725, 1320 |

## Captured views

[World layout and level key](screens/world-layout-map.png). [Blended woodland path](screens/terrain-blend-path.png). The captures show the actual game, not the illustrated reference map.

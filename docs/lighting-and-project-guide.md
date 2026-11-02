# Lighting and finding your content

Open `C:\Dev\Shadowfell\Shadowfell\project.godot` and press **F5**. Use **Continue**, **Characters**, or **New character → Create and enter**. The project launches the new continent. F6 plays only the scene currently being edited, so use F5 for the full character entry flow.

The character roster is local. An older save without a world identifier arrives at Thornford when it first enters the new continent. An untouched copy is kept under its save key plus `.before_world_new` before migration. Its level, inventory and quest progress are retained; old camp, corpse and ground-drop coordinates are cleared because they belonged to the previous world. Subsequent saves include the world identifier and resume at the saved position. Development checks use separate save folders.

## Lighting

The current default camera is 50° downward, with the same distance and field of view. See [the visual review](visual-look-review.md) for the stronger lighting, comparisons and next art priorities.

- Forward+ is the default renderer, enabling actual volumetric fog, sunlight scattering and ambient occlusion. Godot's Compatibility renderer retains the cheaper atmosphere fallback, without volumetric fog.
- Warm windows, lanterns, braziers and inn interiors contrast with cooler outdoor shadow light. Haunted regions have denser, cooler haze. Sparse sun-shaft ribbons supplement the volumetric sunlight at selected tree groups.
- There are 25 authored lantern sources, including 21 new lamp-post placements, alongside the existing hearths and braziers and three new graveyard vigil fires. The game selects at most **16 nearby fixture lights**, with one additional small fill light following the player. At most two nearby outdoor fixtures cast local shadows; the sun supplies the main world shadows.
- Ground mist uses **eight local fog volumes**, a shared small noise texture, and one small foreground clearing volume to keep the player readable. Fog uses a modest base size of 64 and 48 depth slices; its screen dimensions depend on the viewport aspect ratio.
- Place a **lamp_post** or **torch** from the World dock's Prop library and save. It automatically supplies warm light the next time you play. Other sources remain editable in `data/terrain/new_map/scenery.json` under `lights`.
- Lighting tuning lives in `game/world/atmosphere.gd`; general sun, fill and camera settings are in `game/game.gd` and `game/core/db.gd`.

Forward+ support was verified on the project's GTX 1650. The native test captures use the actual game renderer, rather than a mock-up. See the Godot documentation for [volumetric fog and its renderer requirements](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html).

## Movement

WASD is screen-relative and works alongside optional click-to-move. Movement keys immediately override a clicked destination. Leave **Keyboard turning** off for ordinary WASD. See [movement controls](movement-controls.md) for the mouse schemes and controller behaviour.

## Folders and editing

| Content | Location |
| --- | --- |
| Quest definitions and dialogue | `data/quests/` |
| NPCs, enemies, shops and factions | `data/npcs/` |
| Items, rarities and loot tables | `data/items/` |
| Abilities, classes, builds and spell effects | `data/abilities/` |
| Professions, recipes, mining and crafting | `data/professions/` |
| Active continent terrain and placements | `data/terrain/new_map/` |
| Legacy world and world-map definitions | `data/world/` |
| Installed nature trees, grass, plants, rocks and textures | `assets/environment/nature/` |
| Game models: characters, items and environment props | `assets/models/` |
| Original FBX, OBJ and source textures | `assets/source_art/nature/` |

The **World** dock has a category selector for Trees, Grass, Plants, Rocks, Buildings and Props, plus text search. Open the world, choose **Prop**, select a category and place the model. The same tree category finds models from both the nature pack and the game's own model library. Placement, scatter, sculpting, paint, undo and save continue to use the existing authoring tools.

Use the **Game Data** workspace for items, NPCs, quests, abilities and shops. `data/catalogue.json` maps stable logical names to their folders. `assets/model_library.json` maps stable model IDs to their organised files, so item definitions and character saves retain their IDs. Keep those registries in sync when adding or moving files outside Godot.

Source-art archives and browser-build folders have `.gdignore` files. Their contents remain available on disk, while Godot avoids importing duplicate source assets and unrelated browser tooling. The existing asset licence accompanies the nature folder.

## Resource cleanup and checks

Item icons and static portraits now bake into ordinary textures and release their temporary models, cameras and viewports. Quest markers evaluate only quests belonging to the relevant resident; distant head markers, name labels and cursor targets are rejected before expensive updates. Renderer instances are detached during game teardown to avoid the earlier null-material shutdown errors. Terrain geometry and authored sculpt data were preserved.

The isolated CPU probe originally spent about 62 ms updating the HUD and, after the resident-quest filtering change, about 3.8 ms. Quest head markers themselves measured about 0.87 ms after that change. Native foreground/background timing varied with the Windows display setup: recent sampled runs were around 28–43 FPS, with the same window still taking about 33 ms per frame when its game simulation was disabled. The work therefore reduces measured game work without claiming a guaranteed 60 FPS across the continent. Performance logs include the renderer, light budget and frame timings.

Native checks are in `game/tests/`: `atmosphere_check.gd`, `organised_data_check.gd`, `editor_authoring_check.gd`, `campaign_world_check.gd`, `reach_village_check.gd`, `minimap_live_check.gd`, `terrain_blend_check.gd`, and `level_50_check.gd`. `existing_character_check.gd` tests a copy of a locally existing roster. `lighting_profile.gd` compares the same view with atmosphere and game updates enabled/disabled; `step_profile.gd` measures individual game updates. These are local reproducible checks, not a whole-continent performance guarantee.

The older browser prototype's JavaScript data validator still expects its previous content schema. It reports incompatibilities with newer Godot features and is not the acceptance check for the Godot game. Private dungeon instances and the full 45–80 hour campaign remain separate development work.

### Remaining editor diagnostic

Godot 4.7.2 still prints `Can't use get_node() with absolute paths from outside the active scene tree` during editor shutdown with the generated World editor scene open. The editor exits successfully. This does not appear in the tested game startup, character creation, character resume, combat, fishing, inn, minimap or quest flows. The normal empty-project editor and this project's recovery-mode editor do not reproduce it; either editor add-on alone with the generated World scene open does. Its exact remaining source has not been identified. Do not treat this as a fully error-free editor cleanup.

The saved editor layout's references to a disconnected second monitor were corrected. Temporary diagnostic traces have been removed, and both authoring add-ons remain enabled.

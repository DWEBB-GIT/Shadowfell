# Lighting and organisation validation — 1 November 2026

Tested in the local Godot 4.7.2 project. Native rendering used Vulkan Forward+ on the NVIDIA GeForce GTX 1650. Character tests use isolated save folders; the existing-character test reads the actual roster into a separate copy and never writes the original saves.

| Check | Result |
| --- | --- |
| New character through title buttons; new-world entry; save; Continue through title button; saved position | Passed |
| Existing copied character: level, possessions, finished quests, safe Thornford arrival and migration backup | Passed |
| Real volumetric fog, bounded fixture light pool and temporary portrait viewport release | Passed |
| Native inn cutaway hides added window panes | Passed |
| Native graveyard lighting capture after final light-energy balance | Passed |
| Campaign references, hub residents, dungeon approaches, quest route gates, gathering, puzzle and save | Passed |
| Opening combat, fishing and inn interactions | Passed |
| Live overhead minimap and scene resource release | Passed |
| Terrain control blending, shared seams, normals, paint and undo | Passed |
| Level-50 boundaries and older-cap save compatibility | Passed |
| Authoring: ability mechanics, asset catalogue, placements, terrain paint and save/no-op behaviour | Passed |
| Game Data items, NPCs, quests and canonical save/read round trips | Passed |
| Organised data directory: load, no-op save, changed quest saved to its own folder, no duplicate flat file | Passed |
| Native editor opens and closes | Exit succeeds; one unresolved shutdown scene-lookup diagnostic remains |

The path audit found **91 stable model IDs, 68 nature scenes, 28 content tables and 5,161 placed props**, with no missing model or glTF image/buffer companions. All **178 moved binary asset files** match their original hashes. The existing sculpt file and terrain blending shader match their pre-pass hashes; this pass did not change terrain geometry.

The isolated HUD CPU update dropped from roughly 62 ms before the quest-marker fix to about 2–4 ms in subsequent probes. One-shot item and portrait viewports are released after baking. Sixteen pooled fixture lights, one player fill light and eight local mist volumes bound the added local lighting work. Local frame-rate captures vary considerably with view, warm-up and Windows display scheduling; this is not a claim of consistent 60 FPS across the continent.

The separate legacy browser validator still reports schema differences for newer Godot content. See [the project guide](lighting-and-project-guide.md) for the remaining editor diagnostic and the folder/playing instructions.

Screenshots from the native lighting pass: [graveyard](screens/lighting-graveyard.png), [inn cutaway](screens/lighting-inn.png).

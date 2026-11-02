# Building Shadowfell in Godot

Open `project.godot`. Enable **Shadowfell Game Data** and **Shadowfell World tools** under Project Settings > Plugins if their screens are missing. The World dock sits beside the Scene tree; **Game Data** is a main screen beside 2D and 3D.

If a saved editor layout hides World behind other tabs, use **Editor > Editor Docks > World**. You can move that tab beside the Scene tree. Reload the project once after updating plugin code so all rebuilt controls appear.

## Sculpt and place the world

1. In **World**, choose the map and click **Open the world (sculpt and place)**. Choose the new map to work on your painted map. This also selects the map used by the game.
2. Under **Brush**, choose Raise, Lower, Smooth, Flatten, Walkable, Blocked or Paint ground. Left-drag to paint; Shift reverses Raise/Lower or Walkable/Blocked; `[` and `]` change size. Ctrl+Z undoes a stroke.
3. Under **Place**, choose NPC, Enemy, Item, Chest, Prop, Shrine or Signpost. Search by name. The prop library scans `assets/models`, `assets/scenery` and the installed `glTF` nature pack, including subfolders. **Refresh asset library** finds new files. **Choose a project scene** selects any other `.glb`, `.gltf` or `.tscn` in this project.
4. For trees/plants/grass, choose **Prop**. Set minimum/maximum scale, optional random rotation, props per click and scatter radius. One click places a batch as one undo step. Batches use walkable ground; fewer objects may be placed around blocked ground or water. Set props per click to 1 for individual placement. Grid 0 places freely; another grid value snaps X/Z to that spacing.
5. Set a circular collision radius for solid props such as trunks and rocks, or leave 0 for walk-through grass. A radius is in source-model metres and scales with the object. Existing compound collision is preserved. Nonuniform scaling uses the larger horizontal scale for circular collision; tilted props still use upright footprints.
6. Press **Place: click the ground**, then click. Esc stops placing. Set Brush to Off and release Place to select objects normally. Select their named nodes under Props/NPCs/Enemies in the Scene tree if a model is difficult to pick in 3D; F frames the selection. Move, rotate or scale using Godot's gizmos. Ctrl+D duplicates, Delete removes, Ctrl+Z undoes.
7. The Inspector's **Shadowfell placement** panel edits an NPC/enemy definition, a spawn ID, or a prop's scene, height, colour tint and collision. Metadata > record retains advanced fields. Existing IDs should stay stable because saves and quests may use them.
8. Ctrl+S saves the world scene and its data. F5 runs the game using the saved placements.

The editor draws ground around the start and placed objects, and adds ground under the cursor as you sculpt or place. It does not build the entire large map up front. Objects retain their height offsets when their ground is sculpted. Props support all three rotation axes and nonuniform scale.

Act 1 writes `data/world/world.json` and `data/world/scenery.json`. The new map writes `data/terrain/new_map/spawns.json` and `data/terrain/new_map/scenery.json`; it never copies the old town onto the new map. Each map's terrain edits stay in its own `sculpt.json` and `world.bin`. Paint ground overrides the new map image at painted samples, in the editor and game. Save before changing maps.

These additions target the Godot game. The older browser prototype does not support project-scene model paths, full prop transforms or the new map's placement files.

## NPCs, quests, skills and abilities

**Game Data** retains the existing NPC, Dialogue, Quests, Quest chains, Skills, Items, Loot and Chests screens. The active map's placements are used when creating or placing NPCs and chests. Save Game Data, then reopen the World scene to see placements added there. Returning to Game Data reloads it automatically when it has no unsaved changes. Both editors report a save conflict instead of silently replacing placements changed in the other screen; save or copy your pending values, then reopen/revert to load the current data.

For an ability, pick its **Kind** first. This is the runtime operation: instant strike, damage over time, cast, cleave, burst, trap, charge, guard, shield, and so on. A trap and Divine Storm deliberately have different required values because they run different operations.

**Numbers** has a searchable **Add option** library. All implemented number options are offered, with defaults, explanations and supported kinds. Existing numbers remain editable and optional ones can be removed. An option used by another kind is labelled and produces a note; adding a trap-only number to a burst does not turn the burst into a trap. Custom system numbers remain available, with a reminder that they need an implementation.

Examples:

- An Ambush-style finisher: instant, Weapon damage, `damageMultiplier`, `perPoint`, optional `bothHands`, then set **Spends all** to combo. Per-point scaling needs a spent resource; bothHands adds the off hand only while dual wielding.
- A Divine Storm-style spell: burst, `radius`, `damageMultiplier`, `windup`, `stagger`, `knockback`; add `healPerHit` to heal per enemy hit, or `spins` for repeat blows.
- A Tar Trap-style spell: trap, `armTime`, `triggerRadius`, `lifetime`, `maxTraps`, `radius`, `duration`, `slow`. Slow 0.5 means 50% slower. Traps are placed at your feet and create a slow zone when triggered.
- A slowing curse that becomes a stun: control, enable **Applies an aura**, set its slow/duration, then enable **Then apply another aura** and set the second aura's stun/duration.

**Additional mechanics** exposes execute thresholds, bonuses against a status/aura, landed-hit critical-chance stacks, and shield/dual-wield/main-hand-only variants with their own number and resource-gain overrides. The existing follow-up, Shadow replacement, spread, cost/gain, classes and trainer controls remain. Follow-up is a DoT or aura on a landed hit, not an arbitrary second cast. Other fields preserves upgrade trees and other advanced JSON.

These controls cover the existing spell engine. Brand-new operations such as summons, chain lightning or terrain deformation require runtime code before a form can make them work. Existing special actions without a Kind (auto attack, cooking, fishing) use their own systems; duplicating one with a new ID does not create another implementation.

## Nature assets and visual identity

The installed Quaternius Stylized Nature MegaKit has a CC0 1.0 notice in the project's `License_Standard.txt`. CC0 permits copying, modification and commercial distribution; the models do not need modification merely because they were free: https://creativecommons.org/publicdomain/zero/1.0/

Place source pack models directly or make reusable Godot `.tscn` variants under `assets/scenery`. For an individual prop, use the placement tint and transform. For a reusable look, make a scene with the imported model as a child and edit material overrides, scale and composition in that scene, then choose it in World. This preserves the original assets while giving Shadowfell its own palette and silhouettes. Other icon/sound packs have their own licences; the nature pack's notice does not cover them.

## Verification

Run `game/tests/editor_authoring_check.gd` headlessly for placement save/reload, map overlays, transforms, asset material isolation, ability controls and validation. `new_map_check.gd` covers the active map and sculpted terrain; `check_scripts.gd` compiles the game and both plugins. Tests write temporary fixtures under `user://`, not authored project data.

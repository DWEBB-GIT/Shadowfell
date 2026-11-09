# Core loop review — 9 November 2026

The starter loop now has working links from combat to loot and quest progress, from gathering to crafting and usable rewards, and from profession use to rank progression. This pass found and fixed missing world connections rather than changing the recent combat controls or rewriting quests.

Baseline reviewed: `af1b0a4` and the preceding melee/intro updates. Concurrent local arrival-cinematic work was preserved.

## Changes made

| Area | Finding and resulting behavior |
| --- | --- |
| Daggers | A blanket weapon override made almost every attack a stab. Normal attacks in either hand now use the same slash as a one-handed sword. Slash abilities recover their distinct sword swing/combo clips. Explicit jab, thrust and upward-stab abilities retain the authored dagger stab. |
| Gathering | The current terrain inherited legacy herb coordinates, including inaccessible ground. It now reads its own `nodeGroups` from map placements: novice ditchbell near Willow Pond, ditchbell/woundwort near Morrow, and bloodroot along the Hollow verge. All 16 spots have dry ground and an open approach position. |
| Mining | Iren taught Mining, but this map had no ore groups. Six copper outcrops near his forge and four tin outcrops near the Hollow now support gathering and smelting. All ten have dry ground and an open approach position. Only five veins are live at once; normal regrowth and streaming remain in use. |
| Alchemy | Morrow taught Alchemy without a usable bench on the map. A marked, interactable bench now stands beside his outdoor service area. Gathering ditchbell, brewing a draught and consuming it successfully restores health. The visual uses the existing simple crate model. |
| Profession ranks | Rank lessons still referenced old-continent trainers and quests. Current-map rank lessons now use the mapped teachers, keep skill/coin costs, and omit inaccessible old-map quest gates. The original continent retains its original gates. |
| Interaction UI | The bottom Interact prompt looked clickable but could pass the click into world movement. Clicking it now performs the nearby interaction, consumes the click, and clears an existing click-to-move destination. The keyboard binding remains available. |

Normal dagger auto-attacks slash; examples of abilities that retain stabs are Quick Strike, Poisoned Blade, Assassinate, Death Venom and Silencing Blade, through their existing jab/thrust/upstab animation data. Double Cut and Crippling Cut use slash variants. Damage, attack cadence, reach, facing/root rules and movement were not retuned.

## What was played and checked

A fresh, isolated rogue was played through the actual native UI: approach Abel, talk, read the milestone, return and hand in, accept the boar task, fight using dual daggers, collect the physical meat drop, hand in and accept The Road In. Kill and loot objectives updated separately; the meat stayed in the bags after handing in. Quest marks, direction/distance guidance, combat telegraph, loot label, target frame, rewards and follow-up conversation were observed. Click-to-move was enabled only in this test profile.

The longer route into Thornford and the inn was exercised by the existing walking/combat/interaction playthrough. Profession tests use isolated fixtures and reposition the character between service areas; they verify mechanics and approaches, not the subjective pacing of an uninterrupted full-map walk.

| Check | Result |
| --- | --- |
| Current-map core loop | **119 checks, 0 failures**: dagger slash/stab choices on both bodies, resource placement and approaches, actual herb yields/regrowth, potion brewing/use, copper mining/smelting, Willow Pond fishing, quest fish, rank-ups, minimap resource markers and saved possessions. |
| All class kits | **1553 checks, 0 failures**. |
| Introduction quest routes | **1486 checks, 0 failures**. |
| Physical opening playthrough | **270 checks, 0 failures**. |
| Character/bow/logout regression | **151 checks, 0 failures**, updated to respect the latest local attack/cast-facing behavior. |
| Melee reach and chase/loot | Both suites passed. |
| Camera/movement and Tab targeting | Both passed. |
| Existing character | Passed using a copied save; possessions and completed quests retained. |
| Original-continent professions | All passed. The old Blackpool/Briony test now explicitly selects its original map. |
| Rendered minimap | Passed on native OpenGL Compatibility: coordinates, zoom, markers, rendered objects, caching and cleanup. The stale dynamic-prop test was updated to capture the same tile explicitly; production minimap rendering was unchanged. |
| Physical prompt click | Passed with Windows mouse input: nearby conversation opened, the click was consumed and no movement destination remained. |

Forward+ captures of both bodies' dagger slashes/stabs, Morrow's bench and Iren's forge were inspected. The core profession loop also passed in a rendered run. Captures and logs are in the mirror workspace's `core-loop-review` folder. These are direct Godot tests/captures; no sealed game-dev CLI run bundle was produced because that CLI is unavailable locally.

## Assessment and next priorities

The opening has a clear, readable kill → loot → objective → hand-in → next-task sequence. The missing profession connections were blockers to using that same structure outside combat; those starter connections now work. The exercised scenarios have no remaining blocking failure.

Before expanding the world or adding multiplayer/trading, the next useful passes are:

1. **Browser frame pacing and first load.** Profile the same opening/town/combat/gathering route on the real web build, including a cold cache and slower connection. Native Compatibility checks do not measure browser FPS, network behavior or first-download memory. The split browser-pack loader was reviewed in code, not exercised under a throttled browser connection.
2. **First-time profession discovery.** Have a player unfamiliar with the map find the trainers, required tools, resources and stations without hints from the developer. The mechanics now work; whether those opportunities are discovered naturally still needs observation.
3. **Longer-term resource progression.** This fixes the starter copper/tin and early herbalism circuits. Audit later recipes, higher-level material routes and profession rank content before promising a complete high-level economy.
4. **Combat feel under sustained input.** Revisit ability/auto-attack overlap, movement rooting and feedback in a short repeated combat route before treating that tuning as ready for PvP. The latest local facing and reach choices were deliberately preserved.

The milestone's “ALE NOT INCLUDED” line is an intentional in-world joke, not an authoring note; its wording was preserved.

## Preservation and reproduction

No quest definitions, dialogue, targeting implementation, renderer settings, browser-pack pipeline or texture-import settings were replaced. World edits add only resource groups and one station; existing placements remain intact. Live-file checks preceded replacements. Real character data was only read and copied for the existing-save test; playtests used isolated stores. No commit, push or deployment was performed.

From the game project, run `godot --headless --path . --script res://game/tests/core_loop_check.gd` for the new loop regression. Run the same script without `--headless`, followed by `-- <capture-directory>`, for rendered dagger/profession evidence. `game/tests/core_loop_session.gd` starts a separate, isolated manual playtest character.

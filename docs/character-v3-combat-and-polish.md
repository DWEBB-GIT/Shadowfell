# Character v3: combat and presentation

Implemented in the local Shadowfell Godot project on 2026-11-09. Builds on the v1/v2 character integration.

## Behavior

- New settings profiles start with **Lower camera angle off**. Explicit saved camera preferences are respected.
- Selecting or attacking a target no longer automatically rotates the character. Movement, turning controls and deliberate mouse aiming control facing. Hostile attacks require the forward cone; turning away interrupts a hostile cast. After player feedback, WASD turning uses the previous 14 rad/s rate again: a full reversal takes approximately 0.23 seconds, instead of the abrupt 0.13-second setting.
- Melee animation selection follows each hand independently: daggers use authored stab clips, swords swing, two-handed weapons use the heavy clip. Left-hand dagger actions do not replace the right-hand sword action. Finger grips are deterministic, including clips without finger keys.
- After player feedback, walking/running uses the original authored gait and its previous speed-matched cadence again. The stride-shortening, foot-lift and pelvis-bounce modifications were removed. An undrawn bow follows the run's arm swing rather than pinning the bow arm to a fixed aiming position. Gameplay movement speed is unchanged.
- Jump take-off now lasts 0.22 seconds, and landing runs through its final pose over 0.36 seconds. Landing is allowed while moving, instead of being skipped whenever movement input is held. Movement controls and jump physics remain active throughout.
- The hunting bow now uses a packed, locally authored curved model with a leather grip, two animated string segments and a nocked arrow. Static limbs are batched into three material surfaces; the bow has six mesh instances, with no duplicated construction when copied for previews. Hands fit the handle and string; projectiles originate at the arrow tip.
- Bow specials cancel a pending auto-shot and restart the ranged weapon cadence. Instant specials have a 0.12-second visible release windup; the next auto-shot waits for weapon readiness. Retargeting cannot clear that readiness. Starting to move cancels an auto draw even on its release frame. Cast-time shots still use their cast time.
- The sheathe key cycles ranger characters through **bow → melee → all stowed**. Other characters carrying both types cycle **melee → bow → all stowed**. Missing weapon categories are skipped. Character creation/selection previews use the same class preference.
- Head/hair meshes retain their fitted geometry when zooming. This is cached and limited to head features; armour, body and world LOD remain enabled. Source model imports are unchanged by this fix.
- Loading screens show rotating gameplay tips.
- Logout and Exit Game are blocked while alive and in combat. The countdown also cancels if combat starts. Defeated characters can leave; their defeated state and grave possessions persist on re-entry. Released spirits retain their corpse/recovery state.
- Logout stows weapons and sits living characters on the ground for the existing ten-second countdown. Moving or cancelling restores the previous stance. A fallen body stays fallen. The death screen has a Logout button and permits opening the main menu.

## Preservation of local work

Changes were applied to reviewed files with live-file checks before replacement. Recent local quest, Tab targeting, friendly healing, periodic-effect/cover fixes and performance work were retained. No quest files or targeting implementation were edited by this pass. No world, renderer, project settings or texture-import settings were replaced. Actual player saves were only read and copied for compatibility checks; test play and saves used isolated storage.

The existing-character regression now compares item identities/counts, coins and ammo independently of bag-slot placement. This accepts the intentional materials-pouch migration while still detecting lost possessions.

## Verification

- `character_v3_check.gd`: **151 checks, 0 failures**, including ranged cadence, same-frame cancellation, cast-facing interruption, both bodies, independent off-hand stab direction, finger stability, bow endpoints, grounded feet, stance cycling, combat logout guards, actual defeated logout/re-entry, grave retention and ghost recovery.
- `locomotion_check.gd`: **28 checks, 0 failures**, verifying both bodies' run arms/legs against the original authored poses with melee/bow equipped, complete stationary and moving jump landings, and WASD reversal timing at 30/60/120 FPS. Visual evidence for this follow-up is in the mirror workspace's `run-restore` folder.
- `class_kits_check.gd`: **1553 checks, 0 failures** across all six classes and both bodies.
- `intro_journey_check.gd`: **1419 checks, 0 failures**.
- The latest `opening_playthrough_check.gd`: **74 checks, 0 failures**.
- Existing Tab-targeting checks: **PASS**. Friendly healing/thorns checks: **all passed**. Existing-character compatibility: **0 failures** using an isolated copy.
- Native 1280×720 captures inspected in Forward+ and OpenGL Compatibility: bow idle/draw/release, three weapon stances, mixed sword/dagger, run phases, close/far zoom with short/long hair, loading tips and logout sitting. No new script/mesh-construction errors remain. The engine still emits its existing null-material warmup/cleanup warnings.

Evidence is in the mirror workspace's `character-v3` folder. `character_v3_shots.gd` reproduces the captures; `build_bow_asset.gd` rebuilds the packed bow after geometry edits.

## Limits

Native Compatibility verification is not a browser FPS measurement. Browser performance still needs a separate measured profiling pass. This pass preserves existing performance changes and keeps the detailed-geometry exception confined to the player's head; it does not globally increase world detail. Visual inspection covers the listed bodies/styles and sample poses, rather than every possible equipment/animation combination.

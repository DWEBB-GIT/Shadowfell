# Character integration v2: grips, jump, running and framing

Updated 2026-11-09 in the live Mythkeep project. This revision follows the user's v1 feedback and supplied Conquer Online, Diablo and RuneScape visual references.

## Changes

- Weapon grips are derived from the wrist, middle/index/pinky knuckle landmarks on each body. The handle lies in the palm and the shaft points towards the thumb side. Off-hand weapons use their own mirrored palm frame. The club and greatsword handle centres are accounted for separately. Fingers curl around held grips.
- Shields attach to the left forearm rather than inheriting a wrist placement offset. Torches and fishing rods use the palm frame. Bow wind-ups orient the bow and solve the hands to the draw pose. Two-handed support solves the secondary palm and its orientation to the hilt.
- Jumping selects take-off, airborne and landing clips. Seek-driven stages use an explicit zero-duration transition so the previous idle pose cannot remain as a frozen blend. Vertical source translation is constrained along the actual transformed skeleton axis; gameplay physics still controls jump height. The previous random whole-player somersault is disabled for this rig. Teleport/revive resets the new jump state.
- Full-speed jogging plays at approximately 1.56x, with cadence reduced for slower movement. Footstep cadence follows the accelerated cycle. World movement remains 6.4 m/s; collision and jump gravity/velocity are unchanged.
- The default lower camera changes from 45 to 30 degrees down. Perspective FOV changes from 35 to 39 degrees, and the default distance is a little closer. Hero visual scale changes from 1.2 to 1.3. The alternative steeper camera is 42 degrees. Both remain fixed north-up and retain their pitch while zooming. World coordinates, scenery placement and travel distances are unchanged.
- The equipment-panel preview now uses the fitted rig, so it keeps the held-hand pose while idling. A weak owner reference removes a Player/Rig retention cycle.

## Measured checks

At 1280x720, comparing the old default configuration with the selected new default at the same player position:

| Measurement | Before | After |
| --- | ---: | ---: |
| Projected standing reference height | 50.68 px | 72.79 px |
| Ground-plane width through the player | 40.41 m | 37.32 m |
| Forward ground-plane reach at y=60 px | 19.53 m | 39.33 m |

This is about 44% more character height, retaining 92% of lateral ground coverage and reaching roughly twice as far forward on the local ground plane. Terrain, buildings, fog and occlusion affect the actual visible scenery; these figures describe projection geometry at the tested position.

| Regression | Result |
| --- | --- |
| `forge_v2_check.gd` | 60 checks, zero failures: accelerated gait, actual foot motion during jump, landing/recovery, primary/off-hand handle contact within 1.5 cm in sampled poses on both bodies, equipment-panel rig, camera metrics and preview-owner disposal |
| `forge_equipment_check.gd` | 300 checks, zero failures over 29 distinct equipped slot/model paths on both bodies |
| `class_kits_check.gd` | 1,553 checks, zero failures; all 72 class abilities through normal casting on both bodies, plus class mechanics |
| `jump_check.gd` | Zero failures, including WASD/click movement, buffered jumps, landing, grounded shadow, fixed camera and movement speed |
| `camera_movement_check.gd` | Zero failures for screen-relative movement, analogue input and aim |

All save-writing tests use isolated folders. The source kit and real character saves were not modified. Existing unrelated work and world edits are retained.

## Native visual evidence and limits

The delivery capture uses Godot 4.7.2 native Vulkan Forward+ on GTX 1650 with dummy audio. Forty-two captures include a camera comparison, sword/dagger/club/greatsword/dual-wield/shield/bow idle and impact views, and actual physics-driven take-off/air/landing frames on both bodies. Selected views were inspected directly.

Evidence is retained at:
`C:/Users/danja/.codex/.chatgpt-projects/g-p-6ae07996066481919e70f0a7eda6a6ef/character-v2/`.

Delivery images are in `captures-delivery/`; logs are `native-delivery.log`, `v2-delivery.log`, `jump-delivery.log`, `equipment.log`, `camera-movement.log` and `class-kits.log`. Original file snapshots are under `before/`.

The sampled geometric contact and visual checks do not establish perfect finger contact, clipping-free extreme poses, cloth collision or individually authored animation for every item. Armour still shares the supplied fitted outfit as documented in the v1 report. Thumb placement, some two-handed wrist poses and long-cloak/sheath combinations remain candidates for further art refinement. Existing material/resource warning families remain in the logs; no final-run GDScript error is counted as a pass.

The Game Development Studio CLI remains unavailable, so these are direct Godot tests/native captures, not sealed studio capture bundles. No commit, push, upload or publication was performed.

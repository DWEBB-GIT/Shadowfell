# The West Road — first-arrival cinematic

Implemented in the live Mythkeep Godot project, 9 November 2026.

## Player experience

A new character's first entry has a roughly 12-second in-engine arrival. The camera establishes Abel's cart and the roadside, swoops toward the actual equipped player model, pauses for a portrait, then blends into the player's existing isometric camera. The cinematic uses the real terrain, NPCs, enemies, lighting, weather and avatar; it is not a video or a second display character.

Chapter typography, a light vignette, responsive 2.35:1 letterboxing, the existing music with a fade envelope, and a gradual HUD reveal support the transition. The camera reuses the existing shadowless player fill light for its portrait and restores that light at handoff. It creates no extra 3D lights, raises no rendering distance and enables no new expensive blur or postprocessing features.

Skip with **Esc**, **Space**, **Enter**, the on-screen button, or gamepad **B / Start**. Skipping uses a brief fade rather than a rapid camera flight. Skip input is consumed so it does not also jump, attack or open the game menu. Movement and combat resume only after the handoff. Local characters and animals continue their idle poses, and wind/water/ambience stay alive, while combat and respawn simulation are held.

In **Settings → Controls → Arrival**:

- **Cinematic arrival for new characters** enables the full opening by default.
- **Reduced opening motion** replaces the rail flight with a short, stationary fade.

Returning characters use their normal quick entry, including older saves without a cinematic marker. Completing or skipping the sequence records `mk_arrival_seen` through the existing world flags and attempts the normal autosave. No quest is accepted/completed, no character is moved and no resources are granted by the cinematic.

To watch the automatic sequence, press **F5**, create a fresh character and enter the world. Existing characters keep their saved location and skip the full opening.

## Edit it in Godot

Open **`res://game/cinematics/arrival_intro.tscn`**.

| Node / property | Purpose |
| --- | --- |
| `FlightPath` / `Curve3D` | The editable camera rail in metres relative to the player's starting position. |
| `FlightPath/Dolly` | A non-looping `PathFollow3D`. Its progress ratio is animated. |
| `FlightPath/Dolly/Camera3D` | The actual cinematic camera, with animated field of view. |
| `CartFocus` | Initial attention point. `track_authored_cart` binds to nearby `ni_cart` plus the editable `cart_aim_offset`; disable tracking to use the marker directly. |
| `HeroFocus` | Player portrait target. |
| `AnimationPlayer` / `arrival` | Rail travel, lens, target blend, chapter/caption fades, black veil, letterbox removal, final camera blend and HUD reveal. |
| Root exports | Chapter title, location, caption, and timeline-driven presentation values. |

The rail and timeline can be edited/scrubbed in the normal Godot editor. Move the rail and focus markers to change framing; camera orientation is targeted by the director. The tool script updates camera aim in the editor; the runtime director advances the animation manually so the camera and presentation share one clock. The scene does not regenerate itself on startup, so editor changes are retained. The build helper used to create the initial scene is kept outside the game project. Use F5 for an in-world review; the standalone camera prefab does not contain a second copy of the world.

Camera framing was authored for the current West Road/cart start. Moving the starting hub, surrounding geometry, rail or timing calls for another visual pass. The director raises the camera above sampled terrain, but this is an authored shot rather than a general obstacle-avoidance camera. Keep its rail clear of buildings and trees.

## Integration and preservation

`Game.load_world()` begins the director after normal model/sound warm-up. `Game.step()` routes only cinematic time/input while the director is active. `LoadingScreen.arrival_hold` keeps the world-entry lifecycle pending after its black veil becomes transparent, then releases it at completion; this also keeps existing callers waiting for world readiness correctly.

The gameplay camera's transform/FOV, HUD opacity and player fill-light position are restored exactly. Existing zoom and lower-camera preferences remain intact. The new lobby, split web-pack handoff, current combat targeting/reach changes, character rig and equipment work were preserved. The camera scene has no new external assets and references the existing soundtrack only after the world audio system is available, so it does not add that music to the initial web boot dependency chain.

## Verification

- `arrival_cinematic_check.gd`: 58 checks for first entry, actual Camera3D ownership, curve/timeline, terrain clearance, player framing, NPC presence, music bus, HUD timing, exact camera restoration, locked gameplay, no quest changes, saved/read-back marker, skip controls, editable focus, reduced motion and post-handoff movement. Native Forward+ and Compatibility visual passes each passed the 54 checks before the final four editor/preservation checks were added.
- `arrival_boot_check.gd`: 10 checks through the project's real lobby entry and selected-character handoff, plus a returning save with no new cinematic marker.
- Opening movement/quest trial, quest follow-ups, copied existing-character saves, script loading and content validation pass against the combined project.
- Native Forward+ captures reviewed the establishing shot, swoop, portrait, pullback and final gameplay view. A Compatibility/smaller-window pass checks the presentation's fallback path.

Automated runs use Dummy audio. They exercise the existing soundtrack/bus/fade routing; they do not constitute an audible mixing review. Existing null-material and resource/shutdown warnings are still recorded in the underlying game's test logs; no clean-engine-shutdown claim is made here. Browser performance still needs browser profiling—the compatibility renderer alone does not establish it.

Technical reference: Godot's official [Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html), [AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html) and [PathFollow3D](https://docs.godotengine.org/en/stable/classes/class_pathfollow3d.html) documentation.

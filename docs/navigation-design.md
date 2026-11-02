# Shadowfell navigation and world direction

Updated 31 October 2026. See [the current Reach progression guide](reach-progression.md) for the implemented build, tuning and verification.

The direction is an elevated, fixed-angle MMORPG/ARPG view: a stylized world with clearer lighting, soft shadows, atmospheric distance and paths composed for the camera. The player requested no look-ahead control. The earlier pan and orbit proposals are superseded.

The main camera now holds one angle throughout mouse-wheel zoom. Its default framing shows approximately 39 metres across a 16:9 screen at player height. It keeps north up, preserves the current movement/aiming directions and retains building cutaways and a modest indoor zoom. The player and attached gear have a 1.2 visual scale for readability; physics and combat distances are unchanged.

The corner minimap renders the actual world overhead. The new terrain's M screen surveys saved terrain and draws real roads, authored places, the player and tracked quest goals. The illustration remains a regional art reference at `data/terrain/new_map/map.jpg`.

The 2,048 × 3,072 metre continent remains the framework for future regions. The first authored district is Thornford Reach, a 365 × 395 metre area in its western green region. Characters, combat distances and existing props keep their scale. Routes, wooded slopes and physical obstacles bring navigation choices into the local camera view.

The playable route runs from Thornford through the Fallen Lantern, Old Watch and Dawnstone to Mourning Hollow, Nameless Yard and Bell Crypt. Briarwood provides an optional western loop through a scout camp and Wolf Hollow. Holt Orchard supplies an eastern return loop. Two safe fishing ponds, an enterable inn and town hall, local class trainers and independent resident stories make the district useful between battles. Signs, lamps, trees, rocks and buildings identify these spaces; quest goals use actual coordinates.

The earlier [district SVG](navigation-district.svg) is a historical connectivity sketch. The current terrain survey in the game is the authoritative map of the built district.

Expand one connected district at a time after testing travel time, combat readability, quest progression and return routes. Later regions can adapt the illustration's farms, rivers, haunted woods, snow and volcanic country at the same local composition scale.

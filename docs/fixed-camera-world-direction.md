# Shadowfell: camera and outdoor-world direction

Recommendation: build around a **fixed isometric gameplay camera**, and evaluate a locked diagonal orientation before rebuilding the wider continent. Keep the accepted 50° downward pitch during that evaluation. The next production pass should be a compact outdoor pilot in Thornford Reach. Building art remains deferred to the planned modular kit with interchangeable materials.

## What the asset inspection found

The installed `License_Standard.txt` identifies the current nature collection as **Stylized Nature MegaKit Standard, 68 of 116 models**. Those 68 scenes were organised into `assets/environment/nature/` during the folder cleanup. The package is present even though its original product name is no longer the directory name.

Useful existing cover includes:

- `Grass_Common_Short`, `Grass_Common_Tall`, `Grass_Wispy_Short`, `Grass_Wispy_Tall`.
- `Clover_1`, `Clover_2`, `Fern_1`.
- Common bushes, flowering bushes, grouped/single flowers and mushrooms.
- Bark diffuse/normal textures, rock textures and leaf/plant colour atlases.

The streamed grass currently comes from the small procedural mesh in `game/render/meadow_grass.gd`. Its placement makes 1,200 random candidates per 64 m terrain chunk before exclusions. It is therefore not yet making full use of the kit's cover varieties or a deliberate patch layout.

`Grass.png` is a foliage colour atlas, not a seamless painted grass/soil terrain layer. The inspected grass models use that atlas; `CommonTree_1` already references a bark normal map. More useful foliage is available locally, but the presence of these files does not establish that a complete terrain material set is installed.

The publisher distinguishes Standard, Pro and Source editions. The Source edition adds engine projects and custom stylised shaders; those additions should not be assumed present in this Standard copy. There is enough existing cover for the first outdoor dressing pass. [Publisher's pack page](https://quaternius.com/packs/stylizednaturemegakit.html).

## Camera choice

| Direction | Benefit | Work it requires |
| --- | --- | --- |
| Current fixed north-up view | Stable navigation and existing input/cutaways | Compose and reshape individual routes for this view |
| Fixed diagonal orientation, approximately 35–45° around the world | Cardinal roads and building edges appear diagonally; a strong classic isometric composition in the opening | Camera-relative directional input, cutaway checks, and route-by-route composition |
| Player-controlled rotation | Players can inspect another side and choose a clearer view | Camera-relative movement/aim controls, all-angle building and canopy visibility, and scenery that holds up from every side |

The native preview compares 0°, 35° and 45° horizontal orientations at the same 50° pitch. The diagonal view improves the opening village's composition. It is a **visual preview**, not a finished rotatable-camera implementation: camera-relative keyboard/controller movement is now implemented and checked at six orientations; building cutaways and route composition still need the orientation-specific play-test before adopting that view. See [movement controls](movement-controls.md).

The current production camera remains unchanged by this study. The corner minimap remains north-up in the previews.

Route composition is local. A survey of 102 authored roads, about 19.18 km of geometric segments, found approximately 48.8% of their length close to world axes. At the current view, about 18.5% of the total route length projects close to vertical; at a 45° orientation that rises to about 26.7%, because some onward diagonal roads then face into depth. The four opening `tf_` routes behave differently: their near-vertical share falls from about 33% to zero. These are orientation measurements, not travel-time or player-behaviour measurements. Rotating the camera once will not compose every region automatically.

## Geography does the main work

Painted paths on a broadly walkable plain do not create the same experience as a playable lane bounded by a bank, wooded slope, river or cliff. Camera rotation changes the view; the shape, navigable footprint and encounter spacing still need to be authored.

Use connected outdoor spaces with a rhythm:

**Settlement edge → wooded lane → combat clearing → bend or crossing → landmark → optional side loop.**

Working dimensions for the first pilot, to be tested at the actual camera:

| Space | Starting dimensions | Purpose |
| --- | --- | --- |
| Painted walking path | Approximately 3–5 m wide | Legible travel line |
| Overall travel corridor | Approximately 8–14 m of navigable space | Passing room, gathering at edges, purposeful terrain boundaries |
| Ordinary combat clearing | Approximately 25–40 m across | Room for a group and visible telegraphs; roughly one camera-width |
| Larger elite clearing | Approximately 35–50 m across | Retreat and utility space without a broad empty plain |
| Crossing or ramp | Approximately 4–7 m wide | A clear transition with readable entry and exit |
| Fishing pocket | Accessible bank and a clear return path | A quiet destination on an optional local loop |

These dimensions are design hypotheses, not final balance specifications. Preserve collision scale, skill ranges, group movement and existing story locations while testing them.

Prefer diagonal approaches, curves along terrain and changes of direction at landmarks. Short north/south routes remain useful. Avoid imposing the same diagonal grid on every biome. Preserve wider farms, settlement spaces and occasional vistas so outdoor questing has variety and exploration routes.

Blizzard's environment team describes composing foreground assets and detail specifically for its fixed camera to preserve readable player space. That supports camera-aware authorship; it does not require copying Diablo's geography or narrowing the whole world into a single route. [Diablo IV environment-art discussion](https://news.blizzard.com/en-us/article/23788294/diablo-iv-quarterly-updatemarch-2022).

## Recommended pilot

Use Thornford's approach to the Fallen Lantern and Old Watch, with the Briarwood/scout connection as an optional loop. Keep NPCs, quest targets, levelling gates and the fishing-bank destinations connected.

1. Play-test the locked diagonal camera candidate with correct directional controls and cutaways. Choose the view before sculpting the wider world around it.
2. Shape a short stretch into three or four connected spaces. Use real changes of height, rock edges, wooded banks and collision where an edge is meant to constrain travel.
3. Build ground-cover patches from the existing short grasses, clover and ferns. Keep the path centre and combat telegraphs clear. Add taller cover to banks and sheltered margins, with biome-specific variation.
4. Add distinct route landmarks and side destinations. Verify that players can read each exit before reaching the edge of the screen.
5. Walk the route, fight in its clearings, travel both ways, test clicks and controller movement, and inspect it with quest markers and the live minimap. Only then extend the pattern into other regions.

The modular building set is a later pass. Reserve useful footprints, door approaches and heights now; later modules can share grids, connection points and swappable wall, roof and timber materials.

## Native previews

- [Current village orientation](screens/direction-village-current.png)
- [Locked 45° village preview](screens/direction-village-diagonal.png)
- [Current Lantern Road orientation](screens/direction-road-current.png)
- [Locked 45° Lantern Road preview](screens/direction-road-diagonal.png)

The preview uses an isolated character/save directory and temporary camera transforms. It makes no terrain, quest-placement or production-camera changes. The comparison script is retained in the task's diagnostic workspace, outside the game's authoring content.

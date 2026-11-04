# Terrain surface blending

Implemented 1 November 2026. The game and Godot World editor now share a terrain material that blends paint continuously across the surface. The existing retro colour palette, low-poly silhouettes, terrain shape and walkability remain in use.

## What changed

- Paint and road coverage are sampled in world space, with soft transitions across grass, earth, snow and rock. Mesh triangles no longer determine the paint boundaries.
- Terrain lighting uses shared smooth normals across chunk edges. Existing meshes and collision heights are retained.
- Detail uses three projections on steep terrain, reducing stretched texture stripes on cliffs.
- Small world-space variation breaks up road verges without making road centres noisy or changing the walking corridor.
- Painting and undo refresh neighbouring control textures when a brush touches the area they sample. Shared borders use matching padded data.

Use the existing World dock sculpt and paint brushes. Save and undo work as before. No terrain rebake or re-placement of props is required for this material change.

## Implementation and tuning

`game/render/terrain_surface.gdshader` owns the continuous colour blend, road verge and triplanar detail. `game/world/land.gd` creates 2-metre control samples with a 4-metre border around each ground chunk. The shader's default blend radius is 1.4 metres. The control image is a material field, separate from the existing 4-metre collision grid and local 2-metre detail meshes.

Height and grid sampling caches are local to a chunk build, so new strokes and undo do not reuse stale terrain values. This reduced the initial implementation's indicative headless chunk-build average from 23.4 to 16.6 ms over the existing 96-chunk check. These figures are CPU construction samples, not in-game frame rates or a controlled graphics benchmark. The earlier vertex-colour material built faster; the new material adds surface sampling without increasing the whole continent's polygon count.

The coarse heightfield still determines mountain silhouettes. This pass fixes surface blending and lighting; it does not turn blocked cliff faces into walkable terrain or replace every biome with finished texture artwork.

## Verification

- Terrain blend check: matching colour/road samples across the full shared chunk border, matching lighting normals, unchanged vertex heights, brush-neighbour refresh, live painting and exact colour restoration after undo.
- New-map editor check: sculpt save/readback, geometry generation and no writes when opening/saving untouched placements.
- Campaign integration: content references, new NPC/enemy/pickup placement, road centres, all seven dungeon approaches, alternate-region gates, real gathering, a local puzzle and saved progress.
- Opening-village regression: original opening, real combat, fishing, buildings and local quests continue to pass.
- Native OpenGL captures: river, marsh, haunted woodland, snow, desert, woodland path and rock terrain reviewed. Shader compilation succeeds on the installed GTX 1650.
- Baked world and saved sculpt layer are byte-for-byte unchanged by this visual pass.

Godot still emits material/resource-cleanup warnings during test shutdown. Functional checks pass; those warnings are not a claim that resource cleanup is complete. Sustained gameplay frame-rate measurements and full 45/60/80-hour route playthroughs remain outstanding.

See [the world review](world-layout-review.md) for the placed hubs, level brackets, return areas, quest prototypes and seven-dungeon scope.

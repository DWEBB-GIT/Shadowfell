# Lantern Coast terrain survey

Press **F5**, select a character, choose **Lantern Coast** and enter to play with enemies, quests and your character's controls. Young boars graze in Oatwick Lower Pasture, just south of the spawn. Zoom in on the world map to find the named hunting grounds and their level ranges.

Open `lantern_coast.tscn` and press **F6** for the separate terrain preview. It has a survey character and its own movement.

- **WASD or arrows** move in screen directions. **Space** jumps. **R** returns to the closest settlement.
- Use **Survey a region** to inspect any of the 15 hubs. Walk or jump to check their edges and crossings.
- **E** boards at Tidemark, Saltglass, and Starfall. At Starfall, **F** takes the ferry back to Tidemark.

## Edit the scene

Select the root and change **Editor Preview** to draw a region in the editor. **Editor Focus Offset** moves the preview centre in metres relative to that hub. The generated terrain is a viewport preview. Instances under **WorldProps** are saved in the scene and are a place for authored props.

The bridge template is `crossing.tscn`. It has adjustable length, width, and stone or timber variants. The deck top is at its local origin and local +Z runs along the bridge. It has collision on the deck and both rails. The terrain bake aligns the four crossings and their short approaches with the default movement directions. The crossing scene and the terrain collision use the same endpoints.

`layout.json` is the terrain source. Edit hub elevations and flat radii, road control polylines, coastlines, waterways, pond positions, and ridge profiles there. Run `python bake_terrain.py` in this folder with NumPy and Pillow installed. Reopen the scene after the bake. The bake replaces the region resources, textures, manifest, and generated crossings, so put hand-placed bridge variants under **WorldProps**. Terrain heights and road masks are sampled on a shared grid so adjacent chunks agree. The surface shader blends rock from the world-space slope and projects rock detail across all three axes.

Terrain cells are 64 metres across and are assigned to 11 region resources. The game and the terrain preview both stream nearby cells from locally available resources.

Walking uses a 45-degree maximum slope from the terrain mesh. Change `MAX_WALK_SLOPE_DEGREES` in `coast_surface.gd` to tune it. Terrain paint and road textures do not determine walkability.

After changing terrain heights, banks, bridges, piers, or the slope limit, rebuild the Coast's outlet data from the project directory. This calculates safe entry into inland water and which steep drops lead to walkable ground.

```text
godot --headless --path . --script res://game/tests/sample_coast_traversal.gd -- coast-samples.bin
python game/world/lantern_coast/bake_exits.py game/world/lantern_coast/atlas.tres coast-samples.bin game/world/lantern_coast/escape_routes.tres
```

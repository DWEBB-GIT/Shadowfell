# Editing Lantern Coast

1. Open Godot’s **World** dock and choose **Open Lantern Coast**. The editable scene is `game/world/lantern_coast/placements.tscn`.
2. Choose a region. Hover over the 3D view and press **F** to frame it. Use **Select region** to select its centre again later.
3. Choose **Prop**, **NPC**, or **Enemy** and search by name. Hold **Drag to place**, move the preview over the terrain, then release to place it. For repeated placements, choose **Place with preview**, click to place each copy, and press **Esc** when finished. **Q** and **E** rotate the preview. The yaw, scale, and grid controls give you precise placement. You can also drag a prop from Godot’s **FileSystem** dock.
4. Select a placement in the viewport or under **Props**, **NPCs**, or **Enemies** in the Scene tree. Use the transform gizmos or Inspector to move it. Use **Ctrl+D** to duplicate, **Delete selected** to remove it, and **Ctrl+Z** to undo. The **Lamp post** shortcut opens the placement preview with a working lamp selected. Move and rotate it like any other prop.
5. Press **Ctrl+S**. Press **F5**, select your character, and choose **Lantern Coast** to see the saved changes in game.

## Painting and erasing paths

In the **Brush** menu, choose **Paint dirt path**, **Paint cobbles**, or **Erase paths**. Set the radius and drag along the ground. Reduce **Strength** to blend the texture into the ground. Each pass builds up the colour or fades the road further. At full strength the eraser clears paths to reveal the biome underneath. Each drag can be undone with **Ctrl+Z**. Press **Esc** to return to object selection and **Ctrl+S** to save the paint with your placements.

## Editing existing scenery

Select **Edit existing scenery**, then click a generated tree, rock, plant, or landmark on the map. It becomes a placement you can move or remove. Deleting it also keeps the original instance hidden. Use **Ctrl+Z** to undo making it editable and restore the original. Ordinary placements can be selected directly.

Terrain height, water, bridge routes, and the dense ground-cover layer are part of the Coast’s generation data. Individual trees, rocks, shrubs, and landmark fixtures sit above those layers.

## Building with the kit

Find the modules and assembled buildings in `assets/models/environment/buildings/mythkeep_kit`. The inn, round watchtower, chapel, hut, tents, palisades, stone gate, and wall sections are ready to place. The **Finish** picker and the placement Inspector give compatible props finishes such as Ochre or Winter Slate. Use **Place with preview** to apply a finish while placing.

To make your own building, open `counting_house.tscn` as a starting point and save a copy. Replace or extend its roof, walls, windows, and trim with the matching kit modules. Keep the building root at ground level and set this new scene as a prop with **Choose a project scene**. For a custom finish, save unique material overrides on your own scene. Add a **Prop collider** for a custom building that needs a simple blocking footprint. The supplied buildings are exteriors.

# Shadowfell visual review

Keep the new **50° downward camera angle** and stronger, wider fixture lighting. The view shows more tree trunks, building fronts and depth between objects while keeping the fixed, north-up combat composition. The 45° comparison brought more foreground canopy and roof into the playing area; 50° is the better starting point for the current world layout.

## Changes installed

| Setting | Previous | Current |
| --- | --- | --- |
| Default downward camera pitch | 54.94° | 50° |
| Camera distance and FOV | 36.038 m before zoom; 35° FOV | Preserved |
| Cursor look-ahead | None | None |
| Outdoor fixture energy | Previous lighting-pass values | 4× those values |
| Outdoor fixture reach | Typically 7–9 m | 1.7× authored radius, bounded to 9–16 m |
| Outdoor distance attenuation | 1.0 | 0.75, with a softer useful pool |
| Fixture volumetric contribution | 0.35 | 1.4 |
| Window and hearth energy | Previous values | 1.6×, with a smaller reach increase |
| Active fixture pool | 16 | 16 |
| Local fixture shadows | None | At most two eligible fixtures within 16 m |

The previous reach excluded some trees completely: the tree next to the left graveyard torch is about 9.5 m away, beyond that torch's former 7.5 m radius. Increasing reach as well as energy now brings the trunk and nearby props into its lit area. Distance falloff then preserves useful illumination across that area. These are separate controls in [Godot's OmniLight3D documentation](https://docs.godotengine.org/en/stable/classes/class_omnilight3d.html).

The lamps illuminate existing bark, stone, foliage and building materials. Their increased [volumetric contribution](https://docs.godotengine.org/en/stable/classes/class_light3d.html#class-light3d-property-light-volumetric-fog-energy) adds coloured scattering in the real fog. The materials retain their dry, stylised surfaces rather than acquiring a wet gloss.

Local fixture shadows use the cheaper dual-paraboloid mode. Lamp posts, bowls and glowing geometry use render layer 20, excluded from these local shadow maps, so a flame cannot be enclosed by its own opaque model. The sun can still cast the solid fixtures' shadows; emissive flame meshes do not cast shadows. Default gameplay and minimap cameras continue to render the fixtures.

## What is working

- Warm pools against cool haunted shadows now provide useful landmarks. Lit tree trunks, grave markers and patches of mist connect the fixtures to the world around them.
- Village windows and the inn interior give settlements a different mood from the haunted areas. The cutaway still removes the added window panes with their walls.
- The revised angle improves character proportions in the view. A 2.4 m character-height reference projects from about 45 to 50 pixels at the default outdoor view: roughly 12% taller, without a model-scale or zoom change.
- The fixed compass orientation and live overhead minimap continue to support navigation.

## The next visual priorities

1. **Ground cover needs authored patches.** Grass is still spread rather evenly across broad ground. Build patches around roots, fence feet, rocks and pond banks, with worn gaps along paths and doorways. Add low-contrast soil variation and leaf litter in forest edges.
2. **Buildings need more material and doorstep detail.** Large roofs and walls still read as plain colour blocks. Painted shingle variation, timber edges, worn thresholds, hanging inn signs and small profession-specific props would give the villages more identity.
3. **Foreground canopy needs a visibility pass.** Some imported trees can still obscure an approach. Apply selective canopy fading where it blocks the player or a combat encounter, while preserving the trunk and the rest of the woodland. This should use the existing fixed camera composition without adding a character outline or cursor look-ahead.
4. **Ponds and puzzle props need dressing.** Shore reeds, shallow-water transitions, a little bank clutter and more detailed water motion would help the fishing spots. The functional puzzle devices also need an asset pass to feel like local machinery.
5. **Strengthen the character's material hierarchy.** Olive clothing can merge with grass and dark soil. Gear values, silhouette and controlled highlights will help the player remain the focal point. Ordinary ground-cover colours should stay subdued; the saturated red shrubs can serve as deliberate regional accents.

The lighting is now a useful foundation. Ground-cover composition, building materials and foreground visibility are the largest remaining gains for the retro MMO direction.

## Verification

Native Forward+ comparisons reviewed the graveyard, village, pond, forest and inn. Final checks repeated the graveyard and inn after correcting fixture self-shadowing.

- Matched graveyard ground samples increased from about **0.123 to 0.249 display luminance**, approximately **2×**. The camera was held at the original angle for this lighting-only comparison.
- Disabling only fixture fog scattering changed the rendered mist while leaving surface light enabled, confirming a real volumetric contribution.
- The default pitch remains 50° at minimum, normal and maximum zoom, with zero look-ahead. The independent overhead minimap projection is preserved.
- Local shadows remain within their two-light budget; one fixture qualified in the tested graveyard position. The inn window cutaway still passes.
- Sampled main-view GPU medians were approximately **4–5 ms** in these two paused comparison views on the GTX 1650. This is a local rendering check, not an end-to-end frame-rate promise or a full-world benchmark.

Test: `game/tests/look_review_release.gd`. Screenshots: [before](screens/look-graveyard-before.png), [after](screens/look-graveyard-after.png), [inn](screens/look-inn-after.png).

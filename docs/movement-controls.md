# Movement and camera direction

WASD is supported alongside click-to-move. A diagonal isometric camera does not require movement keys to follow the world's grid.

With the normal movement controls:

| Input | Behaviour |
| --- | --- |
| W / Up arrow | Move toward the top of the screen |
| S / Down arrow | Move toward the bottom of the screen |
| A / Left arrow | Move toward the left of the screen |
| D / Right arrow | Move toward the right of the screen |
| Two movement keys | Move diagonally, with the same world running speed |
| Left stick | Move in its on-screen direction, retaining analogue speed |
| Right stick | Aim in its on-screen direction; neutral aim retains character facing |
| Click-to-move | Travel to a world destination using the selected mouse scheme |
| WASD while a click route is active | Cancel that route and take manual control immediately |

Mouse targeting, interactions and ability bindings retain their existing behaviour. Click-to-move destinations and mouse targets are already world positions and are not rotated a second time. A click during manual movement cannot leave a destination queued to resume after the movement keys are released.

In **Settings → Controls and camera**, leave **Keyboard turning** off for normal screen-relative WASD. That separate optional mode deliberately makes A/D turn the character and W/S walk along the character's facing. **Click to move** can be enabled alongside WASD or disabled according to preference. It uses right click with Classic controls, or left click with Mouse aim controls.

The camera's horizontal orientation affects the conversion into world movement. Camera pitch and zoom do not change running speed. This supports the current north-up view and the proposed fixed diagonal view; it does not enable a new camera orbit control or choose a new production camera orientation.

Implementation: `GameInput.camera_direction` converts directional intent once at the game input boundary. Keyboard/stick movement, ghost movement and stick aiming share it. Existing click routes, mouse aiming and the optional character-relative keyboard-turning mode keep their own coordinate meanings.

`game/tests/camera_movement_check.gd` passes actual input and movement checks at 0°, 35°, 45°, 90°, 180° and 270° camera orientations. It verifies projected screen directions, travel speed, diagonal normalisation, analogue speed, stick aim, ghost movement, optional keyboard turning, real right-click destinations, same-frame manual takeover and text-entry focus. The existing `controls_check.gd` also passes. All test characters and settings use isolated save folders.


## Jumping

Press **Space** to jump, or rebind Jump in Settings. On a controller, press the left stick. Jump from a standstill or while moving with WASD, arrow keys, the left stick or click-to-move. A jump keeps the clicked destination active; WASD still takes over if you press a movement key. The player can steer normally in the air, without gaining running speed.

The leap is roughly 1.15 metres high and lasts 0.68 seconds on level ground. Gravity controls world height while airborne, and landing uses the terrain beneath the current position. The camera follows the ground beneath the player rather than the jump, keeping the leap visible. The contact shadow also stays on the ground, and mouse ground targeting keeps the same height reference during a leap.

Each press makes one jump; holding the key does not automatically bounce and pressing it early in the air does not double-jump. A short 0.12-second buffer accepts a press just before landing. Jumping stands a seated player up. Death and teleporting clear the airborne state. Normal obstacles and terrain boundaries still apply; this does not add vaulting or platform collision to the world.

`game/tests/jump_check.gd` checks actual Space input, both click-to-move mouse schemes, WASD, running speed, camera and shadow grounding, mouse targeting, jump animation, landing, jump buffering, key rebinding, sitting, text-field focus, death and teleport reset. It also checks jump height and landing at 10, 30, 60 and 120 simulation frames per second. Test saves are isolated from real characters.

Jump verification: native rendered jump checks and camera-relative movement checks passed. The existing control suite passes with a fixed 60 fps simulation (--fixed-fps 60). Existing resource cleanup warnings still appear on test shutdown; the same warnings were reproduced with the pre-jump source. All real character saves were left untouched.


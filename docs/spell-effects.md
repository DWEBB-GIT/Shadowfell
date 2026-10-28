# Spell effects and cast animations

Every spell gets its own cast pose and its own effect, so a player can tell
what was cast from the picture alone. This is the plan for all of them; the
built ones live in `data/spell_fx.json`.

## How it works

- **Cast poses** are data: `poses` in `data/spell_fx.json` gives, for each body
  part (Torso, Head, Arm_L, Arm_R, Leg_L, Leg_R), its turn at the top of the
  windup and when the blow lands. The rigged player plays each pose as a
  Blender clip of the same name, baked by `assets/blender/import_models.py`;
  built models turn their parts in `game/entities/rig.gd`. Both use the same
  timing, Diablo style: snap straight into the windup (no slow pull back after
  a key press), a fast whip to the blow, a held follow-through, then rest.
- **Weight without stagger or shake**: a landed melee blow holds both bodies
  still for a moment (hit-stop: longer for slower weapons and on crits,
  `CONFIG.impact.hitStop*`), the enemy pops white, and auto attacks draw a
  faint slash across the target.
- **Effect shapes** are built in Blender by `assets/blender/build_fx.py`
  (abstract shapes only: arcs, rings, cracks, tears, streaks, columns, a ward)
  and exported to `assets/models/fx/*.glb`. They carry no colour, only
  brightness, and are drawn additively, so one shape serves every school.
- **Looks** are data: `data/spell_fx.json` says, per spell, which pose to play
  and which shapes and particles to show when it goes and where it lands.
  A spell with no entry keeps its kind's generic pose and effect.
- **Readable from the fixed isometric camera**: flat shapes lie on the ground;
  upright shapes (slashes, tears) turn to face the camera, because side on
  they are a line. Each effect is short (under half a second) apart from
  auras and wards that last as long as the spell.

Shapes: `fx_arc` (swing crescent), `fx_wave` (shockwave wall), `fx_crack`
(ground cracks), `fx_claws` (three tears), `fx_streak` (charge trail, also the
ribbon behind an arrow), `fx_aura` (rising flame column), `fx_ward` (faceted
shield plate), `fx_bolt` (spell bolt head with a wisp tail), `fx_dome` (shield
bubble), `fx_runes` (ground circle of runes), `fx_hammer` (hammer of light),
`fx_spiral` (spinning storm), `fx_vines` (grasping roots), `fx_sigil` (curse
sigil), `fx_chains` (a chain of light), `fx_burst` (starburst: hits, puffs,
flares), `fx_halo` (ring of beads: halos, sleep motes, stun stars),
`fx_pillar` (column of light).

When the parts play: `windup` while a cast is drawn out (Blight Bolt, Long
Shot, Siphon Life), `cast` as the spell goes, `projectile` carried by its
bolt or arrow, `impact` where it lands (the target, a ground spell's spot, a
sprung trap). A cast-time spell can hold one pose through the cast
(`windupAnim`) and play another as it goes (`anim`). Poses can `hop`, `sink`
into a kneel, or `spin` the body round (Divine Storm).

Built in batch 2: Rogue, Ranger, Occultist and Paladin, as planned below
(Sorcerer and Priest have no spells yet). Shapes that seemed too much like
props or creatures stayed abstract: the curse is a sigil, not a skull; the
grave flowers are roots only.

## Warrior (built, batch 1)

| Spell | Cast animation | Effect |
|---|---|---|
| Heavy Strike | `diagonal`: blade high on the right, cut down across to the left | a warm slash crescent across the target, sparks |
| Crushing Blow | `overhead`: both hands high, a small hop, down hard | a vertical chop crescent, glowing ground cracks, a low shockwave, dust, camera kick |
| Cleave | `sweep`: blade held out, the body turns right then sweeps left | a wide flat crescent at waist height the size of the cone, a fainter orange echo, dust |
| Lunge | `thrust`: lean into the charge, blade driven forward on arrival | a speed streak behind you during the charge; on arrival a punch ring, sparks, dust |
| Battle Cry | `roar`: crouch, then chest out, arms flung wide, head back | a column of red-orange flame around you, a ground shockwave and a chest-high ring, camera kick |
| Brace | `guard`: low and wide behind the shield, held for the window | a pale blue faceted ward in front of you while the guard holds, a small ring as it goes up |
| Shield Break | `shieldSlam`: shield raised high, slammed into the ground | a shockwave wall the size of the radius, ground cracks in front, ring, camera kick |
| Rend | `rip`: low backhand ripping up and out to the right | three red tears across the target, red sparks |

## Rogue

| Spell | Cast animation | Effect |
|---|---|---|
| Strike | quick jab, off hand follows | small pale slash crescent, sparks |
| Ambush | step out of Shadow, both blades down from above | dark purple burst of smoke at the target, two crossed slashes, stun stars |
| Double Cut | both blades cut outward in an X | two crossed slash crescents; brighter with more combo points |
| Poisoned Blade | low upward stab, a flick of the wrist | green slash, green droplets that drip from the target |
| Sleep | a blown dust from the open palm | a drifting violet puff to the target, a slow spinning ring of motes over its head while it sleeps |
| Shadow | a crouch, cloak drawn round | smoke puff at the feet; you fade to a dark outline |
| Guile | a light step back, blades crossed | two pale after-images that peel off you each time a blow misses |

## Ranger

| Spell | Cast animation | Effect |
|---|---|---|
| Quick Shot | fast draw from the hip | thin pale trail behind the arrow, small hit puff |
| Venom Arrow | draw with a twist of the arrowhead | green trail, green splash, drip on the target |
| Flaming Arrow | the arrowhead held to a spark, then loosed | burning arrow with an ember trail, small burst of flame that keeps flickering |
| Tar Trap | kneel and press the trap into the ground | a dull ring and a stake at the feet; when sprung a black splash and a dark pool |
| Triple Shot | three quick nocks, a fanned draw | three arrows with trails, three hit puffs |
| Long Shot | a long held draw, leaning back | a glow gathering at the arrowhead while drawing; a bright long trail and a mark ring on the target |
| Disengage | a crouch and a back-flip | dust at the take-off, a short streak along the jump |

## Occultist

| Spell | Cast animation | Effect |
|---|---|---|
| Blight Bolt | both hands cupped at the chest, then thrust out | green-black bolt head with a wisp tail, a rot splash |
| Rot | a clawed hand closing toward the target | skull sigil over the target, black motes falling from it |
| Grave Bloom | a hand pressed down to the earth | a ring of grave flowers and grasping roots on the ground, green fog |
| Hex of Withering | a finger traces a sigil in the air | a sigil drawn in front of you, then the same sigil stamped on the target, sagging chains |
| Purge | arms pulled in, then thrown wide | dark motes rush in from the target, a sickly green flare on you |
| Siphon Life | one arm out, held, fingers pulling | a beam from target to you (exists), red motes travelling along it |

## Paladin

| Spell | Cast animation | Effect |
|---|---|---|
| Holy Strike | a slow heavy overhead | golden chop crescent, a short pillar of light on the target |
| Light's Hammer | an arm raised, then brought down like a gavel | a hammer of light falls from the sky onto the target, a gold shockwave |
| Divine Storm | a full spin with the blade out | a spinning gold ring around you, rising motes |
| Hallowed Ground | the blade planted in the ground, kneel | a rune circle on the ground that glows for the duration |
| Bring to Kneel | an open hand pushed downward | gold chains pulling the target down, then a stun ring |
| Light Shield | the shield lifted to the sky | a faceted gold dome around you while it holds, cracking as it absorbs |
| Smite | a pointed finger | a bolt of light from above onto the target |
| Rebuke | the shield thrust forward | a gold shockwave cone in front, a broken-glyph flash on the target |
| Hallowed Bolt | both hands raised, light gathering | a gold bolt head with a halo, a burst on hit |

## Shared

| Spell | Cast animation | Effect |
|---|---|---|
| Attack, Auto Shot | existing swing and draw | existing sparks |
| Set Camp, Return to Camp, Return Home | kneel and work; a held, still pose | existing dust; a soft column of light when the step-back goes |
| Fishing, Cooking | existing | existing |

## Checking a look

`godot --path . --script res://game/tests/spell_fx_shots.gd -- out_dir heavyStrike,cleave`
(use `xvfb-run` on a server) saves four pictures of each spell mid-cast.

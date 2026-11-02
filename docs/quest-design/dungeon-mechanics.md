# Dungeon mechanics and class usefulness

Updated 1 November 2026. Design and acceptance requirements, not implemented features. **Seven approved layouts; absolute maximum eight.** [Roster](instanced-dungeons.md). An outdoor cave, rehearsal encounter or dungeon entrance marker does not create another private layout.

## Teach, practise, combine, revisit

Introduce a mechanic safely, practise it with light pressure, assess it alongside one familiar demand, then revisit it in later encounters. Explain actions in short NPC lines and readable encounter feedback. Never introduce a lethal rule only after it has already killed someone.

| Stage | New lesson | Useful jobs | Later reinforcement |
|---|---|---|---|
| Blackpick Mine, 8–10 | Telegraph shapes, facing, threat and taunting | Hold and face the foreman, protect a miner, stop a runner, disable supplies | Facing and defender relief recur in the forge and temple |
| Silkburrow Caverns, 19–21 | Stuns, roots, interrupts, sight breaks and web rescues | Control a runner, stop a cast, cut down an ally, group ranged spiders | Crypt bindings and later witness rescues reuse the language |
| Yewbound Catacombs, 26–28 | Cast priority and bounded add waves | Interrupt a grave-heal, hold a custodian, root a runner, rescue a witness | Later bosses combine priorities without endless waves |
| Deep Crucible, 38–40 | Moving hazards and relieving a threatened defender | Move safely, taunt or cool the furnace, control carriers, free workers | Shelter movement in Coldhearth and safe lanes in the finale |
| Coldhearth Sanctuary, 44–46 | Soft pressure and changing jobs | Face a knight, stop an oath-cast, work a brazier, stop a seal carrier | Pressure has room counters, not only a damage threshold |
| Graveshroud Hollow, 48–49 | Linked objectives and coordination | Suppress seals, hold adds, interrupt, rescue and cover an ally | The finale rotates familiar jobs |
| The Unwritten Court, 49–50 | Apply the lessons | Recognise signals and fill the job currently needed | Same-layout level-50 replay supports mastery |

Outdoor rehearsals at approximately 12–16, 30–35 and 41–43 keep these skills in use during long dungeon gaps. They use ordinary hubs and encounters, not additional instanced dungeons. A player who skips regional dungeons must learn the same essentials outdoors before the solo-capable finale. These rehearsal quests remain to implement.

## Telegraphs through the isometric camera

- Use consistent circles, cones, lines and safe lanes with an outline or pattern, a cast name and visible progress. Colour and audio reinforce the cue; neither is its only signal.
- Keep cues visible above grass, webs, terrain and spell effects. Cave ceilings and foreground walls must fade or cut away before they hide a player, target or exit.
- Initial practice attacks target 2.5–3 seconds of warning. Later normal attacks generally start with at least 1.5 seconds. These are tuning targets: test the actual move speed, character radius, attack locks, latency and distance to safety.
- Do not place the only safe ground off screen. Commit an aimed ground attack at a communicated point in its wind-up. A taunt cannot silently move an already announced danger area onto another player.
- Show one mechanic first. Normal bosses overlap at most two major demands, with recovery time. Add variety through sequences and positioning rather than unreadable effects.

## Threat and taunting

Threat generation, enemy target selection and forced targeting need implementation before an encounter can test tanking. Show the enemy's current target and a successful or resisted taunt. A successful taunt raises the user to current top threat and briefly forces future eligible targeting. It does not interrupt a cast, erase a ground attack or provide permanent boss control. Define duration, cooldown and resistance explicitly in ability data.

Blackpick's practice foreman threatens a marked miner. A defender uses a trained taunt and faces its cone away from the miner; another player can stop the runner. A clearly labelled alarm bell offers a room-based temporary fixate when the party lacks a taunt. Solo mode makes the same targeting lesson readable without inventing an extra compulsory player. Later encounters offer cooling or shelter controls as alternatives to a second tank.

## Control is more than a stun button

| Response | What it does | Important boundary |
|---|---|---|
| Interrupt | Stops a marked cast and may apply a short school lockout | Only works on interruptible casts; does not automatically root or stun |
| Stun | Prevents movement and actions for its duration | Show immunity or diminishing returns; do not demand a stun against an immune boss |
| Root | Stops movement | Does not stop a stationary caster from casting |
| Slow | Buys travel time | Does not count as a guaranteed stop when an objective needs one |
| Boss stagger | Builds a separate visible threshold and creates a vulnerability window | Not interchangeable with a normal enemy's hard-control duration |
| Room control | A snare, gate, candle, bell or lever solves an identified encounter need | Clear label, reachable position and reusable reset; no profession or consumable gate |

Use dangerous runners and casters that really can be controlled. The same stun should have a meaningful purpose rather than every important target being immune. A missed runner or interrupt may create bounded extra pressure, but not an infinite add loop or an unavoidable full reset.

## Class coverage and useful jobs

These are capability requirements for the later class-training pass, not new abilities silently granted by this document. Existing class training currently covers opening-level unlocks, so higher-level coverage must be authored and verified.

| Class ID | Natural contribution | Capability to verify before the relevant lesson |
|---|---|---|
| Warden | Defending, facing, close-range disruption, cleave | Train a real taunt/defensive option by 8 and a reliable stun or interrupt by 18 |
| Paladin | Defending, protection, interrupting and group recovery | Train defensive/taunt access by 8 and make the existing Rebuke interrupt obtainable by 18 |
| Rogue | Priority damage, short control, fast rescues and disruption | Obtain an interrupt or hard control by 18; damage-broken control must be signalled |
| Ranger | Runner control, ranged priority damage and covering rescues | Roots/slows by 18 plus an interrupt/hard-control route or an explicit room counter for casts |
| Occultist | Sustained damage, add pressure and disabling priority targets | Obtain suitable hard control or an interrupt by 18; damage-over-time must not make the assigned control impossible |

Do not require all of these classes in one party. Three-player normal runs support flexible compositions through encounter controls, reachable rescues and a manageable incoming-damage budget. A dedicated healer, exact defensive build, profession, rare item or two-tank swap is never mandatory. Healing and protection remain valuable by reducing pressure and creating room for mistakes.

Every encounter offers at least two non-damage contributions, but players do not each press every button. Rotate useful jobs between rooms. Melee players must be able to reach a web or switch without taking unavoidable damage; ranged players must have a reason to move and rescue rather than ignoring the room.

## Web traps and rescue

Silkburrow begins with cutting an NPC out of a harmless cocoon. Hostile webs have a targetable nameplate, finite health, hit feedback and a visible escape state. Ordinary melee attacks, ranged attacks and spells can cut them. An explicit escape interaction also works: no sword type, fire spell or consumable is required.

A player web roots the victim but leaves self-rescue and web targeting available. Allies can free them faster. Keep self-rescue available when solo or when every surviving player is bound. Web lifetime is capped, a web alone does not kill, and escape grants a short rebind grace period. Avoid repeated control locks. Reset, death, exit and disconnect recovery remove invalid bindings. Nearby floor telegraphs remain readable through the web.

Use webs to change priorities: stop damage briefly to free someone, control a runner while an ally cuts, then return to the boss. Later crypt bindings reuse that readable interaction.

## Production order and acceptance

1. Implement private runs, correct entry/return, checkpoints, event scope, reward receipts and safe save recovery. An entrance marker alone is not a playable dungeon.
2. Prove Blackpick's complete run: camera visibility, shapes, threat/facing, taunt and a no-taunt room alternative. Then prove Silkburrow's natural cave geometry, real sight blocking, control and web rescue.
3. Verify each class's obtainable training at the intended level. Test full parties, duplicate-class parties, solo story and short parties. Record whether each required counter is a class ability or a room action.
4. Test telegraphs at the actual supported camera sizes, including foreground props, grass, particles, webs, melee lock-on and the longest required move to safety.
5. Test a rooted caster still casting, a stunned add stopping, a correctly interrupted cast stopping, and a stagger-immune boss displaying the right response. Taunt must change the appropriate target without moving committed ground attacks.
6. Test web self-rescue, ally rescue, all-survivors-bound recovery, a reset while trapped, death, exit and reload. Test seal latches with one player, three players and a disconnect mid-sequence.
7. Test real corner sight breaks: ranged enemies reposition, solid walls block appropriate attacks, and collision/pathing do not strand either side.
8. Measure successful clears and first attempts separately. Checkpoint recovery should be short. Test wipes, repeated rewards, missing-class alternatives and all regional story/gear alternatives.
9. Keep the campaign finale accessible before 50 and award its global capstone once. Level-50 replay reuses the same layout/core bosses, grants no character XP and does not require a raid queue.

The remaining layouts follow only after the first two complete pilots work. Seven is the production target. Eight is a ceiling; an unnamed spare slot is not approved content.

# Mythkeep opening and combat pass — 9 November 2026

This pass builds on the locally authored Abel/cart opening. It preserves the character-integration chat's newer rig, independent weapon animations, bow, player-facing control, loading, logout and performance changes. The live project remains `C:\Dev\Shadowfell\Shadowfell`; project/save identity remains Shadowfell.

## What was broken

The new spawn at **[-617, -182]**, Abel, rats, boar and milestone were all on terrain whose walk value was zero. The opening had no walkable connection to Miller's Lane. A stationary player could not escape because the walk gradient was also zero. Earlier quest tests advanced objectives directly and did not reveal this.

There was also incorrect control advice: mouse-aim uses **G** to interact, while classic controls use **F**. Instructions now resolve the current key binding, including player rebindings, rather than assuming F. Jump remains Space by default.

## The playable opening

1. Speak to Abel at the broken cart. Walk east to the milestone, read it, and return.
2. Accept **Rats in the Grain**, fight four passive rats, learn targeting, the first ability and collecting drops. Starter rats no longer flee or recruit a pack; their respawn allows time to finish the encounter.
3. Accept **A Pig With Ideas**. The young boar's committed **Tusk Sweep** marks a wedge for 1.2 seconds. Moving out avoids it. Its warning and bite pose refer to a boar rather than an undead cleaver attack.
4. Accept **The Road In**. Follow the repaired West Road to the existing Miller's Lane, then Lantern Lane into Thornford. Deliver Abel's note to Elsie at the inn. **Odd Jobs** opens as the local follow-up, with acceptance still left to the player.
5. Deliver Elsie's hinge to Iren for a tool belt. Choose useful local work: Heda's orchard, Hobb's kitchen, Tobin's fishing lesson, or the watch when ready.

The cart clearing has short ground cover and a readable road. The approach bends around Miller's Pool before joining Miller's Lane: a closing repeat caught the original straight segment grazing the pond's collision boundary. The pond, dock and shoreline scenery remain in place. Terrain repair changes walk/surface samples through the existing sculpt layer, preserving every authored terrain height. It does not rebake the continent or remove the user's scenery. The inn is reachable through its existing west entrance or its visible south entrance; the trial follows the existing approach lane and south doorway.

## Chains and independent entry points

- The cart's four quests remain ordered. Players can abandon its auto-started first quest through the quest log and return to Abel later.
- Elsie offers **Odd Jobs** even if the player walks past the tutorial. The letter hand-in still leads directly to her offer.
- Cooking no longer gates Heda's referral to Rowan. At level 2, Rowan can offer **Where the Lanterns Went Out** directly to a traveller who skipped the village errands. Its subsequent courier/watch/burial chapters retain their real prerequisites.
- Tobin's fishing lesson needs the tool belt, rather than the hunting/cooking quest. Hobb can still suggest it after the cooking route.
- `leadsFrom` is presentation metadata for a natural follow-up, separate from mandatory `requires` and `requiresAny`. Locked quests still cannot be accepted through a handoff.
- Later NPC menus defer advanced reforging, sockets, refining, gems and runecraft choices to level 10. Basic smelting remains available to a trained miner. Existing advanced stations remain in the world; the opening does not send a player to use them.

The full recommended 1–10 journey and both middle routes remain intact. Their scripted quest/kill budgets still reach level 10. This is not a measurement of an unfamiliar player's elapsed levelling time.

## A peaceful first livelihood

Tobin lends a rod and teaches Fishing on accepting **The Borrowed Rod**. A correctly timed strike during that first Willow Pond lesson reliably lands its requested perch. Striking too soon still fails. Ordinary fishing retains its fish tables, skill, bait and timing; beginner waters start with a 90% landing chance before skill bonuses rather than 75%.

Tobin's one-time payment is now ten silver. Combined with the hinge job, this lets a player buy the ten-silver basic rod without having to fight. The old loan rod is returned normally.

**From Pond to Pot** is an optional job from Hobb after the fishing lesson. He teaches basic Cooking when it is accepted, asks for three actually grilled perch and pays twelve silver once. The player catches fish, uses a real hearth recipe and delivers the cooked meals. Extra meals can be eaten for recovery. The existing boar-meal route remains available for its own story and recipe.

There is no new repeatable cash faucet or attendance requirement. This proves a small civilian session, not a full level-50 noncombat economy.

## Three optional discoveries

| Place | Clue and interaction | Reward / story |
| --- | --- | --- |
| Roadwardens' Reserve, **[-588, -201]** | Ask Abel about the milestone's sword. Three cairns mark a traveller's chest just off the road. | Bread, a draught and two silver, once. The wardens still use a much older mark. |
| Dry-Stone Cache, **[-398, -180]** | Tobin describes his father's tackle above Willow Pond's north bank. Open the actual box. | Bait and four silver, once. A note questions the story that Avel held the crossing alone. |
| Bell Garden, **[-421, -213]** | Follow the small uphill path. Read the carved verse and physically ring **Bridge → Hearth → Watch**. Wrong notes safely reset the sequence. | The solution opens the Lamplighters' Casket: draughts and eight silver, once. Avel's older inscription names the ordinary people who held the crossing while the hero carried children to safety. |

Examining the verse does not solve the puzzle. The mechanism works without a quest, has a proximity check, saves its state and cannot duplicate its chest reward after reloading. The secret sites have no ordinary discovery marker before they are found. Their hints are local rumours rather than mandatory story objectives.

## Combat and interaction polish

- Road revenants have slower, committed ground telegraphs to reinforce the first boar's lesson.
- Direct hits retain weapon trails, contact flashes, material sounds, blood/bone responses, flinch and restrained hit-stop. Periodic damage retains its numbers and spell effects without replaying a weapon contact, flinch, impact sound or camera kick every tick.
- Camera kicks are reserved for critical/heavier attacks rather than every auto attack, including light off-hand and bow shots.
- Walls stop melee hits in both directions and block targeted spells before their resource cost is spent. A target moving behind cover interrupts an in-progress cast. Auto arrows test cover from their release point.
- Arrow trails retain timer fractions across frames. Emission is capped at four motes per update to bound work during a long frame; normal unenchanted arrows retain their faint wisp.
- Quest examination waypoints point at the actual interaction rather than a large area's centre. Puzzle reset/test labels now hide outside interaction-label range.

## Verification and limits

All test characters use separate test storage. No real character was deleted or reset.

- **Opening movement/input trial:** 284 checks. Moves through the actual road and inn entrance, fights four rats and the boar, uses normal quest dialogue and verifies local follow-up offers. Checks every approach segment for dry walkability and physical clearance, then traverses the pool bypass from three different entry offsets. Tests skipped work, chain locks, mouse-aim G, classic F and a custom Interact binding.
- **Peaceful district trial:** 52 checks, including a native renderer run. Completes the hinge/fishing/cooking route, buys a rod from Tobin, crafts at the hearth, eats a leftover meal, verifies one-time wages, opens both caches, operates the bell sequence, restores its saved state and checks spell cover / avoidable boar damage.
- **Both full intro routes:** 1,496 checks; both reach level 10. Includes all six classes' initial boar fights and the later quest/state routes. These later journeys use scripted travel and objective helpers; they are not an uninterrupted manual playthrough.
- Existing quest follow-up checks: 85 passed. Starter chains and combat-feel checks passed. Class kits: 1,553 checks, zero failures. Existing-character compatibility passed using copied saves. Script loading: zero failures; data-link validation: zero problems. Test logs are kept with the workspace's `opening-polish` backup and evidence folder.
- Native 1280×800 screenshots reviewed the start, pond, bell garden, telegraph and contact effect. The contact capture deliberately triggers the contact event to inspect the effect, rather than claiming a recorded player attack.
- A binary comparison verifies that terrain height data is unchanged: only three terrain tiles differ, with 210 walk samples and 117 surface samples changed. A content comparison verifies that 219 unrelated existing quests, original world spawns, roads, puzzles and population match the pre-pass snapshot.

The scripted five-fight Warrior route finished with roughly 62% health without food or recovery. This is forgiving while making food useful. Existing six-class starter trials remain comfortably survivable. Different classes have different first-fight kill times; balancing sustained encounters and later kits still needs play observations.

Tests use Dummy audio: sound events and existing material/ability routes are exercised, but an audible mix review is still required. Existing renderer null-material and shutdown/resource warnings remain in test logs; this pass does not claim a clean engine shutdown. Fun, an uninterrupted first-hour timing, unfamiliar-player comprehension and an actual two-player outing remain human/integration review gates. No multiplayer proof or broader endgame build is claimed here.

Next review: play a fresh adventurer and a fresh fisher without developer directions, listen to the actual mix, and record where they hesitate. Then tune encounter rhythm and travel from that evidence before adding more zones.

## Authoring notes

Opening records live in `data/quests/quests.json`; resident rumours in `data/quests/dialogue.json`; placements, roads, puzzles and chests in `data/terrain/new_map/spawns.json`; props in the neighbouring `scenery.json`. Walk edits are saved in that map's `sculpt.json` and `world.bin` through the editor's normal sculpt format.

Quest prose can use `{interact}`, `{jump}`, `{bar0}`, `{cycleTarget}` and `{toolbelt}`. Dialogue quest pages, quest-log details and turn-in guidance resolve these against the current controls. A chest's optional `puzzle` names the mechanism that holds its latch; `puzzleHint` explains the lock. The bell garden's `visual: "hangingBells"` and `labelRadius: 9` affect only that new mechanism.

Reproducible tests: `opening_playthrough_check.gd`, `district_life_check.gd`, `intro_journey_check.gd`, `quest_followups_check.gd`, `class_kits_check.gd`, `starter_chain_check.gd`, `combat_feel_check.gd`, `validate_data.gd`, and `check_scripts.gd`, under `game/tests`.

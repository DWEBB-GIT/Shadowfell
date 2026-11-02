# Shadowfell intro trial and readability review

1 November 2026. Tested against the current new continent with isolated fresh characters. No real character saves or combat balance values were changed.

The opening is promising, but the next milestone should be a polished first 15–20 minutes. Readability and teaching have more value now than another batch of zones or quests.

## What was actually tested

- Native Forward+ captures of character creation, Thornford, the farm approach, combat, the meadow objective, the town hall and Lantern Road.
- Recorded WASD input along the authored roads; the first three boars, meadow discovery, the first quest reward and the next chapter through three revenants.
- Twenty-two seeded encounter samples: three fresh level-one boar attempts for each of five classes, one level-one Briarjaw attempt per class, a Warrior auto-attack-only comparison and a level-three Warrior Bellkeeper attempt without dodging.
- After the corrections: every walk-in building's front approach and collision, actual walking into the inn and town hall, a normal-reach mayor conversation/reward action, screen-space clearance of outgoing damage numbers and real attacks at one simulation step per rendered frame.

This was a scripted trial with visual inspection, not a human usability study. Encounter samples reposition fresh characters at real spawns. The route knows its destinations and skips reading time. One route fight included a 54.6-second wait before the roaming target entered attack range; that is a harness targeting delay and must not be treated as enemy time-to-kill. The trial does not establish human levelling time, a complete 60-hour campaign or sustained multiplayer performance. Audio event wiring was inspected; no subjective listening verdict is claimed.

## Starting difficulty

All fifteen basic-ability boar samples and all five wolf samples survived. These are small samples, not statistical balance proof.

| Fresh level-one class | Young boar clear time, three seeds | Health lost per boar | Briarjaw, one under-level attempt |
| --- | --- | --- | --- |
| Warrior | 4.1–6.8 seconds | 10–14 / 98 | Won; 90 / 98 health left |
| Rogue | 3.0 seconds | 7–8 / 68 | Won; 59 / 68 left |
| Ranger | 1.6–3.1 seconds | 0–4 / 74 | Won; 74 / 74 left |
| Occultist | 4.4 seconds | 3–4 / 50 | Won; 16 / 50 left after 13.7 seconds |
| Paladin | 4.6–5.1 seconds | 10–12 / 98 | Won; 94 / 98 left |

The basic boar encounter is appropriately forgiving. The Warrior took 15.6 seconds and lost 33 health using auto-attacks alone, versus 4–7 seconds with Heavy Strike. A player who misses the ability explanation gets a noticeably slower and rougher first fight. Teach the first ability explicitly before increasing enemy damage.

Three consecutive Lantern Road revenant fights left the level-two Warrior at 36 / 116 health without consumable use or deliberate recovery. The road already has a meaningful increase in pressure. Check pull spacing and give a clear recovery prompt before raising its numbers.

Briarjaw's quest is available at level one: its displayed level two is not an enforced `minLevel`. The single Occultist wolf result deserves repeat testing; do not make every enemy tougher based on the stronger ranged or melee classes. Consider making this optional quest available at level two, or clearly warning about its recommended level, while keeping it independent of the main story.

The level-three Warrior died to the Bellkeeper after 17.7 seconds while standing in attacks, leaving the boss on 99 health. That is acceptable as a failure case only if players have already learned to recognise and leave telegraphs. It is not evidence that the correctly played fight is balanced. Repeat with telegraph avoidance and with each class before tuning the boss.

## Visual and combat findings

The warm village, compact hub, actual inn/resting location and quieter countryside support the intended stylised MMO identity. The local-work opening also gives the darker story something grounded to threaten. The overdue grain bill and dead workers' contract suit the intended adult humour without depending on explicit content.

The most serious remaining visual issue is foreground foliage obscuring the player in a starter fight. The second boar capture hides much of the character under conifers. Fade the intervening canopy and clear small fighting pockets around initial spawns. Preserve the decision against a character outline.

The ground is still subdued and sparse in places. Use grouped short grass, a few contrasting ground-cover patches, better shore transitions and clearer path shoulders. Do this within the chosen fixed-camera composition. The larger building art pass remains deferred to the planned modular kit.

The opening text is easy to lose in the scrolling log, while many quest markers compete for attention. Give the first objective a short, readable introduction and a deliberate first route. Keep the independent village problems available without presenting all of them as equally urgent.

## Corrections made after the trial and player feedback

1. **Entrances:** all sixteen existing walk-in buildings have a camera-facing primary doorway, a clear collision gap, doorstep and sign. Existing side access and interior/NPC positions remain usable. Decorative house doors are corrected when their authored side would face away from or edge-on to the fixed camera. The fixed-camera view is the current camera orientation; a future camera rotation system would require another entrance/cutaway review.
2. **Damage numbers:** retained the current fonts, colours, crit emphasis and upward drift. Outgoing numbers start above the whole enemy nameplate with a screen-space gap, rather than crossing the enemy name and health bar. XP has additional clearance.
3. **Impacts:** successful hits produce an immediate, short contact flash when the visible impact lands, with a stronger melee slash. The opening auto-attack's flash and hit-stop follow its visible windup timing. Living beasts can produce a few brief blood droplets; these have a separate setting. Misses do not show a false contact, and undead do not use living-beast blood.
4. **Cleanup:** temporary effect meshes/materials detach before disposal. The World/Town reference cycle is broken on game exit so it cannot retain the world and its materials indefinitely. Verification logs record any remaining shutdown diagnostics separately.

## Recommended next pass

1. Fade obstructing foreground trees; author a clear first combat pocket and route from Thornford.
2. Teach movement, first attack/ability, looting and recovery in context. Introduce a forgiving telegraphed attack before the Bellkeeper; then test actual avoidance, control and interrupt lessons as their abilities become available.
3. Repeat level-one and level-two class trials with several wolf seeds, two-enemy pulls and a player who initially uses only auto-attack. Tune class outliers and encounter spacing before globally raising difficulty.
4. Re-test the first 15–20 minutes with a human who has not read the map. Measure first-enemy time, wrong turns, deaths, ability discovery and dialogue time. Use those observations to set the early levelling pace.
5. Profile cold boot and ordinary play separately. The measured post-confirmation loading phase was about 4.1 seconds; this excludes initial application/world/UI construction and is not a full cold-start measurement.

Keep the seven-dungeon plan and existing zone structure. Finish this small opening slice before expanding the quantity of content.

## Verification and limits

- `readability_check`: zero failed. All sixteen front approaches/interiors, decorative door orientation, walking into the inn/town hall, the mayor reward page, actual hit effects, number clearance, effect expiry and blood/miss/undead rules passed in a native rendered run.
- `reach_village_check`: zero failed after the entrance changes.
- `camera_movement_check`: zero failed after the changes.
- `jump_check`: zero failed during this pass.
- Normal frame-by-frame combat in the final readability run did not reproduce the null-material messages seen in the accelerated intro/reset trial. The effect-disposal correction is retained. Repeated full-world resets and ordinary gameplay are different workloads; this is not a comprehensive renderer performance certification.
- The World/Town cycle fix removed the retained-world shader/material set from the final native shutdown diagnostics. Some texture/font, CanvasItem and object cleanup warnings remain at shutdown. Do not describe the editor or renderer as error-free.

### Captures

- [Earlier combat under the trees](screens/intro-combat-before.png)
- [Raised outgoing number and contact effect](screens/intro-combat-after.png)
- [Lantern Inn front entrance](screens/intro-inn-entrance.png)
- [Town hall front entrance](screens/intro-town-hall-entrance.png)
- [Mayor quest page inside the town hall](screens/intro-mayor-quest-page.png)

The post-change combat capture is a focused test scene entered shortly after a quest reward, so it also contains reward/discovery banners. Those banners are not a proposed combat UI change.

# Shadowfell instanced dungeon plan

**World placement update, 1 November 2026:** The opening now connects to 34 authored onward hubs and 109 regional/return quest prototypes. The new map has 134 quests. Terrain routes, level districts, public return areas and seven sealed dungeon approaches are placed. Full private dungeons and measured 60-hour progression remain future work. See the [world review](../world-layout-review.md). Earlier future-content wording below refers to the fuller designs, not the absence of this first placement pass.

Updated 1 November 2026. **Seven approved layouts, absolute maximum eight.** No eighth dungeon is scheduled. These are design blueprints; private instances and their encounters are not yet playable. [Structured plan](instanced-dungeons.json). [Mechanics and acceptance requirements](dungeon-mechanics.md).

## Scope and pacing

The active roster replaces the earlier eight-layout proposal. Blackpick Mine replaces the Siltwheel waterworks concept. Silkburrow Caverns replaces the Tollward Vaults concept. Yewbound Catacombs and Coldhearth Sanctuary refine the existing woodland and snow designs. Their planning IDs remain stable. Rootlock Sluice and Broken Crown Quarry leave the active roster; their local stories remain outdoor content. Graveshroud Hollow uses the late return to Thornford already planned, with no extra macro-region.

Seven unscheduled reference designs are preserved in the [backlog](deferred-dungeons.md). They are not additions to the release roster, guaranteed expansion content or an approved eighth slot. Replays, difficulty variants and alternative entrances reuse existing rooms and core bosses.

The dungeon clock stays inside the 45/60/80-hour journey envelopes. Seven available runs do not mean seven required clears. All regional group clears are optional; the shared finale is solo-capable. Outdoor alternatives retain equivalent story outcomes and gear budgets. Target times describe successful normal clears, excluding queues, travel, explanations and wipes; measure those separately before calibrating XP.

The first introduction remains 8–10, within the Hook. The middle has wider gaps, followed by three late runs at 44–46, 48–49 and 49–50. Level spacing does not guarantee equal hours: the baseline takes about 9h30 from 44 to 48. Outdoor patrols, caves and quest encounters must rehearse mechanics during those gaps without creating extra instanced layouts.

## Seven-dungeon roster

| Dungeon | Recommended | Successful clear | Setting |
|---|---|---|---|
| Blackpick Mine | 8–10 | 15–20 min | A bandit-held working mine |
| Silkburrow Caverns | 19–21 | 20–25 min | A natural cave system beneath the toll road |
| Yewbound Catacombs | 26–28 | 25–30 min | An old woodland crypt beneath the archive |
| Deep Crucible | 38–40 | 25–30 min | A volcanic cave forge |
| Coldhearth Sanctuary | 44–46 | 30–35 min | A forgotten snowbound temple inside the old bastion, still defended by dead knights who remember their oath. |
| Graveshroud Hollow | 48–49 | 30–35 min | A deep natural cave reached through Thornford’s sealed crypt wing, with necromancer workshops and stolen memorials. The early exterior crypt stays unchanged. |
| The Unwritten Court | 49–50 | 35–40 min | The binding Court |

## Modes, rewards and the finale

Three-player parties are the design target, with a solo story route. Normal encounters supply universal room actions wherever an absent class tool would otherwise block completion. Party jobs include defending and facing, damage, interrupting, controlling runners, rescues and mechanisms. Every class contributes; no fixed class composition or dedicated healer is mandatory.

The Unwritten Court admits at 48, is recommended 49–50 and concludes the chapter that earns 50. The final chapter’s XP is budgeted across its approach, encounters and hand-in within the existing 48→50 allocation; a single clear does not grant two levels automatically. A planned level-50 replay reuses its rooms and core bosses, grants zero character XP and never repeats the ending/capstone payout. Frame repeat enemies as residual binding echoes. Optional raid preparation does not gate the campaign, and future raids remain undesigned/unbuilt.

First clears offer a class-appropriate equipment choice once per character per dungeon. Repeat boss loot, materials and cosmetics use separate run receipts. Cover all five classes and current equipment slots, with no invented trinket slot. Numeric stats, drop weights and raid-readiness budgets remain to author. Equivalent outdoor rewards preserve progression when regional dungeons are skipped.

## Dungeon designs

### Blackpick Mine (`di_siltwheel`)

**Rillbank Vale; entry 8; recommended 8–10; 15–20 minutes.** Entrance: Lantern Crossing.

**Setting:** A bandit-held working mine: timber galleries, ore carts and a stolen-payroll camp. No waterworks dungeon.

**Local story:** Bandits have occupied the crossing’s mine and taken tools and a shift crew hostage. Recover the payroll, free the miners and reopen the supply road. One miner is furious that the ransom includes a charge for using his own shovel.

**Wider thread:** A stolen relief-delivery seal connects a buyer of the ore to the Quiet Levy. The bandit problem matters locally even before that connection is understood.

**Boss order:** Hobb the Paymaster → Foreman Blackpick.

**Encounters:**

- An empty marked practice bay shows a cone, a line and a circle before combat. A miner explains each shape in one sentence.
- A shield bearer escorts a vulnerable payroll runner. Draw its attacks away, face its cone into clear ground, and let another player stop the runner.
- A tauntable foreman threatens a marked miner in a forgiving practice encounter. A room-mounted alarm bell supplies a visible fallback fixate for parties without a trained taunt.
- Two bosses, a checkpoint after the first, a rescue shortcut and a safe exit.

**Teaching and assessment:**

- **Read direction, shape and impact timing.** Practice: Non-damaging demonstration, then one slow attack at a time. Assessment: Foreman combines a frontal sweep with a separately timed circle. Recovery: First practice mistake causes a modest hit and a short hint, never an instant death.
- **Taunt a threatening enemy away from a vulnerable ally and face its frontal safely.** Practice: Marked miner practice and an explained alarm-bell fixate. Assessment: Party protects a miner while disabling the foreman’s supply cart. Recovery: Ally retreats safely; the objective resets without deleting boss progress.

**Loot direction:** Blackpick Workgloves — hands; Recovered Payband — ring; Freed Miners’ Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### Silkburrow Caverns (`di_tollward`)

**Rillbank Vale; entry 18; recommended 19–21; 20–25 minutes.** Entrance: Tollhouse Rise.

**Setting:** A natural cave system beneath the toll road: limestone chambers, root tunnels, web bridges and a spider nursery.

**Local story:** Couriers and livestock have vanished into webbed smuggling tunnels. Cut trapped people down, recover an ordinary family parcel and stop the brood reaching the farms.

**Wider thread:** A trapped courier carries duplicate seizure orders. Rescue provides evidence, while the brood remains a wildlife problem rather than another servant of the Collector.

**Boss order:** The Threadkeeper → Old Mother Manylegs.

**Encounters:**

- Cut a harmless practice cocoon open before any player can be trapped. Every weapon or damaging spell can break a hostile web.
- The first player web roots but does not silence, disarm or prevent targeting the web. Its nameplate and self-target action remain visible.
- An ally can cut a victim free faster. In solo mode the player can attack or interact with their own web. No consumable, blade type, fire spell or extra player is required.
- Control a skitterer before it reaches an egg clutch. Roots stop movement, stuns stop movement and actions, and interrupts stop the broodcaller’s marked cast.
- Cave corners teach sight breaks on ordinary ranged spiders before the boss adds pressure. Two bosses and checkpoints bound the run.

**Teaching and assessment:**

- **Notice a trapped ally and cut a targetable web before focusing the boss.** Practice: Free an NPC, then a self-breakable practice web. Assessment: An announced cocoon overlaps a clearly separate frontal attack. Recovery: Webs have a maximum lifetime, do no lethal damage by themselves and dissolve on reset.
- **Choose the right tool for a runner or a caster.** Practice: One runner and one marked broodcaller in separate packs; a reusable cave snare is available. Assessment: Bounded add wave includes a runner to root/stun and a caster to interrupt or hard-control. Recovery: A missed runner adds a small bounded wave, not an endless egg cascade.
- **Use a real rock corner to make ranged enemies reposition.** Practice: One low-damage ranged spider with a safe retreat corner. Assessment: Group ranged adds before a web rescue. Recovery: No sealed door or irreversible pull requires a specific tank class.

**Loot direction:** Silkburrow Wrap — back; Courier’s Unlost Ring — ring; Broodbreaker’s Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### Yewbound Catacombs (`di_yewbound`)

**Paleweald; entry 25; recommended 26–28; 25–30 minutes.** Entrance: Scribes’ Hollow.

**Setting:** An old woodland crypt beneath the archive: burial niches, mossy stone, undead custodians and a small grave-cult.

**Local story:** The archive’s burial custodians have risen. Recover a family name-book and return disturbed memorials while rescuing the living caretaker.

**Wider thread:** Copied burial names reveal how the Levy turns remembrance into ownership. A grave-cult has been selling those names onward; the later necromancer lair reveals its buyer.

**Boss order:** The Namekeeper → The Hollow Copyist.

**Encounters:**

- A practice grave-caller demonstrates an interruptible heal. Breaking its binding candle is the universal fallback.
- Two limited add groups teach target priority. Grave-callers cast, bone runners pursue a witness and shielded custodians face their current threat target.
- A safe chamber teaches an index-and-epitaph puzzle with a visible reset. Evidence has a readable solution, not a random interaction sequence.
- Two bosses revisit web-style ally rescue using breakable grave bindings. Roots do not interrupt casts; boss stagger is shown separately from hard control.

**Teaching and assessment:**

- **Stop the important cast rather than every small attack.** Practice: One long, named grave-heal cast with a candle alternative. Assessment: The Copyist combines a heal cast with a controllable runner. Recovery: A missed heal restores a capped amount of health, not a full reset.
- **Split useful jobs: hold the front, control the runner, stop the caster and rescue the witness.** Practice: Two short packs introduce jobs separately. Assessment: A capped wave combines previously practised jobs. Recovery: No encounter requires a dedicated healer, cleanse or a particular class composition.

**Loot direction:** Namekeeper’s Cord — waist; Unforgotten Mantle — back; Caretaker’s Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### Deep Crucible (`di_crucible`)

**Cinder Reach; entry 37; recommended 38–40; 25–30 minutes.** Entrance: Ember Relay.

**Setting:** A volcanic cave forge: basalt galleries, ore channels and a furnace operated with bound labour.

**Local story:** The inner works are consuming their safety wards. A crew needs a usable way out before the next furnace cycle.

**Wider thread:** The plant’s orders show how bound work is being turned into power for the wider network. Its rescue/evidence route matches the upland route’s onward result.

**Boss order:** The Slag Shepherd → The Bound Furnace → The Red Foreman.

**Encounters:**

- Practise a stationary heat lane, then one moving furnace sweep before combining them.
- A furnace ward pressures the current threat holder. A trained taunt or cooling lever can relieve the marked defender; taunt does not cancel an already committed ground attack.
- Stun or root slag carriers before they reach a hot channel. A room gate supplies a slower control alternative.
- Cooling channels and machinery have visible states and manual resets. Keep the first build on stable floors; collapsing platforms are outside scope.
- Rescue workers and recover their wage record. Three bosses, each followed by a safe checkpoint.

**Teaching and assessment:**

- **Read environmental telegraphs while continuing useful combat jobs.** Practice: Static heat lane, moving sweep, then a simple add pack. Assessment: Safe-lane rotation overlaps one controllable slag carrier. Recovery: Safe edges stay visible, hazards cannot seal the only exit and falling never deletes the run.
- **Use taunt or a universal room control to relieve a threatened defender.** Practice: One labelled furnace mark and a cooling-lever demonstration. Assessment: An announced heat mark overlaps a manageable frontal. Recovery: No perfect taunt chain or mandatory two-tank composition is required.

**Loot direction:** Cinderproof Pauldrons — shoulders; Quenched Ember Charm — neck; Crucible Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### Coldhearth Sanctuary (`di_coldhearth`)

**Frostward Marches; entry 43; recommended 44–46; 30–35 minutes.** Entrance: Hearthwatch.

**Setting:** A forgotten snowbound temple inside the old bastion, still defended by dead knights who remember their oath.

**Local story:** Dead knights protect a sanctuary whose living refugees have been reclassified as intruders. Restore the original oath and open the shelter without treating every defender as mindless evil.

**Wider thread:** A forged amendment to the sanctuary charter mirrors the altered relief contracts. The oath’s wording gives living witnesses a way to challenge the larger binding.

**Boss order:** Sir Edric, Last at the Door → The Ashen Vigil → The Oathbound Castellan.

**Encounters:**

- A training effigy practises a frontal that must be faced away from allies and a named interruptible oath-cast.
- A slow pressure meter is reduced by lighting shelter braziers and dealing with attendants, not only by meeting a damage threshold.
- Control a squire carrying a replacement seal, rescue a chilled witness and rotate useful jobs as the safe shelter changes.
- An optional oath-reading resolution releases one named knight after the encounter. It preserves the same reward budget and does not require killing a sympathetic character.
- Three bosses with checkpoints. A generous normal-mode soft enrage rewards good play without a rigid gear gate.

**Teaching and assessment:**

- **Manage mounting pressure through damage, control and useful room actions.** Practice: One pressure source and an explained brazier counter. Assessment: The Castellan adds familiar frontals while an attendant feeds the pressure meter. Recovery: Story mode caps pressure and supplies a recovery window; higher tuning is a later pass.
- **Read the encounter and take an available useful job.** Practice: Optional NPC prompts describe an unfilled job without assigning a class. Assessment: A shelter move changes who can safely rescue, interrupt or control. Recovery: Room controls remain reachable for melee and ranged characters, including short parties.

**Loot direction:** Hearthwarden’s Boots — feet; Coalkeeper’s Coat — chest; Winter Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### Graveshroud Hollow (`di_graveshroud`)

**Thornford Reach; entry 48; recommended 48–49; 30–35 minutes.** Entrance: Thornford village.

**Setting:** A deep natural cave reached through Thornford’s sealed crypt wing, with necromancer workshops and stolen memorials. The early exterior crypt stays unchanged.

**Local story:** Return to the opening village after its apparent recovery. Necromancers are stealing the names the player restored and using them to bind the recently dead. Recover a villager’s memorial keepsake rather than simply collecting another ledger.

**Wider thread:** The Debtkeeper supplies binding vessels to the Court. Destroying the stock weakens this operation, but equivalent outdoor evidence keeps this dungeon optional for the campaign.

**Boss order:** The Bone Lantern → The Choir of Borrowed Names → Magister Vey, the Debtkeeper.

**Encounters:**

- Introduce two linked seals sequentially in a safe room before using them during combat.
- In a full party, teams can suppress two seal channels concurrently while another player controls a bone runner or protects a witness.
- Solo mode uses persistent seal latches and sequential actions. Short parties and a dead or disconnected ally switch to the same recoverable sequence.
- Do not teleport players into isolated lethal rooms. Maintain sight lines, short walkways and reachable rescues.
- Three bosses combine known interrupts, controllable adds and breakable bindings. The existing low-level Crypt Keeper is not replaced or rescaled.

**Teaching and assessment:**

- **Coordinate linked objectives while preserving combat priorities.** Practice: Two safe seals with long-lived latches and an explicit reset. Assessment: Vey combines linked channels, one runner and a familiar telegraph. Recovery: No simultaneous-input hard lock. Latches persist in solo/short-party mode; a missed sequence delays the encounter rather than wiping everyone.

**Loot direction:** Graveshroud Cowl — class-compatible head choices; Unborrowed Name — neck; Debtbreaker’s Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

### The Unwritten Court (`di_unwritten`)

**Shared final realm; entry 48; recommended 49–50; 35–40 minutes.** Entrance: Rimewatch Gate or Sunseal Court.

**Setting:** The binding Court: a shared final realm where recovered names can be freed.

**Local story:** Recovered names and evidence are brought to the place that turns them into binding orders. The rescued witnesses must leave as people, not entries.

**Wider thread:** The northern and southern approaches converge on this one private final instance. Completing the chapter ends the campaign’s collection scheme and earns level 50 once.

**Boss order:** The Empty Witness → The Keeper of Bonds → The Collector.

**Encounters:**

- Three short chapters combine previously practised telegraphs, threat/facing, interruptible casts, controllable adds, rescue bindings and linked room controls.
- Introduce at most one new variation: evidence changes which of two familiar attack lanes is safe. Practise it harmlessly before the Collector.
- Each boss has only one primary mechanic plus one supporting pressure at a time. The finale does not stack every lesson at once.
- Solo and party versions reach the same ending. Entry remains 48; the planned final chapter earns level 50 once rather than requiring level 50 first.
- Reuse the same layout and core bosses for the planned level-50 replay. Raid preparation is optional, and first-clear rewards are never paid twice.

**Teaching and assessment:**

- **Recognise familiar signals and choose a useful response without a new rule for every room.** Practice: A harmless evidence-lane demonstration and familiar opening packs. Assessment: The Collector rotates, rather than simultaneously stacks, threat, control, rescue and seal phases. Recovery: Checkpoint at each boss. Reset clears bindings and hazards, preserves earned receipts and provides an exit.

**Loot direction:** Cord of the Unbound — neck; Witness of Dawn — back; Liberator’s Armament — class weapon choices. Actual item stats and drop tables remain to author, covering all five classes.

## Instancing implementation contract

Current `Game` construction creates one `World`, `Collision`, entity set and `WorldState`; the save serializes that world. A new scene below the existing terrain or a teleported outdoor boss would not meet this plan.

1. **Private context:** create an isolated solo/party run, with separate map data, collision, enemy state, room mechanisms and loot. Keep the overworld state intact.
2. **Entry/return:** validate entry, remember the exact overworld position/facing and chosen map, load the instance, then restore the world camera, lighting, minimap and safe return position on exit.
3. **Death/rejoin:** checkpoint at bosses, guarantee an exit, handle leaving/rejoining and define party ownership. Do not use an unrelated overworld shrine to revive an instanced character.
4. **Scoped objectives:** carry instance/run IDs and participant eligibility with encounter events. Outdoor kills or another party’s completion cannot satisfy this run’s objectives.
5. **Save/recovery:** persist supported checkpoints, boss progress and reward receipts. If a run cannot resume, recover safely at its verified entrance without putting dungeon drops/corpses in the outdoor save or duplicating payouts.
6. **Loot:** create real class-compatible item pools and receipt-backed first clears, with normal repeat boss loot and no duplicate capstone from the alternative entrance.
7. **Authority:** before real group play, implement authoritative party membership, shared boss state, owner departure and reconnect behavior. A local private-copy pilot is not proof multiplayer works.
8. **Validation:** test solo entry, two independent runs, correct return, checkpoint death, reload, interrupted completion, repeat clear, alternative-entrance completion and every class’s viable normal route.

9. **Mechanics:** run-local threat, bindings, control vulnerabilities, seal latches and pressure. Validate the full [teaching checklist](dungeon-mechanics.md).

Build Blackpick Mine first. Silkburrow Caverns is the second pilot, proving different cave geometry, web rescue, control and sight-line behaviour. Complete each pilot before producing all later scenes.

## Plotted exterior approaches

Seven layouts remain blueprints. Their exterior locations are now saved and walkable. Two Court markers enter the same planned finale.

| Dungeon | Recommended | Approach coordinates |
|---|---|---|
| Blackpick Mine | 8–10 | lantern_crossing: -175, -204 |
| Silkburrow Caverns | 19–21 | tollhouse_rise: 133, -608 |
| Yewbound Catacombs | 26–28 | scribes_rest: 557, -424 |
| Deep Crucible | 38–40 | ember_relay: 253, 680 |
| Coldhearth Sanctuary | 44–46 | hearthwatch: 293, -1420 |
| Graveshroud Hollow | 48–49 | thornford: -305, -486 |
| The Unwritten Court | 49–50 | north_ledger_gate: 697, -1316; sunseal_court: 725, 1320 |

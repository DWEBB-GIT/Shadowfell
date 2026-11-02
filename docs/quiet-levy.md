# The Quiet Levy — playable chapter and local stories

Built 31 October 2026. This is installed content, distinct from the earlier research catalogue's future proposals. Restart the game, select **New map**, and create a fresh character for the complete opening. Existing characters retain their completed quests, items and positions; new optional jobs appear when their prerequisites are met.

## Narrative direction

Thornford accepted three carts of winter grain. Rook & Sons bought the debt, then used an altered continuation clause, stolen family names and burial seals to conscript the dead. The watch bell once ended the working day; now the collector uses it to call another shift.

Mayor Alder signed the agreement. His mistake has consequences, and his response is to restore the roll and put his own account on public record. Rowan wants his watch brought home. The villagers still need food, shelter, sound tools and enough quiet to sleep. The chapter ends with the families recovering their names; a memorial epilogue lets them have the final word. Rillbank is a future lead, not an advertised playable next region.

The tone targets an older teen/adult audience through responsibility, financial pressure, imperfect authority, loss and neighbourly solidarity. Humour comes from familiar behaviour: council disputes, trade pride, borrowed property, contradictory paperwork and the work still waiting after a victory. It does not depend on explicit sex, graphic cruelty, slurs or repeated jokes at grieving people's expense. This is a writing target, not a formal age classification.

Dialogue is brief enough for play. Give each resident a point of view; let serious moments stay serious. A quest can finish a local problem without revealing another global conspiracy. No one needs a punchline in every reply. Later dialogue passes should retain that restraint.

## Main chapter

| Chapter | Recommended level / zone | Story and activity |
|---|---|---|
| An Honest Day’s Work (`vr_first_hunt`) | 1–2 / Holt Fields | Clear three boars, inspect the fence and learn why timber stopped arriving. |
| Where the Lanterns Went Out (`tf_lanterns`) | 2–3 / Lantern Road | Inspect a work chit in the fallen lantern; defeat three revenants. |
| The Silent Watch (`tf_bell`) | 3–4 / Old Watch and Dawnstone | Defeat the Bellkeeper; compare his orders with the old charter. |
| The Names They Left Behind (`vr_names`) | 4–5 / Mourning Hollow | Read altered headstones, lay three gravewalkers to rest, confront Alder with the evidence. |
| What the Bell Remembers (`vr_crypt`) | 5 / Bell Crypt | Defeat the keeper, recover the family seals and restore the burial roll. |

These five keep their existing IDs, objective IDs, prerequisites, rewards and saved completion. Their writing and environmental evidence are revised. Character class is respected in Rowan's reward text. The crypt remains an exterior world encounter. Ending the levy does not claim to despawn every existing undead encounter.

## Twelve additions

| Quest / ID | Resident / zone / level | What the player does | XP / coins |
|---|---|---|---|
| A Gauge Worth Trusting / `nr_gauge` | Iren / Thornford / 1–2 | Compare two witness marks; recover a gauge case. Iren diagnoses her own tool. | 20 / 4 |
| The Dry Stack / `nr_timber` | Osric → Iren / Holt Fields / 1–2 | Carry two tagged seasoned billets to the actual smith. | 0 / 5 |
| Two Waters, One Notebook / `nr_water_notes` | Tobin / Willow and Miller's / 1–3 | Compare reed-edge and open-bank shelter. No rod or catch required. | 20 / 4 |
| The Route on the Reverse / `nr_reverse_route` | Mira / Briarwood / 2–3 | Read both route marks and learn the return approach. | 20 / 5 |
| No One Turned Away / `nr_bedding` | Lyra / Thornford / 1–3 | Carry two clean rolls from the inn's west door to the chapel. | 20 / 5 |
| A Shelter, Not a Lair / `nr_shelter_tracks` | Fen / Briarwood / 2–3 | Inspect bootprints and a borrowed-kettle note before assuming the occupants are bandits. | 20 / 5 |
| The Label Facing In / `nr_bottle_labels` | Morrow / Mourning Hollow / 3–5 | Check the shelf list and recover two labels. Morrow does the relabelling. | 0 / 4 |
| The Orchard's Small Tenants / `nr_pollinator_notes` | Heda / Holt Fields / 1–3 | Find a blocked bee box and inspect blossoms. Heda undertakes the roof repair; no animated ecological restoration is claimed. | 20 / 4 |
| No Overtime for the Dead / `nr_overtime` | Rowan / Old Watch / 3–4 | Put two named-duty sentry types to rest. Requires `tf_lanterns`. | 25 / 8 |
| Quiet Hours / `nr_quiet_hours` | Morrow / Nameless Yard / 4–5 | Defeat the two archers preventing medicine collection. Requires `tf_bell`. | 25 / 8 |
| Reasonable Use / `nr_water_rights` | Tobin / Common Water / 1–3 | Physically set and test three allocation handles. Requires the independent reeds-for-apples message. | 20 / 6 |
| The Bell's Last Word / `nr_last_word` | Lyra / Nameless Yard / 5–6 | Read a verse and play its four-note farewell. Requires `vr_crypt`. | 30 / 10 |

The previous eight local stories remain: boundary dispute, Briarjaw, trade message, lost brooch, perch supper, ditchbell, Wolf Hollow and Widow's Mirror. Their useful objectives remain, with clearer hand-in directions and selected dialogue revisions. Together this is **25 quests: five main, twenty optional**. No new side quest gates the main chain.

The twelve additions award **220 XP and 68 coins**; the first eight total 120 XP / 36 coins. This restrained budget avoids replacing combat progression with a large stack of starter errands. All district quests total 3,900 XP before combat, discovery, professions and rested gains. Recommended levels are advisory. Full class balance and human pacing still need playtesting.

## Places and mechanisms

The map now names Holt Fields (1–2), Briarwood (2–3), Lantern Road (2–3), and Old Watch and Dawnstone (3–4) as distinct quest-log regions alongside Thornford and Mourning Hollow. These are connected local districts in the existing continent, not newly claimed continents or an enlarged travel requirement. A small forester shelter and original bee box support the local stories. Short paths connect the shelter and common-water mechanism. Twenty-six earlier generated nature props were thinned to keep foreground canopies off the new interactions; original untagged placements remain intact.

The Common Water regulator stands at **X −411, Z −182**, just south of Willow Lane. Read the board, turn each handle, then use the test block. Its three states are Closed, Trickle and Full. The four memorial bells stand at **X −366, Z −443**, on Nameless Yard's western approach. Read the verse nearby, then ring the controls in its order. Mouse clicks and the usual nearby interaction key use the same actions. Labels identify controls and their state near the player; visual/text feedback accompanies the bell sounds.

Both mechanisms have safe resets and no irreplaceable consumables. Wrong answers grant no objective credit. Partial dial positions and verse progress survive saving; solved states cannot be accidentally reset or repeatedly rewarded. Normal clue examination does not satisfy a puzzle objective. The text log retains full feedback; transient messages are kept short.

For authors: **World → Puzzles** previews and moves the real mechanism as a whole. The placement Inspector edits name, instruction and a one-based answer list. Metadata → record contains nodes, offsets, state labels, owning quest and feedback. **Game Data → Quests** includes **Solve a world mechanism** with a mechanism picker. Clues use ordinary placed Props/examine text, and fetch items use quest-bound Loot. Keep published IDs stable.

## Verification and limits

`quiet_levy_check.gd` completes the eight workplace/discovery quests through real placed clues, timed gathering and recipient dialogue, then the combat jobs and main chapter with actual strike resolution. It tests both puzzle solutions, wrong answers, remote-operation rejection, resets, partial state, full save/apply, invalid save rejection, old saves without puzzle fields, reactive dialogue and duplicate-reward protection. The rendered run reports **zero failed assertions** and captures the regulator, memorial and shelter. Visual review found and corrected canopy occlusion, regulator placement and camera-distance label culling.

The existing world-editor checks and terrain checks also pass. The complete village/fishing and road/trainer regressions are run separately for this pass. Resource/RID cleanup warnings still occur when the test game shuts down. They remain unresolved; functional passes are not a clean engine-exit claim.

Advanced profession trials, daily schedules, escort/defense controllers, social seating puzzles, catch release and later regions remain future work. The first eight additions adapt the research plan's gauge, timber, notebook, reverse route, bedding, shelter, labels and pollinator ideas. The earlier [design catalogue](quest-design/shadowfell-zone-quest-plan.md) remains a dated planning record; its `qp_` keys are not production IDs. This guide and canonical `nr_` records describe what was actually built.

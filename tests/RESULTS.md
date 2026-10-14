# Shadowfall acceptance test results

Run: 2026-10-14T19:34:35.390Z  
Result: **171/171 passed**


## Launch and movement

| | Check | Evidence |
|---|---|---|
| ✅ | Game loads in a supported desktop browser | title screen, then HUD, from file://index.html |
| ✅ | No blocking errors occur during startup |  |
| ✅ | Player can move in all four directions | W 2.00m, S 2.11m, A 2.78m, D 2.50m (real key events) |
| ✅ | Diagonal movement is normalised | 1s straight 5.00m, 1s diagonal 5.00m |
| ✅ | Camera follows the player | camera offset after moving: x -0.00, z 10.00 (target 0, 10) |
| ✅ | Movement is frame-rate independent (extra) | 1s at 24 fps 5.00m, at 144 fps 5.00m |
| ✅ | Player remains within the playable area | A→(-35.6, 0.0) D→(35.6, 0.0) S→(0.0, 46.6) W→(-2.0, -48.6) |

## Combat

| | Check | Evidence |
|---|---|---|
| ✅ | Basic attack damages a nearby enemy | ghoul 1.6m away: 48 → 30 from a real left click |
| ✅ | Attacks do not damage enemies at arbitrary distances | ghoul 6m away after a strike: 48/48 |
| ✅ | Shield Break damages enemies within its radius | inside radius: 12, 12 (48-36); 5m away: 48 |
| ✅ | Ability cooldown behaves correctly | re-press after ~1s ignored (2.92s left); works again after 4s |
| ✅ | Brace (Space) turns aside the next blow, and only one | raised during the global cooldown; first claw blocked (hp 100), second lands (hp 92) |
| ✅ | Brace has a cooldown of about 7 seconds | 6.97s after use |
| ✅ | Brace window expires and cannot be spammed | re-press on cooldown ignored; raised shield drops after 2.5s and the next claw lands (hp 92) |
| ✅ | No dodge or sprint: Shift does nothing special | 2.50m in 0.5s holding D and Shift (walking is 5 m/s) |
| ✅ | Enemies pursue and attack | ghoul closed from 6.5m to 3.5m in 1s (chase); player hp 100 → 76 after 5s |
| ✅ | Enemy attacks are telegraphed before landing (extra) | 0.45s wind-up with raised arms and an amber health-bar outline |
| ✅ | Enemies stop attacking when the player is out of melee range (extra) | frozen ghoul, player 5.6m away for 3s: hp 100 |
| ✅ | Enemy health reaches zero correctly | three strikes of 18 on 48 hp → 0, dead=true |
| ✅ | Enemy defeat grants experience once and leaves a body to loot | +28 xp at once, coins stay with the body; reprocessing and striking the corpse changed nothing |
| ✅ | Looting the body gives its coins, once | body still there 6s later, prompt "Loot the Ashen Ghoul"; E: +3 coins; E again: nothing |
| ✅ | Defeated enemy is removed once looted (extra) | the looted body sinks away |
| ✅ | Healing draught restores 42 and reports when none remain (extra) | 40 → 82 hp; second use: "You have no healing draughts left." |
| ✅ | Draught never heals past maximum (extra) | 95 → 100 |
| ✅ | No script errors during combat (extra) |  |

## Exploration

| | Check | Evidence |
|---|---|---|
| ✅ | Abandoned cart is discoverable | walking west from the road: prompt "null" → "Examine the cart" |
| ✅ | Examining the cart advances the objective (extra) | "A merchant cart lies off the road, missing a wheel. Search i…" |
| ✅ | Manifest can be examined and collected | prompt "Read the manifest", document opened, in pack, objective complete |
| ✅ | Manifest text gives clues without resolving them (extra) | scratched-out driver, altered count, warning about bells |
| ✅ | Escape closes the active interface | modal after Esc: null |
| ✅ | Material can be collected | prompt "Take the grave-iron" |
| ✅ | Currency can be collected | 8 → 14 coins; purse removed from the world |
| ✅ | Equipment can be collected | brute drop at (-20.9, -45.0), prompt "Take Watchman's Edge (and 1 more nearby)"; the brute's 9 coins came with it |
| ✅ | Equipment is not silently swapped (extra) | still equipped: worn_longsword |
| ✅ | Shrine can restore health | 31 → 100 hp; respawn set to (7.8, 5.2) |
| ✅ | Contextual prompts update correctly | open road: none; at shrine: "E Rest at the shrine" |
| ✅ | Bags and the character panel do not pause the game | with both open: walked 2.50m and the world ran 0.50s; Esc closed them |
| ✅ | No script errors during exploration (extra) |  |

## Progression

| | Check | Evidence |
|---|---|---|
| ✅ | Experience increases after enemy defeat | 0 → 28 |
| ✅ | Level-up occurs at the required threshold | 84/100 xp after three ghouls (level 1); brute +65 → level 2 with 49/160 carried over |
| ✅ | Maximum health increases | max health 100 → 112, restored to full on level-up |
| ✅ | Basic attack damage increases | strike 18 → 20 |
| ✅ | Equipment upgrade improves damage | strike 20 → 25 after dragging it from the bag onto the main-hand slot (panel shows 22–28 +2) |
| ✅ | Upgraded weapon is shown on the character (extra) | Blender model swapped in the right hand |
| ✅ | Inventory reflects collected items | 2 filled bag slots; the worn longsword swapped into the slot the Edge left; coins: 17 coins |
| ✅ | Escape closes the bags and character panel (extra) | real Escape key |
| ✅ | No script errors during progression (extra) |  |

## Death

| | Check | Evidence |
|---|---|---|
| ✅ | Player death occurs at zero health (extra) | hp 0 |
| ✅ | Player death interrupts combat | no movement or attacks while dead; ghoul return |
| ✅ | Death screen appears | You have fallen The road takes what it can. You will wake 5 coins lighter. Return to the last shrine |
| ✅ | Respawn restores health | 112/112 |
| ✅ | Player returns to the correct shrine | (7.80, 5.20) beside the roadside shrine |
| ✅ | Currency loss respects the cap | 40 coins → 35 (20% capped at 5); 12 coins → 10 |
| ✅ | Equipment and progression are retained | level 2, xp 20, watchmans_edge, 5 items |
| ✅ | Surviving enemies reset to their posts on respawn (extra) |  |
| ✅ | No script errors during death and respawn (extra) |  |

## Persistence

| | Check | Evidence |
|---|---|---|
| ✅ | Manual save works | 934 bytes in localStorage (key shadowfall.save) |
| ✅ | A successful save produces confirmation | toast: "Game saved" |
| ✅ | Reload restores player position and progression | pos (3.25, 12.50), level 2, xp 8, hp 77, coins 14 |
| ✅ | Defeated enemies remain defeated | 3 enemies alive; ghoul_cart lies where it fell |
| ✅ | An unlooted body is still there to loot after a reload | ghoul_cart body lootable: true, +3 coins |
| ✅ | Collected loot does not reappear | loot in world: grave_iron, purse_wall, draught_rocks, satchel_ruin, helm_rocks |
| ✅ | Manifest progress persists | objective: Complete |
| ✅ | Shrine state and respawn point persist (extra) | {"x":7.8,"z":5.2} |
| ✅ | Repeated save/load cycles are stable (extra) | 3 cycles |
| ✅ | Autosave on close (extra) | position after closing and reopening: (-2.50, 21.50) |
| ✅ | Invalid save data does not crash the game | 4 corrupt saves: kept, kept, kept, kept; game started fresh each time and the original was not overwritten |

## Quality

| | Check | Evidence |
|---|---|---|
| ✅ | The game remains playable without audio | Web Audio removed before load; moved, attacked, braced and opened the pack |
| ✅ | Interface remains readable | smallest HUD text 9px (the xp numbers inside the bar); body text 13–15px at 1280×720 |
| ✅ | Scene stays light (extra) | 44 draw calls, 99726 triangles; 6 fps with software WebGL in headless Chromium |

## Build 2: spell bar and global cooldown

| | Check | Evidence |
|---|---|---|
| ✅ | Bottom of the screen has the spell bar, experience bar, bag and menu icons | 7 spell-bar slots (5 with icons), experience bar above them, character and save buttons, 4 bag slots; bar spans y 625–712 of 720 |
| ✅ | Global cooldown is shared by Shield Break and Lunge (WoW-style) | GCD 1.47s left just after Shield Break; Lunge pressed 0.45s later was refused; Lunge slot shows the GCD sweep (0.68) |
| ✅ | Strike stays off the global cooldown | left click during the GCD still swings |
| ✅ | Lunge is usable once the GCD has run out | pressed 1 again after 1.5s |
| ✅ | Lunge charges towards the cursor and strikes on arrival | 5.13m charge; ghoul 48 → 21 (1.5 × 18) |
| ✅ | Lunge has its own cooldown shown on the bar (extra) | 7.4s left of 8s |
| ✅ | No script errors (build 2 abilities) |  |

## Build 2: ground telegraphs

| | Check | Evidence |
|---|---|---|
| ✅ | Big enemy wind-ups paint their area on the ground (FFXIV-style) | Grave Slam: cone mesh in the scene, 51% filled halfway through its 1.4s wind-up; cast bar reads "Grave Slam" |
| ✅ | Standing in the telegraph when it fills hits the player | player inside the cone: 100 → 76 (Grave Slam 24) |
| ✅ | The telegraph is removed once resolved (extra) |  |
| ✅ | Walking out of the telegraph avoids the hit | walked south for 1.5s: hp 100 |
| ✅ | Brace blocks the Grave Slam | braced 1s into the wind-up: hp 100; "You brace and turn aside the Grave Slam." |
| ✅ | The marked area is locked when the wind-up starts (extra) | cone did not turn to follow the player |
| ✅ | The brute telegraphs its ordinary cleave too; Shield Break interrupts it but not the slam (extra) | cleave: smaller amber cone; Grave Slam: orange cone that cannot be interrupted |
| ✅ | No script errors (telegraphs) |  |

## Build 2: gamepad

| | Check | Evidence |
|---|---|---|
| ✅ | A starts the game from the title screen |  |
| ✅ | Left stick moves the Warden, with analogue speed | full stick north: 5.00m in 1s; half stick east: 1.79m |
| ✅ | Button prompts switch to the gamepad | spell bar shows RB, X / RT |
| ✅ | X strikes towards the right stick (aim without tab targeting) | ghoul to the east, right stick east: 48 → 30 |
| ✅ | Y uses Shield Break | ghoul 0 |
| ✅ | B raises Brace (the defensive button) | braced: true |
| ✅ | RB lunges towards the right stick | 5.13m south |
| ✅ | Start opens the bags; the d-pad moves a highlight between slots | focus b:0:0 → b:0:1 |
| ✅ | The stick does not move the Warden while a panel is open (extra) |  |
| ✅ | X equips the highlighted item | helm worn; maximum health 106 |
| ✅ | View opens the character panel; A picks an item up and puts it down | carried the helm from the head slot to b:0:2 |
| ✅ | Y drops the highlighted item on the ground | ground: watch_helm |
| ✅ | B closes the panels; A picks the item back up | prompt "A Pick up Dented watch helm" |
| ✅ | No script errors (gamepad) |  |

## Build 2: bags, character panel and the ground

| | Check | Evidence |
|---|---|---|
| ✅ | Bags and the character panel open separately (WoW-style) | backpack button and character button on the bottom bar |
| ✅ | A bag dragged into a bag slot adds its slots | free slots 13 → 22 (+8, and the satchel left the backpack); 2 bag windows |
| ✅ | Dragging an item from the bag onto the character panel equips it | helm on the head slot and on the model; maximum health 106 |
| ✅ | Dragging it back from the character panel into a bag unequips it | helm now in the satchel's 4th slot; maximum health 100 |
| ✅ | Items only fit the slots they belong in (extra) | helm dropped on the main-hand slot was refused |
| ✅ | Each bag opens and closes on its own, and two open bags do not freeze the game | game time advanced 0.30s with both bags and the character panel open; closing the backpack left: Traveller's satchel |
| ✅ | Dragging an item out of the bag drops it on the ground (RuneScape-style) | helm lies 0.90m from the Warden and is shown in the world |
| ✅ | A dropped item can be picked up again from the ground | prompt "Pick up Dented watch helm" |
| ✅ | Dropped items stay on the ground after saving and reloading | [{"uid":1,"id":"watch_helm","count":1,"x":-5.24,"z":27.51}]; satchel still in its bag slot |
| ✅ | Picking it up removes it from the world and the save (extra) |  |
| ✅ | A full bag leaves loot where it lies (extra) | "Your bags are full." |
| ✅ | Saves from before shields existed get the kite shield (extra) | off hand: kite_shield |
| ✅ | Saves from build 1 are upgraded on load | wielding watchmans_edge; bag holds healing_draught, worn_longsword, manifest, grave_iron, travelling_clothes, watchmans_edge, kite_shield; 21 coins |
| ✅ | No script errors (bags and ground) |  |

## Build 2: editing the spell bar

| | Check | Evidence |
|---|---|---|
| ✅ | Spells can be dragged to another slot on the bar | Lunge moved from slot 1 to slot 3 (bar was lunge, draught, , , strike, shieldBreak, brace) |
| ✅ | A moved spell fires from its new key | key 3 now lunges; key 1 does nothing |
| ✅ | Spells can be removed from the bar by dragging them off it | bar: —, draught, —, —, strike, shieldBreak, brace |
| ✅ | The spellbook (P) puts removed spells back on the bar | Lunge dragged from the spellbook to slot 4 (key 4) |
| ✅ | Swapping two spells swaps their keys (extra) | Brace on left click, Strike on Space |
| ✅ | The bar layout is saved | —, draught, —, lunge, brace, shieldBreak, strike |
| ✅ | Old saves with Dodge on the bar get Brace instead (extra) | lunge, draught, —, —, strike, shieldBreak, brace |
| ✅ | The spell bar can be edited with a gamepad | D-pad up opened the spellbook; A carried strike to slot 3; Y removed it; B closed |
| ✅ | No script errors (spell bar) |  |

## Controls, targeting and looting

| | Check | Evidence |
|---|---|---|
| ✅ | One control scheme: no mode switch on the title screen | 1 controls table, mode button gone |
| ✅ | The spell bar keeps the mouse buttons, with Space as the defensive slot | slots: 1 / 2 / Q / 3 / 4 / LMB / RMB / Space |
| ✅ | The camera is fixed (no free rotation) | camera holds its isometric offset; W moved (0.00, -5.00), straight up the screen |
| ✅ | Soft lock: a strike aimed roughly at an enemy hits it | aimed 40° off the ghoul: 48 → 30; a faint ring marked it, nothing hard-locked |
| ✅ | Soft lock does not reach behind you | aimed the other way: ghoul untouched (48) |
| ✅ | Lunge (and any targeted spell) goes to the soft-locked enemy | aimed near the ghoul: charged 4.90m east, ghoul 48 → 21 |
| ✅ | Tab hard-locks the enemy you aim at; Tab again releases | locked ghoul_cart (frame "Ashen Ghoul", red ring), then released |
| ✅ | A hard lock keeps the Warden facing the target and strikes it wherever the cursor is | facing 0° (towards the ghoul); clicked off to the west: ghoul 48 → 30 |
| ✅ | Escape releases the lock |  |
| ✅ | A defeated target is let go (extra) |  |
| ✅ | R3 locks and releases on a gamepad; X strikes the locked enemy | locked ghoul_road; right stick pushed away, X still hit it (48 → 30); R3 again released |
| ✅ | One press of E loots every body and drop nearby | prompt "Pick up Grave-iron bar (and 2 more nearby)"; +6 coins from two ghouls and the grave iron back in the bag |
| ✅ | Looted bodies sink away (extra) |  |
| ✅ | Clicking a body loots it and everything close by (no swing) | real left click on a body: 14 → 20 coins (both bodies) |
| ✅ | Clicking a body out of reach says so | "Too far away to loot that." |
| ✅ | Clicking open ground is the basic attack | a click away from any body swings the sword |
| ✅ | Gamepad A loots the area too | 20 → 26 coins from two bodies |
| ✅ | World objects such as the manifest are not swept up by area looting | looting a body beside the manifest took 1 thing; manifest still there |
| ✅ | No script errors (controls and looting) |  |

## Stats, damage and damage numbers

| | Check | Evidence |
|---|---|---|
| ✅ | The character panel shows attributes and combat stats | Level 1 Warden, Health 100 / 100, Might 4, Finesse 2, Intellect 1, Vitality 10, Weapon Worn longsword (12–16), Strike 16–20, Shield Break 32–40, Lunge 24–30, Critical chance 6.0%, Haste 0% (swing 0.60s, GCD 1.50s), Armour 20 (−29%), Block 10%, stops 30%, Block rating 0, Resistance 0 (−0%), Wears Cloth, Leather, Mail, Plate, shields |
| ✅ | Weapon hits roll within the weapon range plus power | lowest roll 16, highest 20, average 18 (worn longsword 12–16, +4 from Might) |
| ✅ | Hits show a damage number over the enemy | [{"text":"18","cls":"dmg dealt"}] |
| ✅ | Critical hits do 150% and show a distinct number | 27 damage, number "27!" (dmg dealt crit); log: "You strike the Ashen Ghoul for 27. A critical blow!" |
| ✅ | Armour reduces the damage an enemy takes | average strike 18 on the Brute (10 armour): 15 |
| ✅ | Armour reduces the damage the Warden takes | a ghoul's 11: 8 in travelling clothes (20 armour), 11 without |
| ✅ | Hits taken show a red number | [{"text":"8","cls":"dmg taken"}] |
| ✅ | Enemy blows vary a little either side of their damage (extra) | lowest 7, highest 9 (±15% before armour) |
| ✅ | A shield block stops 30% of a melee blow | 8 with 30% blocked: 6; number "6 (2 blocked)"; log "The Ashen Ghoul hits you for 6 (2 blocked)." |
| ✅ | Enemies can crit too, shown as a distinct number | 12 damage; "The Ashen Ghoul critically hits you for 12." |
| ✅ | Block chance comes from the shield and block rating, capped at 50% | kite shield 10%, no shield 0%, +50 rating 15%, +400 rating 50%; shield worn on the left arm |
| ✅ | Grave Slam cannot crit or be blocked | lowest roll of 31 after armour: 20; "The Grave Slam hits you for 20." |
| ✅ | Heals show a green number; numbers fade after about a second | "+42", 0 numbers left 1.3s later |
| ✅ | Enemy health shows in the target frame without locking on | aiming at a wounded ghoul: "Ashen Ghoul" 30 / 48 (Level 1), bar over its head; no mana bar |
| ✅ | Enemies with mana show a mana bar too | target frame mana "20 / 30", blue bar under its health |
| ✅ | Stat formulas are driven by config (extra) | crit chance 6% → 11% with critBase 5 → 10 |
| ✅ | Armour stops less against higher-level enemies | a 20-damage blow: 14 from a level 1 foe (29% off), 16 from a level 5 foe (20% off) |
| ✅ | Armour types limit what an archetype can wear | mail helm on a cloth-and-leather wearer: "A Warden cannot use mail armour."; the Warden (all types) wears it |
| ✅ | Haste shortens swings, windups and the global cooldown | 20% haste: swing 0.6s → 0.50s, GCD 1.5s → 1.25s; 80% is capped at 30% (GCD 1.15s, floor 1s) |
| ✅ | Level-up shows each stat increase | Might 4 → 6 +2 / Vitality 11 → 13 +2 / Maximum health 106 → 118 +12 / Strike 16–20 → 18–22 +2 |
| ✅ | The character screen marks what rose at the last level-up | health+12, might+2, vitality+2, strike+2 |
| ✅ | No script errors (stats and damage) |  |

## Item database

| | Check | Evidence |
|---|---|---|
| ✅ | Every item comes from one database with slot, stats, price and icon | 9 items in src/data/items.json, all valid |
| ✅ | The database check catches a malformed item (extra) | broken_blade: unknown quality shiny; broken_blade: price must be a whole number of coins; broken_blade: a weapon needs damage [min, max] |
| ✅ | Tooltips show what a merchant would pay, and the item quality | Healing draughtConsumableA small bottle of something bitter and red. Restores 42 health.Sells for 1 coinRight-click to drink |
| ✅ | Quest items cannot be dropped (extra) | "You keep hold of the Carriage manifest. Someone will want it." |
| ✅ | No script errors (item database) |  |

## Build 2: fog and lighting

| | Check | Evidence |
|---|---|---|
| ✅ | View-distance fog fades the world out with distance | linear fog 14–40m in the sky colour; nothing drawn past 46m |
| ✅ | Atmospheric lighting: a warm light on the Warden, braziers and ground mist | 2 braziers at the watch post, 8 mist layers |
| ✅ | No script errors (atmosphere) |  |

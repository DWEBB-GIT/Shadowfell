# Stats and damage: design note

Status: approved by Dan and built. The attributes and the damage formula were approved on 2026-10-14. Armour by your own level, growth by level, item stat budgets, enemy types and the level-gap rule were approved on 2026-10-15 (the proposal and its working are in `design/armour-and-item-budget.md` in the project files).

Where the numbers live:

- `src/config.js` (`stats`): the constants that do not grow with level, such as health per Stamina, power per Strength, the crit multiplier, the caps and the block reduction.
- `src/data/scaling.js` (`SCALING`, also `CONFIG.scaling`): everything that grows with level, and the formulas that turn an item's level, slot and rarity into its numbers, and an enemy's level and type into its.
- `data/items.json`: each piece of gear states its item level, slot, armour type, rarity and stat split. `data/enemies.json`: each enemy states its level and type. The game works out the rest.

A balance pass changes a constant, not every item and enemy.

## In short

- **Four attributes:** Strength, Agility, Intellect and Stamina.
  - Each archetype has a main attribute that feeds its damage; the Warden's is Strength.
  - Stamina gives everyone health.
- **One growth line:** everything that gets bigger with level grows in a straight line with **n = level + 4**. That covers the armour constant, the armour on items, every item's stat budget, weapon damage, player spells, and the enemy table's health and hits. Level 1 is 5, level 10 is 14 and level 40 is 44.
- **Armour** reduces damage by armour ÷ (armour + 400 + 100 × your own level), capped at 75%. The reduction on the character panel is what you get against everyone.
- **Level gaps:** every hit is ×1.2 for each level the attacker is above its target, and ÷1.2 for each level below. A level 40 takes 1 damage a hit in a level 10 zone; a level 10 in a level 25 zone dies in a few hits.
- **No world scaling:** an enemy's health, damage and armour come from its own level and type, never from yours.
- **Items are worked out, not hand-typed:** armour, weapon damage, a shield's block chance and the stat points come from item level, slot, armour type and rarity.
- **Left out on purpose:** hit chance and misses, dodge and parry, and penetration. Avoiding damage is the player's job (telegraphs and the defensive button), so tanks stack armour, block and Stamina.
- **Resources:** health, plus one resource per archetype. The Warden has none; a caster would have mana from Intellect. Enemies can have mana too, shown as a blue bar.
- **Damage numbers** float up from whoever is hit. They stay small, serif and muted: dealt in parchment white, taken in dull red, crits larger and amber with a "!", blocks show how much was stopped, heals in green.

## The stats

| Stat | Comes from | What it does |
|---|---|---|
| Strength | Archetype, level, gear | The Warden's main attribute: 0.25 power a point |
| Agility | Archetype, level, gear | Crit chance: 1% per 0.4 × (level + 4) Agility (0.5% a point at level 1); a rogue's main attribute later |
| Intellect | Archetype, level, gear | 0.25 spell power and 10 mana a point (mana for archetypes that use it) |
| Stamina | Archetype, level, gear | 40 health + 6 a point |
| Weapon damage | Main hand | A min–max range per swing, from the weapon's item level, rarity and speed |
| Power | Main attribute | Added to every ability hit, and to every swing in proportion to the weapon's speed |
| Spell power | Intellect | Added to every spell hit |
| Crit chance | 5% + Agility ÷ (0.4 × (level + 4)) | Chance of a critical hit, which does 150% |
| Armour | Gear | Physical reduction = armour ÷ (armour + 400 + 100 × your level), capped at 75% |
| Resistance | Gear (later) | The same curve, against spells |
| Block chance | A shield (10% of its own), plus block chance on gear | Chance to stop 30% of a melee blow, capped at 50%. Brace is a guaranteed full block |
| Haste | Gear only | Shortens the time between swings (T = W ÷ (1 + H)), ability windups, casts and the global cooldown (floor 1 s), capped at 30%. The swing animation keeps its own timing |

## The formula

```
auto attack swing = roll(weapon min..max) + power × weapon speed ÷ 0.6
weapon ability    = (roll(the weapon's damage over 0.6 s) + power) × ability multiplier
spell             = roll(spell min..max) × (level + 4) ÷ 5 + spell power
enemy blow        = the enemy's damage × (1 ± 15%)

then, for every hit:
  × 1.2 ^ (attacker's level − target's level)        the level gap
  crit?    × 1.5
  defence  × (1 − armour or resistance %)            K from the defender's own level
  block?   − 30% (melee blows only; Grave Slam cannot be blocked, only Braced)
  round; at least 1 unless fully blocked
```

Ability multipliers: Shield Break 2.0, Lunge 1.5, Cleave 1.2, Rend 0.45 a tick. Enemies' normal attacks can crit; Grave Slam cannot.

## The swing timer

Dan's formula (2026-10-15):

```
T = W ÷ (1 + H)
T  seconds between swings
W  the weapon's speed
H  haste as a fraction (20% = 0.20), gear only, capped at 0.30
```

| Haste | 2.5 s weapon | Swings a minute |
|---|---|---|
| 0% | 2.500 s | 24.0 |
| 10% | 2.273 s | 26.4 |
| 20% | 2.083 s | 28.8 |
| 30% (cap) | 1.923 s | 31.2 |

Auto attack is three separate parts, timed the way WoW times them: the swing timer bar fills at the moment the blow lands.

1. **The swing clock** (`player.cooldowns.attack`) counts down, on delta time, to the moment of the next blow, so the rhythm is the same at 30, 60 or 144 fps. When a blow lands the clock restarts at T. If it ran out partway through a frame, the overshoot (up to 0.25 s, `catchUp` on Attack in `data/abilities.json`) comes off the next interval, so a slow frame keeps the beat without a burst.
2. **The animation** (0.8 s, impact frame 0.32 s in) starts 0.32 s *before* the clock runs out, so its impact frame and the hit are the same moment. It only starts if the target is in reach and in front of you. Haste does not speed it up.
3. **The damage** resolves at the impact frame, when the clock runs out. Reach and target are checked then: if the target has stepped out of reach there is no blow, the swing is called off, and the clock waits at zero. You swing the moment you are back in reach (a short 0.12 s windup, `readyWindup`), then every T. Moving does not cancel a swing.

When the clock starts: as in WoW, a fresh fight opens the moment you reach the target, nothing runs while you close in, and the first blow registers at once (damage and swing clock, as WoW's server does) but is *shown* after a weighty **opening windup** (0.3 s, `openerWindup`; Dan, 2026-10-17): the flinch, knockback, damage number and hit-stop wait for the animation's impact frame. Switching target mid-fight keeps the running clock. A cast drops a swing in progress and restarts the clock when it ends, and charges such as Lunge hold the clock until they land. Stopping auto attack before a blow lands calls it off.

### Combat feel, as in WoW

- **No animation lock.** Swings, shots and abilities play on the upper body; you move at full speed through all of them. Only a charge (Lunge) carries you, and moving breaks a cast.
- **Nothing eats a key press.** A swing or shot on its way never blocks an ability; only another cast, a charge in flight or the global cooldown does. Instant abilities do not touch the swing timer. Cleave and Shield Break land at their own impact frame without delaying your next swing.
- **Spell queue.** An ability pressed in the last 0.4 s of the global cooldown (or of its own cooldown) goes off the moment it can, with no error (`spellQueueWindow` in `data/abilities.json`).
- **Facing.** Swings and shots need the target within the front 180° (`coneDegrees`). While you fight, you keep the target in front of you as you move (strafing), so attacks carry on; standing still you turn to it.
- **Melee leeway.** While you and the target are both moving, melee reach stretches by 1 m (`movingLeeway`), so a chase does not drop swings.
- **Casts.** A cast bar, broken by moving. Each hit taken while casting sets it back 0.5 s, at most twice (Classic pushback: `castPushback`, `maxPushbacks`). Bolts home in on the target and hit on arrival.

### Bows and Auto Shot

A bow goes in the **ranged** slot (any class, as in WoW; Mara sells a hunting bow, 2.8 s, 20 m). While auto attack is on and the target is beyond melee reach but within the bow's range, **Auto Shot** looses an arrow each time the ranged clock (`cooldowns.ranged`, T = bow speed ÷ (1 + haste)) runs out. The draw starts early, so the arrow leaves the string as the clock runs out; it homes in on the target at 30 m/s and does its damage on arrival. You must stand still to shoot (WoW Classic; Dan, 2026-10-16, because shooting on the move made melee pointless): moving calls off a draw and holds Auto Shot until you stop. A bow is a pulling weapon for the Warden: bows have half a melee weapon's weapon damage (`rangedDamage` 0.5 in scaling.js), and ranged power comes from Agility at half the main-stat rate (`rangedPowerShare`), never from Strength. The hunting bow reaches 20 m. When the target comes into melee reach the sword takes over; when it leaves, the bow does. The swing bar shows whichever is in use. The bow rides on your back and comes to the left hand to shoot.

**Arrows** (Dan, 2026-10-16: Classic style, with a quiver). Each shot uses one arrow; with none, Auto Shot does not fire and the log says so. Arrows (`kind: "ammo"`) stack to 200 and are sold by the hundred (`buyCount`): rough arrows (1 silver, Mara and Tam) and barbed arrows (6 silver, Tam). Each adds `ammoDps` damage for every second of bow speed (rough +0.25, barbed +0.75). Auto Shot uses the best arrows you carry. A **quiver** (Tam, 25 silver) goes in a bag slot like a bag, holds only arrows (`holds: "ammo"`, six stacks), takes new arrows first, and makes Auto Shot 10% faster (`rangedHaste`, on top of haste).

**Bow abilities** (2026-10-16, for testing the bow). Abilities with `ranged: true` are bow shots: they need a bow in the ranged slot and an arrow, reach as far as the bow, use one arrow, and land when the arrow arrives. They don't touch the Auto Shot clock (as WoW's Arcane Shot). Their damage is a bow roll plus the arrow's damage. **Quick Shot**: instant, 120% of a bow shot, 6 s cooldown, 10 mana. **Venom Arrow**: an instant nature poison, 30% of a bow shot every 3 s for 15 s, 15 mana; using it again refreshes it. Both go onto free bar slots (keys 6 and 7) the first time a bow is equipped.

### Dual wielding

A one-handed weapon (`slot: "oneHand"`) goes in either hand; the off hand takes one only for a class with `dualWield` in `data/archetypes.json` (the Warden can). As in modern WoW:

- **Each hand has its own swing clock** (`cooldowns.attack` and `cooldowns.attackOff`), at its own weapon's speed and the same T = W ÷ (1 + H), its own animation (the left arm) and its own impact frame. A sword at 2.4 s and a dirk at 1.6 s swing 25 and 37.5 times a minute.
- **Staggered:** when a fight opens, the off hand's first blow comes half a main-hand swing after the main hand's. After that, the off hand never lands within 0.2 s of a main-hand blow (`staggerGap` on Attack); if it would, its clock is pushed back to just after that blow. The main hand is never held.
- **Off-hand penalty:** off-hand blows do 50% damage (`offHandDamage` in `src/config.js`), knock back half as far and build half the Resolve.
- Abilities use the main-hand weapon. Casting drops both swings in progress; charges hold both clocks.
- **Budget:** a one-hand weapon weighs 0.75 of a slot, so two of them carry the same stat points as a main-hand weapon (1) and a shield (0.5). Damage per second is the same formula as any weapon of its item level.

| One-handers | Item level | Speed | Damage a swing |
|---|---|---|---|
| Arming sword (white) | 2 | 2.4 s | 4–9 |
| Rusty dirk (white) | 2 | 1.6 s | 3–6 |
| Militia sword (green, +Strength) | 4 | 2.5 s | from the formula |
| Ghoulbone knife (green, +Agility, +haste) | 4 | 1.7 s | from the formula |

Mara sells the arming sword and the dirk; ghouls drop dirks and the ghoulbone knife, archers arming and militia swords.

## One growth line

Everything that should get bigger with level grows with **(level + 4)**. Percentages, the crit multiplier, cooldowns, weapon speeds, ranges and movement do not grow. Level gaps are the one place that works by a percentage per level, because a gap should feel steep.

- **Numbers stay small.** A level 60 Warden has 800 to 1,600 health and swings its sword for about 38 to 89 plus Strength.
- **Steepness is tuned on its own.** A percentage per level on everything (+8% a level) would put level 60 at about 90 times level 1; a straight line gives 13 times, and the gap rule sets how steep levels feel. Either can change without the other.
- **The cost:** early levels are bigger steps than late ones (level 1 to 2 is +20%, level 40 to 41 is +2%), so a gap bites a little harder at level 10 than at level 40. That suits short early zones.

## Armour

```
K                = 400 + 100 × your own level          (= 100 × (level + 4))
damage reduction = armour ÷ (armour + K), at most 75%
effective health = health × (1 + armour ÷ K)
```

- **Effective health rises in a straight line:** every K ÷ 100 points of armour add 1% effective health, at any amount of armour, so armour needs no soft cap.
- **Why the +400:** without it, K doubles from level 1 to level 2 and armour loses half its worth in one level.
- **Whose level:** the defender's own. Against a same-level enemy it makes no difference; with it, the panel's number is the number, and level gaps are one separate rule. An enemy's armour works the same way, with the enemy's level.
- **The scale:** armour numbers are 10 times the first build's (the travelling clothes have 30), so rolls and upgrades move in visible steps.
- **The cap** (75%, four times effective health) only stops someone in gear far above their level from becoming immune. On-level plate and shield is 50%.
- **Resistance** works the same way against spells, with the same K.

| Your level | K | 250 armour | 500 | 1,000 | 2,000 | 4,000 |
|---|---|---|---|---|---|---|
| 1 | 500 | 33% | 50% | 67% | 75% (cap) | 75% (cap) |
| 10 | 1,400 | 15% | 26% | 42% | 59% | 74% |
| 20 | 2,400 | 9% | 17% | 29% | 45% | 63% |
| 40 | 4,400 | 5% | 10% | 19% | 31% | 48% |
| 60 | 6,400 | 4% | 7% | 14% | 24% | 38% |

## Items

Each piece of gear in `data/items.json` states:

- `itemLevel`: the level of the place or enemy it comes from (rarer items may sit a level or two above);
- `slot`, `armourType` and `rarity`;
- `speed`, for a weapon;
- `statSplit`, how its stat points are shared, e.g. `{ "strength": 1, "stamina": 1 }` (shares, not points).

The game works out everything else (`scaledItem` in `src/data/scaling.js`). A special item can still state an exact `damage`, or a stat in `stats`; `npm run validate` refuses an item more than 10% over its budget unless it is marked `budgetException`, and prints each item's budget against what it spends. Anyone can wear any item level for now. Dropped gear still rolls a little either side of these numbers.

### Slots

One weight per slot sets both an item's armour and its stat points. A full set weighs 10.

| Slot | Weight | Armour |
|---|---|---|
| Head, chest, legs | 1 | Yes |
| Main hand (one-handed) | 1 | No: weapon damage |
| Shoulders, hands, waist, feet | 0.75 | Yes |
| Wrists | 0.5 | Yes |
| Back (cloak) | 0.5 | A little, the same for every wearer |
| Neck, each of two rings | 0.5 | No |
| Off hand: shield or torch | 0.5 | A shield: armour and block |
| Two trinkets | 0 | Effects only, outside the budget |
| Two-handed weapon (later) | 1.5 | No: 1.3 × one-handed damage |

A helm is worth a third more than a belt and twice a cloak.

### Armour on items

```
armour = type factor × slot weight × (item level + 4) × rarity's main multiplier
type factor: cloth 3, leather 6, mail 9, plate 12
cloak  = cloth for every wearer
shield = 20 × (item level + 4) × rarity's main multiplier, plus a 10% block chance
```

The factors make a full on-level set give the same reduction at every level:

| Full on-level set | Damage reduction | Effective health |
|---|---|---|
| Cloth | 17% | +21% |
| Leather | 29% | +41% |
| Mail | 38% | +60% |
| Plate | 44% | +80% |
| Plate and shield | 50% | +100% |

Each heavier type adds about 20% effective health, and a shield another 20%; archetypes limit which types they wear. Gear you have out-levelled loses ground: plate and shield from 10 levels ago gives 37% at level 20 and 43% at level 40.

Armour per piece at item levels 10 and 40 (white or green):

| Slot | Cloth 10 | Leather 10 | Mail 10 | Plate 10 | Cloth 40 | Leather 40 | Mail 40 | Plate 40 |
|---|---|---|---|---|---|---|---|---|
| Head, chest, legs | 42 | 84 | 126 | 168 | 132 | 264 | 396 | 528 |
| Shoulders, hands, waist, feet | 32 | 63 | 95 | 126 | 99 | 198 | 297 | 396 |
| Wrists | 21 | 42 | 63 | 84 | 66 | 132 | 198 | 264 |
| Back | 21 | 21 | 21 | 21 | 66 | 66 | 66 | 66 |

A shield has 100 armour at item level 1, 280 at 10 and 880 at 40.

### Rarity and the stat budget

```
stat points = 0.4 × slot weight × (item level + 4) × rarity budget
```

| Rarity | Budget | Main multiplier (armour, weapon damage, a shield's block) |
|---|---|---|
| Common (white) | 0: no stats | ×1 |
| Enhanced (green) | ×1 | ×1 |
| Rare (blue) | ×1.3 | ×1.1 |
| Epic (purple) | ×1.6 | ×1.2 |
| Legendary (orange) | ×2 | ×1.3 |

A green is a white item with a suffix spending the green budget: common gear that drops at the Enhanced rarity gets a suffix such as *of the Bear*, whose stats share that budget (each ±20%, at least 1).

| Item level | Weight 1: green | blue | purple | Weight 0.75: green | blue | purple | Weight 0.5: green | blue | purple |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 2.0 | 2.6 | 3.2 | 1.5 | 2.0 | 2.4 | 1.0 | 1.3 | 1.6 |
| 5 | 3.6 | 4.7 | 5.8 | 2.7 | 3.5 | 4.3 | 1.8 | 2.3 | 2.9 |
| 10 | 5.6 | 7.3 | 9.0 | 4.2 | 5.5 | 6.7 | 2.8 | 3.6 | 4.5 |
| 20 | 9.6 | 12.5 | 15.4 | 7.2 | 9.4 | 11.5 | 4.8 | 6.2 | 7.7 |
| 40 | 17.6 | 22.9 | 28.2 | 13.2 | 17.2 | 21.1 | 8.8 | 11.4 | 14.1 |
| 60 | 25.6 | 33.3 | 41.0 | 19.2 | 25.0 | 30.7 | 12.8 | 16.6 | 20.5 |

A full set of on-level greens gives 4 × (level + 4) points, about what the Warden's own levels give.

What a point buys:

| Stat | Cost |
|---|---|
| Strength, Agility, Intellect, Stamina | 1 point each |
| Bonus armour or resistance (beyond the item's own) | 1 point per 50 |
| Haste | (item level + 4) ÷ 15 points per 1% |
| Block chance | (item level + 4) ÷ 50 points per 1% |

Percentages are priced by item level, so an item gives about the same percentage at any level: a green helm that spends everything on haste gets 6% at level 10 and at level 40. An effect (a proc, an aura) is paid from the same budget: a small one about a quarter of the points, a strong one half.

Examples: a level 10 green mail chest *of the Bear* has 126 armour, +3 Strength and +3 Stamina; a level 40 green leather belt has 198 armour and 13.2 points (say +7 Agility, +6 Stamina); a level 42 purple plate chest has 662 armour and 29.4 points.

### Weapons

```
damage a second = 0.45 × (item level + 4) × rarity's main multiplier
one swing       = damage a second × the weapon's speed, ±40%
abilities use the weapon's damage over 0.6 s, so they hit the same with any speed
```

| Item level | Damage a second (white or green) | A 2.2 s swing | A 2.8 s swing | Blue, a second | Purple, a second |
|---|---|---|---|---|---|
| 1 | 2.25 | 3–7 | 4–9 | 2.5 | 2.7 |
| 5 | 4.05 | 5–12 | 7–16 | 4.5 | 4.9 |
| 10 | 6.3 | 8–19 | 11–25 | 6.9 | 7.6 |
| 20 | 10.8 | 14–33 | 18–42 | 11.9 | 13.0 |
| 40 | 19.8 | 26–61 | 33–78 | 21.8 | 23.8 |
| 60 | 28.8 | 38–89 | 48–113 | 31.7 | 34.6 |

A slow weapon swings harder and a quick one more often, for the same damage over a fight. Dan's 3–7 starting sword (2.2 s) sets the scale.

### Percentage stats

- **Haste** (gear only, cap 30%) reads "+X% haste" on gear. A full set of greens could reach the cap by spending half its points on it.
- **Block** (cap 50%): every shield has 10% of its own (more on blue and up), and more comes from gear as "+X% block chance". Block rating is gone: a fixed "10 rating = 1%" cannot survive budgets that grow with level, and pricing block chance by item level reads more simply.
- **Crit** = 5% + Agility ÷ (0.4 × (character level + 4)), so an Agility character keeps about the same crit as it levels. The Warden stays near 5%.
- **Fixed percentages, not WoW-style ratings:** a rating that converts by your level shrinks every time you level ("my haste went down"). A fixed "+4% haste" means what it says for ever.
- **Strength and spell power:** each point of Strength gives 0.25 power and each point of Intellect 0.25 spell power. That makes Strength about 40% of a level 1 Warden's damage and about 60% from level 10 on, close to how attack power works in WoW.

## What a Warden looks like by level

Each pair is **par** (its own attributes and white gear) / **with a full set of on-level greens**, split evenly between Strength and Stamina. Auto attack is an on-level weapon's damage a second plus Strength ÷ 2.4, before crits. Armour is on-level plate and shield.

| Level | Strength | Stamina | Health | Auto attack a second | Armour | Reduction |
|---|---|---|---|---|---|---|
| 1 | 4 / 14 | 10 / 20 | 100 / 160 | 3.9 / 8.1 | 498 | 50% |
| 5 | 12 / 30 | 18 / 36 | 148 / 256 | 9.1 / 16.6 | 896 | 50% |
| 10 | 22 / 50 | 28 / 56 | 208 / 376 | 15.5 / 27.1 | 1,393 | 50% |
| 20 | 42 / 90 | 48 / 96 | 328 / 616 | 28.3 / 48.3 | 2,388 | 50% |
| 40 | 82 / 170 | 88 / 176 | 568 / 1,096 | 54.0 / 90.6 | 4,378 | 50% |
| 60 | 122 / 250 | 128 / 256 | 808 / 1,576 | 79.6 / 133.0 | 6,368 | 50% |

From level 10 up, a full set of greens adds about 70% to damage and 80–95% to health.

## Enemies

### No world scaling

An enemy's health, damage and armour come from its own level and its type, and never look at the player: a level 10 ghoul is the same whether a level 5 or a level 50 walks up to it. A high-level character crushes a low zone, and a low-level one dies in a high zone, through the level-gap rule.

Each level's **normal** enemy is sized once against **par**, a character of that level with only its own attributes (the Warden's) and white gear. Par is a yardstick for writing the table, not something the game reads in play; anything better is the player's edge.

```
par damage   = an on-level white weapon's damage a second + Strength ÷ 2.4   (3.9 a second at level 1)
par health   = 40 + 6 × Stamina                                             (100 at level 1)
normal enemy = the health of 7 seconds of par damage, a hit of par health ÷ 12, a blow every 1.35 s
```

| Level | Par damage a second | Par health | Normal: health / hit | Elite: health / hit / special | Heavy (ogre): health / hit / special |
|---|---|---|---|---|---|
| 1 | 3.9 | 100 | 27 / 8 | 47 / 11 / 25 | 110 / 25 / 50 |
| 5 | 9.1 | 148 | 63 / 12 | 108 / 17 / 37 | 253 / 37 / 74 |
| 10 | 15.5 | 208 | 108 / 17 | 184 / 24 / 52 | 433 / 52 / 104 |
| 20 | 28.3 | 328 | 198 / 27 | 337 / 38 / 82 | 792 / 82 / 164 |
| 40 | 54.0 | 568 | 378 / 47 | 642 / 65 / 142 | 1,511 / 142 / 284 |
| 60 | 79.6 | 808 | 557 / 67 | 948 / 93 / 202 | 2,230 / 202 / 404 |

Hits are before the player's armour.

### Enemy types

Each enemy in `data/enemies.json` has a `type`, which multiplies its level's normal enemy (`scaledEnemy` in `src/data/scaling.js`). Each spawn point's enemy has its own health within ±10% of its type's (fixed per spawn point, so a lean hound stays lean), on top of the ±15% every blow varies by. Any number stated in the record wins: the seer keeps its caster's staff and its own spells.

| Type (`type`) | Health | Hit | A blow every | Armour | Danger | In the game |
|---|---|---|---|---|---|---|
| Fodder (`fodder`) | ×0.5 | ×0.5 | 1.35 s | None | 0.25 | None yet |
| Pack beast (`pack_beast`) | ×0.6 | ×0.6 | 0.95 s | None | 0.5 | Barrow Hound |
| Normal (`normal`) | ×1 | ×1 | 1.35 s | None | 1 | Ashen Ghoul |
| Skirmisher (`skirmisher`): fragile, hits hard, often ranged | ×0.6 | ×1.75 | 2.5 s | Light | 0.6 | Hollow Archer |
| Armoured (`armoured`) | ×1.25 | ×1 | 1.35 s | Heavy | 1.75 | None yet |
| Elite (`elite`) | ×1.7 | ×1.375 | 1.2 s | Armoured | 3.2 | Gravebound Brute, Blackwood Seer |
| Heavy, an ogre (`heavy`) | ×4 | ×3 | 2.2 s | Armoured | 8.8 | None yet |
| Boss (`boss`) | ×15 and up | Designed per fight | | Armoured | | None yet |

- **Armour** is a share of K at the enemy's own level: light 0.1 × K (9% reduction), armoured 0.2 × K (17%), heavy 0.4 × K (29%). An enemy can name its own `armourClass`.
- **Specials:** an elite's or heavy's telegraphed special is sized from par health, not its own hit: a quarter for an elite (31 for the brute's Grave Slam at level 3), half for a heavy. Half a par character's health in one blow wants a ground telegraph and a dodge.
- **Aimed shots** hit for the type's hit at the type's speed unless the record says otherwise.
- **A boss** states its own hits and attack speed.

### Danger and packs

**Danger** is how much a type hurts compared with a normal enemy of its level: its health times its damage a second, with armour counted as extra health. A pack costs more than its parts, because the others keep hitting while you kill the first: a pack of n costs n(n+1)/2 times one of them.

| Group | Danger |
|---|---|
| 4 pack beasts (wolves) | 5.1 |
| 6 pack beasts | 10.7 |
| 8 fodder | 9.0 |
| 3 normals | 6.0 |
| 4 normals | 10.0 |
| 2 elites | 9.5 |
| 1 heavy (ogre) | 8.8 |
| 2 heavies | 26.5 |

**Capacity** is how much danger a character can take before it dies, using its auto attack and abilities. Because everything grows on one line, it is the same at every level: a par character in cloth 9.8, in leather 11.4, a par Warden in plate and shield 16.2, and the same Warden in full on-level greens 40 to 45. Brace and potions add to it.

The most you can pull at once and win:

| Type | Par, cloth | Par Warden, plate and shield | Full greens, plate and shield |
|---|---|---|---|
| Fodder | 8 | 10 | 17 |
| Pack beast | 5 | 7 | 12 |
| Normal | 3 | 5 | 8 |
| Skirmisher | 5 | 6 | 11 |
| Armoured | 2 | 3 | 6 |
| Elite | 2 | 2 | 4 |
| Heavy (ogre) | 1 | 1 | 2 |

So a par Warden in plate beats a pack of four wolves for a quarter to a third of its health, or one ogre for about half, and two ogres kill anyone not in full greens.

### Fight length

The first swing waits for the weapon's speed, so a fight opens with Shield Break and Cleave and the first swing lands 2.2 s in. A par Warden in plate and shield (an on-level white sword, Shield Break, then Cleave, then Rend on each global cooldown) against enemies of its own level; each cell is how long the fight lasts and the share of your health it costs:

| | One normal | 4 wolves | 6 wolves | One elite | One ogre | Two ogres |
|---|---|---|---|---|---|---|
| Par Warden, plate and shield | 4.8 s, 16% | 8.8 s, 57% | you die | 8.8 s, 40% | you die | you die |
| Par character in cloth (health cost) | 27% | 95% | you die | 66% | you die | you die |

Raised on 16 Oct 2026 (Dan: too easy even at the start) from 4.5 s and ÷ 18, when one normal enemy cost 8% of your health. The heavy type (no ogre is in the game yet) is now more than one par character can take, so its multipliers want a look when the first ogre arrives.

Fight length and danger are one pair of numbers, `enemyHealthSeconds` and `enemyHitShare`.

### Level gaps

```
damage × 1.2 ^ (attacker's level − target's level)
```

An enemy 5 levels above you hits 2.5 times as hard and takes 2.5 times as long to kill; one 5 levels below does the reverse. A hit always does at least 1 damage.

A par Warden in plate and shield, with its abilities, against one normal enemy. Each cell is its hits to kill you / the seconds you need to kill it, then the share of your health the fight costs. These figures are from before the 16 Oct raise; every enemy now has about 1.55 times the health and 1.5 times the hit, so each fight costs about 2.3 times the share shown:

| Enemy | Its hits on you | Level 10 Warden | Level 20 | Level 40 |
|---|---|---|---|---|
| 10 below | ×0.16 | | 328 / 0.3 s, 0% | 282 / 0.4 s, 0% |
| 5 below | ×0.4 | 126 / 0.7 s, 0% | 109 / 0.9 s, 1% | 100 / 1.1 s, 1% |
| 3 below | ×0.58 | 75 / 1.3 s, 1% | 70 / 1.5 s, 2% | 66 / 1.6 s, 2% |
| Same level | ×1 | 36 / 3.0 s, 6% | 36 / 3.0 s, 6% | 36 / 3.0 s, 6% |
| 3 above | ×1.7 | 18 / 6.4 s, 27% | 19 / 5.9 s, 23% | 20 / 5.5 s, 21% |
| 5 above | ×2.5 | 11 / 10 s, 69% | 12 / 9.1 s, 55% | 13 / 8.3 s, 47% |
| 10 above | ×6.2 | 3.7 / 33 s, you die | 4.2 / 27 s, you die | 4.8 / 23 s, you die |
| 15 above | ×15.4 | 1.2 / 101 s, you die | 1.5 / 77 s, you die | 1.8 / 62 s, you die |

- **3 levels up** is hard work: one enemy at a time, about a quarter of your health each.
- **5 levels up** is a fight you plan: one normal enemy costs a Warden in plate half to two-thirds of its health, and a cloth wearer most or all of it.
- **10 levels up** kills a Warden in plate in four or five hits and a cloth wearer in three.
- **Each level of gap** makes an enemy about 1.5 times as dangerous, so 4 wolves two levels up are as dangerous as 6 or 7 at your level.

One average hit from full health kills you at these gaps, from a normal enemy / an ogre:

| Character | Level 5 | Level 10 | Level 20 | Level 40 |
|---|---|---|---|---|
| Par, cloth | +13 / +9 | +14 / +9 | +15 / +10 | +16 / +10 |
| Par Warden, plate and shield | +16 / +11 | +17 / +11 | +17 / +12 | +18 / +13 |
| Full greens, plate and shield | +18 / +13 | +19 / +14 | +21 / +15 | +22 / +16 |

**Why 1.2.** It keeps 3 levels up hard work and 5 up a fight you plan. At 1.25, one normal enemy 5 levels up kills a level 10 Warden in plate and any cloth wearer; at 1.15, a Warden in full greens wins a fight 10 levels up from level 15 on. Changing it is one number (`levelGap`).

## Today's items and enemies

Weapons show damage per swing at their own speed; armour is on the ×10 scale.

| Item | Item level | Numbers |
|---|---|---|
| Worn longsword (white, 2.2 s) | 1 | 3–7 |
| Rusted falchion (white, 2.6 s) | 2 | 4–10 |
| Watchman's Edge (green, 2.0 s) | 3 | 4–9, +4% haste, +1 Strength |
| Blackwood cleaver (green, 2.8 s) | 4 | 6–14, +3 Strength |
| Witchbane (purple, 2.4 s) | 5 | 7–16, +2 Strength, +2 Stamina, +3% haste |
| Travelling clothes (white leather chest) | 1 | 30 armour |
| Dented watch helm (white mail) | 2 | 54 armour |
| Iron-studded gloves (white mail) | 2 | 41 armour |
| Hobnailed boots (white leather) | 2 | 27 armour |
| Mail chausses (white mail) | 3 | 63 armour |
| Warden's hauberk (white mail) | 3 | 63 armour |
| Blackened sabatons (white plate) | 3 | 63 armour |
| Helm of the Old Watch (blue mail) | 5 | 89 armour, +3 Stamina, +2 Strength |
| Battered kite shield (white) | 1 | 100 armour, 10% block |
| Iron-faced kite shield (green) | 4 | 160 armour, 20% block |

The Warden starts with 130 armour (21% at level 1) and reaches 444 in the full kit (47% at level 1, 33% at level 5).

| Enemy | Level and type | Health | Hits | Armour |
|---|---|---|---|---|
| Ashen Ghoul | 1, normal | 18 (16–19 by spawn point) | 6 every 1.35 s | None |
| Barrow Hound | 3, pack beast | 18 | 4 every 0.95 s | None |
| Hollow Archer | 3, skirmisher | 18 (17–19) | 12 every 2.5 s, shot or blade | 70 (9%) |
| Gravebound Brute | 3, elite | 50 (45 at Hallow Cut) | 9 every 1.2 s; Grave Slam 31 | 140 (17%) |
| Blackwood Seer | 5, elite, light armour | 69 (72 in the glade) | Staff 6 every 1.3 s; Rot Bolt 10, Grasping Dark 17 | 90 (9%); resistance 200 (18%) |

Played in order, the Warden tends to meet the brute and the seer a level or two under them, and each level under makes their hits 20% harder and their health last 20% longer. If that is too much in play, drop them a level.

## Spells

Player spells grow with the caster as weapons grow with item level: a spell's `damageMin`–`damageMax` in `data/abilities.json` is its level 1 damage, ×(level + 4) ÷ 5, plus spell power. At level 1: Hallowed Bolt 3–4 (a 1.6 s cast), Smite 1–3, Hallowed Ground 1 a second, Rebuke 1. Enemy spells are hits on you, so they follow the enemy table instead.

## Building future archetypes

- **Tank:** Strength main attribute, heavy armour, a shield, block chance and Stamina gear. Its defensive slot is Brace.
- **Rogue:** Agility main attribute, so Agility gives both power and crit. Leather, energy as its resource, and a defensive slot such as Evade.
- **Caster:** Intellect main attribute, mana and spell power, and resistance gear. Its defensive slot is a Ward, which absorbs damage.

Each one is an `archetypes` entry: base attributes, gains per level, main attribute, resource and defensive ability. No new formula is needed.

## Not built yet

- **The same growth for the rest of the economy:** potions (a level 40 healing draught should heal about 9 times as much), mana costs, merchant prices, and experience and coin rewards.
- **Items for the new slots** (shoulders, waist, wrists, back, neck, rings, trinkets): the rules cover them; they need models and icons.
- **Two-handed weapons** (weight 1.5, 1.3 × one-handed damage) and trinket effects.
- **Resistance gear and more magical enemy attacks:** the formula and the stat exist.

## How the reference games do it

| | Attributes | How damage is worked out | Defence | Crit | Lesson for Shadowfall |
|---|---|---|---|---|---|
| **RuneScape** | Attack, Strength, Defence, Hitpoints (skills you level by use) | Roll to hit (your accuracy against their Defence), then roll 0 to max hit | Defence lowers the enemy's chance to hit, not the damage | None in classic | Very readable, but many attacks miss, which feels bad in an action game with telegraphs |
| **Skyrim** | Health, Magicka, Stamina | Weapon base × skill and perk multipliers | Armour rating reduces damage %, capped at 80% | Small, mostly sneak attacks | Armour as a capped % works |
| **Diablo (II–IV)** | Strength, Dexterity, Intelligence, Vitality | Weapon damage × (1 + main stat %) × skill % | Armour % reduction against monster level; block chance on shields; resistances | Crit chance and crit damage | Main stat per class plus a health attribute is compact and scales well |
| **Lost Ark** | Strength, Dexterity or Intellect plus Vitality; six combat stats | Attack power from √(main stat × weapon power) × skill | Defence % reduction | Crit rate, crit damage 200% | Too many secondary stats for a small game, but the class main stat is useful |
| **World of Warcraft** | Strength, Agility, Intellect, Stamina | Weapon damage + attack power, abilities normalised to weapon speed | Armour ÷ (armour + K), K by level, capped at 75%; cloth to plate | Crit chance | The armour curve, armour types, item budgets by slot and item level, and a 1.5 s global cooldown |

## Earlier decisions (2026-10-14), still standing

- **No misses and no dodge chance.** Misses feel bad in action combat, where the player has already aimed; WoW removed hit rating for the same reason. Avoidance is the player's skill (telegraphs and Brace). A rogue could later get a small passive dodge as part of its kit.
- **A block stops a percentage of the hit** (30%), as in WoW since Cataclysm and Diablo IV, rather than a flat value that stops whole hits early and nothing later. Brace stays a guaranteed full block, and telegraphed specials such as Grave Slam cannot be blocked.
- **Haste** divides the time between swings, ability windups, casts and the global cooldown (floor 1 s), capped at 30%. It does not speed up the swing animation (since 2026-10-15, see The swing timer), enemy telegraphs or Brace's window.
- **No server for now.** The game is single-player and saves in the browser. The damage formula is one pure function (`src/systems/stats.js`) fed by config and data, and the growth formulas are plain functions too, so they could run on a server or in Unity unchanged.

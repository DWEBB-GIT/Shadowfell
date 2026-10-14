# Stats and damage: design note

Status: built in the prototype on 2026-10-14. Every number below lives in `src/config.js` (`stats`, the archetypes and the enemies) and in `src/data/items.js`, so a balance pass never has to touch code.

## Recommendation

Use **four attributes, a handful of derived combat stats, and one damage formula shared by everything**.

- **Attributes:** Might, Finesse, Intellect and Vitality.
  - Each archetype has a **main attribute** that feeds its damage, as in Diablo and Lost Ark. The Warden's is Might, a future rogue's would be Finesse and a caster's would be Intellect.
  - Vitality gives health to everyone.
- **Derived stats:** weapon damage, power, spell power, crit chance and crit damage, armour, resistance, block chance (from a shield) and haste.
- **Left out on purpose:** hit chance and misses, dodge and parry chance, haste, and penetration.
  - Avoiding damage is the player's job: walking out of telegraphs and pressing the defensive button. A random roll should not do it for them.
  - This keeps tanks simple: a tank stacks armour, block and Vitality.
- **Resources:** Health, plus one resource per archetype.
  - The Warden has none. A caster would have mana from Intellect, and a rogue would have energy.
  - Enemies can have mana too. The HUD shows a blue bar for any enemy whose config gives it mana.
- **Damage numbers:** they float up from whoever is hit. The original doc asked for no bright numbers, so they stay small, serif and muted:
  - damage you deal is in parchment white;
  - damage you take is in dull red;
  - crits are larger and amber, with a "!";
  - blocks show how much was stopped, and heals are in green.

## How the four reference games do it

| | Attributes | How damage is worked out | Defence | Crit | Lesson for Shadowfall |
|---|---|---|---|---|---|
| **RuneScape** | Attack, Strength, Defence, Hitpoints (skills you level by use) | Roll to hit (your accuracy against their Defence), then roll 0 to max hit (from Strength and gear) | Defence lowers the enemy's chance to hit, not the damage | None in classic | Very readable, but many attacks miss, which feels bad in an action game with telegraphs |
| **Skyrim** | Health, Magicka, Stamina (pick one per level) | Weapon base × skill and perk multipliers | Armour rating reduces damage %, capped at 80% | Small, mostly from sneak attacks | Three pools are easy to grasp; armour as a capped % works |
| **Diablo (II–IV)** | Strength, Dexterity, Intelligence, Vitality | Weapon damage range × (1 + main stat %) × skill % | Armour gives % reduction that shrinks against higher-level foes; block chance on shields; resistances per element | Crit chance and crit damage | Main stat per class plus Vitality is a compact model that scales well |
| **Lost Ark** | Strength, Dexterity or Intellect (by class) plus Vitality; six combat stats (Crit, Specialisation, Swiftness, …) | Attack power from √(main stat × weapon power) × skill | Defence % reduction | Crit rate, crit damage 200% | Too many secondary stats for a small game, but the class main-stat idea is useful |

Shadowfall takes three things from these games:

- Diablo's attribute set, with Lost Ark's idea of a main stat per class, because it supports tank, caster and rogue builds with very few stats.
- Skyrim's and Diablo's capped percentage armour.
- Diablo's crit chance and crit damage.

It drops RuneScape's hit roll, because telegraphs and Brace already provide the avoidance.

## The stats

| Stat | Comes from | What it does (default numbers) |
|---|---|---|
| Might | Archetype, level, gear | Warden's main attribute: +1 power per point |
| Finesse | Archetype, level, gear | +0.5% crit chance per point; rogue main attribute later |
| Intellect | Archetype, level, gear | +1 spell power and +10 mana per point (for archetypes that use mana) |
| Vitality | Archetype, level, gear | 40 health + 6 per point |
| Weapon damage | Main-hand item | A min–max range, rolled on every hit |
| Power | Main attribute | Added to every weapon hit before ability multipliers |
| Spell power | Intellect | Added to spells (scaled by each spell's coefficient) |
| Crit chance | 5% + Finesse | Chance of a critical hit |
| Crit damage | 150% | Crit multiplier |
| Armour | Gear (cloth, leather, mail and plate; archetypes limit the types) | Physical reduction = armour ÷ (armour + 40 + 10 × attacker level), capped at 75% |
| Resistance | Gear (later) | Same curve, against magical damage |
| Block chance | Shield, plus block rating (10 = +1%) | Chance to stop 30% of a melee blow, capped at 50%. Brace is a guaranteed full block |
| Haste | Gear only | Divides swing time, windups, casts and the GCD (floor 1 s), capped at 30% |

## The formula

```
player weapon hit = (roll(weapon min..max) + power) × ability multiplier
spell hit         = (spell base + spell power × coefficient)
enemy hit         = enemy damage × (1 ± 15% variance)

then, for every hit:
  crit?    × 1.5 (crit damage)
  defence  × (1 − armour or resistance %)
  block?   − 30% (melee blows only; Grave Slam cannot be blocked, only Braced)
  round; at least 1 unless fully blocked
```

Ability multipliers: Strike 1.0, Lunge 1.5, Shield Break 2.0. Enemies' normal attacks can crit; Grave Slam cannot.

## The Warden and the region, re-expressed

The numbers were picked so the region plays as before at average rolls. At an average roll the Strike does 18 at level 1 and the Brute's Grave Slam does 24. A ghoul's 11 raw damage becomes 8 after the Warden's armour.

| | Level 1 | Each level |
|---|---|---|
| Might / Finesse / Intellect / Vitality | 4 / 2 / 1 / 10 | +2 Might, +2 Vitality |
| Health | 100 | +12 |
| Strike (worn longsword 12–16) | 16–20 (avg 18) | +2 |
| Crit chance | 6% | |
| Armour | 20 from travelling clothes (29% reduction) | |
| Block | 10% from the kite shield, stops 30% | |

| Enemy | Health | Armour | Damage (raw) | Crit |
|---|---|---|---|---|
| Ashen Ghoul | 48 | 0 | 11 (≈ 8 after armour) | 5% |
| Gravebound Brute | 96 | 10 (17%) | 17 (≈ 13); Grave Slam 31 (≈ 24) | 5% |

Gear now carries stats:

- **Watchman's Edge:** 16–22 damage and +4% haste.
- **Travelling clothes:** leather, 20 armour.
- **Battered kite shield:** a 10% block chance.
- **Dented watch helm:** mail, +10 armour and +1 Vitality.

## Building future archetypes on this

- **Tank:** Might main attribute, heavy armour, a shield with a high block chance, block rating, and Vitality gear. Its defensive slot is Brace.
- **Rogue:** Finesse main attribute, so Finesse gives both power and crit. Light armour, energy as its resource, and a defensive slot such as Evade (a short dodge).
- **Caster:** Intellect main attribute, mana and spell power, and resistance gear. Its defensive slot is a Ward, which absorbs damage.

Each one is an `archetypes` entry in config: base attributes, per-level gains, main attribute, resource, and defensive ability. No new formula is needed.

## Not built yet

- Resistance gear and magical enemy attacks: the formula and the stat exist, but nothing uses them yet.
- Player resources: the Warden has none. The mana bar only appears for enemies or archetypes that define mana.

## Follow-up questions (Dan, 2026-10-14)

Dan approved all of the recommendations below, and they are built. The Warden now starts with a battered kite shield (10% block chance). Watchman's Edge adds 4% haste. The armour formula's constant is 40 + 10 × the attacker's level. The Brute's damage was lowered (17, and 31 for Grave Slam) so that the region still plays as before.

### Defence and armour types

**World of Warcraft**
- Armour is a single number. Damage reduction is `armour ÷ (armour + K)`, where K grows with the attacker's level. In classic, K = 400 + 85 × level. The reduction is capped at 75%.
- Armour types (cloth, leather, mail, plate) give more armour per piece as they get heavier. Each class can only wear certain types, and that is what makes the types matter.
- Classic also had a separate *Defense skill*. It lowered the chance of being crit and added a little dodge, parry and block. It was confusing, and WoW removed it in Cataclysm.

**Diablo**
- In Diablo II, "Defense" was a chance for monsters to miss you, not damage reduction.
- Diablo III changed to `armour ÷ (armour + 50 × monster level)`, plus a resistance for each element on the same curve.
- Diablo IV uses one armour number with a cap that depends on the monster's level.

**Recommendation**
- Keep a single **Armour** stat, which is already our "defence".
- Make armour types matter the way WoW does:
  - every chest, head, hands, legs and feet item is cloth, leather, mail or plate;
  - heavier types carry more armour;
  - each archetype can wear only some types (Warden mail and plate, rogue leather, caster cloth).
- Make the formula's constant grow with the attacker's level, the way WoW and Diablo III do, so that armour does not become worthless or overwhelming as levels rise:

  ```
  reduction = armour ÷ (armour + 40 + 10 × attacker level)
  ```

  This is the same as today's numbers at level 1.
- No separate Defense skill.

### Haste

- In WoW, haste speeds up swing timers, cast times and the global cooldown (to a minimum of 1 s), and it applies a small slowdown at high values.
- In Diablo, "attack speed" works the same way.

**Recommendation:** yes, as a **gear-only** stat (it does not grow with level):
- `speed = 1 + haste% / 100`;
- Strike's cooldown, cast times and the global cooldown are divided by `speed`;
- the global cooldown floor is 1.0 s, and haste is capped at 30%.

It should not shorten enemy telegraph timing or Brace's window. Haste fits rogues and casters best.

### Should stats be server-side?

- **Today there is no server.** The game runs in the browser and saves to local storage, so anyone with the browser tools can change anything. For a single-player game that is normal and harmless; Skyrim and offline Diablo II were the same.
- **A server only matters if the game goes online:** multiplayer, trading, leaderboards or anything bought with money. In that case the server works out every hit and owns the save, and the client only shows the results.
- **Recommendation:** no server for now. The damage formula is already one pure function (`src/systems/stats.js`) fed by config data, so it could run server-side later without being rewritten, whether in a Unity backend or Node.

### Hit chance, misses and dodge

- **WoW classic:**
  - an attack on a same-level enemy misses 5% of the time, plus a chance for the enemy to dodge or parry;
  - "hit rating" on gear exists only to remove those misses.
  - Players found it a chore, and WoW removed it in Warlords of Draenor.
- **Diablo III and IV:** your attacks never miss. Avoidance is a defensive stat only (Dodge in Diablo III).

**Recommendation:**
- **No misses on the player's attacks.** Misses feel bad in action combat, where the player has already aimed.
- **No dodge chance for the Warden either.** Avoidance is the player's skill (telegraphs and Brace).
- If the rogue archetype needs avoidance later, it can get a small passive dodge chance as part of its kit, not as a general stat.

### Shield block

- **WoW classic:**
  - block chance comes from the shield plus a rating;
  - a block subtracts a flat **block value**, which is what we do now.
  - The problem: at low levels it stops whole hits, and later it becomes irrelevant.
  - So from Cataclysm onwards WoW changed it to a block that stops a **percentage** of the hit (30% by default), with tanks able to get "critical blocks" that stop 60%.
- **Diablo IV:** a block also reduces the hit by a percentage.

**Recommendation:**
- Yes, give **shields a block chance**: about 10% on a basic shield, rising to about 25% on good ones. **Block rating** on other gear raises it further (10 rating = +1%), capped at 50%.
- A block stops **30% of the hit**.
  - Tank talents or gear could raise that to 40–50%.
  - Brace stays a guaranteed 100% block.
  - Grave Slam and other telegraphed specials still cannot be blocked.
- This replaces today's flat block value of 6, which can stop a weak hit entirely.
- The Warden would get the block from an actual off-hand shield item rather than from the archetype.

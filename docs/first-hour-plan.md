# Mythkeep — a life worth leaving home for

Proposed design and delivery plan, 9 November 2026. This document proposes work; it does not claim the mechanics, economy, secrets or multiplayer described below are already implemented.

## The promise

Arrive as an ordinary traveller in a place worth caring about. Find useful work, become known, glimpse a much older world and decide how far to venture into it. A fisher, cook or trader should have satisfying goals of their own. Adventuring should make those lives richer through places, materials and stories, while those professions provide things adventurers value.

Magic exists from the opening, alongside ordinary needs. Legendary status is earned through deeds and discoveries. Ancient heroes remain impressive, mysterious and sometimes misunderstood long after the player becomes locally capable.

## Current foundation and gaps

The existing 1–10 journey supplies residents, useful errands, hunting, cooking, a fishing lesson, an undead mystery, two middle routes and an outdoor finale. Quest follow-up presentation and guidance have recently been corrected. Fishing already has casting, a bobber bite/strike loop, rods, bait, skill ranks and different waters. Cooking already has recipes, ingredients, stations and skill requirements. These are foundations to improve, not systems to rebuild by default.

The Quiet Levy grounds the story in grain, labour and people. The opening needs earlier wonder and more independent choices of livelihood. Automated success and experience budgets do not establish whether a first-time player feels curiosity, satisfaction or boredom. Social play must be established through a real two-player engineering test; party UI and solo simulations do not prove multiplayer.

## Priority 1 — a first-hour journey through one district

Use Thornford, Holt Fields, Willow Pond and the approach to Mourning Hollow. Keep the full 1–10 route intact. The hour is an experience target, not a promise that level 10 arrives in sixty minutes; the existing 1–10 pacing target is about two hours.

Proposed beats, flexible enough for different activities:

| Rough elapsed time | Desired experience | Concrete content |
| --- | --- | --- |
| 0–10 minutes | I can understand this place and choose useful work. | Meet a resident, perform a short job and see the inn, forge and pond as usable destinations. Offer a viable first paid task without combat. |
| 10–25 minutes | My actions feel satisfying and my supplies matter. | An enjoyable first hunt or fishing session; a meal made from ordinary ingredients; an immediately useful reward. |
| 25–40 minutes | There is something here I was not sent to find. | An optional path, an environmental clue and a small secret with a coherent local reward. |
| 40–60 minutes | This valley belongs to an older, larger story. | A glimpse of an ancient hero's legacy, a readable threat and an earned return to familiar people. Leave the next road inviting. |

These windows guide placement and density, not a compulsory itinerary. Test a curious adventurer and a player who prefers fishing and work rather than forcing both down an identical route.

### Exploration and ancient history

Author three small secrets in this district, each with a fair clue and a reward. Examples for design review are a pond-side cache connected to a fisher's story, a shrine whose inscription changes the meaning of a local tale, and an old watchman's route revealing a useful shortcut. Define the cause and interaction for each secret; merely examining a note must not stand in for a puzzle mechanic.

Introduce one legendary figure through an impressive landmark, a resident's incomplete story and contradictory physical evidence. Names and details remain proposals until checked against existing lore. Let the player learn what the hero did, what ordinary people believe and what the landscape remembers. A dangerous or sealed place should communicate a future return opportunity and give a fair warning before lethal commitment.

Keep accepted-quest handoffs readable. Unmarked secrets, rumours and optional investigation supply uncertainty. Guidance for a known job should remain reliable.

## Priority 2 — combat with weight and readable decisions

Build on the character integration chat's final rig and equipment mappings. Record a baseline now, then tune animation timings after that integration is stable.

Polish a small set of representative attacks first: a heavy melee hit, fast dual-wield strikes, a bow shot and a spell impact. Connect anticipation, contact, sound, target reaction and recovery. Give weapons and surfaces distinct sound/material responses. Reserve stronger camera and impact accents for heavier events; retain reduced-shake and blood settings.

Use three early enemy behaviours to teach decisions: a committed boar rush, a wolf with a clear approach/escape pattern and a slow undead heavy swing. Separate ordinary hits, interrupts and avoidable heavy attacks visually. Check repeated fights and recovery, not only one fresh-health duel. Tune each class's opening with the actual low-level kit.

Success means players notice when they hit, understand why they were hurt, discover a better response and choose another fight. Fair challenge and satisfying contact matter more than increasing damage numbers.

## Priority 3 — one complete livelihood loop

Start with fishing → cooking → local orders → better fishing opportunities. This uses existing systems and gives the inn, pond, marketplace and roads a reason to exist between quests.

- Fishing: improve anticipation, casting, bobber readability, sounds and landing feedback. Reliable execution should usually land ordinary fish. Let bait, location knowledge and progression influence what is caught. Prototype and test before adding a compulsory tension minigame or reaction-heavy demands to every catch.
- Cooking: make a small set of meals worth preparing and using. Fish should have ordinary practical value, rather than existing solely for a quest turn-in or a rare jackpot.
- Orders: provide a few understandable demands from named residents, such as the inn needing meals or a worker needing supplies. Costs, payouts and repeatability must be budgeted together. Finite orders and explicit demand prevent an unlimited profitable buy/sell loop. Avoid daily attendance requirements.
- Progression: profession ranks, recipes, equipment and local reputation should advance without compulsory main-story combat gates. Keep combat level and profession mastery legible as distinct forms of progress. Prove the first safe district supports a satisfying non-combat session before promising a complete level-50 civilian career.
- Trading: begin with moving useful goods between two nearby communities with clear differences in supply and demand. A player-run market is a later infrastructure and economy milestone.

The first livelihood milestone is a satisfying 20–30-minute session with a clear next goal. It is not an entire simulated economy or every crafting profession.

## Priority 4 — adventure through preparation and earned familiarity

Preserve travel choices, local services and places with identities. Food, a rod, suitable bait and knowledge of a safe road can prepare an outing. Reaching and helping an inn, ferry or outpost can establish a later shortcut. Repeated journeys need landmarks, variation or a service worth paying for.

Controls, readable telegraphs, accessible text and reliable hand-ins remain clear. Choose friction that creates a decision: which route, what to bring, whether to turn back or who to travel with. Assess repeated trips during playtests; travel that repeatedly contributes no new choice needs revision.

## Priority 5 — prove an adventure with a friend

Before broad world expansion, make one real two-player outing work: depart the inn, fight a tougher optional enemy, share appropriate quest credit and rewards, gather or fish together and return. Verify character progress and item ownership through joining, disconnecting and rejoining. A fisherman or cook should be able to contribute useful supplies without being forced into a full damage role.

This is a separate implementation milestone. Do not describe the local prototype as a functioning MMO until actual shared sessions and persistence have been demonstrated.

## Review and release gates

1. Run an uninterrupted fresh-player baseline with normal controls and audible sound. Record confusion, dead time, travel, fights, rewards, readability and frame pacing. Automated known-route trials remain valuable supporting checks.
2. Test the revised district with unfamiliar players. Give one minimal guidance, let another pursue fishing/work, and later test a pair of friends. Ask what they want to do next and what they think the old landmark means.
3. Look for concrete behaviours: finding the next main-story contact without developer intervention, choosing an optional detour, understanding a failed attack, wanting another catch, using or selling a crafted meal and naming a personal next goal.
4. Repeat focused tests after changes. Preserve existing save, quest-chain, combat and roster checks. Do not claim that a fixed number of assertions proves fun, human levelling time or multiplayer capacity.

Proposed next deliverable: the first-hour district, with one complete livelihood loop, three authored secrets, one ancient-hero thread, a small polished enemy roster and an honest playtest report. Further continent content, additional professions, housing, player markets and raids follow evidence from that deliverable. Keep the existing maximum of eight planned dungeons and the level-50 framework.

## Reference boundary

The user specifically identifies the original Fable's grounded zero-to-hero feeling and ancient history as the tonal reference. The design above is original Mythkeep content, rather than an adaptation of the announced Fable reboot. RuneScape's official [skills guide](https://www.runescape.com/game-guide/skills) describes useful connections between gathering, fishing, food and production; that connection informs the proposed livelihood loop. Existing Mythkeep code and design documents are the implementation baseline.

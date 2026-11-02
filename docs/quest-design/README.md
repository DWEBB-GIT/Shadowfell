# Shadowfell quest research and design

**World placement update, 1 November 2026:** The opening now connects to 34 authored onward hubs and 109 regional/return quest prototypes. The new map has 134 quests. Terrain routes, level districts, public return areas and seven sealed dungeon approaches are placed. Full private dungeons and measured 60-hour progression remain future work. See the [world review](../world-layout-review.md). Earlier future-content wording below refers to the fuller designs, not the absence of this first placement pass.

Updated 1 November 2026. Original research prepared 31 October 2026. The zone plan and catalogue now use a level-50 cap and 45/60/80-hour journey targets. The original comparative research and initial audit remain historical records. The subsequent [Quiet Levy implementation guide](../quiet-levy.md) describes the twelve additions now installed, including adaptations of the first eight recommendations. Its canonical `nr_` IDs supersede the planning-only `qp_` keys for those implementations. The remaining proposals are future content.

- [Zone and quest plan](shadowfell-zone-quest-plan.md): GPT-6.1 Sol's original designs, local progression, eight suggested first additions, mechanic dependencies and acceptance checks.
- [Structured catalogue](shadowfell-quest-catalogue.json): 25 existing quests and 28 proposals, with explicit status, level, complexity, motivation, rewards and consequences. Planning schema, not a game import file.
- [Comparative research](game-quest-research.md): GPT-6 Astra's 19 sourced examples across LOTRO, Conquer Online, Lost Ark, WoW and RuneScape, original adaptation seeds and source limitations.
- [Initial code/data audit](design-audit.md): current engine capabilities and gaps found before the final plan. Its initial documentation-lag observation is historical; the earlier playable-slice guide now redirects to the current guide.

Read the [current playable-build guide](../reach-progression.md) for what is installed and tested. The existing five main and twenty optional quests remain distinct from proposals. Advanced interactions and future zones require implementation before they can be played.

The [level-50 pacing model](level-50-pacing.json) owns the 49 transition targets; [CSV](level-50-pacing.csv) provides an importable schedule. Runtime XP prices remain uncalibrated placeholders. Snow and desert are end-level regions.

[Editable pacing workbook](Shadowfell-level-50-pacing.xlsx): formula-driven phase and region totals, the 45/60/80-hour comparisons and the level curve.

The zone ladder now has overlapping world bands and four pairs of alternative progression regions. Mirefen and Highmere Downs are new future-region briefs. Each pair shares one journey budget; completing both is optional.

The [questing-hub plan](quest-hubs.md) and [structured hub records](quest-hubs.json) supersede the broad regional 8–22 assignments. Hub chains provide smaller stays; dangerous pockets support later returns. Level-50 endgame uses level-50 normal or elite enemies only.

- [World scope and names](world-scope-and-names.md): official reference comparisons, biome identities and selected name refinements.
- [Instanced dungeons](instanced-dungeons.md) and [structured blueprints](instanced-dungeons.json): seven approved layouts, a level-50 replay configuration and seven unscheduled reference designs, loot direction and the runtime contract.
- [Naming records](world-names.json): display names and aliases; production IDs remain stable.

[Deferred dungeon backlog](deferred-dungeons.md): seven reference designs outside the approved seven-layout roster.

[Dungeon mechanics curriculum](dungeon-mechanics.md): seven-dungeon teaching ladder, class usefulness, web rescues, encounter fallbacks and implementation acceptance checks. Seven layouts are approved; eight is the absolute maximum.

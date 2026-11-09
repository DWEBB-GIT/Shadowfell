# Mythkeep v6 character integration

Implemented 2026-11-09 in the existing Godot game at `C:/Dev/Shadowfell/Shadowfell`.

## Runtime and saves

`ForgeCharacter` builds the male or female v6 body from the supplied manifest. `Player` uses it by default. The creator, roster preview and world player share this model/equipment path. Source demo UI and its `res://saves` system are not installed.

Creation stores a sanitized initial appearance on the roster entry, retaining the existing roster ID and save key. Gameplay saves store appearance in `player.appearance`. Absent or invalid appearance fields resolve to a safe default without rejecting progress or inventory. The actual creator, logout scene reload and re-entry paths have been tested. The Godot project name and save namespace remain Shadowfell.

Choices: two bodies, three faces, bald/seven hair styles, four beards/none, independent moustache, six skin tones, five hair colours and five eye colours. Creation uses the existing framed panels, fantasy fonts, class crests/colours and warm preview lighting. Appearance controls scroll at small screen sizes. Native creator captures cover 960x540, 1280x720 and 1920x1080.

## Equipment and motion

Hand frames use a sampled canonical idle pose to accommodate the kit's T-pose bind. Held equipment still uses existing item models, rune effects, stats and inventory rules. Torso/head attachments follow the corresponding bones. The two-handed secondary grip and bow draw use two-bone arm fitting. The existing movement, jump physics, collision, facing and camera code remain in place. Contact-shadow placement is unchanged.

The supplied body-specific outfit provides fitted chest, shoulder, bracer, glove, belt, leg, foot and cloak meshes with its recorded skin coverage masks. Plain trousers and boots form the underlying travel look when their armour slots are empty, as clothing did on the previous player. Equipped slots select fitted surfaces. Headgear hides scalp hair; open hood support uses the supplied fitted hair. Existing watch helmets and built horns/halos have adjusted scale/offsets.

`ForgeRig` plays actual supplied animation tracks. The source loop catalog is restored per model instance; one-shot actions do not repeat. Actions are sampled against the game's impact and recovery clocks, and moving actions affect the upper body while locomotion continues. Cast/channel poses follow the live cast clock, including pushback. Existing interruption paths clear the action. The rig supports hit reactions, death, sitting, jumping/landing, off-hand swings and interaction gestures.

## Verification evidence

All tests used unique isolated save folders, except the existing-character test, which first copied the real save folder and operated on that copy. No real character saves were overwritten or deleted.

| Check | Result |
| --- | --- |
| Source kit SHA-256 roster | 244 files checked, zero mismatches |
| `forge_character_check.gd` | 626 checks, zero failures; both bodies, choices, save/load, loop flags, sockets, legacy defaults, actual creator/logout/re-entry |
| `class_kits_check.gd` | 1,553 checks, zero failures; 72 live class abilities on both bodies through normal spell casting, plus existing class mechanic regressions |
| `forge_equipment_check.gd` | 29 distinct slot/model paths; 300 checks, zero failures; identity, finite poses, sheathing, bows, dual wield and two-handed support |
| Two-handed secondary grip | Six sampled action/body combinations below the test's 8 cm error threshold |
| `character_select_check.gd` | 123 checks, zero failures; ten slots, saved gear, deletion confirmation/recovery, restoration and world entry |
| `jump_check.gd` | Zero failures; WASD, click movement, jumping/landing, unchanged speed, fixed camera and grounded contact shadow |
| `existing_character_check.gd` | Zero failures; copied existing level, possessions and finished quests retained |
| Native rendering | Vulkan Forward+ on GTX 1650, dummy audio; creator, selection, actual world, male/female action poses, shields, greatsword, bow, horns/wings, helmet/cloak |

Logs, native PNGs and original file snapshots are retained under:
`C:/Users/danja/.codex/.chatgpt-projects/g-p-6ae07996066481919e70f0a7eda6a6ef/character-integration/`.

The final native run is `native-delivery.log` with images in `captures-delivery/`. Final measured logs are `character-final.log`, `equipment-final.log`, `class-kits-final.log`, `character-select.log`, `jump.log` and `existing-character.log`.

The engine still emits material/RID/resource cleanup warning families described in the existing project context. Material warnings also occur around world warm-up in these runs. Final test runs contain no GDScript errors, but the warnings were not independently baseline-profiled here; a successful test result is not a warning-free renderer claim.

## Art limits and remaining review

- Armour identities and stats are preserved, but distinct cloth/leather/plate items currently share the supplied Ranger geometry. The kit includes one fitted outfit; separate visual families for the live armour catalogue have not been authored.
- The 29-path equipment test checks attachment/stability/visibility; it is not a per-item or per-frame clipping audit. Native captures sample shield, greatsword, bow, helmet/cloak and cosmetic combinations on both bodies.
- Bow draw and secondary two-handed grips are fitted procedurally over supplied gestures. Finger curl, bowstring contact, grip orientation and all extreme poses still need art polish. The 8 cm check measures sampled secondary palm position, not finger contact or clipping.
- Several abilities share source clip families. All 72 class abilities trigger rig playback in the normal casting test, but this does not prove an individually authored or visually approved animation for every follow-up form or utility action.
- Long hair/beards, helmets and cloth can still intersect in extreme poses. Hair remains head-weighted. The three-bone cloak has no cloth/body collision simulation. Sitting uses the supplied sitting idle; complete transition choreography and runtime LOD switching are not included.
- Shields, long weapons and sheathed weapons require further extreme-pose review with long cloaks and wings. No universal clipping-free claim is made.

## Source and provenance

Read-only source projects are preserved at `C:/Users/danja/Documents/Codex/2026-10-30/i/outputs/godot-character-creator-v6` and `modular-character-kit-v6`, including earlier versions and Blender masters. Runtime assets live under `assets/characters/forge_v6/`; original CC0 notices are retained in its `licenses` directory. The source identifies the character/outfit/animation libraries as Quaternius CC0. Texture generation and weathering provenance remain in the preserved source kit reports.

The Game Development Studio CLI is unavailable on this machine. The integration used direct Godot import, isolated runtime tests and native captures; no canonical-vendoring receipt or sealed studio capture bundle is claimed. No assets were purchased, published, uploaded, committed or pushed.

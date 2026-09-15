# CLAUDE.md

This file provides guidance to coding agents working in this repository.

## Project

"Tank Battle" is a Battle City / Tank 1990-inspired game in **Godot 4.5** using GDScript and Forward+. It combines arcade tank combat with a Slay-the-Spire-style branching campaign map, persistent campaign stat rewards, in-battle structure building, local 2-player co-op, and host-authoritative ENet online co-op.

The visual style is Sokpop/claymation-inspired. Gameplay is 2D; art is rendered to PNG assets from Blender-oriented tooling and loaded at runtime. Sound effects are synthesized in code rather than stored as audio files.

## Progression rule: STAR pickups own tank tier

This is an important gameplay rule:

- There is **no RPG XP/level progression**.
- Enemies do not award XP.
- Campaign events do not award XP.
- Tank weapon tier (`upgrade_tier`, 0-3) is upgraded by collecting the `STAR` power-up during battle.
- Campaign STAR upgrades are persisted to `GameState.player_tier` / `GameState.p2_tier` immediately so death and respawn do not roll them back.
- Map events, rest nodes, and shops may grant economy or persistent stat bonuses such as ATK, max HP, speed, or lives, but they must not directly increase tank tier.

Do not reintroduce `player_xp`, `current_xp`, `xp_to_next`, `add_xp()`, automatic level bonuses, or a second level-based upgrade path unless the game design is explicitly changed.

## Commands

The project targets Godot 4.5. On the main development machine the intended executable is:

```powershell
$godot = "C:\Godot\tools\Godot_v4.5-stable_win64.exe"

& $godot --path .
& $godot --path . scenes/main.tscn
& $godot --headless --path . --check-only --script scripts/main.gd
& $godot --headless --path . --editor --quit
```

Do not open/write the project with a newer Godot build if that would rewrite imports or project metadata unintentionally.

There is currently no automated test suite or linter. Validation is script parsing/type checking plus runtime testing. Online changes require two-instance testing.

## Scene flow

Campaign:

`title_screen.tscn` -> `spire_map.tscn` -> `main.tscn` -> `spire_map.tscn`

Arcade:

`title_screen.tscn` -> `main.tscn`, with restart handled inside the battle scene.

Online currently starts in Arcade mode only.

## State architecture

### `GameState` (`scripts/game_state.gd`)

`GameState` is a `RefCounted` that uses static variables as run/session state across scene changes. It stores:

- game mode and player count
- ENet session flags and peer IDs
- campaign floor/map state
- campaign gold
- P1/P2 tank tier and lives
- persistent max-HP, ATK, and speed bonuses
- current encounter type

Tank tiers in campaign must be written back immediately when a STAR is collected.

### `RPGManager` (`scripts/rpg_manager.gd`)

Despite the legacy class name, this is no longer an XP/level manager. It is a per-battle economy/stat view owned by `MainGame` and currently stores:

- battle gold
- ATK bonus
- fire-rate modifier level
- speed modifier level
- max-HP modifier level
- regen modifier level
- building-HP modifier level

Campaign entry copies the applicable persistent `GameState` values into this object. Avoid adding another persistent progression layer here; cross-scene state belongs in `GameState`.

## Battle controller

`main.gd` builds and runs the battlefield. It owns spawning, base state, lives, victory/defeat, battle HUD, campaign stat projection, and power-up effects.

The battlefield uses a 13x13 logical layout with `TILE_SIZE = 48.0`. Current PNG tile assets are 256x256 and the correct render scale is:

```gdscript
const TILE_SCALE: float = TILE_SIZE / 256.0 # 0.1875
```

Do not restore the old 0.38 scale; that was an obsolete asset-era value.

## Tank tier behavior

`PlayerTank.upgrade_tier` ranges from 0 through 3.

STAR handling lives in `scripts/player.gd::apply_powerup()`:

- increments tier, capped at 3
- refreshes tank appearance
- tells `MainGame.persist_player_tier()` to save campaign tier immediately
- triggers upgrade VFX/toast

Weapon behavior by tier is also handled in `player.gd` (fire rate, projectile speed, twin shot, plasma/steel destruction). Keep tier behavior centralized around STAR collection rather than duplicating upgrades in map-event code.

## Campaign map rewards

`event_dialog.gd` should only modify persistent campaign resources/stats. Current reward categories are gold, ATK, max HP, speed, and lives. These are independent of tank weapon tier.

When changing reward text, keep the displayed value consistent with implementation. In particular, one `speed_bonus` currently represents +15% movement speed.

## Online multiplayer

Online co-op uses Godot 4 `ENetMultiplayerPeer` and is host-authoritative.

- UDP port: `24567`
- 2 players total: host P1 + one remote P2
- client sends P2 input at 30 Hz
- host sends world snapshots at 20 Hz
- host owns enemy AI/spawning, player-authoritative movement, bullets, collisions, damage, drops, score, lives, terrain destruction, buildings, and win/loss state
- client disables competing gameplay simulation and interpolates replicated state

`NetworkBattleSync` replicates players, enemies, bullets, pickups, coins, buildings, terrain/base-wall state, HUD state, and round restarts.

Online Campaign, relay/NAT traversal, matchmaking, and client-side movement prediction are not implemented yet.

## Collision/groups

The project relies heavily on groups rather than strict type dispatch. Common groups include:

- `player`, `p1`, `p2`
- `enemy` / `enemies`
- `bullet`
- `brick`, `steel`, `water`, `border`
- `base` / `base_eagle`
- `building` / `buildings`
- `powerups`
- `collectibles`

`bullet.gd` is the central collision/destruction dispatch point. When adding a new destructible object type, verify both collision layers/masks and group handling.

## Assets

Runtime textures are loaded by path through `TextureHelper.get_tex(path)` rather than being fully wired through scene `ext_resource` declarations. Naming conventions therefore matter.

Examples:

- player tanks: `player_tier{0-3}_f{0,1}.png`
- enemies: `enemy_{basic,fast,power,armor}[_bonus]_f{0,1}.png`
- water: `tile_water_f0.png`, `tile_water_f1.png`

Current repository tooling under `tools/` includes the unified Sokpop/clay asset builder, animation builder, clay UI builder, and render/color analyzer. Before changing generated assets, inspect the current tool instead of relying on older script names from historical commits.

## Input

Player input uses the `p1_*` and `p2_*` action sets. Gamepad device 0 maps to P1 and device 1 to P2 for local co-op.

Building selection/placement currently uses raw keycodes in `builder_controller.gd` rather than InputMap actions.

## Coupling / future refactors

Several gameplay scripts access `get_tree().current_scene` and duck-type `MainGame` methods/properties. This is acceptable for the current prototype but is the main architectural pressure point as the project grows.

Prefer incremental refactors over a large rewrite. Good future extraction targets are:

- enemy spawning / encounter director
- HUD controller
- campaign stat projection
- building-placement validation

Preserve the host-authoritative online model while refactoring battle code.

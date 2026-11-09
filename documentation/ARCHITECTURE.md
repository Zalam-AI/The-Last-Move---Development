# THE LAST MOVE — architecture

## Shape of the project

```
project.godot                 6 autoloads, Forward+, 60 Hz physics, gravity 14
scenes/core/root.tscn         empty scene; the game lives in the `Game` autoload
scripts/core/                 autoloads + shared building blocks
scripts/physics/              furniture, doors, truck
scripts/player/               first-person controller + procedural body
scripts/levels/               level kit, property base, 8 properties, headquarters
scripts/missions/             mission runtime (contracts, clock, scoring, replication, hints)
scripts/ai/                   creatures + creature director
scripts/ui/                   entire interface, built in code
resources/*.json              items, properties, upgrades, modifiers, flavour text
tools/                        audio synthesis, audio manifest, multiplayer runner
tests/                        six integration suites + property audit
documentation/                this folder
```

There is no scene-based content beyond `root.tscn`. Everything else is constructed from
code so that content stays diffable, reviewable, and impossible to desync between machines.

## Autoloads

| autoload | file | responsibility |
| --- | --- | --- |
| `Settings` | `settings_manager.gd` | InputMap, `user://settings.cfg`, bus volumes, accessibility flags |
| `DB` | `db.gd` | parses the five JSON content files, normalises items, lookup helpers |
| `Save` | `save_manager.gd` | atomic JSON profile (v3), migration, credits, unlocks, achievements |
| `Audio` | `audio_manager.gd` | 4 buses, pooled 3D/2D players, music crossfade, ambience, subtitles |
| `Net` | `net.gd` | solo/host/join, player registry, chat, ping, **transport swap point** |
| `Game` | `game.gd` | state machine, HQ ↔ mission, player spawning, scoring hand-off, UI owner |

`Game` is the only node that knows about all the others. Nothing below it references `Game`
except through `Game.get_player()`, `Game.mission`, `Game.ui`, `Game.report_noise()` and
`Game.state`.

## State machine

```
BOOT → MENU → LOBBY → HEADQUARTERS ⇄ MISSION → RESULTS → HEADQUARTERS
```

`Game._clear_world()` removes and frees previous world children explicitly with
`remove_child()` before `queue_free()`, because `queue_free()` is deferred and any path
lookup in the same frame would otherwise find a stale `Player` node.

## Authority model

One code path for single-player and online multiplayer: solo uses Godot's
`OfflineMultiplayerPeer`, which reports `multiplayer.is_server() == true`, so every host
check in the code is exercised in single-player too. The host is the authority for:

- furniture physics (clients send grip requests, never positions)
- contract state, clock, scoring
- doors, creature AI, truck validation
- property events and the creature director

Clients send input-shaped requests (`_server_grab`, `_server_release`, `_server_rotate`,
`_client_set_ready`) and receive state (`_rpc_furniture_batch`, `_rpc_clock`,
`_rpc_creature_state`, `_sync_players`, `_rpc_mission_result`).

Furniture replication is batched: 14 Hz, up to 26 objects within 48 m, 11 floats per
object (`pack_state`/`unpack_state`), with client-side interpolation. Creatures replicate
at 12 Hz as position/yaw/state/lunge.

### Steam transport

`Net.transport` is the swap point. `Net.create_host()`, `Net.join()` and
`Net.leave_session()` are the only functions that touch the multiplayer peer, and the
transport name is stored on the session. Adding Steam Datagram Relay means implementing the
same three functions against `SteamMultiplayerPeer` and leaving the rest of the game
untouched; see `MULTIPLAYER.md`.

## Determinism

The property and its furniture are generated from `(property_id, seed)`. The host
broadcasts `_rpc_start_mission(property_id, seed, modifiers)`; every peer builds the same
world, so node paths match across machines and per-object RPCs work without a spawner.
Furniture uid is an incremental counter in spawn order, which is itself seeded.

## Building blocks

- `MeshBuilder` (`mesh_builder.gd`): accumulates boxes/cylinders/spheres with vertex colours,
  merges them into one `ArrayMesh` with one surface per material class (plain/metal/glass/
  emissive), and commits a `StaticBody3D` with box collision per part. A whole building is
  a handful of draw calls.
- `AssetLib` (`asset_lib.gd`): ~45 furniture templates. Each template is a function taking
  size/colour/accent and emitting parts in local space with the origin at the footprint
  centre on the floor, +Z forward.
- `LevelKit` (`level_kit.gd`): floors, ceilings, walls with door openings, window panes,
  lights, stairs, railings, environment presets, moonlight.
- `PropertyBase` (`property_base.gd`): the property interface — `build()`,
  `on_mission_start()`, `mission_tick()`, `handle_event()`, `on_loud_noise()`, spawn list
  helpers, door/light/portal helpers.

## Adding content

**A furniture item:** add an entry to `resources/items.json` with `id`, `name`,
`template`, `size`, `color`, `accent`, `weight`, `value`, `fragility`, `material`, `grips`,
`min_carriers`, `category`. If the template does not exist, add it to `AssetLib.build()`.

**A property:** add an entry to `resources/properties.json` (including
`layout: res://scripts/levels/level_<id>.gd`), write that script as a `PropertyBase`
subclass implementing `build()`, then run `tests/level_audit.tscn` to check spawn validity.

**An event:** add the name to the property's `event_pool` and handle it in
`handle_event()`. The mission scheduler picks from the pool on a seeded timer.

**A creature:** add a `Kind` to `creature.gd`, a `KIND_DATA` row, a `_build_*` model
function and a `_think_*` brain, then add it to the director's availability table.

**An upgrade:** add to `resources/upgrades.json` and read it with
`Save.owns_upgrade("<id>")` at the point of use.

**A first-run hint:** add a row to `HintDirector.HINTS` and a condition in
`HintDirector._applies()`. Hints are keyed, shown once per save profile, stored in
`profile.hints_seen`, and can be switched off in Settings. The director is created by
`MissionManager` and only ever speaks through the mission's `notification` signal, so a
client that has not loaded the mission yet is never spammed.

## Failure behaviour

- Missing audio clip → one warning, silent degrade, game continues.
- Missing property layout → `push_error`, mission reports a build failure rather than
  crashing.
- Corrupt save → backed up to `profile.corrupt.json`, defaults loaded.
- Version mismatch between host and client → kicked with a readable reason.
- Lost host → clients return to the menu with the session closed.

## Performance structure

- Static architecture is merged per building into a few meshes; furniture is one mesh per
  item with vertex colours (no per-item materials, except the damage tint override).
- Furniture physics is host-only; clients interpolate.
- Lights are omni with shadows only where the level designer asked for them (the properties
  keep this in the low single digits).
- The audio pool is fixed (28 × 3D, 8 × 2D) and reused, so no per-shot node allocation.

# THE LAST MOVE — multiplayer

## Model

- **Topology:** one listen host + up to three clients. No dedicated server, no relay.
- **Transport:** Godot's `ENetMultiplayerPeer`, isolated behind `Net.create_host()`,
  `Net.join()` and `Net.leave_session()`.
- **Solo is a real session.** Single-player runs on an `OfflineMultiplayerPeer`, which
  reports `is_server() == true` and unique id 1. Every RPC and every authority check is
  exercised in single-player; there is no separate "single-player code path".
- **Determinism by construction.** The host broadcasts
  `_rpc_start_mission(property_id, seed, modifiers)`; every peer builds the same world from
  the same seed, so node paths and furniture uids match on every machine. That is what
  makes per-object RPCs and batched replication work without a spawning protocol.

## What the host owns

| system | host | client |
| --- | --- | --- |
| Furniture physics | simulates every rigid body | interpolates 11-float batches at 14 Hz |
| Grip / carry | validates and applies forces | sends `_server_grab` / `_server_release` |
| Doors | toggles, slams | requests via interact |
| Truck validation | every 0.25 s | sees `delivered` flags |
| Creature AI | runs the director and every brain | interpolates at 12 Hz |
| Clock, contract, scoring | authoritative | mirrors via `_rpc_clock`, `_rpc_delivery` |
| Player health / down / revive | authoritative | predicts locally, corrected by state |

## Bandwidth

- Furniture: 14 Hz, ≤26 objects within 48 m of each viewer, 11 floats each → about 4 KB/s
  per client in a busy room, less when the crew is spread out.
- Creatures: 12 Hz, position + yaw + state + two flags per creature.
- Player: 18 Hz input-driven state (position, yaw, pitch, flags, speed, name).
- Voice: see below.

## Proximity voice

`scripts/core/voice_chat.gd`, mounted at `/root/Net/VoiceChat` so the RPC path is identical
on every peer.

- Capture: `AudioStreamMicrophone` on a capture bus, 20 ms frames, downsampled to 16 kHz
  mono, 16-bit, silence gate at 0.006.
- Transport: unreliable RPC per frame; the host relays to other clients.
- Playback: one `AudioStreamGenerator` + `AudioStreamPlayer3D` per remote speaker, so
  distance attenuation and stereo placement come for free; `unit_size` 7 m, max 28 m.
- Occlusion: a raycast between listener and speaker switches a per-speaker low-pass filter
  between ~16 kHz (line of sight) and ~900 Hz (through walls).

**Honest status:** the voice pipeline is implemented and code-reviewed, but this sandbox has
no audio input device, so no real microphone has ever been through it. See
`PLACEHOLDER_REGISTER.md` — this is one of the two things that must be verified on real
hardware before launch.

## Leaving a contract

The host owns departure, and the truck leaves with the whole crew or not at all: any living,
consenting mover further than 14 m from the truck steps on the brakes with a named reminder
("Still inside: …"). A downed mover is cargo, not crew, so nobody is held hostage by a body
in the hallway — an unconscious mover is revived, or bleeds out and is filed as missing.
Solo play is unaffected: one mover beside the truck is the whole crew.

## Testing

`tools/mp_test.sh <clients> <seconds>` launches the host and each client as **separate OS
processes** (an in-process loopback client cannot be trusted to model real latency), each
writing a log, and the runner asserts:

1. every process reports `ok=true`
2. every process reports the same maximum peer count as the host
3. the host saw at least one delivery
4. clients saw the mission, at least 10 furniture bodies, a delivery from the host, and
   another player moving
5. no `SCRIPT ERROR` in any log

Latest results (this machine, headless, loopback):

| crew | port | duration | result |
| --- | --- | --- | --- |
| 1 host + 1 client | 7815 | 20 s | PASS |
| 1 host + 2 clients | 7824 | 22 s | PASS |
| 1 host + 3 clients | 7836 | 26 s | PASS |

Logs from the last run are kept in `tests/mp_logs/`.

What this proves: connection, registration, roster sync, deterministic world building,
mission start broadcast, furniture validation replication, player state replication, and
the absence of script errors across processes.

What it does **not** prove: real-latency behaviour over the internet, packet loss recovery
beyond what ENet provides, or four humans with microphones talking over each other. Those
are in `MANUAL_ASSET_TASKS.md`.

## Steam transport plan

1. Add the Steamworks SDK through Godot's official Steam plugin (or GDExtension bindings).
2. Implement a small `steam_transport.gd` exposing `create_host/join/leave` over
   `SteamMultiplayerPeer`, with `Net.transport = "steam"`.
3. Use Steam lobbies for discovery and friend invites; keep direct-IP as the fallback for
   LAN and for testing.
4. Keep `Net` as the only file that knows which transport is live.

Nothing in gameplay code needs to change. This step requires a Steamworks partner account
and an app id, which is why it is prepared but not performed here.

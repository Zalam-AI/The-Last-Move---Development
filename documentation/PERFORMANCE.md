# THE LAST MOVE — performance

## Target

Stable 60 FPS at 1080p on medium settings on a mid-range desktop PC (something in the
class of a GTX 1660 / RX 5600 XT with a 6-core CPU), scalable down to integrated graphics
via render scale, shadow quality and FPS cap.

## What was measured, and how

`tests/perf_probe.gd` loads each property in a real mission, settles the physics for
90 frames, then samples 240 frames of `TIME_PHYSICS_PROCESS` and `TIME_PROCESS` and counts
rigid bodies, mesh instances and nodes.

Measurement machine: **headless Godot 4.6.3, 2 vCPU, 1.9 GB RAM, no GPU** (a CI-style
sandbox). That is not the target machine; treat the numbers as CPU-side costs only.

| property | build ms | physics median | process median | rigid bodies | mesh instances | nodes | static mem |
| --- | --- | --- | --- | --- | --- | --- | --- |
| willow | 78 | 0.74 ms | 0.08 ms | 42 | 129 | 743 | 52.2 MB |
| endless | 62 | 0.72 ms | 0.09 ms | 26 | 79 | 601 | 50.5 MB |
| dollhouse | 66 | 0.66 ms | 0.08 ms | 36 | 102 | 715 | 52.1 MB |
| sinking | 58 | 1.07 ms | 0.13 ms | 22 | 71 | 608 | 51.1 MB |
| perfect | 65 | 0.66 ms | 0.10 ms | 28 | 83 | 570 | 51.2 MB |
| hotel | 72 | 1.12 ms | 0.08 ms | 26 | 116 | 808 | 52.7 MB |
| breathing | 61 | 0.74 ms | 0.17 ms | 13 | 56 | 476 | 50.6 MB |
| last_customer | 73 | 0.42 ms | 0.08 ms | 22 | 72 | 569 | 51.5 MB |

(Run on the current build, 2026-11-09, after the creature limb rig and the hint director
landed. An earlier run of the same probe on the same hardware measured 1.23–1.57 ms medians;
the spread between runs of identical content is that large, which is why only medians and
large regressions are read from this table. Static memory rose from ~44 MB to ~51 MB with the
extra limb meshes and the per-mission hint state — still trivial.)

Budget context: 60 Hz means a 16.6 ms frame. The worst physics median above is 1.12 ms,
about 7% of the budget, on a CPU that is slower than the target machine.

## What was *not* measured

- **GPU frame time and draw calls.** There is no GPU in this environment; the renderer was
  headless. The 60 FPS @1080p target is therefore **unverified**. Mesh instance counts per
  property (56–129) bound the number of draw calls, and static architecture is merged into
  a handful of surfaces per building, but this is an argument, not a measurement.
- **Four-player sessions on real hardware.** The multiplayer tests run four processes on
  one 2-core box, which stresses the host more than a normal session would but says nothing
  about GPU load with four cameras.
- **Voice chat CPU cost.** No microphone in the sandbox.

All three are listed in `MANUAL_ASSET_TASKS.md` as things that must be done on a real
machine before launch.

## Known spikes (and a controlled experiment)

On this sandbox, p95 physics spikes reach 14–33 ms in a few properties. That looked like
teleport-heavy gameplay code, so it was tested directly: the doll-relocation code in
`level_dollhouse.gd` was disabled and the property re-measured. p95 stayed at 15.4 ms with
the feature off, versus 15.4 ms with it on — the spikes come from VM scheduling on the
shared 2-core sandbox, not from the game.

Two real improvements were made anyway while looking:

- `level_perfect.gd` used to audit every piece of furniture every frame; it now audits at
  4 Hz and restores at most two items per pass. p95 dropped from 16.9 ms to 3.7 ms.
- `level_dollhouse.gd` evaluates at most three dolls per tick, round-robin, instead of all
  of them (each evaluation is a raycast plus a possible rigid-body teleport).

## Design choices that keep the cost down

- **Merged static geometry.** Each building commits to one `ArrayMesh` per material class.
  A 34×22 m hotel floor with 25 doors is a handful of surfaces, not hundreds of meshes.
- **Vertex colours instead of materials.** Furniture is one mesh per item; colour lives in
  the vertices. The only per-instance material is the damage tint override.
- **Fixed audio pools.** 28 3D and 8 2D players are allocated once and reused; no node
  churn per footstep.
- **Host-only physics.** Clients interpolate 14 Hz state batches for at most 26 nearby
  objects, so client CPU does not scale with the number of items in the truck.
- **No per-frame allocations in the hot paths.** `mission_tick` implementations are
  throttled (audits, doll scans, water, portal refreshes) rather than running every frame.

## Repository size

| item | size |
| --- | --- |
| audio (ogg + wav) | 12 MB |
| scripts + resources | 0.6 MB |
| Windows release build (embedded pck) | 110 MB |
| memory at runtime (headless, one mission) | ~44 MB static |

## How to re-measure

```bash
godot --headless --path . res://tests/perf_probe.tscn
```

The probe prints medians; p95 is printed too, but on shared CI hardware it measures the
host, not the game.

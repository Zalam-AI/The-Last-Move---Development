# THE LAST MOVE — testing

Everything claimed in this repository is backed by a suite that can be re-run. Nothing in
this document is aspirational: if it is not in a table below, it is not claimed.

## Running everything

```bash
cd the_last_move
godot --headless --path . --import                                  # rebuild import cache
godot --headless --path . res://tests/test_runner.tscn              # systems + content
godot --headless --path . res://tests/level_audit.tscn              # all 8 properties
godot --headless --path . res://tests/carry_test.tscn              # carry physics
godot --headless --path . res://tests/systems_test.tscn             # modifiers, economy, crew
godot --headless --path . res://tests/creature_test.tscn            # creature AI
godot --headless --path . res://tests/campaign_test.tscn            # 8-property campaign
bash tools/mp_test.sh 3 26                                          # 1 host + 3 clients
godot --headless --path . res://tests/perf_probe.tscn               # CPU cost per property
```

Each suite prints `PASS`/`FAIL` per check, a summary line, and exits non-zero on failure,
so they drop straight into CI.

## Latest results (this machine, 2026-11-09)

| suite | checks | failures | result | what it proves |
| --- | --- | --- | --- | --- |
| `test_runner.tscn` | 70 | 0 | PASS | content integrity, save round-trip, solo boot, mission build, grab/carry/deliver, damage, scoring, settings, audio banks |
| `level_audit.tscn` | 8 properties | 0 | PASS | no contracted item spawns inside architecture, under the floor, or outside the playable volume; nothing is ejected by interpenetration; nearest item to truck is sane |
| `carry_test.tscn` | 17 | 0 | PASS | one mover lifts and carries a light item with real PD forces; an under-crewed wardrobe drags instead of flying; the grip breaks at 3.2 m; a shoved door swings open; cargo rejects a half-loaded item and accepts a fully-loaded one |
| `systems_test.tscn` | 85 | 0 | PASS | all eight contract modifiers change the mission (deadline, fragility, darkness, damage charges, insurance, extra item); upgrades change grip strength, capacity and armour; crew downing, bleedout and revive; scoring cannot go negative and a no-delivery contract pays nothing; economy and unlock chain; achievements; the departure muster rule; first-run hints firing once, persisting and obeying the setting; all 16 upgrades doing something real (ramp, straps, suspension, medkit, detector, paint, flashlight); every scripted supernatural event in all eight properties firing through the real dispatch path |
| `creature_test.tscn` | 23 | 0 | PASS | all four creature kinds spawn away from the crew, pursue, damage, react to light, banish after three hits, steal items; dolls relocate only when unobserved |
| `campaign_test.tscn` | 74 | 0 | PASS | all eight properties build, all contracted items validate through the real cargo zone, payouts and unlocks are recorded, campaign completes |
| `mp_test.sh 1 20` | 2 processes | — | PASS | host + 1 client agree on crew, mission, deliveries |
| `mp_test.sh 2 22` | 3 processes | — | PASS | same with 3 players |
| `mp_test.sh 3 26` | 4 processes | — | PASS | same with a full crew of 4 |
| `perf_probe.tscn` | 8 properties | — | measured | CPU cost per property, see `PERFORMANCE.md` |

### What each suite actually does

**`test_runner.gd`** — the systems suite.
Loads the content database and asserts every item has a mesh, collision, sane size and a
layout file; round-trips a save through corrupt-file recovery and migration; boots a solo
session; builds a mission and asserts furniture, truck and contract; grabs an item, carries
it, drops it in the cargo zone and asserts the delivery fires; damages an item to
destruction and asserts the mission is told; runs a departure to the results state and
asserts the payout maths; verifies the audio manifest and that every listed clip exists.

**`level_audit.gd`** — the level design suite.
For every property: builds it, runs 150 physics frames, then for every furniture body
checks velocity (interpenetration ejection), position (below world), a point query against
static architecture (spawned inside a wall), and pairwise overlap with vertical separation
so correctly-stacked items are not false positives. Also reports build time, door count and
the distance from the truck to the nearest contracted item.

**`carry_test.gd`** — the core-mechanic suite.
Uses the real grip API and real forces: takes a grip on a stool, walks the carrier away,
and measures how far the object actually rises and travels. Then repeats with a wardrobe
(needs two carriers) and asserts it does **not** lift but drags. Then walks off to check the
grip break distance, shoves a coffee table into a closed door and asserts it swings open,
and finally checks cargo validation with an item half out of the doors and one fully in.

Creature checks also assert the walk cycle really moves the limbs (the tenant's leg pivot
swings 0.68 rad over 40 frames) so an animation cannot silently regress into a sliding
statue.

This suite is also what caught a real door bug: the shove trigger volume was a 0.55 m slab
centred on the leaf, so a body that physically hit the door was stopped *before* it could
enter the volume, and shoving a door never worked. The volume now extends 0.65 m either
side of the leaf.

**`systems_test.gd`** — the rules suite.
Builds the same property with and without each of the eight modifiers and compares the
observable consequences: the deadline shortens, furniture fragility rises, the ambient
light energy drops, damage charges and equipment-loss charges appear, the extra item is
added exactly once, and a given noise value produces a larger director response. Then it
buys upgrades and asserts crew strength, cargo capacity and incoming damage change; downs a
mover and asserts bleedout, blocked grabbing and the revive; and closes on scoring edges, the
credit economy, the unlock chain and the achievement table. It also covers the departure
muster rule (a remote crew member blocks the truck; the same crew member aboard releases it)
and the hint director (a hint fires once, is persisted, is never repeated, and obeys the
setting). It finishes by building all eight properties and firing all 31 distinct scripted
supernatural events through `trigger_event()`, then asserting the scheduler picks one on
its own.

This section exists because of a class of bug the other suites could not see: content that is
purchasable or scripted but never read. Five upgrades (portable ramp, cargo straps, heavy
suspension, field medkit, object detector) and both truck paint jobs were buyable and inert,
and two of the eleven achievements (occupational hazard, not insured) had no code path that
could ever award them. All are now wired and asserted.

This suite caught two real problems: `fragile` multiplied a key the mission never read
(data-only modifier, silently dead), and the crew survival bonus was paid on a contract
where nothing was delivered. It also caught a dead variable in `request_departure()`: a
crew could leave a living mover behind and the code computed the fact, then ignored it.

**`creature_test.gd`** — the AI suite.
Spawns all four kinds, measures pursuit over 150 frames, forces contact damage, points the
flashlight at the Tenant and checks the light response, hits it three times and checks
banishment and the scoring counter, takes a carried item and checks the forced drop,
steals an item and checks it leaves the contract and registers damage, relocates a doll and
checks it moved.

**`campaign_test.gd`** — the end-to-end suite.
Plays all eight properties back to back with no cheat flags: real mission build, real
cargo validation for every contracted item, real departure, real payout, real save
progression, real unlock chain. Asserts the campaign completion achievement and the final
credit balance.

**`mp_test.sh`** — the multiplayer suite.
Launches 2–4 separate Godot processes (a genuine host and genuine clients, not an
in-process loopback), each with `--mp-probe`, waits for the run, then asserts: every process
reports `ok=true`, all report the same maximum crew size, the host saw a delivery, clients
saw the mission, at least ten furniture bodies, a delivery from the host, and another
player moving; and that no process logged a script error.

## The bug this suite caught (kept as a record)

Early on, `Save._migrate` silently reset credits to zero on every load. The cause: JSON
numbers come back as floats, so an `typeof(persisted) == typeof(default)` comparison failed
for every integer field and the whole profile was overwritten with defaults. The fix is
explicit per-key type coercion, and `test_runner.gd` now round-trips a save with non-default
values through disk twice.

A second real bug: `Game` left a stale `Player` node under `mission/` after a contract
ended, because `queue_free()` is deferred and the next frame's path lookup still found it.
Teardown now calls `remove_child()` before `queue_free()`.

## Not covered

Listed here so nobody assumes they are tested:

- GPU frame rate, draw call counts, and the 60 FPS @1080p target (no GPU in this
  environment) — see `PERFORMANCE.md`.
- Voice chat with a real microphone (no audio input device here).
- Steam transport, Steam lobbies, Steam achievements (needs a Steamworks account).
- Long sessions (a 3-hour stream), memory growth over many contracts, alt-tab and
  resolution-change behaviour on Windows.
- Four humans playing cooperatively with voice; the multiplayer suite tests the network
  protocol, not the social experience.

`MANUAL_ASSET_TASKS.md` assigns each of these to a person with the hardware to do it.

# THE LAST MOVE — placeholder register

Everything in this file is real, working code or real, playable content — but it is not
final-quality, or it could not be verified in the environment it was built in. Nothing here
is a stub that pretends to work.

Status key:
**P1** = placeholders a player will notice. **P2** = invisible to players, matters to
developers or to shipping. **P3** = unverified, not known-broken.

---

## Audio

| # | item | status | detail | replacement |
| --- | --- | --- | --- | --- |
| A1 | All sound effects | **P1** | 102 clips synthesised from oscillators, filtered noise and impulse modelling by `tools/generate_audio.py`. Original and licence-clean, but synthetic: impacts have no real room, scrapes have no grit. | Record real foley (see `MANUAL_ASSET_TASKS.md` §1). |
| A2 | Music | **P1** | 8 procedurally composed loops (menu, HQ, 5 property moods, escape, results). Functional, thematically consistent, but static: no adaptive layers, no stingers on events. | Commission a composer or licence a library; keep the same stem names so no code changes. |
| A3 | Ambience beds | **P2** | 10 loops (suburb night, endless hum, hotel hum, organic breathing, …). Convincing enough at low volume. | Field recording pass. |
| A4 | PA / dispatch voice | **P1** | 29 lines rendered with `espeak-ng`. This is **clearly placeholder speech** and is labelled as such in-game documentation. No human performance. | Hire a voice actor; the subtitle text and stem names are already in place. |
| A5 | Creature vocalisations | **P1** | Growl, shriek, breath, whisper, heartbeat — synthesised. Effective in context, but a sound designer would replace all five. | Same. |
| A6 | Voice chat with a real microphone | **P3** | Implemented (16 kHz capture, generator playback, occlusion low-pass, push-to-talk) but this environment has **no audio input device**, so it has never been exercised with a live mic. | Must be verified on real hardware before launch. |

## Visuals

| # | item | status | detail | replacement |
| --- | --- | --- | --- | --- |
| V1 | All geometry | **P1** | Built at runtime from boxes, cylinders and spheres with vertex colours. No textures, no normal maps, no baked lighting, no skeletal meshes. Deliberately stylised, and consistent. | Either keep the style (it is a coherent look) or commission models: `AssetLib` is a single file per template, so replacement is localised. |
| V2 | Player bodies | **P1** | Procedural primitives with limb rotation, walk bob and a hat. No rig, no IK, no facial animation, no ragdoll. | Rigged character + animations. |
| V3 | Creatures | **P1** | Four primitive models. Silhouettes are distinct (tall man, doll, ribbed breather, bellhop) and readable in the dark. | Character art pass. |
| V4 | Dolls | **P2** | Dolls are furniture items (`doll_porcelain`, `doll_large`) plus one creature; they read correctly but are simple. | — |
| V5 | Animations | **P1** | Furniture has no animation (it is physics). Doors tween. Players bob and swing arms. Creatures bob and lunge. No blending, no additive layers. | Animation pass with a rigged skeleton. |
| V6 | VFX | **P2** | Debris on destruction is spawned rigid bodies; light flicker is tweened energy. No particle systems, no post-processing beyond the environment settings. | — |
| V7 | UI art | **P2** | Entirely constructed from Godot controls with a code-defined theme: paper-document panels, stencil headings. No icons, no illustrations. | Optional UI art pass. |
| V8 | Boot splash / logo | **P2** | Boot splash disabled; icon is a generated SVG/ICO (a truck with two eyes in the back). | Branding. |

## Systems

| # | item | status | detail |
| --- | --- | --- | --- |
| S1 | Steam transport | **P2** | Not implemented. `Net.create_host/join/leave` is the swap point; the game ships on direct-IP ENet. Requires a Steamworks account and app id, so it cannot be done here. |
| S2 | Steam lobbies / invites / achievements API | **P2** | 11 achievements exist and unlock in the profile; none are pushed to Steam. |
| S3 | Key rebinding UI | **P2** | The InputMap is built from a table in `settings_manager.gd`; there is no remap screen. Players can edit `user://settings.cfg` but that is not a shipped feature. |
| S4 | Gamepad support | **P2** | No gamepad bindings, no glyph switching. |
| S5 | Localisation | **P2** | English only. A `language` setting exists and is stored, but no translation catalogues exist; all player-facing strings are inline. |
| S6 | Colour-blind palettes | **P2** | The palette is high-contrast but not colour-blind verified; no palette options. |
| S7 | Screen reader / full accessibility | **P2** | Comfort options (bob, sway, shake, flashing, FOV, subtitles) exist; no screen-reader narration of UI. |
| S8 | Dedicated server mode | **P2** | Listen host only. The authority model already supports a headless host, but no DS binary is configured. |
| S9 | Anti-cheat | **P2** | None. Co-op with friends; the host is trusted. |
| S10 | Telemetry / crash reporting | **P2** | None, by choice. Logs go to stdout only. |
| S11 | Cloud saves | **P2** | Local `user://profile.json` with atomic write and corrupt-file backup. No Steam Cloud wiring. |
| S12 | Tutorial | **P2** | No dedicated tutorial. The first contract (Willow, "Easy") acts as one, with contextual prompts for grab, rotate, load and depart. |
| S13 | Photo mode / replay / spectator | **P2** | Not implemented. |

## Content

| # | item | status | detail |
| --- | --- | --- | --- |
| C1 | 8 properties | final | All eight are hand-authored, distinct, and covered by the level audit. This is the shipped campaign. |
| C2 | 53 furniture items | final | 45 mesh templates; every item is grabbable, damageable and deliverable. |
| C3 | 4 creature types | **P1** | The four in the design doc. More variety would be welcome; the director supports any number. |
| C4 | 8 contract modifiers, 16 upgrades, 11 achievements | final | Sized for a 6–10 hour campaign. |
| C5 | Story | final | 8 company memos, 2 endings, flavour pools (announcements, emails, tips, report lines) in `resources/flavor.json`. |

## Verification gaps

| # | item | status | detail |
| --- | --- | --- | --- |
| G1 | 60 FPS @1080p on a mid-range PC | **P3** | Cannot be measured here: no GPU. CPU-side costs are measured and documented in `PERFORMANCE.md`; the GPU half of the target is unverified. |
| G2 | 4 players on real hardware, real latency | **P3** | Four separate processes on one machine is tested and passing. Internet latency, packet loss and four humans with microphones are not. |
| G3 | Windows binary execution | **P3** | The Windows export is produced by the official 4.6.3 template, but this environment is Linux; the *code and data* are verified through an identical Linux export. The `.exe` itself has not been launched. |
| G4 | Long sessions | **P3** | No 3-hour soak test. Memory is flat across the eight-property campaign run, which is the best signal available here. |

## What is deliberately *not* a placeholder

Contract generation, carry physics, damage and destruction, cargo validation, the clock,
scoring, the payout maths, progression and unlocking, save/load with migration, the
creature director and all four brains, proximity voice plumbing, the eight level layouts,
the headquarters, the campaign, both endings, the UI flows, and the multiplayer protocol
are complete implementations and are covered by automated tests. They are not sketches
waiting to be replaced.

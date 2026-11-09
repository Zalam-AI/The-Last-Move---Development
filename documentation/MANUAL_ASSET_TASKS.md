# THE LAST MOVE — work only a human can do

Everything here needs hardware, an account, a budget, or a person that code cannot
substitute for. Each task is written so that whoever picks it up knows where to put the
output and which stem or hook name it has to match.

## 1. Foley and sound recording (1–2 weeks)

Replace the synthesised SFX. The game loads by stem name, so files can be dropped in
without code changes.

- `assets/audio/sfx/imp_<material>_NN.wav` — impact, 3 variations each, for
  `wood, metal, glass, ceramic, fabric, paper, electronics, default`
- `assets/audio/sfx/break_<material>_NN.wav` — destruction, 2 variations each, for
  `wood, metal, glass, ceramic`
- `assets/audio/sfx/scrape_<material>_NN.wav` — dragging on a hard floor, 3 variations,
  for `wood, metal, fabric, default`
- `foot_step|foot_run|foot_crouch_NN.wav`, `door_open|door_close|door_slam|door_locked_NN.wav`,
  `house_creak_NN.wav`, `whisper_NN.wav`, `light_buzz_NN.wav`, `radio_static_NN.wav`
- Creature set: `creature_growl`, `creature_shriek`, `creature_breath`, `creature_steps`,
  `heartbeat`, plus `doll_move`, `doll_drop`
- After adding files: `python3 tools/build_audio_manifest.py`, then run
  `tests/test_runner.tscn` (it asserts every manifest path exists).

## 2. Music (2–4 weeks or a licence)

8 loops, `assets/audio/music/*.ogg`: `menu_corporate`, `hq_lobby`, `prop_calm`,
`prop_uneasy`, `prop_tension`, `prop_dread`, `escape`, `result_sting`.
Each must loop cleanly (the game crossfades but does not re-time). If an adaptive score is
wanted, add layers as `prop_tension_a/…_b` and extend `Audio.play_music()`.

## 3. PA and dispatch voice acting (1 day in a booth)

29 lines, `assets/audio/voice/voice_*.ogg` — see the filename list produced by
`tools/generate_audio.py` (`VO_LINES`). Each line already has subtitle text stored in the
script; replacing audio does not change subtitles. The current espeak-ng version is
explicitly labelled placeholder speech.

## 4. Character and creature art (6–10 weeks)

- **Player model**: rigged humanoid, first-person arms, 4–8 cosmetic hats, uniform. Hook:
  `scripts/player/player_model.gd` — replace `_build_nodes()`; keep the limb node names
  (`Torso`, `Head`, `ArmL`, `ArmR`, `LegL`, `LegR`, `Hat`) so the existing animation and
  cosmetics still work.
- **Creatures** (Tenant, Doll, Breather, Bellhop): hook `Creature._build_model()` and
  `_build_tenant/_build_doll/_build_breather/_build_bellhop`. Keep capsule collision
  (`radius 0.36`, height from `KIND_DATA`) or update it alongside the art.
- **Furniture**: 45 templates in `scripts/core/asset_lib.gd`. Each template is one
  function; swapping to imported meshes means changing `AssetLib.build()` to load a
  `PackedScene` keyed by `template` and leaving `Furniture` untouched.

## 5. Hardware verification (blocking, 2–3 days)

None of this could be done in the build environment:

1. **Frame rate.** Run all eight properties at 1080p on the target mid-range PC, medium
   settings, with 4 players. Record worst-case frame time in the hotel lobby and the
   breathing house (the two heaviest). Fill in the GPU column in `PERFORMANCE.md`.
2. **Voice chat.** Two machines with real microphones: verify capture, push-to-talk,
   occlusion muffling through walls, and that four speakers do not clip. There is currently
   no automated proof of this feature.
3. **Windows `.exe`.** The export is produced with the official template but has never
   been executed (this environment is Linux). Run it, check the icon, check that it does not
   trip antivirus heuristics (an unsigned Godot exe often does — consider code signing).
4. **Four-player session over the internet.** Two sites, port-forwarded or via a VPN, to
   confirm ENet survives real latency and NAT.
5. **Soak test.** Three hours, five contracts, watch memory and thermals.

## 6. Steam and legal (blocking, 1–2 weeks, needs accounts and money)

- Steamworks partner account + $100 app fee; app id; depots; launch options.
- Steam transport implementation (`MULTIPLAYER.md` → "Steam transport plan").
- Map the 11 achievements to Steam achievement API names.
- EULA, privacy policy (the game collects nothing, so the policy is short but required),
  and the mature-content survey.
- Age rating submissions (IARC / ESRB / PEGI) — mild fantasy horror, no gore, no drugs, no
  sexual content, but dread and threat throughout.
- Code signing certificate for the Windows executable.

## 7. Localisation (optional, 2–4 weeks)

All strings are inline in scripts. Before translation, extract them into a `.csv`/
`.translation` catalogue and replace literals with `tr()`. Then: UI labels, contract text,
memos, flavour pools (announcements, emails, tips, report lines, both endings), and
achievement text. Voice is English-only; subtitles would need to match re-recorded lines if
audio is localised.

## 8. Marketing material (1 week)

Screenshots with four players, a trailer, Steam capsules (616×353, 460×215, 1920×620,
3840×1240), a short loop of a sofa failing to fit through a door, and a store description
in the company's deadpan voice. The in-game screenshots must be captured from a real
four-player session, not staged.

## 9. Playtesting (2–3 weeks, blocking for balance)

Eight properties have never been played by a human. What needs answering:

- Does the deadline pressure feel fair on properties 1–3 and punishing on 7–8?
- Is the carry weight curve satisfying, or is the grand piano just miserable?
- Are creatures a spice or a nuisance? Does the banishing counterplay read?
- Is the payout curve (900 → 12,000) aligned with the upgrade costs (0 → 1,600)?
- Where does the game need a tutorial and does the Willow contract cover it?

Expect balance numbers to move in `resources/properties.json` (deadline, base_pay) and
`scripts/physics/furniture.gd` (carry constants) as a result.

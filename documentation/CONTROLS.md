# THE LAST MOVE — controls

## On foot

| action | keyboard / mouse | notes |
| --- | --- | --- |
| Move | `W A S D` / arrow keys | 3.15 m/s walk, 5.25 m/s sprint, 1.65 m/s crouch |
| Look | Mouse | sensitivity and invert-Y in Settings |
| Sprint | `Shift` | drains stamina; carrying heavy items drains it faster |
| Crouch | `Ctrl` or `C` | reduces noise, changes head height, slower |
| Jump | `Space` | 5.15 m/s — just enough for a truck bed, not enough for a counter |
| Grab / release | `E` / Left mouse | hold to keep the grip; release to drop |
| Rotate carried item | `Q` / `R` | torque-based; heavy items turn slowly |
| Throw | `G` / Right mouse | throws what you are holding. Yes, at the creature |
| Leave contract | `[E]` at the truck | the truck only leaves when every living mover is beside it |
| Flashlight | `F` | the only reliable deterrent |
| Push to talk | `V` | proximity voice, spatialised, occluded by walls |
| Scoreboard | `Tab` (hold) | crew, ping, contract progress |
| Emote | `X` | contextual line |
| Pause | `Esc` | pause menu, settings, contract, leave |

Additional contexts:

- **Interact prompts** appear when a door, the contract board, the departure point, the
  equipment station or the truck doors are in range. The prompt always states what the
  action does, not just "use".
- **Revive**: stand next to a downed crewmate and hold interact for 2.2 seconds.
- **Contract board** (in the property and at headquarters): re-reads the contract and the
  company memo.

## Multiplayer defaults

| item | value |
| --- | --- |
| Port | `27015` (editable in the host dialog) |
| Max crew | 4 |
| Password | optional, hashed before it leaves the client |
| Discovery | direct IP entry; Steam lobby handles this once the Steam transport is wired |

## Accessibility

Everything below is a persistent setting (`user://settings.cfg`), applied on boot.

| setting | effect |
| --- | --- |
| Render scale 0.5–1.0 | resolution scaling for weak GPUs |
| Anti-aliasing | off / 2× / 4× MSAA |
| Shadows | off / low / high |
| FPS limit | unlimited / 60 / 120 / 144 |
| Volume sliders | master, music, effects, ambience, voice |
| Push to talk | optional open mic |
| Microphone gain | 0.2–3.0 |
| Mouse sensitivity / FOV / invert Y | standard |
| Head bob | 0–1, can be zeroed completely |
| View sway | 0–1, can be zeroed completely |
| Camera shake | 0–1, can be zeroed completely |
| Reduce flashing | light-flicker events become a single slow dim instead of a strobe |
| Subtitles | on by default; PA lines and story beats are always subtitled |

Not yet implemented, and listed honestly in `PLACEHOLDER_REGISTER.md`: full key rebinding
UI (the InputMap is built from a table in `settings_manager.gd` but there is no remap
screen yet), colour-blind palettes, and gamepad support.

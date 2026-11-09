# Publishing the repository to GitHub

The project is a normal Git repository with a single commit on `main`; nothing about the
source depends on GitHub. This page covers how to get it onto a remote and what is
deliberately *not* committed.

## What is in the repository

425 tracked files, ~13 MB of history: all GDScript, scenes, resources, the generated
texture and audio assets, the test suites, the build/asset-regeneration tools and the
documentation.

## What is not committed (and why)

| Excluded | Reason | How to regenerate |
| --- | --- | --- |
| `.godot/` | Godot import cache, editor state | `godot --headless --path . --import` |
| `build/`, `dist/` | exported binaries and zips, large and reproducible | `tools/build_all.sh` |
| `tests/mp_logs/` | per-run multiplayer probe logs | `tools/mp_test.sh` |
| `*.exe`, `*.pck` | export output | `tools/build_all.sh` |

`assets/textures/*.png` and `assets/audio/*` **are** committed: they are original
generated work and the game should build from a fresh clone without re-running the
generators. `tools/generate_textures.py` and `tools/generate_audio.py` reproduce them if
you ever want to rebake.

## Pushing to an existing repository

```bash
GH_TOKEN=ghp_xxxxxxxxxxxxxxxx tools/push_to_github.sh https://github.com/<you>/the-last-move.git
```

* the token is used for that one push through a temporary credential helper — it is never
  written into `.git/config`, so it cannot leak if the repository is later made public
* an SSH remote works too: `tools/push_to_github.sh git@github.com:<you>/the-last-move.git`
* the script renames the local branch to `main`, sets `origin` and pushes with `-u`

## Creating the repository first

Either create it in the web UI (github.com/new) — public or private, **do not** initialise
it with a README, since the local history already has one — or, with the GitHub CLI:

```bash
gh repo create the-last-move --private --source=. --remote=origin --push
```

## Notes for a public release

* The game is currently **not** licensed for redistribution by third parties: add a
  `LICENSE` file before publishing if you want to grant rights. All art and audio in the
  repo is original procedural work made for this project, so there is no third-party
  content to reconcile.
* Steam-specific configuration, store assets and depots are *not* in this repository;
  see `documentation/STEAM_CHECKLIST.md`.

# shelltoolbox

A personal Linux shell environment installer for **Debian 13 (trixie) only**. One script sets up Starship, a Nerd Font, fastfetch, and a curated set of shell aliases — no build system, no test suite, four config files.

## Files

| File | Purpose |
|---|---|
| `setup-sh.sh` | Idempotent installer — the only entry point |
| `uninstall-sh.sh` | Reverses everything the installer did |
| `.bashrc` | Bash config (aliases, functions, fastfetch on startup) |
| `starship.toml` | Starship prompt config, written in palette "slot" colors |
| `config.jsonc` | fastfetch config (system info on shell startup) |
| `starship-theme` | Palette switcher for `starship.toml` |

## Quick start

```sh
git clone <this repo> && cd shelltoolbox
chmod +x setup-sh.sh
./setup-sh.sh
exec bash
```

Re-running is safe: every step checks state before acting. After editing any file in this repo, re-run the installer — the repo is only a staging area, and the live files are copies in `~/.local/share/shelltoolbox` symlinked into place.

## What the installer does

1. **apt dependencies** — bash-completion, bat, tree, multitail, fastfetch, vim, neovim, trash-cli, fzf, zoxide, curl, fontconfig, tar, xz-utils (only the ones missing).
2. **Starship** — downloaded from starship.rs to `~/.local/bin` (no sudo).
3. **CaskaydiaMono Nerd Font** — downloaded from the Nerd Fonts releases into `~/.local/share/fonts`.
4. **Configs** — copies everything to `~/.local/share/shelltoolbox`, then symlinks:

   | Live path | Points to |
   |---|---|
   | `~/.bashrc` | `~/.local/share/shelltoolbox/.bashrc` |
   | `~/.config/starship.toml` | `~/.local/share/shelltoolbox/starship.toml` |
   | `~/.config/fastfetch/config.jsonc` | `~/.local/share/shelltoolbox/config.jsonc` |
   | `~/.local/bin/starship-theme` | `~/.local/share/shelltoolbox/starship-theme` |

   Anything in the way is backed up as `<target>.bak.<timestamp>`, never deleted.
5. **Terminal font** — points Ptyxis / GNOME Terminal at `CaskaydiaMono Nerd Font 12` via gsettings (or prints a manual hint). Original settings are saved first.

The linked `.bashrc` handles the rest on startup: fastfetch, Starship and zoxide init, and the aliases below.

## The aliases worth knowing

The `.bashrc` is derived from the zachbrowne.me / Chris Titus Tech alias collection, and its aliases are intentionally invasive:

- `rm` → `trash-put` (with `gio trash` / `rm -i` fallbacks) — nothing is ever really deleted
- bare `cd` prints the directory contents after switching
- `Ctrl+f` opens zoxide's interactive jumper (`zi`)
- `fastfetch` runs on every interactive shell start

## Switching prompt palettes

`starship-theme` swaps the six color "slots" in `starship.toml` for any of 12 palettes:

```sh
starship-theme          # pick interactively with fzf
starship-theme list     # show palettes
starship-theme nord     # apply one directly
```

Available palettes: ubuntu, claude, arch, fedora, debian, mint, manjaro, popos, kali, gentoo, dracula, nord.

Note: the repo's `starship.toml` is deliberately kept in its pristine (nord slot) form — that's what `starship-theme` validates against and rewrites. Applied palettes are written to `~/.config/starship.toml`, not back to the repo.

## Uninstall

```sh
./uninstall-sh.sh        # asks first
./uninstall-sh.sh -y     # no prompt
```

Reverses everything: restores terminal font settings from the installer's backups, unlinks the four symlinks (restoring the `.bak.<timestamp>` backups, falling back to `/etc/skel/.bashrc`), removes `~/.local/share/shelltoolbox`, the Nerd Font, and the Starship binary. apt packages are only removed when nothing installed depends on them — `tar`, `curl`, `fontconfig` and `xz-utils` are typically kept because `dpkg`, `firefox-esr` and friends need them, and the script says so as it goes.

Also idempotent, so it's safe to re-run (e.g. to retry the apt step after a failure — apt transactions are all-or-nothing).
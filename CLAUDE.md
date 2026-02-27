# Custom Arch Linux Installer

## Project Overview

A modular, bash-based Arch Linux workstation installer with a Sway/Wayland desktop.
Runs from a live Arch ISO (stock or custom-built). Part of a three-repo architecture:
**arch-install** (system-level install), **debian-server** (server install), **dotfiles** (user-level config).
This repo handles partitioning, packages, services, and hardware. User-level configuration
(shell, editor, desktop configs) is deployed from the dotfiles repo via `profiles/base.sh`.

See @docs/TODO.md for the roadmap and @docs/ARCHITECTURE.md for structural details.

## Current Status

Phases 0-2 complete. All scripts pass shellcheck. Tested end-to-end in Hyper-V VM
including all packages, services, modules, AUR builds, and dotfiles integration.

## Git

- Do not add Claude as co-author in git commit messages
- Do not commit files that contain secrets (.env, credentials, passwords)

## Code Conventions

- All scripts use `#!/usr/bin/env bash` shebang
- Every script starts with `set -euo pipefail`
- Use `shellcheck`-clean bash — no bashisms that shellcheck flags
- Use `shellcheck -x` to follow source directives
- Indent with 2 spaces, no tabs
- Functions use `snake_case`, variables use `UPPER_SNAKE_CASE` for config, `lower_snake` for locals
- Use `local` for all function-scoped variables
- Quote all variable expansions: `"$var"`, `"${array[@]}"`
- Prefer `[[ ]]` over `[ ]` for conditionals
- Prefer `$(command)` over backticks
- Use `printf '%b...'` for color codes, never put variables in printf format strings

## File Organization

- `install.sh` — entry point, sources lib and runs workstation profile
- `config.sh` — default configuration variables (USERNAME is prompted, not hardcoded)
- `lib/` — shared utilities (logging, disk ops, checks, chroot wrapper, UI prompts)
- `profiles/workstation.sh` — workstation profile orchestrator
- `profiles/base.sh` — base setup: AUR helper (yay) + dotfiles deployment
- `modules/` — feature scripts (gpu, firewall, ssh, virtualization)
- `packages/` — plain-text package lists, one package per line, `#` for comments
- `iso/` — custom ISO build system (Dockerfile + archiso overlay + build script)
- `tests/` — VM test configs, ISO download, VM creation scripts, and testing guide
- `docs/` — project documentation

## Commands

- Lint: `npx shellcheck -x install.sh lib/*.sh profiles/*.sh modules/*.sh`
- Build custom ISO: `docker build -t archiso-builder iso/ && docker run --rm --privileged -v "$(pwd)":/build archiso-builder`
- Download stock ISO: `.\tests\download-iso.ps1`
- Create test VM: `.\tests\create-vm.ps1`
- Test in VM: see `tests/README.md` for full guide

## Key Patterns

- All user-facing output goes through `lib/log.sh` (`log_info`, `log_warn`, `log_error`, `log_section`)
- Package installation uses `install_packages_from_list <file.list>` reading from `packages/`
- Modules handle non-trivial system-level work (GPU detection, config file generation, virtualization)
- Simple setup steps (env vars, group membership, font cache) are inlined in `workstation.sh`
- User-level config deployment is NOT in this repo — it's in the dotfiles repo
- Everything after pacstrap runs inside chroot via `lib/chroot.sh`
- Configuration variables follow a 3-layer precedence: CLI flags > config file > `config.sh` defaults
- All interactive input (username, hostname, timezone, passwords) is collected up front before install begins
- `--auto` flag enables fully unattended mode (skips confirmations, uses `PASSWORD` from config)
- AUR packages (google-chrome, dropbox, python-gpgme) are installed via yay in the workstation profile
- Default shell is zsh; user is created with `/usr/bin/zsh`
- Username and hostname are always prompted (no defaults) unless set via CLI/config
- Docker and QEMU/KVM are always installed
- Custom ISO auto-launches an install menu on boot (full install / test install / shell)

## Editing Guidelines

- When adding a new feature, create a module in `modules/` and a package list in `packages/`
- Do not hardcode package names in scripts — always use package list files
  - Exception: modules that install small sets of tightly-coupled packages (GPU drivers, virtualization)
- Do not add user-level configs to this repo — they belong in the dotfiles repo
- Keep modules independent — a module should work regardless of what calls it
- Test changes with `shellcheck -x` before committing
- AUR packages go in the workstation profile (not package lists), installed via `sudo -u "$USERNAME" yay -S`

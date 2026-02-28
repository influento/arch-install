#!/usr/bin/env bash
# config.sh — Default configuration variables
# Override via CLI flags, config file (--config), or environment variables.

# --- Disk ---
TARGET_DISK="${TARGET_DISK:-}"                # /dev/sdX or /dev/nvmeXnY (prompted if empty)
FS_TYPE="${FS_TYPE:-ext4}"                    # ext4 | btrfs
EFI_SIZE="${EFI_SIZE:-1G}"                    # EFI system partition size
ROOT_SIZE="${ROOT_SIZE:-}"                    # default 128G (auto-set if empty)
SWAP_SIZE="${SWAP_SIZE:-}"                    # auto: RAM size, min 8G
WIPE_HOME="${WIPE_HOME:-}"                   # yes|no (prompted if empty and existing /home found)

# --- System ---
HOSTNAME=""                                   # always prompt (shell sets HOSTNAME automatically)
USERNAME="${USERNAME:-}"                       # non-root user (prompted if empty)
TIMEZONE="${TIMEZONE:-UTC}"                   # prompted if still UTC at install time
LOCALE="${LOCALE:-en_US.UTF-8}"
KEYMAP="${KEYMAP:-us}"

# --- Boot ---
BOOTLOADER="${BOOTLOADER:-grub}"               # grub (UEFI only)

# --- Hardware ---
GPU_DRIVER="${GPU_DRIVER:-auto}"              # auto | amd | intel | nvidia | none

# --- Software ---
EDITOR="${EDITOR:-nvim}"                      # default editor for visudo, git, etc.
AUR_HELPER="${AUR_HELPER:-yay}"               # yay | paru

# --- Repos (cloned to ~/dev/infra/) ---
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/influento/dotfiles.git}"
DOTFILES_DEST="${DOTFILES_DEST:-}"            # clone target (auto-set to /home/$USERNAME/dev/infra/dotfiles)
ARCH_INSTALL_REPO="${ARCH_INSTALL_REPO:-https://github.com/influento/arch-install.git}"
SERVER_INSTALL_REPO="${SERVER_INSTALL_REPO:-https://github.com/influento/debian-server.git}"

# --- Mirrors ---
MIRROR_COUNTRY="${MIRROR_COUNTRY:-}"          # reflector country filter (e.g. "US" or "US,DE")

# --- Paths (internal, don't override) ---
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/arch-install.log}"
MOUNT_POINT="${MOUNT_POINT:-/mnt}"

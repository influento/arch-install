#!/usr/bin/env bash
# install.sh — Main entry point for the custom Arch Linux installer
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Resolve installer directory
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source defaults
# shellcheck source=config.sh
source "${INSTALLER_DIR}/config.sh"

# Source libraries
# shellcheck source=lib/log.sh
source "${INSTALLER_DIR}/lib/log.sh"
source "${INSTALLER_DIR}/lib/ui.sh"
source "${INSTALLER_DIR}/lib/checks.sh"
source "${INSTALLER_DIR}/lib/disk.sh"
source "${INSTALLER_DIR}/lib/packages.sh"
source "${INSTALLER_DIR}/lib/pacstrap.sh"
source "${INSTALLER_DIR}/lib/chroot.sh"

# --- CLI argument parsing ---

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --disk DEVICE         Target disk (e.g. /dev/nvme0n1, /dev/sda)
  --hostname NAME       System hostname (prompted if not set)
  --user USERNAME       Non-root username (prompted if not set)
  --timezone ZONE       Timezone (default: UTC, prompted if UTC)
  --locale LOCALE       System locale (default: en_US.UTF-8)
  --keymap MAP          Console keymap (default: us)
  --fs-type TYPE        Root filesystem: ext4 | btrfs (default: ext4)
  --swap SIZE           Swap size (e.g. 8G, 16G; auto-detected from RAM if omitted)
  --root-size SIZE      Root partition size (default: 128G)
  --wipe-home yes|no    Wipe /home or keep existing
  --mirror-country CC   Reflector country filter (e.g. US, "US,DE")
  --config FILE         Source a config file with variable overrides
  --auto                Unattended mode (skip confirmations, use PASSWORD var)
  --dry-run             Show what would be done without making changes
  --debug               Enable debug output
  --help                Show this help message
EOF
  exit 0
}

DRY_RUN=0
AUTO_MODE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --disk)        TARGET_DISK="$2"; shift 2 ;;
    --hostname)    HOSTNAME="$2"; shift 2 ;;
    --user)        USERNAME="$2"; shift 2 ;;
    --timezone)    TIMEZONE="$2"; shift 2 ;;
    --locale)      LOCALE="$2"; shift 2 ;;
    --keymap)      KEYMAP="$2"; shift 2 ;;
    --fs-type)     FS_TYPE="$2"; shift 2 ;;
    --swap)        SWAP_SIZE="$2"; shift 2 ;;
    --root-size)   ROOT_SIZE="$2"; shift 2 ;;
    --wipe-home)   WIPE_HOME="$2"; shift 2 ;;
    --mirror-country) MIRROR_COUNTRY="$2"; shift 2 ;;
    --config)      # shellcheck source=/dev/null
                   source "$2"; shift 2 ;;
    --auto)        AUTO_MODE=1; shift ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --debug)       DEBUG=1; shift ;;
    --help)        usage ;;
    *)             die "Unknown option: $1. Use --help for usage." ;;
  esac
done

# --- Initialize logging ---

mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
log_info "Arch Linux Installer started"
log_info "Log file: $LOG_FILE"

# --- Preflight ---

run_preflight_checks

# --- Detect geo location (timezone default + mirror country) ---

_GEO_TIMEZONE=""
_GEO_COUNTRY=""

if [[ "$TIMEZONE" == "UTC" || -z "$MIRROR_COUNTRY" ]]; then
  log_info "Detecting location..."
  _geo_json="$(curl -sf --max-time 5 "https://ipapi.co/json/" 2>/dev/null)" || _geo_json=""

  # Fallback to ip-api.com
  if [[ -z "$_geo_json" ]]; then
    _geo_json="$(curl -sf --max-time 5 "http://ip-api.com/json/?fields=countryCode,timezone" 2>/dev/null)" || _geo_json=""
  fi

  if [[ -n "$_geo_json" ]]; then
    # ipapi.co uses "country_code", ip-api.com uses "countryCode" — try both
    _GEO_COUNTRY="$(printf '%s' "$_geo_json" | sed -n 's/.*"country_code": *"\([^"]*\)".*/\1/p')"
    [[ -z "$_GEO_COUNTRY" ]] && _GEO_COUNTRY="$(printf '%s' "$_geo_json" | sed -n 's/.*"countryCode": *"\([^"]*\)".*/\1/p')"
    _GEO_TIMEZONE="$(printf '%s' "$_geo_json" | sed -n 's/.*"timezone": *"\([^"]*\)".*/\1/p')"
  fi

  # Validate country code (exactly 2 uppercase letters)
  if [[ ! "$_GEO_COUNTRY" =~ ^[A-Z]{2}$ ]]; then
    _GEO_COUNTRY=""
  fi

  # Validate timezone (must exist in zoneinfo)
  if [[ -n "$_GEO_TIMEZONE" && ! -f "/usr/share/zoneinfo/${_GEO_TIMEZONE}" ]]; then
    _GEO_TIMEZONE=""
  fi

  if [[ -n "$_GEO_COUNTRY" || -n "$_GEO_TIMEZONE" ]]; then
    log_info "Detected: country=${_GEO_COUNTRY:-unknown}, timezone=${_GEO_TIMEZONE:-unknown}"
  else
    log_warn "Could not detect location."
  fi

  # Set mirror country if not already configured
  if [[ -z "$MIRROR_COUNTRY" && -n "$_GEO_COUNTRY" ]]; then
    MIRROR_COUNTRY="$_GEO_COUNTRY"
  fi
fi

# --- Gather configuration interactively ---

log_section "Configuration"

# Username
if [[ -z "$USERNAME" ]]; then
  USERNAME=$(prompt_input "Enter non-root username" "")
  while [[ -z "$USERNAME" ]]; do
    log_warn "Username cannot be empty."
    USERNAME=$(prompt_input "Enter non-root username" "")
  done
fi
log_info "Username: $USERNAME"

# Hostname
if [[ -z "$HOSTNAME" ]]; then
  HOSTNAME=$(prompt_input "Enter hostname" "")
  while [[ -z "$HOSTNAME" ]]; do
    log_warn "Hostname cannot be empty."
    HOSTNAME=$(prompt_input "Enter hostname" "")
  done
fi
log_info "Hostname: $HOSTNAME"

# Timezone — prompt if still default UTC, suggest detected timezone
if [[ "$TIMEZONE" == "UTC" ]]; then
  _tz_default="${_GEO_TIMEZONE:-UTC}"
  TIMEZONE=$(prompt_input "Enter timezone (e.g. America/New_York)" "$_tz_default")
  while [[ ! -f "/usr/share/zoneinfo/${TIMEZONE}" ]]; do
    log_warn "Invalid timezone: $TIMEZONE"
    TIMEZONE=$(prompt_input "Enter timezone (e.g. America/New_York)" "$_tz_default")
  done
fi
log_info "Timezone: $TIMEZONE"

# Passwords — collect now so the rest of the install is unattended
if [[ -n "${PASSWORD:-}" ]]; then
  # PASSWORD set via config/env (e.g. test runs) — use for both
  ROOT_PASSWORD="$PASSWORD"
  USER_PASSWORD="$PASSWORD"
else
  ROOT_PASSWORD=$(prompt_password "Root password")
  USER_PASSWORD=$(prompt_password "Password for $USERNAME")
fi
export ROOT_PASSWORD USER_PASSWORD

# Disk selection
if [[ -z "$TARGET_DISK" ]]; then
  TARGET_DISK=$(select_disk)
fi
log_info "Target disk: $TARGET_DISK"

# Swap size (RAM-based, min 8G)
if [[ -z "$SWAP_SIZE" ]]; then
  SWAP_SIZE=$(detect_swap_size)
fi
log_info "Swap size: $SWAP_SIZE"

# Root size default: 128G
if [[ -z "$ROOT_SIZE" ]]; then
  ROOT_SIZE="128G"
fi

# Check for existing /home and ask about wipe
if [[ -z "$WIPE_HOME" ]]; then
  _prefix=$(part_prefix "$TARGET_DISK")
  if [[ -b "${_prefix}4" ]]; then
    log_warn "Existing partition detected at ${_prefix}4 (possibly /home)."
    if confirm "Wipe /home partition? (No = keep existing data, reformat only EFI+swap+root)"; then
      WIPE_HOME="yes"
    else
      WIPE_HOME="no"
    fi
  else
    WIPE_HOME="yes"
  fi
fi

# --- Show summary and confirm ---

print_summary \
  "Hostname=$HOSTNAME" \
  "Username=$USERNAME" \
  "Timezone=$TIMEZONE" \
  "Locale=$LOCALE" \
  "Keymap=$KEYMAP" \
  "Filesystem=$FS_TYPE" \
  "Swap=$SWAP_SIZE" \
  "Root size=$ROOT_SIZE" \
  "Kernels=linux + linux-lts" \
  "Bootloader=$BOOTLOADER" \
  "Disk=$TARGET_DISK" \
  "Wipe /home=$WIPE_HOME"

if [[ "$DRY_RUN" -eq 1 ]]; then
  log_info "Dry run — exiting before making changes."
  exit 0
fi

confirm "Proceed with installation?" || die "Aborted by user."

# ===================================================================
#  Phase 1: Disk + Base System (live ISO environment)
# ===================================================================

setup_disk

# Pre-resolve UUIDs while we still have direct device access
SWAP_UUID=""
if [[ -n "${PART_SWAP:-}" ]]; then
  SWAP_UUID="$(blkid -s UUID -o value "$PART_SWAP")"
fi
export SWAP_UUID

setup_mirrors
bootstrap_base_system

# ===================================================================
#  Phase 2: System Configuration (inside chroot)
# ===================================================================

run_in_chroot "lib/configure.sh" "configure_system" "enable_base_services"

# ===================================================================
#  Phase 3: Profile Execution (inside chroot)
# ===================================================================

run_in_chroot "profiles/workstation.sh"

# ===================================================================
#  Post-chroot fixups (must happen outside chroot)
# ===================================================================

# Point resolv.conf to systemd-resolved stub resolver.
# This can't be done inside chroot because arch-chroot bind-mounts
# the host's /etc/resolv.conf for DNS resolution during the session.
log_info "Configuring resolv.conf symlink..."
rm -f "${MOUNT_POINT}/etc/resolv.conf"
ln -s ../run/systemd/resolve/stub-resolv.conf "${MOUNT_POINT}/etc/resolv.conf"

# ===================================================================
#  Cleanup and Reboot
# ===================================================================

log_section "Installation Complete"

cleanup_chroot

log_info "Installation finished successfully!"
log_info "Log saved to: ${MOUNT_POINT}${LOG_FILE}"

# Copy log into the installed system
cp "$LOG_FILE" "${MOUNT_POINT}${LOG_FILE}" 2>/dev/null || true

log_info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
sleep 5
swapoff -a 2>/dev/null || true
umount -R "$MOUNT_POINT" 2>/dev/null || true
reboot

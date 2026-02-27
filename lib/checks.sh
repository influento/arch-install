#!/usr/bin/env bash
# lib/checks.sh — Preflight checks before installation

run_preflight_checks() {
  log_section "Preflight Checks"

  check_root
  check_uefi
  check_network
  check_disks
  sync_clock
  apply_live_keymap
  refresh_keyring

  log_info "All preflight checks passed."
}

check_root() {
  if [[ $EUID -ne 0 ]]; then
    die "This script must be run as root."
  fi
  log_info "Running as root — OK"
}

check_uefi() {
  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    die "UEFI boot mode not detected. This installer requires UEFI. Disable CSM/Legacy in your firmware settings."
  fi
  log_info "UEFI boot mode detected — OK"
}

check_network() {
  if ping -c 1 -W 3 archlinux.org &>/dev/null; then
    log_info "Network connectivity — OK"
    return 0
  fi

  log_warn "No network connectivity detected."

  # In auto mode, don't attempt interactive WiFi setup
  if [[ "${AUTO_MODE:-0}" -eq 1 ]]; then
    die "No network connectivity. Ensure network is available before using --auto mode."
  fi

  # Check for wireless devices and offer WiFi setup
  if _has_wireless_devices && command -v iwctl &>/dev/null; then
    while true; do
      if ! confirm "Set up WiFi?"; then
        break
      fi
      _setup_wifi
      if _wait_for_network; then
        log_info "Network connectivity — OK"
        return 0
      fi
      log_warn "Still no connectivity after WiFi setup."
    done
  fi

  die "No network connectivity. Connect via Ethernet or use 'iwctl' to set up WiFi before running the installer."
}

_has_wireless_devices() {
  local dev_path
  for dev_path in /sys/class/net/*/wireless; do
    [[ -e "$dev_path" ]] && return 0
  done
  return 1
}

_wait_for_network() {
  local _i
  for _i in $(seq 1 10); do
    if ping -c 1 -W 3 archlinux.org &>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

_setup_wifi() {
  local device ssid passphrase

  # Unblock WiFi if soft-blocked
  rfkill unblock wifi 2>/dev/null || true

  # Find wireless devices
  local devices=()
  local dev_path
  for dev_path in /sys/class/net/*/wireless; do
    [[ -e "$dev_path" ]] || continue
    local dev_name
    dev_name="$(basename "$(dirname "$dev_path")")"
    devices+=("$dev_name")
  done

  # Pick device
  if [[ ${#devices[@]} -eq 1 ]]; then
    device="${devices[0]}"
    log_info "Using wireless device: $device"
  else
    device=$(select_option "Select wireless device" "${devices[@]}")
  fi

  # Ensure device is powered on
  ip link set "$device" up 2>/dev/null || true

  # Scan for networks
  log_info "Scanning for wireless networks..."
  iwctl station "$device" scan
  sleep 3

  # Display available networks
  printf '\n' >&2
  iwctl station "$device" get-networks
  printf '\n' >&2

  # Prompt for SSID
  ssid=$(prompt_input "Enter WiFi network name (SSID)" "")
  if [[ -z "$ssid" ]]; then
    log_warn "No SSID entered."
    return 1
  fi

  # Prompt for passphrase
  printf '%b:: %bWiFi passphrase (leave empty for open network): ' "$_CLR_CYAN" "$_CLR_RESET" >&2
  read -rs passphrase
  printf '\n' >&2

  # Connect
  log_info "Connecting to $ssid..."
  if [[ -n "$passphrase" ]]; then
    iwctl --passphrase "$passphrase" station "$device" connect "$ssid" || true
  else
    iwctl station "$device" connect "$ssid" || true
  fi
}

check_disks() {
  local disk_count
  disk_count=$(lsblk -dpno NAME | grep -cE '(sd|nvme|vd)' || true)
  if [[ "$disk_count" -eq 0 ]]; then
    die "No suitable block devices found."
  fi
  log_info "Found $disk_count block device(s) — OK"
}

sync_clock() {
  # Ensure system clock is accurate (prevents TLS/SSL failures during install)
  run_logged "Enabling NTP time sync" timedatectl set-ntp true
  log_info "System clock synced — OK"
}

apply_live_keymap() {
  # Apply console keymap in the live environment if non-default
  if [[ "$KEYMAP" != "us" ]]; then
    run_logged "Loading keymap: $KEYMAP" loadkeys "$KEYMAP"
  fi
}

refresh_keyring() {
  # Initialize keyring if missing or corrupted (common on older/custom ISOs)
  if ! pacman-key --list-keys &>/dev/null; then
    run_logged "Initializing pacman keyring" pacman-key --init
    run_logged "Populating Arch Linux keys" pacman-key --populate archlinux
  fi
  # Refresh pacman keyring — stale keys on older ISOs cause signature failures
  run_logged "Refreshing pacman keyring" pacman -Sy --noconfirm archlinux-keyring
}

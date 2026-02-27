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

  # Unblock WiFi before checking for devices (soft-block can hide interfaces)
  rfkill unblock wifi 2>/dev/null || true

  # If WiFi hardware exists but no interface, try reloading the driver
  if ! _has_wireless_devices && _has_wifi_hardware; then
    _recover_wifi_driver
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
  else
    if ! command -v iwctl &>/dev/null; then
      log_warn "iwctl not available — cannot set up WiFi interactively."
    elif ! _has_wireless_devices; then
      log_warn "No wireless devices detected."
      _print_wifi_diagnostics
    fi
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

_has_wifi_hardware() {
  # Check if PCI lists any wireless/WiFi hardware (even if driver failed to load)
  lspci 2>/dev/null | grep -qi 'network controller\|wireless' 2>/dev/null
}

_recover_wifi_driver() {
  local _attempt driver
  driver="iwlwifi"

  # Detect the right driver from PCI device info
  if lspci -k 2>/dev/null | grep -qi 'ath[0-9]\|qualcomm'; then
    driver="ath10k_pci"
  elif lspci -k 2>/dev/null | grep -qi 'broadcom'; then
    driver="brcmfmac"
  fi

  log_warn "WiFi hardware found but no interface — attempting driver reload ($driver)..."

  # Attempt 1: simple driver reload (handles soft failures)
  modprobe -r "$driver" 2>/dev/null || true
  sleep 1
  modprobe "$driver" 2>/dev/null || true
  sleep 3

  if _has_wireless_devices; then
    log_info "WiFi interface recovered after driver reload."
    return 0
  fi

  # Attempt 2: PCI device reset (handles warm-reboot firmware hangs)
  log_warn "Driver reload failed — attempting PCI device reset..."
  if _reset_wifi_pci_device "$driver"; then
    return 0
  fi

  log_warn "WiFi recovery failed after all attempts."
  return 1
}

_reset_wifi_pci_device() {
  local driver="$1"
  local pci_addr

  # Find the PCI address of the wireless device
  pci_addr=$(lspci -D 2>/dev/null | grep -i 'network controller\|wireless' | awk '{print $1}' | head -1)
  if [[ -z "$pci_addr" ]]; then
    log_warn "Could not find WiFi PCI address for reset."
    return 1
  fi

  log_warn "Resetting PCI device $pci_addr..."

  # Unload the driver first
  modprobe -r "$driver" 2>/dev/null || true
  sleep 1

  # Remove the device from the PCI bus (forces hardware teardown)
  if [[ -e "/sys/bus/pci/devices/$pci_addr/remove" ]]; then
    echo 1 > "/sys/bus/pci/devices/$pci_addr/remove"
    sleep 2
  else
    log_warn "PCI device sysfs path not found — skipping reset."
    return 1
  fi

  # Rescan the PCI bus (re-discovers and reinitializes the device)
  echo 1 > /sys/bus/pci/rescan
  sleep 3

  # Load the driver for the freshly initialized hardware
  modprobe "$driver" 2>/dev/null || true
  sleep 3

  if _has_wireless_devices; then
    log_info "WiFi interface recovered after PCI device reset."
    return 0
  fi

  log_warn "PCI device reset did not recover WiFi interface."
  return 1
}

_print_wifi_diagnostics() {
  log_warn "--- WiFi diagnostics ---"
  log_warn "PCI devices:"
  lspci 2>/dev/null | grep -i 'network controller\|wireless' | while IFS= read -r line; do
    log_warn "  $line"
  done
  log_warn "rfkill status:"
  rfkill list 2>/dev/null | while IFS= read -r line; do
    log_warn "  $line"
  done
  log_warn "Check 'dmesg | grep -i iwlwifi' from a shell for firmware errors."
  log_warn "------------------------"
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

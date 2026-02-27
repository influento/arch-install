#!/usr/bin/env bash
# lib/ui.sh — User prompts, menus, and confirmation dialogs

# Prompt the user for text input.
# Usage: result=$(prompt_input "Enter hostname" "default-value")
prompt_input() {
  local prompt_text="$1"
  local default="${2:-}"
  local input

  if [[ -n "$default" ]]; then
    printf '%b:: %b%s [%b%s%b]: ' "$_CLR_CYAN" "$_CLR_RESET" "$prompt_text" "$_CLR_BOLD" "$default" "$_CLR_RESET" >&2
  else
    printf '%b:: %b%s: ' "$_CLR_CYAN" "$_CLR_RESET" "$prompt_text" >&2
  fi

  read -r input
  if [[ -z "$input" && -n "$default" ]]; then
    input="$default"
  fi
  printf '%s' "$input"
}

# Prompt for a password (no echo). Asks twice for confirmation.
# In AUTO_MODE, uses PASSWORD variable if set.
# Usage: result=$(prompt_password "Enter root password")
prompt_password() {
  local prompt_text="$1"

  if [[ "${AUTO_MODE:-0}" -eq 1 && -n "${PASSWORD:-}" ]]; then
    log_info "Using pre-set password for: $prompt_text"
    printf '%s' "$PASSWORD"
    return 0
  fi

  local pass1 pass2

  while true; do
    # Flush any buffered stdin (stray keypresses during long installs)
    while read -t 0.01 -n 1 -rs _ 2>/dev/null; do :; done

    printf '%b:: %b%s: ' "$_CLR_CYAN" "$_CLR_RESET" "$prompt_text" >&2
    read -rs pass1
    printf '\n' >&2

    printf '%b:: %bConfirm: ' "$_CLR_CYAN" "$_CLR_RESET" >&2
    read -rs pass2
    printf '\n' >&2

    if [[ "$pass1" == "$pass2" ]]; then
      if [[ -z "$pass1" ]]; then
        log_warn "Password cannot be empty. Try again."
        continue
      fi
      printf '%s' "$pass1"
      return 0
    else
      log_warn "Passwords do not match. Try again."
    fi
  done
}

# Yes/No confirmation. Auto-accepts in AUTO_MODE.
# Usage: confirm "Wipe /dev/sda?" || exit 1
confirm() {
  local prompt_text="$1"

  if [[ "${AUTO_MODE:-0}" -eq 1 ]]; then
    log_info "Auto-confirmed: $prompt_text"
    return 0
  fi

  local response
  printf '%b:: %b%s [y/N]: ' "$_CLR_YELLOW" "$_CLR_RESET" "$prompt_text" >&2
  read -r response
  case "$response" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

# Select from a list of options. Returns the selected value.
# Usage: result=$(select_option "Choose disk layout" "ext4" "btrfs")
select_option() {
  local prompt_text="$1"
  shift
  local options=("$@")
  local i

  printf '\n%b:: %b%s\n' "$_CLR_CYAN" "$_CLR_RESET" "$prompt_text" >&2
  for i in "${!options[@]}"; do
    printf '   %b%d)%b %s\n' "$_CLR_BOLD" "$((i + 1))" "$_CLR_RESET" "${options[$i]}" >&2
  done

  local choice
  while true; do
    printf '%b:: %bEnter number [1-%d]: ' "$_CLR_CYAN" "$_CLR_RESET" "${#options[@]}" >&2
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf '%s' "${options[$((choice - 1))]}"
      return 0
    fi
    log_warn "Invalid selection. Try again."
  done
}

# Print partition details and OS detection for a disk.
# Used by select_disk to show context under each disk entry.
_print_disk_details() {
  local disk="$1"
  local parts=()
  local has_ntfs=0
  local has_linux_fs=0

  while IFS= read -r line; do
    # Parse KEY="VALUE" pairs from lsblk -P output
    local type fstype size
    type="${line#*TYPE=\"}"; type="${type%%\"*}"
    [[ "$type" != "part" ]] && continue
    fstype="${line#*FSTYPE=\"}"; fstype="${fstype%%\"*}"
    size="${line#*SIZE=\"}"; size="${size%%\"*}"

    [[ -z "$fstype" ]] && fstype="raw"
    parts+=("${fstype}(${size})")

    case "$fstype" in
      ntfs) has_ntfs=1 ;;
      ext4|btrfs|xfs) has_linux_fs=1 ;;
    esac
  done < <(lsblk -Pno TYPE,FSTYPE,SIZE "$disk" 2>/dev/null)

  if [[ ${#parts[@]} -eq 0 ]]; then
    printf '      %bEmpty (no partitions)%b\n' "$_CLR_DIM" "$_CLR_RESET" >&2
  else
    local summary="${parts[*]}"
    if [[ $has_ntfs -eq 1 ]]; then
      printf '      %b%s%b  %bWindows detected%b\n' "$_CLR_DIM" "$summary" "$_CLR_RESET" "$_CLR_YELLOW" "$_CLR_RESET" >&2
    elif [[ $has_linux_fs -eq 1 ]]; then
      printf '      %b%s%b  %bLinux detected%b\n' "$_CLR_DIM" "$summary" "$_CLR_RESET" "$_CLR_YELLOW" "$_CLR_RESET" >&2
    else
      printf '      %b%s%b\n' "$_CLR_DIM" "$summary" "$_CLR_RESET" >&2
    fi
  fi
}

# Select a disk from available block devices.
# Usage: result=$(select_disk)
select_disk() {
  local disks=()

  while IFS= read -r line; do
    disks+=("$line")
  done < <(lsblk -dpno NAME,SIZE,MODEL | grep -E '/dev/(sd|nvme|vd)' | sort)

  if [[ ${#disks[@]} -eq 0 ]]; then
    die "No suitable disks found."
  fi

  printf '\n%b:: %bAvailable disks:\n' "$_CLR_CYAN" "$_CLR_RESET" >&2
  local i dev
  for i in "${!disks[@]}"; do
    printf '   %b%d)%b %s\n' "$_CLR_BOLD" "$((i + 1))" "$_CLR_RESET" "${disks[$i]}" >&2
    dev="$(echo "${disks[$i]}" | awk '{print $1}')"
    _print_disk_details "$dev"
  done

  local choice
  while true; do
    printf '%b:: %bSelect disk [1-%d]: ' "$_CLR_CYAN" "$_CLR_RESET" "${#disks[@]}" >&2
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#disks[@]} )); then
      local selected="${disks[$((choice - 1))]}"
      dev="$(echo "$selected" | awk '{print $1}')"
      printf '%s' "$dev"
      return 0
    fi
    log_warn "Invalid selection. Try again."
  done
}

# Print a summary table of key=value pairs for user review.
# Usage: print_summary "Hostname=myhost" "Disk=/dev/nvme0n1" ...
print_summary() {
  printf '\n%b  Installation Summary%b\n' "$_CLR_BOLD" "$_CLR_RESET" >&2
  printf "  %s\n" "$(printf '─%.0s' {1..40})" >&2
  local item
  for item in "$@"; do
    local key="${item%%=*}"
    local val="${item#*=}"
    printf '  %b%-16s%b %s\n' "$_CLR_BOLD" "$key" "$_CLR_RESET" "$val" >&2
  done
  printf "  %s\n\n" "$(printf '─%.0s' {1..40})" >&2
}

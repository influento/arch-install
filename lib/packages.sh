#!/usr/bin/env bash
# lib/packages.sh — Package list reading and installation helpers

# Read a package list file and return package names.
# Strips comments (#) and blank lines.
# Usage: packages=($(read_package_list "packages/base.list"))
read_package_list() {
  local list_file="$1"

  if [[ ! -f "$list_file" ]]; then
    die "Package list not found: $list_file"
  fi

  local packages=()
  while IFS= read -r line; do
    line="${line%%#*}"            # strip inline comments
    line="$(echo "$line" | xargs)" # trim whitespace
    [[ -z "$line" ]] && continue
    packages+=("$line")
  done < "$list_file"

  printf '%s\n' "${packages[@]}"
}

# Install packages from one or more .list files.
# Usage: install_packages_from_list "packages/base.list" "packages/workstation.list"
install_packages_from_list() {
  local all_packages=()

  local list_file
  for list_file in "$@"; do
    local file_packages
    mapfile -t file_packages < <(read_package_list "$list_file")
    all_packages+=("${file_packages[@]}")
    log_debug "Loaded ${#file_packages[@]} packages from $list_file"
  done

  if [[ ${#all_packages[@]} -eq 0 ]]; then
    log_warn "No packages to install."
    return 0
  fi

  log_info "Installing ${#all_packages[@]} packages..."
  run_logged "pacman install" pacman -S --noconfirm --needed "${all_packages[@]}"
}

# Install packages via pacstrap (used before chroot, from live ISO).
# Usage: pacstrap_packages "packages/base.list"
pacstrap_packages() {
  local all_packages=()

  local list_file
  for list_file in "$@"; do
    local file_packages
    mapfile -t file_packages < <(read_package_list "$list_file")
    all_packages+=("${file_packages[@]}")
  done

  if [[ ${#all_packages[@]} -eq 0 ]]; then
    die "No base packages to install."
  fi

  log_info "Running pacstrap with ${#all_packages[@]} packages..."
  run_logged "pacstrap" pacstrap -K "$MOUNT_POINT" "${all_packages[@]}"
}

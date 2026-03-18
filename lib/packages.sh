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

# Install a single app from a GitHub release tarball.
# The tarball should contain a binary and optional .desktop file.
# Usage: install_github_release "owner/repo" "app-{tag}-x86_64.tar.gz" "/home/user"
install_github_release() {
  local repo="$1"
  local tarball_pattern="$2"
  local user_home="$3"
  local app_name="${repo##*/}"
  local bin_dir="${user_home}/.local/bin"
  local apps_dir="${user_home}/.local/share/applications"

  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" \
    | grep '"tag_name"' | head -1 | cut -d'"' -f4 2>/dev/null)" || {
    log_warn "${app_name}: failed to fetch latest release, skipping"
    return 0
  }

  if [[ -z "$tag" ]]; then
    log_warn "${app_name}: no release found, skipping"
    return 0
  fi

  local tarball="${tarball_pattern//\{tag\}/$tag}"
  local url="https://github.com/${repo}/releases/download/${tag}/${tarball}"

  log_info "Installing ${app_name} ${tag}..."

  local tmp_dir
  tmp_dir="$(mktemp -d)"

  if ! curl -fsSL -o "${tmp_dir}/${tarball}" "$url"; then
    log_warn "${app_name}: download failed (${url}), skipping"
    rm -rf "$tmp_dir"
    return 0
  fi

  tar xzf "${tmp_dir}/${tarball}" -C "$tmp_dir"

  # Find the binary — look in extracted subdirectory or directly in tmp
  local binary=""
  local desktop=""
  local f
  for f in "${tmp_dir}"/*/"${app_name}" "${tmp_dir}/${app_name}"; do
    [[ -f "$f" ]] && binary="$f" && break
  done
  for f in "${tmp_dir}"/*/"${app_name}.desktop" "${tmp_dir}/${app_name}.desktop"; do
    [[ -f "$f" ]] && desktop="$f" && break
  done

  if [[ -z "$binary" ]]; then
    log_warn "${app_name}: binary not found in tarball, skipping"
    rm -rf "$tmp_dir"
    return 0
  fi

  mkdir -p "$bin_dir" "$apps_dir"
  chown "${USERNAME}:${USERNAME}" "${user_home}/.local" "$bin_dir" "${user_home}/.local/share" "$apps_dir"
  install -o "${USERNAME}" -g "${USERNAME}" -m 755 "$binary" "$bin_dir/"

  if [[ -n "$desktop" ]]; then
    install -o "${USERNAME}" -g "${USERNAME}" -m 644 "$desktop" "$apps_dir/"
  fi

  rm -rf "$tmp_dir"
  log_info "${app_name} ${tag} installed to ${bin_dir}/${app_name}"
}

# Install all custom apps from a config file.
# Usage: install_custom_apps "packages/custom-apps.conf"
install_custom_apps() {
  local conf_file="$1"
  local user_home
  user_home="$(eval echo "~${USERNAME}")"

  if [[ ! -f "$conf_file" ]]; then
    log_warn "Custom apps config not found: ${conf_file}"
    return 0
  fi

  local repo pattern
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs)"
    [[ -z "$line" ]] && continue
    repo="${line%% *}"
    pattern="${line#* }"
    install_github_release "$repo" "$pattern" "$user_home"
  done < "$conf_file"
}

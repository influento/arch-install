#!/usr/bin/env bash
# modules/jetbrains-toolbox.sh — JetBrains Toolbox App
# Downloads the latest Toolbox tarball from JetBrains and unpacks its bin/
# tree to ~/.local/share/JetBrains/Toolbox/bin. On first launch Toolbox
# writes its own ~/.local/share/applications/jetbrains-toolbox.desktop,
# so we don't ship one. We do drop an autostart entry so Toolbox launches
# into the tray on first login — from there the user signs in and pulls
# Rider and the rest of dotUltimate.
# Toolbox self-updates and manages IDE updates after that.
# Non-fatal: a failed download must not abort the workstation install.

install_jetbrains_toolbox() {
  log_info "Installing JetBrains Toolbox..."

  local user_home toolbox_dir autostart_dir
  user_home="$(eval echo "~${USERNAME}")"
  toolbox_dir="${user_home}/.local/share/JetBrains/Toolbox"
  autostart_dir="${user_home}/.config/autostart"

  # Resolve the latest Toolbox tarball URL via the official release feed.
  local release_json download_url
  release_json="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' 2>/dev/null)" || {
    log_warn "JetBrains Toolbox: failed to query release feed, skipping."
    return 0
  }

  download_url="$(printf '%s' "$release_json" \
    | grep -oE '"linux":\{[^}]*"link":"[^"]+"' \
    | grep -oE 'https://[^"]+\.tar\.gz' \
    | head -1)"

  if [[ -z "$download_url" ]]; then
    log_warn "JetBrains Toolbox: could not parse download URL, skipping."
    return 0
  fi

  local tmp_dir tarball
  tmp_dir="$(mktemp -d)"
  tarball="${tmp_dir}/jetbrains-toolbox.tar.gz"

  if ! curl -fsSL -o "$tarball" "$download_url"; then
    log_warn "JetBrains Toolbox: download failed (${download_url}), skipping."
    rm -rf "$tmp_dir"
    return 0
  fi

  if ! tar xzf "$tarball" -C "$tmp_dir"; then
    log_warn "JetBrains Toolbox: tarball extraction failed, skipping."
    rm -rf "$tmp_dir"
    return 0
  fi

  # Tarball layout: jetbrains-toolbox-<version>/bin/{jetbrains-toolbox,jre,lib,...}
  # The whole bin/ tree must be copied — the binary depends on the bundled JRE
  # and native libs sitting alongside it.
  local extracted_bin
  extracted_bin="$(find "$tmp_dir" -maxdepth 2 -type d -name bin -path '*/jetbrains-toolbox-*/bin' | head -1)"
  if [[ -z "$extracted_bin" || ! -f "${extracted_bin}/jetbrains-toolbox" ]]; then
    log_warn "JetBrains Toolbox: bin/ directory not found in tarball, skipping."
    rm -rf "$tmp_dir"
    return 0
  fi

  mkdir -p "$toolbox_dir" "$autostart_dir"
  rm -rf "${toolbox_dir:?}/bin"
  cp -r "$extracted_bin" "$toolbox_dir/"

  # Autostart entry — launches Toolbox into the tray on first login.
  # Toolbox manages its own entry from then on via its "Launch at system
  # startup" setting, but we need this one so it runs before the user has
  # signed in and opened the settings.
  cat > "${autostart_dir}/jetbrains-toolbox.desktop" <<AUTOSTART
[Desktop Entry]
Type=Application
Name=JetBrains Toolbox
Icon=jetbrains-toolbox
Exec=${toolbox_dir}/bin/jetbrains-toolbox
Terminal=false
X-GNOME-Autostart-enabled=true
AUTOSTART

  chown -R "${USERNAME}:${USERNAME}" "${user_home}/.local" "${user_home}/.config"

  rm -rf "$tmp_dir"
  log_info "JetBrains Toolbox installed. Sign in on first launch to install Rider and dotUltimate tools."
}

install_jetbrains_toolbox

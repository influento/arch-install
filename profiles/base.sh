#!/usr/bin/env bash
# profiles/base.sh — Shared base setup called by all profiles
# This runs inside chroot. Libraries are already sourced by the chroot wrapper.

run_base_profile() {
  log_section "Base Profile Setup"

  install_aur_helper
  deploy_dotfiles

  log_info "Base profile setup complete."
}

# Install yay (or configured AUR helper) as the non-root user.
# AUR helpers cannot build as root — we use sudo -u to run as USERNAME.
install_aur_helper() {
  local helper="${AUR_HELPER:-yay}"

  # Skip if already installed
  if command -v "$helper" &>/dev/null; then
    log_info "AUR helper '$helper' already installed, skipping."
    return 0
  fi

  log_info "Installing AUR helper: $helper"

  local build_dir="/tmp/${helper}-build"

  # Build and install as the non-root user
  sudo -u "$USERNAME" bash -c "
    set -euo pipefail
    git clone https://aur.archlinux.org/${helper}-bin.git '${build_dir}'
    cd '${build_dir}'
    makepkg -si --noconfirm
  "

  # Cleanup
  rm -rf "$build_dir"

  if command -v "$helper" &>/dev/null; then
    log_info "AUR helper '$helper' installed successfully."
  else
    log_warn "AUR helper '$helper' installation may have failed."
  fi
}

# Deploy the dotfiles repository to the user's home directory.
# Checks for a pre-cloned cache (from custom ISO) before attempting a network clone.
# After deployment, runs the dotfiles installer if it exists.
deploy_dotfiles() {
  if [[ -z "${DOTFILES_REPO:-}" ]]; then
    log_warn "DOTFILES_REPO not set — skipping dotfiles deployment."
    log_warn "Set DOTFILES_REPO in config.sh or pass --config with a git URL to enable."
    return 0
  fi

  local dest="${DOTFILES_DEST:-/home/${USERNAME}/.dotfiles}"
  local cache_dir="${INSTALLER_DIR}/.dotfiles-cache"

  if [[ -d "$dest" ]]; then
    log_info "Dotfiles already present at $dest, pulling latest..."
    sudo -u "$USERNAME" git -C "$dest" pull --ff-only || log_warn "Dotfiles pull failed, using existing."
  elif [[ -d "$cache_dir" ]]; then
    # Pre-cloned in the custom ISO — copy and set remote
    log_info "Deploying dotfiles from ISO cache..."
    cp -a "$cache_dir" "$dest"
    chown -R "${USERNAME}:${USERNAME}" "$dest"
    sudo -u "$USERNAME" git -C "$dest" remote set-url origin "$DOTFILES_REPO"
    log_info "Dotfiles deployed from cache. Remote set to $DOTFILES_REPO"
  else
    log_info "Cloning dotfiles from $DOTFILES_REPO..."
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" "$dest"
  fi

  # Run the dotfiles installer if it exists
  if [[ -f "${dest}/install.sh" ]]; then
    log_info "Running dotfiles installer with profile: workstation"
    bash "${dest}/install.sh" --profile workstation --user "$USERNAME"
  else
    log_warn "No install.sh found in dotfiles repo — skipping dotfiles installer."
    log_info "Dotfiles repo is available at $dest for manual setup."
  fi
}

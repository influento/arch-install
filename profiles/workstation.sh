#!/usr/bin/env bash
# profiles/workstation.sh — Workstation profile orchestrator
# Sway/Wayland workstation with dev tools. Runs inside chroot.

# Temporary passwordless sudo for install-time operations (AUR builds, dotfiles, etc.)
# Removed at the end of this script.
echo "${USERNAME} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99-installer-temp
chmod 440 /etc/sudoers.d/99-installer-temp

source "${INSTALLER_DIR}/profiles/base.sh"
run_base_profile

log_section "Workstation Profile"

# Install workstation packages
install_packages_from_list \
  "${INSTALLER_DIR}/packages/workstation.list" \
  "${INSTALLER_DIR}/packages/dev-tools.list" \
  "${INSTALLER_DIR}/packages/fonts.list" \
  "${INSTALLER_DIR}/packages/audio.list"

# Run hardware/system modules
source "${INSTALLER_DIR}/modules/gpu.sh"
source "${INSTALLER_DIR}/modules/firewall.sh"
source "${INSTALLER_DIR}/modules/ssh.sh"
source "${INSTALLER_DIR}/modules/virtualization.sh"

# Add user to docker group
if id "$USERNAME" &>/dev/null; then
  usermod -aG docker "$USERNAME"
  log_info "User $USERNAME added to docker group."
fi

# Set default editor system-wide
if [[ ! -f /etc/environment ]] || ! grep -q 'EDITOR=' /etc/environment; then
  log_info "Setting EDITOR and VISUAL to nvim..."
  echo "EDITOR=nvim" >> /etc/environment
  echo "VISUAL=nvim" >> /etc/environment
fi

# Set Qt theming platform
if ! grep -q 'QT_QPA_PLATFORMTHEME=' /etc/environment 2>/dev/null; then
  log_info "Setting QT_QPA_PLATFORMTHEME=qt6ct..."
  echo "QT_QPA_PLATFORMTHEME=qt6ct" >> /etc/environment
fi

# Rebuild font cache
run_logged "Rebuilding font cache" fc-cache -fv

# Install AUR packages (yay is available from base profile)
log_info "Installing AUR packages..."
sudo -u "$USERNAME" "${AUR_HELPER:-yay}" -S --noconfirm --needed \
  google-chrome \
  dropbox \
  python-gpgme

# Install global npm tools
log_info "Installing Claude Code..."
npm install -g @anthropic-ai/claude-code

# Enable workstation services
# TTY1 autologin for the created user (Sway auto-launches from .zshrc)
log_info "Configuring TTY1 autologin for ${USERNAME}..."
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USERNAME} --noclear %I \$TERM
AUTOLOGIN

enable_services \
  bluetooth \
  docker

# Remove temporary passwordless sudo
rm -f /etc/sudoers.d/99-installer-temp

log_info "Workstation profile complete."

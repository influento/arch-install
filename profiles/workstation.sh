#!/usr/bin/env bash
# profiles/workstation.sh — Workstation profile orchestrator
# Sway/Wayland workstation with dev tools. Runs inside chroot.

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
source "${INSTALLER_DIR}/modules/battery.sh"
source "${INSTALLER_DIR}/modules/jetbrains-toolbox.sh"

# Add user to docker group
if id "$USERNAME" &>/dev/null; then
  usermod -aG docker "$USERNAME"
  log_info "User $USERNAME added to docker group."
fi

# Register git-lfs filter hooks system-wide (writes to /etc/gitconfig)
# Without this, cloning LFS repos pulls pointer files instead of real content.
log_info "Registering git-lfs filter hooks system-wide..."
git lfs install --system --skip-repo

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

# Set XDG_CURRENT_DESKTOP for D-Bus/systemd activation environment
# Display managers set this automatically; TTY login does not.
# Without it, D-Bus-activated Wayland apps (e.g. Telegram from wofi) crash.
if ! grep -q 'XDG_CURRENT_DESKTOP=' /etc/environment 2>/dev/null; then
  log_info "Setting XDG_CURRENT_DESKTOP=sway..."
  echo "XDG_CURRENT_DESKTOP=sway" >> /etc/environment
fi

# Auto-power Bluetooth adapter on boot so paired devices reconnect automatically.
# Without this, the adapter stays off after reboot and paired devices (keyboards, etc.) drop.
if [[ -f /etc/bluetooth/main.conf ]]; then
  sed -i 's/^#AutoEnable=true$/AutoEnable=true/' /etc/bluetooth/main.conf
  sed -i 's/^#AutoEnable=false$/AutoEnable=true/' /etc/bluetooth/main.conf
  sed -i 's/^AutoEnable=false$/AutoEnable=true/' /etc/bluetooth/main.conf
  log_info "Bluetooth AutoEnable set to true for persistent connections."
fi

# Restart bluetooth after suspend/hibernate so paired devices (keyboards, etc.) reconnect.
# The BT controller loses power during sleep; without this, devices stay disconnected on wake.
log_info "Installing bluetooth sleep hook..."
mkdir -p /etc/systemd/system-sleep
cat > /etc/systemd/system-sleep/bluetooth-restart.sh <<'BTSLEEP'
#!/usr/bin/env bash
if [[ "$1" == "post" ]]; then
  sleep 1
  systemctl restart bluetooth
fi
BTSLEEP
chmod +x /etc/systemd/system-sleep/bluetooth-restart.sh

# Allow Bluetooth input from non-bonded HID devices (Keychron keyboards, etc.)
# Without this, some BT keyboards connect but produce no input.
if [[ -f /etc/bluetooth/input.conf ]]; then
  sed -i 's/^#ClassicBondedOnly=true/ClassicBondedOnly=false/' /etc/bluetooth/input.conf
  log_info "Bluetooth ClassicBondedOnly set to false for HID input support."
fi

# Disable btusb autosuspend to prevent Intel BT firmware load failures (error -19).
# USB power management can yank the controller mid-firmware-load; safe no-op on non-Intel HW.
log_info "Disabling btusb autosuspend..."
mkdir -p /etc/modprobe.d
printf 'options btusb enable_autosuspend=n\n' > /etc/modprobe.d/btusb.conf

# Rebuild font cache
run_logged "Rebuilding font cache" fc-cache -fv

# Install AUR packages (yay is available from base profile)
log_info "Installing AUR packages..."
sudo -u "$USERNAME" "${AUR_HELPER:-yay}" -S --noconfirm --needed \
  google-chrome \
  dropbox

# Optional AUR packages — a build failure here must not abort the install
log_info "Installing optional AUR packages..."
# wlvncc-git: Wayland-native VNC client written for wayvnc; best quality of the
# three clients, but a -git package that can fail to build. virt-viewer (official
# repo) stays the dependable default.
sudo -u "$USERNAME" "${AUR_HELPER:-yay}" -S --noconfirm --needed wlvncc-git ||
  log_warn "wlvncc-git failed to build — use remote-viewer (virt-viewer) instead."

# Install custom apps from GitHub releases
install_custom_apps "${INSTALLER_DIR}/packages/custom-apps.conf"

# Run dotfiles installer (after all packages so npm, cargo, etc. are available)
run_dotfiles_installer

# TTY1 autologin for the created user (Sway auto-launches from .zshrc).
# Needed so an unattended reboot — after a power cut, say — brings the compositor
# up on its own; otherwise sshd comes back but there is no session to connect to.
# Safe only because the dotfiles Sway config runs the lock screen on startup, so
# the session comes up locked: autologin starts the compositor, it does not remove
# authentication. This matters because / and /home are unencrypted.
#
# Scoped to tty1 only, so the other VTs keep a normal login prompt.
# The empty ExecStart= is required: ExecStart is a list, so without clearing it
# systemd appends and refuses to start a unit carrying two commands.
# Flags mirror the stock getty@.service, which passes the tty as - (from stdin)
# rather than %I; matching the shipped unit avoids surprises across upgrades.
#
# The drop-in is installed only if the deployed Sway config really does lock at
# startup — the invariant spans two repos, so it is enforced here rather than
# documented and hoped for. The match is anchored: `exec ~/.local/bin/lock` at the
# start of a line counts, but `bindsym $mod+Escape exec ~/.local/bin/lock` does
# not — a keybinding locks on demand and leaves a booted machine wide open.
sway_lock_re='^[[:space:]]*exec(_always)?[[:space:]]+~/\.local/bin/lock'
sway_config="/home/${USERNAME}/.config/sway/config"

if grep -Eq "$sway_lock_re" "$sway_config" 2>/dev/null; then
  log_info "Configuring TTY1 autologin for ${USERNAME}..."
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<AUTOLOGIN
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty --noreset --noclear --autologin ${USERNAME} - \${TERM}
AUTOLOGIN
else
  log_warn "TTY1 autologin NOT installed — this is deliberate, not a failure."
  log_warn "No startup lock found in ${sway_config}"
  log_warn "  (looked for a line matching: ${sway_lock_re})"
  log_warn "Autologin without it would drop straight to an unlocked desktop on a"
  log_warn "machine with no full-disk encryption, so it was skipped."
  log_warn "This machine will stop at a login prompt after reboot; a headless box"
  log_warn "will have sshd but no graphical session to connect to."
  log_warn "Fix: add 'exec ~/.local/bin/lock' to the dotfiles Sway config, then"
  log_warn "re-run the installer or write the drop-in by hand."
fi

# Enable workstation services
enable_services \
  bluetooth \
  docker

log_info "Workstation profile complete."

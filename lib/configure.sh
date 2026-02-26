#!/usr/bin/env bash
# lib/configure.sh — System configuration (runs inside chroot)

configure_system() {
  log_section "System Configuration"

  configure_pacman
  configure_timezone
  configure_locale
  configure_hostname
  configure_dns
  configure_initramfs
  configure_bootloader
  configure_users
  configure_sudo
}

configure_pacman() {
  log_info "Configuring pacman..."

  # Enable parallel downloads
  sed -i 's/^#ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf

  # Enable Color output
  sed -i 's/^#Color/Color/' /etc/pacman.conf

  # Enable multilib repository (needed for 32-bit libs: Steam, Wine, some drivers)
  log_info "Enabling multilib repository..."
  # Uncomment the [multilib] section (header + Include line)
  sed -i '/^\[multilib\]$/,/^Include/ s/^#//' /etc/pacman.conf

  # Sync package database with new config
  run_logged "Syncing package databases" pacman -Syy
}

configure_timezone() {
  log_info "Setting timezone to $TIMEZONE"
  ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  run_logged "Syncing hardware clock" hwclock --systohc
}

configure_locale() {
  log_info "Configuring locale: $LOCALE"

  # Uncomment the desired locale
  sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen

  # Always ensure en_US.UTF-8 is available as fallback
  sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen

  run_logged "Generating locales" locale-gen

  echo "LANG=${LOCALE}" > /etc/locale.conf
  echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf
}

configure_hostname() {
  log_info "Setting hostname: $HOSTNAME"

  echo "$HOSTNAME" > /etc/hostname

  cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF
}

configure_dns() {
  log_info "Configuring systemd-resolved for DNS..."

  # Enable systemd-resolved service
  run_logged "Enabling systemd-resolved" systemctl enable systemd-resolved

  # NOTE: resolv.conf symlink is created post-chroot in install.sh because
  # arch-chroot bind-mounts the host's /etc/resolv.conf for DNS during chroot.

  log_info "DNS configured (systemd-resolved + NetworkManager)."
}

configure_initramfs() {
  log_info "Configuring initramfs..."

  # Add resume hook for hibernation support
  if [[ -n "$SWAP_UUID" ]]; then
    log_info "Adding resume hook for hibernation support..."
    # Insert 'resume' after 'filesystems' in HOOKS
    sed -i 's/\(HOOKS=.*filesystems\)/\1 resume/' /etc/mkinitcpio.conf
  fi

  run_logged "Generating initramfs" mkinitcpio -P
}

configure_bootloader() {
  log_info "Installing bootloader: $BOOTLOADER"

  case "$BOOTLOADER" in
    systemd-boot)
      run_logged "Installing systemd-boot" bootctl install

      # Loader configuration
      cat > /boot/loader/loader.conf <<'EOF'
default arch.conf
timeout 3
console-mode max
editor  no
EOF

      # Determine microcode initrd line
      local microcode_line=""
      if [[ -f /boot/amd-ucode.img ]]; then
        microcode_line="initrd  /amd-ucode.img"
      fi
      if [[ -f /boot/intel-ucode.img ]]; then
        microcode_line="initrd  /intel-ucode.img"
      fi

      # Build kernel options
      local root_uuid
      root_uuid="$(findmnt -no UUID /)"
      local base_opts="root=UUID=${root_uuid} rw"

      # Add resume= for hibernation
      if [[ -n "$SWAP_UUID" ]]; then
        base_opts="${base_opts} resume=UUID=${SWAP_UUID}"
      fi

      # --- linux (standard kernel) entries ---
      cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
${microcode_line}
initrd  /initramfs-linux.img
options ${base_opts} quiet
EOF

      cat > /boot/loader/entries/arch-fallback.conf <<EOF
title   Arch Linux (Fallback)
linux   /vmlinuz-linux
${microcode_line}
initrd  /initramfs-linux-fallback.img
options ${base_opts}
EOF

      # --- linux-lts entries ---
      cat > /boot/loader/entries/arch-lts.conf <<EOF
title   Arch Linux (LTS)
linux   /vmlinuz-linux-lts
${microcode_line}
initrd  /initramfs-linux-lts.img
options ${base_opts} quiet
EOF

      cat > /boot/loader/entries/arch-lts-fallback.conf <<EOF
title   Arch Linux (LTS Fallback)
linux   /vmlinuz-linux-lts
${microcode_line}
initrd  /initramfs-linux-lts-fallback.img
options ${base_opts}
EOF

      log_info "systemd-boot installed with 4 entries (linux, linux-lts, + fallbacks)."
      ;;
    *)
      die "Unsupported bootloader: $BOOTLOADER (only systemd-boot is supported)"
      ;;
  esac
}

configure_users() {
  log_section "User Setup"

  # Root password (collected up front in install.sh)
  echo "root:${ROOT_PASSWORD}" | chpasswd
  log_info "Root password set."

  # Non-root user
  log_info "Creating user: $USERNAME"
  useradd -m -G wheel -s /usr/bin/zsh "$USERNAME"

  echo "${USERNAME}:${USER_PASSWORD}" | chpasswd

  # Remove bash skeleton files (user shell is zsh, not bash)
  rm -f "/home/${USERNAME}/.bash_logout" \
        "/home/${USERNAME}/.bash_profile" \
        "/home/${USERNAME}/.bashrc"

  log_info "User $USERNAME created."
}

configure_sudo() {
  log_info "Configuring sudo for wheel group..."

  # Enable wheel group in sudoers
  sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

  # Set default editor for visudo
  echo "Defaults editor=/usr/bin/${EDITOR}" > /etc/sudoers.d/00-editor
  chmod 440 /etc/sudoers.d/00-editor
}

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
  sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf

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
    grub)
      # Enable os-prober for dual-boot detection (Windows, etc.)
      sed -i 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub

      # Add hibernation resume parameter to kernel command line
      if [[ -n "$SWAP_UUID" ]]; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=\"\(.*\)\"|GRUB_CMDLINE_LINUX_DEFAULT=\"\1 resume=UUID=${SWAP_UUID}\"|" /etc/default/grub
      fi

      # Install Catppuccin Mocha GRUB theme
      log_info "Installing Catppuccin Mocha GRUB theme..."
      local theme_dir="/boot/grub/themes/catppuccin-mocha"
      local tmp_dir
      tmp_dir="$(mktemp -d)"
      git clone --depth 1 https://github.com/catppuccin/grub.git "$tmp_dir"
      mkdir -p "$theme_dir"
      cp -r "$tmp_dir/src/catppuccin-mocha-grub-theme/"* "$theme_dir/"
      rm -rf "$tmp_dir"

      # Set theme in GRUB config
      echo "GRUB_THEME=\"${theme_dir}/theme.txt\"" >> /etc/default/grub

      # Install GRUB to EFI system partition
      run_logged "Installing GRUB" grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot \
        --bootloader-id=GRUB

      # Mount other EFI System Partitions so os-prober can detect Windows.
      # os-prober does NOT auto-mount partitions inside a chroot, so we must
      # make other ESPs (e.g. Windows on a second SSD) visible manually.
      local mounted_esps=()
      while IFS= read -r esp_dev; do
        [[ -z "$esp_dev" ]] && continue
        # Skip if already mounted (our own /boot ESP)
        if findmnt -n "$esp_dev" > /dev/null 2>&1; then
          continue
        fi
        local mnt
        mnt="/run/os-prober-esps/$(basename "$esp_dev")"
        mkdir -p "$mnt"
        if mount -r "$esp_dev" "$mnt" 2>/dev/null; then
          mounted_esps+=("$mnt")
          log_info "Mounted $esp_dev at $mnt for os-prober"
        fi
      done < <(lsblk -rno PATH,PARTTYPE | awk '$2 == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1}')

      # Generate GRUB configuration (picks up os-prober, theme, resume param)
      run_logged "Generating GRUB config" grub-mkconfig -o /boot/grub/grub.cfg

      # Clean up temporary ESP mounts
      for mnt in "${mounted_esps[@]}"; do
        umount "$mnt" 2>/dev/null || true
      done
      rm -rf /run/os-prober-esps

      # Set GRUB as first UEFI boot entry (prepend to existing boot order)
      local grub_entry
      grub_entry="$(efibootmgr | grep -i "GRUB" | head -1 | grep -oP 'Boot\K[0-9A-Fa-f]+')"
      if [[ -n "$grub_entry" ]]; then
        local current_order
        current_order="$(efibootmgr | grep -oP 'BootOrder: \K.*')"
        # Remove GRUB from current order, then prepend it
        local new_order
        new_order="$(echo "$current_order" | sed "s/${grub_entry},\?//;s/,$//")"
        if [[ -n "$new_order" ]]; then
          new_order="${grub_entry},${new_order}"
        else
          new_order="$grub_entry"
        fi
        run_logged "Setting GRUB as first boot entry" efibootmgr --bootorder "$new_order"
      fi

      # Clean up stale systemd-boot EFI entry if present
      local stale_entry
      stale_entry="$(efibootmgr | grep -i "Linux Boot Manager" | head -1 | grep -oP 'Boot\K[0-9A-Fa-f]+' || true)"
      if [[ -n "$stale_entry" ]]; then
        log_info "Removing stale systemd-boot EFI entry (Boot${stale_entry})..."
        efibootmgr -b "$stale_entry" -B
      fi

      log_info "GRUB installed with os-prober + Catppuccin Mocha theme."
      ;;
    *)
      die "Unsupported bootloader: $BOOTLOADER (only grub is supported)"
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

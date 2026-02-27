#!/usr/bin/env bash
# lib/pacstrap.sh — Mirror configuration and base system bootstrap

setup_mirrors() {
  log_section "Mirror Configuration"

  if command -v reflector &>/dev/null; then
    local reflector_args=(
      --sort rate
      --protocol https
      --latest 20
      --save /etc/pacman.d/mirrorlist
    )

    # Country is normally detected early in install.sh via geo IP.
    # Fallback: try plain-text endpoints if MIRROR_COUNTRY is still empty.
    if [[ -z "$MIRROR_COUNTRY" ]]; then
      local detected_country=""
      local geo_urls=(
        "https://ipapi.co/country_code"
        "https://ifconfig.io/country_code"
        "http://ip-api.com/line/?fields=countryCode"
      )
      for geo_url in "${geo_urls[@]}"; do
        detected_country="$(curl -sf --max-time 5 "$geo_url" | tr -d '[:space:]')"
        if [[ "$detected_country" =~ ^[A-Z]{2}$ ]]; then
          MIRROR_COUNTRY="$detected_country"
          log_info "Auto-detected mirror country: $MIRROR_COUNTRY"
          break
        fi
        detected_country=""
      done
      [[ -z "$MIRROR_COUNTRY" ]] && log_warn "Could not detect country, using worldwide mirrors."
    fi

    if [[ -n "$MIRROR_COUNTRY" ]]; then
      reflector_args+=(--country "$MIRROR_COUNTRY")
      log_info "Filtering mirrors by country: $MIRROR_COUNTRY"
    fi

    run_logged "Updating mirrorlist with reflector" reflector "${reflector_args[@]}"
  else
    log_warn "reflector not available, using existing mirrorlist."
  fi

  # Enable parallel downloads in pacman
  if ! grep -q '^ParallelDownloads' /etc/pacman.conf; then
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
  fi

  run_logged "Syncing package databases" pacman -Syy
}

bootstrap_base_system() {
  log_section "Base System Installation"

  # Pre-create vconsole.conf so mkinitcpio's sd-vconsole hook doesn't error
  # during pacstrap's post-install kernel hooks.
  mkdir -p "${MOUNT_POINT}/etc"
  echo "KEYMAP=${KEYMAP}" > "${MOUNT_POINT}/etc/vconsole.conf"

  pacstrap_packages "${INSTALLER_DIR}/packages/base.list"

  log_info "Generating fstab..."
  genfstab -U "$MOUNT_POINT" >> "${MOUNT_POINT}/etc/fstab"
  log_info "fstab generated."
}

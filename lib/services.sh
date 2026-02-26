#!/usr/bin/env bash
# lib/services.sh — Service enablement helpers

# Enable one or more systemd services.
# Usage: enable_services NetworkManager sshd systemd-timesyncd
enable_services() {
  local svc
  for svc in "$@"; do
    if systemctl list-unit-files "${svc}.service" &>/dev/null; then
      run_logged "Enabling $svc" systemctl enable "$svc"
    else
      log_warn "Service not found, skipping: $svc"
    fi
  done
}

# Enable base services common to all profiles.
enable_base_services() {
  log_info "Enabling base services..."
  enable_services \
    NetworkManager \
    systemd-timesyncd
}

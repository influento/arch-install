#!/usr/bin/env bash
# modules/sddm.sh — SDDM display manager setup

log_info "Configuring SDDM..."

# SDDM Wayland session configuration
mkdir -p /etc/sddm.conf.d

cat > /etc/sddm.conf.d/10-wayland.conf <<'EOF'
[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=sway
EOF

log_info "SDDM configured for Wayland (Sway compositor)."

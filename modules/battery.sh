#!/usr/bin/env bash
# modules/battery.sh — Battery charge threshold (laptop only)
# Sets charge_control_end_threshold to 80% via udev rule.
# Works on any laptop whose kernel driver exposes the standard
# charge_control_end_threshold sysfs attribute (ASUS, ThinkPad,
# Framework, Huawei, etc.). The udev rule enforces the threshold
# at boot even if the EC doesn't persist it across power cycles.
# Non-fatal: failure here must not abort the install.

if [[ -f /sys/class/power_supply/BAT0/charge_control_end_threshold ]] 2>/dev/null ||
   [[ -f /sys/class/power_supply/BAT1/charge_control_end_threshold ]] 2>/dev/null; then
  log_info "Battery detected — installing 80% charge threshold udev rule..."
  mkdir -p /etc/udev/rules.d
  printf '%s\n' \
    'ACTION=="add", SUBSYSTEM=="power_supply", ATTR{charge_control_end_threshold}="80"' \
    > /etc/udev/rules.d/90-battery-charge-threshold.rules || log_warn "Failed to write battery charge threshold udev rule — skipping."
else
  log_info "No battery with charge_control_end_threshold found — skipping."
fi

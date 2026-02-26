#!/usr/bin/env bash
# modules/virtualization.sh — QEMU/KVM + virt-manager setup

log_info "Installing virtualization packages..."

# Replace iptables with iptables-nft (nftables backend) — libvirt needs iptables
# commands for NAT networking, and iptables-nft translates them to nftables rules.
# This avoids a conflict with the stock iptables package.
if pacman -Qi iptables &>/dev/null && ! pacman -Qi iptables-nft &>/dev/null; then
  log_info "Replacing iptables with iptables-nft..."
  pacman -S --noconfirm --ask 4 iptables-nft
fi

pacman -S --noconfirm --needed \
  qemu-full \
  libvirt \
  virt-manager \
  dnsmasq \
  edk2-ovmf

# Add user to libvirt group for non-root VM management
if id "$USERNAME" &>/dev/null; then
  usermod -aG libvirt "$USERNAME"
  log_info "User $USERNAME added to libvirt group."
fi

enable_services libvirtd

log_info "Virtualization configured (QEMU/KVM + virt-manager)."

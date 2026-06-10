#!/usr/bin/env bash
# modules/ssh.sh — OpenSSH server (enabled by default, hardened)
#
# Enabled by default. Root login is off; you log in as the user account only.
# Password auth is allowed but throttled hard: MaxAuthTries caps guesses per
# connection, and OpenSSH's native PerSourcePenalties impose an escalating
# per-source lockout (30s, 60s for invalid users, accumulating to a 10-minute
# cap), so online brute force is impractical against a strong password — no
# fail2ban needed. Set ENABLE_SSH=no (config.sh / --config / env) to skip
# installing/enabling sshd; the nftables firewall permits port 22 either way,
# so a disabled service can be turned on later with `systemctl enable --now sshd`.

# Accept yes/true/1 (any case) as "enabled"; anything else = disabled.
_ssh_enabled="${ENABLE_SSH:-yes}"
if [[ ! "${_ssh_enabled,,}" =~ ^(yes|true|1)$ ]]; then
  log_info "SSH server disabled (ENABLE_SSH=${ENABLE_SSH:-}); skipping sshd setup."
else
  log_info "Configuring SSH (enabled by default; set ENABLE_SSH=no to disable)..."

  # Harden sshd_config
  mkdir -p /etc/ssh/sshd_config.d

  cat > /etc/ssh/sshd_config.d/10-hardened.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
MaxAuthTries 3
LoginGraceTime 30
# Escalating per-source lockout on repeated failures (OpenSSH 9.8+, native —
# replaces fail2ban): refuse a failing source for 30s (60s for invalid users),
# accumulating up to a 10-minute cap once it passes the 15s min threshold.
PerSourcePenalties authfail:30s invaliduser:60s max:10m
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  enable_services sshd

  log_info "SSH configured and enabled."
fi

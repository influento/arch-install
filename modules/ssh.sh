#!/usr/bin/env bash
# modules/ssh.sh — OpenSSH server with hardened configuration

log_info "Configuring SSH..."

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
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

log_info "SSH hardened configuration deployed."

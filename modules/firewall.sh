#!/usr/bin/env bash
# modules/firewall.sh — nftables firewall setup

log_info "Configuring nftables firewall..."

cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;

        # Accept established/related
        ct state established,related accept

        # Accept loopback
        iif "lo" accept

        # Accept ICMP/ICMPv6
        ip protocol icmp accept
        ip6 nexthdr icmpv6 accept

        # Accept SSH
        tcp dport 22 accept

        # Log and drop everything else
        log prefix "nftables-drop: " counter drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;

        # Allow Docker container traffic
        iifname "docker0" accept
        oifname "docker0" ct state established,related accept
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

enable_services nftables

log_info "nftables firewall configured (SSH allowed, everything else dropped)."

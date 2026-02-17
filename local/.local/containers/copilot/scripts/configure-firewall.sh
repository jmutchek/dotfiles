#!/bin/bash
# OCI Hook: Configure container firewall to block private IP ranges
# Only allows public DNS servers for maximum isolation from local network

# Configure nftables to block private IPs and restrict DNS to public servers
/usr/bin/nft -f - <<'NFTEOF'
table inet ghcp_filter {
  # Private IP ranges to block
  set private_networks {
    type ipv4_addr
    flags interval
    elements = {
      10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
      169.254.0.0/16, 224.0.0.0/4, 240.0.0.0/4
    }
  }
  
  # Public DNS servers allowed
  set public_dns {
    type ipv4_addr
    elements = {
      8.8.8.8, 8.8.4.4,        # Google DNS
      1.1.1.1, 1.0.0.1,        # Cloudflare DNS
      9.9.9.9, 149.112.112.112 # Quad9 DNS
    }
  }
  
  chain output {
    type filter hook output priority filter; policy accept;
    
    # Allow established/related connections
    ct state {established, related} accept
    
    # Allow loopback (container-internal services)
    ip daddr 127.0.0.0/8 accept
    
    # Allow DNS only to public DNS servers
    ip daddr @public_dns udp dport 53 accept
    ip daddr @public_dns tcp dport 53 accept
    
    # Block all other private IP traffic
    ip daddr @private_networks counter drop
    
    # Everything else (public internet) allowed by default policy
  }
}
NFTEOF

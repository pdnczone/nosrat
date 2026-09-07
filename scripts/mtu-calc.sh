#!/usr/bin/env bash
# Prints the MTU budget for GRE-over-IPsec(transport, AES-GCM) given a
# physical link MTU. Defaults to 1500 (standard Ethernet).
set -euo pipefail
LINK_MTU="${1:-1500}"

OUTER_IP=20      # IPv4 outer header (34 if outer is IPv6, use --v6 to adjust)
ESP_HDR=8        # SPI(4) + Sequence Number(4)
ESP_IV=8          # AES-GCM 8-byte IV
ESP_TRAILER=2     # Pad Length(1) + Next Header(1), plus up to 3B alignment padding
ESP_ICV=16        # GCM-16 authentication tag
GRE_HDR=4         # minimal GRE header, no key/seq/checksum flags

ESP_TOTAL=$((ESP_HDR + ESP_IV + ESP_TRAILER + ESP_ICV))
OVERHEAD=$((OUTER_IP + ESP_TOTAL + GRE_HDR))
TUNNEL_MTU=$((LINK_MTU - OVERHEAD))
MSS=$((TUNNEL_MTU - 40))   # inner IPv4(20) + TCP(20)

cat <<EOF
Link MTU:               $LINK_MTU
  - Outer IPv4 header:  -$OUTER_IP
  - ESP (header+IV):    -$((ESP_HDR + ESP_IV))
  - ESP trailer+ICV:    -$((ESP_TRAILER + ESP_ICV))
  - GRE header:         -$GRE_HDR
                        ------
Usable tunnel MTU:       $TUNNEL_MTU   (config default: 1400, safety margin: $((TUNNEL_MTU - 1400)))
Recommended TCP MSS:     $MSS
EOF

#!/usr/bin/env bash
# Compares baseline (public IP) vs over-tunnel (GRE IP) performance.
# Run on Server A with Server B's public IP + GRE IP as arguments, and with
# iperf3 -s already running on Server B.
#
# Usage: ./benchmark.sh <remote_public_ip> <remote_gre_ip> [duration_seconds]
set -euo pipefail

REMOTE_PUB="${1:?usage: benchmark.sh <remote_public_ip> <remote_gre_ip> [duration]}"
REMOTE_GRE="${2:?usage: benchmark.sh <remote_public_ip> <remote_gre_ip> [duration]}"
DURATION="${3:-15}"

section() { echo; echo "==== $* ===="; }

section "Baseline (direct, public IP $REMOTE_PUB)"
echo "-- ping (10 packets) --"
ping -c 10 "$REMOTE_PUB" || true
echo "-- tracepath --"
tracepath "$REMOTE_PUB" 2>&1 | head -20 || true
echo "-- iperf3 (${DURATION}s) --"
iperf3 -c "$REMOTE_PUB" -t "$DURATION" || echo "(iperf3 server not reachable directly - skipping)"

section "Over tunnel (GRE IP $REMOTE_GRE)"
echo "-- ping (10 packets) --"
ping -c 10 "$REMOTE_GRE" || true
echo "-- ping with DF bit at tunnel MTU (expect success at configured MTU) --"
TUNNEL_MTU=$(ip -j link show nosrat 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d[0]["mtu"])' 2>/dev/null || echo 1400)
PAYLOAD=$((TUNNEL_MTU - 28))
ping -M do -s "$PAYLOAD" -c 5 "$REMOTE_GRE" || echo "(fragmentation/DF issue at MTU=$TUNNEL_MTU - check MSS clamping)"
echo "-- tracepath --"
tracepath "$REMOTE_GRE" 2>&1 | head -20 || true
echo "-- iperf3 (${DURATION}s) --"
iperf3 -c "$REMOTE_GRE" -t "$DURATION" || echo "(iperf3 server not reachable over tunnel - check ESP/GRE firewall)"

section "Summary"
echo "Compare throughput and RTT above: baseline vs tunnel."
echo "Expect: tunnel throughput slightly lower (ESP/GRE overhead + AES-GCM CPU cost),"
echo "        tunnel RTT slightly higher (extra encap/decap), no packet loss in either."

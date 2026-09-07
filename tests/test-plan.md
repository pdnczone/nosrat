# nosrat Test Plan

Run these against a real pair of VPS (Server A / Server B), not the build
sandbox - GRE/XFRM/strongSwan need real kernel networking and two public IPs.

## Test 1: Server A → Server B
```
# On A
ping -c 20 <remote_gre_ip>
iperf3 -c <remote_gre_ip>
```
Expect: 0% loss, `nosrat status` shows IKE=ESTABLISHED, ESP=INSTALLED.

## Test 2: Server B → Server A
Same as Test 1, reversed. Confirms symmetry (IPsec SAs are bidirectional but
routing/firewall rules must be checked on both ends independently).

## Test 3: 1000+ concurrent connections
```
# On B (target)
iperf3 -s -p 5201
# On A - open many short TCP connections through the tunnel
for i in $(seq 1 1000); do
  (echo -n | nc -w1 <remote_gre_ip> 5201 &)
done
wait
nosrat status   # watch RX/TX PPS and confirm ESP SA doesn't drop under load
```
Expect: no IKE renegotiation storms, no ESP SA drop, CPU on both ends stays
reasonable (check with `mpstat 1` - AES-NI should keep ESP cost low).

## Test 4: iperf3 throughput
```
iperf3 -c <remote_gre_ip> -t 30 -P 4   # 4 parallel streams
```
Compare against `scripts/benchmark.sh` baseline (direct, no tunnel) numbers.
Expect tunnel throughput within ~10-20% of baseline (AES-GCM + GRE overhead).

## Test 5: Packet loss
Simulate loss with `tc`:
```
tc qdisc add dev eth0 root netem loss 2%
nosrat health   # loss_threshold_pct in config should catch this
tc qdisc del dev eth0 root netem
```

## Test 6: High latency
```
tc qdisc add dev eth0 root netem delay 150ms 20ms
nosrat health   # should flag latency_threshold_ms if exceeded
tc qdisc del dev eth0 root netem
```

## Test 7: IPsec renegotiation (rekey)
Set `ipsec.rekey_seconds: 60` temporarily, then:
```
watch -n1 swanctl --list-sas
```
Expect: a new SA is negotiated before the old one expires, with **zero**
GRE-level packet loss during the swap (verify with a background `ping -i 0.2`).

## Test 8: Server reboot
```
sudo reboot
# after boot:
systemctl status nosrat strongswan
nosrat status
```
Expect: tunnel comes back automatically (systemd `WantedBy=multi-user.target`
+ `enable`), no manual intervention needed.

## Test 9: Network interface restart
```
sudo ip link set eth0 down && sleep 3 && sudo ip link set eth0 up
nosrat health          # should detect and, if auto_recover: true, self-heal
nosrat diagnose
```

## Test 10: MTU / fragmentation
```
scripts/mtu-calc.sh 1500
ping -M do -s 1372 -c 5 <remote_gre_ip>   # 1372+28=1400, should pass
ping -M do -s 1400 -c 5 <remote_gre_ip>   # 1400+28=1428 > tunnel MTU, should need clamping/fail
```
Confirm TCP MSS clamping works: `curl` a large file through a service bound
behind the tunnel and check no silent stalls (classic PMTUD-blackhole symptom).

## Test 11: NAT-T
If either server sits behind NAT (test with a NAT'd client machine acting as
one endpoint, or a cloud NAT gateway):
```
swanctl --list-sas   # look for "encap: yes" - confirms ESP-in-UDP/4500
```
Expect: strongSwan auto-detects NAT via IKE NAT-D payloads and switches ESP
transport from proto-50 to UDP/4500 encapsulation automatically; nosrat's
firewall rules already allow UDP/4500 for exactly this case.

## Test 12: Replay / invalid packets
```
# Capture and replay an old ESP packet using scapy/tcpreplay
tcpreplay -i eth0 captured_esp_packet.pcap
```
Expect: kernel XFRM anti-replay window silently drops the replayed packet;
confirm via `ip -s xfrm state` replay-window counters incrementing on
"replay" or a drop counter, and no GRE-level effect.

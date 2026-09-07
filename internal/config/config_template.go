package config

// GetDefaultStarterConfig returns the default starter configuration content.
func GetDefaultStarterConfig() string {
	return `# nosrat starter configuration
# Edit the values below for your tunnel endpoints, then run:
#   nosrat create && nosrat start

tunnel:
  name: nosrat

local:
  public_ip: ""
  gre_ip: "10.200.0.1/30"

remote:
  public_ip: ""
  gre_ip: "10.200.0.2/30"

ipsec:
  ike_version: 2
  mode: transport
  encryption: aes256gcm16
  integrity: ""
  dh_group: 14
  psk_file: /etc/nosrat/secrets/psk
  rekey_seconds: 3600
  dpd_delay: 10
  dpd_timeout: 30

routing:
  enabled: true
  static_routes: []

firewall:
  enabled: true
  allow_ssh: true

mtu:
  value: 1400
  mss_clamp: true

keepalive:
  enabled: true
  interval: 10

health:
  interval_seconds: 15
  latency_threshold_ms: 200
  loss_threshold_pct: 5
  auto_recover: true

failover:
  enabled: false
  secondary_public_ip: ""
  switch_after_failures: 3
`
}
